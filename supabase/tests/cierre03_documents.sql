\set ON_ERROR_STOP on
-- Disposable local DB only. All identities, grants, rows and objects roll back.
BEGIN;
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'delivery assertion: %',label; END IF;
 PERFORM set_config('d.assertions',(COALESCE(NULLIF(current_setting('d.assertions',true),''),'0')::int+1)::text,true);
END $$;
CREATE FUNCTION pg_temp.denied(q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE q;EXCEPTION WHEN insufficient_privilege THEN RETURN;END;
 RAISE EXCEPTION 'expected insufficient privilege';
END $$;
CREATE FUNCTION pg_temp.actor(u uuid,c uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated',
 'iss','https://synthetic-access.invalid/auth/v1','user_metadata',jsonb_build_object('financial_full',true))::text,true);
 PERFORM set_config('request.headers',CASE WHEN c IS NULL THEN '{}' ELSE jsonb_build_object('x-rotero-scope','company','x-rotero-company-id',c) END::text,true);
END $$;
SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
 public.membership_company_capabilities,private.financial_principal_bindings,public.membership_consolidation_grants,
 public.consolidation_grant_companies TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
GRANT SELECT,INSERT ON private.operation_company_classification_events TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_finance_scope_owner;
GRANT SELECT,INSERT ON private.finance_invoices_company_evidence TO postgres;
RESET ROLE;
-- Fresh limited-role execution must not depend on a plan warmed by a privileged
-- caller. The UUID selector helper does not expose the complete request headers.
SET LOCAL ROLE rotero_delivery_capture_owner;
SELECT pg_temp.ok(private.delivery_company_ids() IS NULL,'limited capture selector helper');
SELECT pg_temp.denied('SELECT private.delivery_headers()');
RESET ROLE;
CREATE FUNCTION pg_temp.resolve(root text,entity uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t uuid;e uuid;ledger text;idcol text;
BEGIN
 IF root NOT IN('operations','finance_invoices') THEN RAISE EXCEPTION 'fixture root'; END IF;
 EXECUTE format('SELECT tenant_id FROM public.%I WHERE id=$1',root) INTO t USING entity;
 ledger:=CASE root WHEN 'operations' THEN 'operation_company_classification_events' ELSE 'finance_invoices_company_evidence' END;
 idcol:=CASE root WHEN 'operations' THEN 'operation_id' ELSE 'entity_id' END;
 EXECUTE format('INSERT INTO private.%I(tenant_id,%I,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES($1,$2,$3,''resolved'',''verified_source_record'',''synthetic-only'',$4) RETURNING id',ledger,idcol)
 INTO e USING t,entity,c,current_setting('d.u')::uuid;
 EXECUTE format('UPDATE public.%I SET company_id=$1,company_classification_status=''resolved'',company_classification_event_id=$2 WHERE id=$3',root)
 USING c,e,entity;
END $$;
DO $$ DECLARE t uuid;x uuid;a uuid;b uuid;xc uuid;u uuid:=gen_random_uuid();ng uuid:=gen_random_uuid();op uuid;inv uuid;f uuid;e uuid;
BEGIN
 INSERT INTO public.tenants(name,slug) VALUES('Delivery synthetic','delivery-'||gen_random_uuid()) RETURNING id INTO t;
 INSERT INTO public.tenants(name,slug) VALUES('Delivery other','delivery-'||gen_random_uuid()) RETURNING id INTO x;
 INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(ng,t,'admin');
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
 INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(t,u,a,u),(t,u,b,u);
 INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT t,u,a,c,'synthetic-only',u FROM unnest(ARRAY['operations.read','billing.document.read','receivables.read','export.operational','export.receivables'])c;
 PERFORM set_config('d.t',t::text,true);PERFORM set_config('d.x',x::text,true);PERFORM set_config('d.u',u::text,true);
 PERFORM set_config('d.a',a::text,true);PERFORM set_config('d.b',b::text,true);PERFORM set_config('d.xc',xc::text,true);PERFORM set_config('d.ng',ng::text,true);
 INSERT INTO private.delivery_tenant_cutovers(tenant_id,enabled,approval_reference,approved_by) VALUES(t,true,'synthetic-only',u);
 FOR i IN 1..3 LOOP
  INSERT INTO public.operations(tenant_id,reference_code,provider_cost_amount,customer_price_amount,notes,status,created_at,updated_at)
  VALUES(t,'A-'||i,12345,54321,'FINANCIAL_CANARY',CASE WHEN i=1 THEN 'delivered' ELSE 'planned' END,
   CASE WHEN i=1 THEN now()-interval '71.4 hours' ELSE now() END,now()) RETURNING id INTO op;
  PERFORM pg_temp.resolve('operations',op,a);IF i=1 THEN PERFORM set_config('d.op',op::text,true);END IF;
 END LOOP;
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(t,'B') RETURNING id INTO op;PERFORM pg_temp.resolve('operations',op,b);PERFORM set_config('d.ob',op::text,true);
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(x,'X') RETURNING id INTO op;PERFORM pg_temp.resolve('operations',op,xc);PERFORM set_config('d.ox',op::text,true);
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(t,'UNCLASSIFIED') RETURNING id INTO op;PERFORM set_config('d.pending',op::text,true);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ar','Synthetic customer','AR-A',1000,'MXN','open',current_setting('d.op')::uuid) RETURNING id INTO inv;
 PERFORM pg_temp.resolve('finance_invoices',inv,a);PERFORM set_config('d.invoice',inv::text,true);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ap','Synthetic provider','AP-A',88888,'MXN','open',current_setting('d.op')::uuid) RETURNING id INTO inv;PERFORM pg_temp.resolve('finance_invoices',inv,a);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ar','Other customer','AR-B',77777,'MXN','open',current_setting('d.ob')::uuid) RETURNING id INTO inv;PERFORM pg_temp.resolve('finance_invoices',inv,b);
 INSERT INTO public.document_files(tenant_id,storage_bucket,storage_path,file_name,mime_type,size_bytes,file_kind,source_module,source_entity_type,source_entity_id,status,access_class)
 VALUES(t,'tenant-documents',t||'/operations/synthetic.txt','synthetic.txt','text/plain',12,'operation_evidence','operations','operation',current_setting('d.op')::uuid,'active','operational') RETURNING id INTO f;
 INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,access_class,evidence_reference,recorded_by)
 VALUES(t,'document_files',f,a,'operational','synthetic-only',u) RETURNING id INTO e;
 UPDATE public.document_files SET company_id=a,company_classification_status='resolved',company_classification_event_id=e WHERE id=f;
 PERFORM set_config('d.file',f::text,true);
