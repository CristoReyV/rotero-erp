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

DO $$DECLARE u uuid:=gen_random_uuid();binding uuid;t uuid:=current_setting('d.t')::uuid;BEGIN
 INSERT INTO auth.users(id,email) VALUES(u,'financial-doc-'||u::text||'@example.test');
 INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(t,u,'finance');
 INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(t,u,current_setting('d.a')::uuid,current_setting('d.u')::uuid);
 INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,identity_issuer,approval_reference,verified_by,verified_at)
 VALUES(t,u,'approved_financial_01','verified_human','https://synthetic-access.invalid/auth/v1','local synthetic permission combination',current_setting('d.u')::uuid,now()-interval '1 minute') RETURNING id INTO binding;
 INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
 SELECT t,u,current_setting('d.a')::uuid,c,CASE WHEN c='financial.full.read' THEN binding END,'local synthetic C03',current_setting('d.u')::uuid
 FROM unnest(ARRAY['financial.full.read','finance.write','billing.document.read','documents.upload','documents.manage'])c;
 PERFORM set_config('d.full',u::text,true);PERFORM set_config('d.binding',binding::text,true);
END $$;
CREATE FUNCTION pg_temp.financial_prepare() RETURNS jsonb LANGUAGE sql AS $$
SELECT public.rpc_delivery_prepare_upload(current_setting('d.t')::uuid,gen_random_uuid(),jsonb_build_object('entity_type','finance_invoice',
 'entity_id',current_setting('d.invoice'),'access_class','financial','file_name','c03-financial.txt','mime_type','text/plain','size_bytes',12,'checksum_sha256',repeat('c',64)));
$$;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.financial_prepare()->>'error'='unauthorized','finance membership alone cannot upload financial evidence');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.full')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT set_config('d.fin_upload',pg_temp.financial_prepare()::text,true);
SELECT pg_temp.ok(current_setting('d.fin_upload')::jsonb->>'id' IS NOT NULL,'verified full plus write permits financial upload');
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tenant-documents',current_setting('d.fin_upload')::jsonb->>'path',current_setting('d.full'),'{"size":12,"mimetype":"text/plain"}');
SELECT set_config('d.fin_file',public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.fin_upload')::jsonb->>'id')::uuid)->>'id',true);
SELECT pg_temp.ok(current_setting('d.fin_file')<>'' AND public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.fin_file')::uuid)->>'id'=current_setting('d.fin_file'),'full financial download authorized');
SELECT pg_temp.ok(jsonb_array_length(public.rpc_delivery_document_history(current_setting('d.t')::uuid,'finance_invoice',current_setting('d.invoice')::uuid)->'items')=1,'financial versions visible to explicit full reader');
RESET ROLE;
-- The third supported parent is a local draft, not an issued fiscal document.
SET LOCAL ROLE rotero_finance_scope_owner;
GRANT SELECT,INSERT ON private.billing_documents_company_evidence TO postgres;
RESET ROLE;
DO $$DECLARE doc uuid;e uuid;BEGIN
 INSERT INTO public.billing_documents(tenant_id,operation_id,status,created_by)
 VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'draft',current_setting('d.full')::uuid) RETURNING id INTO doc;
 INSERT INTO private.billing_documents_company_evidence(tenant_id,entity_id,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES(current_setting('d.t')::uuid,doc,current_setting('d.a')::uuid,'resolved','verified_source_record','LOCAL SYNTHETIC DRAFT',current_setting('d.full')::uuid) RETURNING id INTO e;
 UPDATE public.billing_documents SET company_id=current_setting('d.a')::uuid,company_classification_status='resolved',company_classification_event_id=e WHERE id=doc;
 PERFORM set_config('d.billing_document',doc::text,true);
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('d.bill_upload',public.rpc_delivery_prepare_upload(current_setting('d.t')::uuid,gen_random_uuid(),
 jsonb_build_object('entity_type','billing_document','entity_id',current_setting('d.billing_document'),'access_class','financial',
 'file_name','c03-billing-draft.txt','mime_type','text/plain','size_bytes',12,'checksum_sha256',repeat('d',64)))::text,true);
SELECT pg_temp.ok(current_setting('d.bill_upload')::jsonb->>'id' IS NOT NULL,'full plus explicit write permits billing draft file');
INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tenant-documents',current_setting('d.bill_upload')::jsonb->>'path',current_setting('d.full'),'{"size":12,"mimetype":"text/plain"}');
SELECT set_config('d.bill_file',public.rpc_delivery_finalize_upload(current_setting('d.t')::uuid,(current_setting('d.bill_upload')::jsonb->>'id')::uuid)->>'id',true);
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.bill_file')::uuid)->>'id'=current_setting('d.bill_file'),'billing draft authenticated download positive');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_document_history(current_setting('d.t')::uuid,'billing_document',current_setting('d.billing_document')::uuid)->>'error'='unauthorized','partial cannot enumerate billing parent files');
SELECT pg_temp.ok((SELECT count(*)=0 FROM storage.objects WHERE name=current_setting('d.bill_upload')::jsonb->>'path'),'partial direct Storage denied for billing parent');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.full')::uuid,current_setting('d.a')::uuid);
DO $$DECLARE payroll uuid:=gen_random_uuid();BEGIN
 IF to_regclass('public.payroll_periods') IS NOT NULL THEN
  EXECUTE 'INSERT INTO public.payroll_periods(id,tenant_id,name,period_start,period_end) VALUES($1,$2,$3,current_date,current_date+14)'
   USING payroll,current_setting('d.t')::uuid,'C03 SYNTHETIC ROLLBACK';
 END IF;
 UPDATE public.finance_invoices SET payroll_period_id=payroll WHERE id=current_setting('d.invoice')::uuid;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.financial_prepare()->>'error'='unauthorized','direct IDs cannot bypass existing Finance payroll exclusion');
RESET ROLE;
UPDATE public.finance_invoices SET payroll_period_id=NULL WHERE id=current_setting('d.invoice')::uuid;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.fin_file')::uuid)->>'error'='unauthorized','partial reader cannot download financial file by ID');
SELECT pg_temp.ok((SELECT count(*)=0 FROM storage.objects WHERE name=current_setting('d.fin_upload')::jsonb->>'path'),'direct Storage cannot bypass financial classification');
SELECT pg_temp.ok(public.rpc_delivery_document_history(current_setting('d.t')::uuid,'finance_invoice',current_setting('d.invoice')::uuid)->>'error'='unauthorized','financial metadata denied to partial reader');
RESET ROLE;
UPDATE private.financial_principal_bindings SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.u')::uuid WHERE id=current_setting('d.binding')::uuid;
SELECT pg_temp.actor(current_setting('d.full')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.fin_file')::uuid)->>'error'='unauthorized','binding revocation closes authenticated file downloads');
SELECT pg_temp.ok((SELECT count(*)=0 FROM storage.objects WHERE name=current_setting('d.fin_upload')::jsonb->>'path'),'binding revocation closes direct Storage');
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.bill_file')::uuid)->>'error'='unauthorized','binding revocation also closes billing parent');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=1 FROM storage.objects WHERE name=current_setting('d.fin_upload')::jsonb->>'path'),'financial bytes retained after revocation');
SELECT 'C03_FINANCIAL_DOCUMENT_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