END $$;

INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'doc-'||current_setting('d.u')||'@example.test');
UPDATE public.memberships SET role='operator' WHERE user_id=current_setting('d.u')::uuid;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
SELECT current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,c,'local-C03',current_setting('d.u')::uuid
FROM unnest(ARRAY['documents.upload','documents.manage','operations.evidence.write'])c;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
CREATE FUNCTION pg_temp.prepare(parent uuid DEFAULT NULL,classification text DEFAULT 'operational',previous uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
SELECT public.rpc_delivery_prepare_upload(current_setting('d.t')::uuid,gen_random_uuid(),jsonb_build_object(
 'entity_type','operation','entity_id',COALESCE(parent,current_setting('d.op')::uuid),'access_class',classification,
 'file_name','synthetic.txt','mime_type','text/plain','size_bytes',12,'checksum_sha256',repeat('a',64),'replaces_file_id',previous,'reason','Synthetic replacement'));
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.prepare(current_setting('d.ob')::uuid)->>'error'='unauthorized','company B parent denied');
SELECT pg_temp.ok(pg_temp.prepare(current_setting('d.ox')::uuid)->>'error'='unauthorized','other tenant parent denied');
SELECT pg_temp.ok(pg_temp.prepare(current_setting('d.pending')::uuid)->>'error'='unauthorized','unclassified parent denied');
SELECT pg_temp.ok(pg_temp.prepare(NULL,'financial')->>'error'='unauthorized','operator cannot select financial classification');
SELECT set_config('d.upload',pg_temp.prepare()::text,true);
SELECT pg_temp.ok(current_setting('d.upload')::jsonb->>'id' IS NOT NULL,'authorized upload prepared');
SELECT pg_temp.ok(public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.upload')::jsonb->>'id')::uuid)->>'error'='storage_object_not_verified','metadata cannot precede verified object');
SELECT pg_temp.denied('INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES(''tenant-documents'','''||current_setting('d.t')||'/operations/operation/'||current_setting('d.op')||'/arbitrary.txt'','''||current_setting('d.u')||''')');
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tenant-documents',current_setting('d.upload')::jsonb->>'path',current_setting('d.u'),'{"size":12,"mimetype":"text/plain"}');
SELECT pg_temp.ok((SELECT count(*)=0 FROM storage.objects WHERE name=current_setting('d.upload')::jsonb->>'path'),'unregistered upload not readable');
SELECT set_config('d.final',public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.upload')::jsonb->>'id')::uuid)::text,true);
SELECT pg_temp.ok(current_setting('d.final')::jsonb->>'success'='true','file registered with classification evidence');
SELECT set_config('d.newfile',current_setting('d.final')::jsonb->>'id',true);
SELECT pg_temp.ok(public.rpc_delivery_operation_child_action(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'document.save',
 jsonb_build_object('document_type','proof_of_delivery','requirement_level','required','status','present','file_id',current_setting('d.newfile')),
 gen_random_uuid(),(public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->>'workflow_revision')::bigint)->>'success'='true','POD linked before version replacement');
SELECT pg_temp.ok(public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.upload')::jsonb->>'id')::uuid)=current_setting('d.final')::jsonb,'finalization idempotent');
SELECT pg_temp.ok((SELECT count(*)=1 FROM storage.objects WHERE name=current_setting('d.upload')::jsonb->>'path'),'direct Storage read explicitly authorized');
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.newfile')::uuid)->>'path'=(current_setting('d.upload')::jsonb->>'path'),'authenticated download lookup works');
SELECT pg_temp.ok(public.rpc_delivery_document_history(current_setting('d.t')::uuid,'operation',current_setting('d.op')::uuid)::text NOT LIKE '%FINANCIAL_CANARY%','history projects safe metadata');
SELECT pg_temp.denied('SELECT * FROM private.c03_document_uploads');
SELECT pg_temp.denied('SELECT * FROM private.c03_document_events');
SELECT pg_temp.denied('UPDATE public.document_files SET access_class=''operational''');
RESET ROLE;
UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.u')::uuid WHERE tenant_id=current_setting('d.t')::uuid AND user_id=current_setting('d.u')::uuid AND capability_code='documents.upload';
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.prepare()->>'error'='unauthorized','upload capability revocation immediate');
RESET ROLE;
UPDATE public.membership_company_capabilities SET status='active',revoked_at=NULL,revoked_by=NULL WHERE tenant_id=current_setting('d.t')::uuid AND user_id=current_setting('d.u')::uuid AND capability_code='documents.upload';
SET LOCAL ROLE authenticated;
SELECT set_config('d.replacement',pg_temp.prepare(NULL,'operational',current_setting('d.newfile')::uuid)::text,true);
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tenant-documents',current_setting('d.replacement')::jsonb->>'path',current_setting('d.u'),'{"size":12,"mimetype":"text/plain"}');
SELECT set_config('d.replaced',public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.replacement')::jsonb->>'id')::uuid)::text,true);
SELECT pg_temp.ok(current_setting('d.replaced')::jsonb->>'success'='true','replacement creates new version');
SELECT pg_temp.ok(EXISTS(SELECT FROM jsonb_array_elements(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'documents')d
 WHERE d->>'document_type'='proof_of_delivery' AND d->>'file_ref'=current_setting('d.replaced')::jsonb->>'id'),'POD relation follows the active replacement without rewriting historical evidence');
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.newfile')::uuid)->>'error'='unauthorized','old superseded download denied');
SELECT pg_temp.ok((SELECT count(*)=0 FROM storage.objects WHERE name=current_setting('d.upload')::jsonb->>'path'),'old object cannot bypass replacement');
SELECT pg_temp.ok(public.rpc_delivery_cancel_file(current_setting('d.t')::uuid,(current_setting('d.replaced')::jsonb->>'id')::uuid,'Synthetic cancel')->>'success'='true','cancel preserves history');
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,(current_setting('d.replaced')::jsonb->>'id')::uuid)->>'error'='unauthorized','cancelled download denied');
SELECT pg_temp.ok(public.rpc_get_operation_document_summary(current_setting('d.op')::uuid)->>'pod_present'='false','cancelling the only POD content restores missing readiness');
SELECT pg_temp.ok(jsonb_array_length(public.rpc_delivery_document_history(current_setting('d.t')::uuid,'operation',current_setting('d.op')::uuid)->'items')=3,'history retains original and both new versions');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=2 FROM storage.objects WHERE name IN(current_setting('d.upload')::jsonb->>'path',current_setting('d.replacement')::jsonb->>'path')),'historical bytes retained');
SELECT pg_temp.ok((SELECT count(*)=3 FROM private.c03_document_events WHERE tenant_id=current_setting('d.t')::uuid),'all document effects audited');
DO $$BEGIN BEGIN UPDATE private.c03_document_events SET reason='erase' WHERE tenant_id=current_setting('d.t')::uuid;RAISE EXCEPTION 'immutable evidence unexpectedly writable';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'document_evidence_immutable' THEN RAISE;END IF;END;END $$;
SELECT pg_temp.actor(current_setting('d.ng')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.prepare()->>'error'='unauthorized','admin without grants denied');
RESET ROLE;
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.rpc_delivery_prepare_upload(uuid,uuid,jsonb)','EXECUTE'),'anonymous prepare denied');
SELECT pg_temp.ok(NOT has_table_privilege('authenticated','private.c03_document_events','INSERT'),'audit direct writes closed');
SELECT 'C03_DOCUMENT_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
