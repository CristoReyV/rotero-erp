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

INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'child-'||current_setting('d.u')||'@example.test');
UPDATE public.memberships SET role='operator' WHERE user_id=current_setting('d.u')::uuid;
UPDATE public.operations SET operation_scope='international' WHERE id=current_setting('d.op')::uuid;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
SELECT current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,c,'local-C03',current_setting('d.u')::uuid
FROM unnest(ARRAY['operations.edit','operations.evidence.write'])c;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
CREATE FUNCTION pg_temp.child(action text,payload jsonb,key uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
SELECT public.rpc_delivery_operation_child_action(current_setting('d.t')::uuid,current_setting('d.op')::uuid,action,payload,
 COALESCE(key,gen_random_uuid()),(public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->>'workflow_revision')::bigint);
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.child('incident.create','{"category":"general","title":"Synthetic issue","description":"Operational detail","is_blocking":true}')->>'success'='true','create scoped operational incident');
SELECT set_config('d.incident',(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'incidents'->0->>'id'),true);
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'incidents'->0->>'description'='Operational detail','new typed detail available');
SELECT pg_temp.ok(pg_temp.child('incident.resolve',jsonb_build_object('id',current_setting('d.incident'),'note','Synthetic resolution'))->>'success'='true','resolve own scoped incident');
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'incidents'->0->>'resolution_note'='Synthetic resolution','latest immutable fact selected deterministically');
SELECT pg_temp.ok(pg_temp.child('incident.dismiss',jsonb_build_object('id',current_setting('d.incident'),'note','Synthetic discard'))->>'error'='invalid_status','resolved incident cannot be dismissed');
SELECT pg_temp.ok(pg_temp.child('evidence.add','{"kind":"external_link","external_url":"https://example.invalid/secret"}')->>'error'='invalid_payload','raw external evidence cannot bypass managed document scope');
SELECT pg_temp.ok(pg_temp.child('evidence.add',jsonb_build_object('kind','file_reference','file_id',current_setting('d.file'),'note','Synthetic attached evidence'))->>'success'='true','authorized operational file evidence');
SELECT pg_temp.ok(pg_temp.child('evidence.add','{"kind":"operational_note","note":"Synthetic note"}')->>'success'='true','typed operational note');
SELECT pg_temp.ok(pg_temp.child('document.save',jsonb_build_object('document_type','proof_of_delivery','requirement_level','required','status','present','file_id',current_setting('d.file'),'note','Synthetic POD'))->>'success'='true','canonical POD linked to own managed file');
SELECT pg_temp.ok(pg_temp.child('crossing.save','{"crossing_type":"entry","crossing_point":"Synthetic gate","note":"Synthetic crossing"}')->>'success'='true','international crossing records existing contract');
SELECT set_config('d.crossing',public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'crossings'->0->>'id',true);
SELECT pg_temp.ok(pg_temp.child('crossing.save',jsonb_build_object('id',current_setting('d.crossing'),'crossing_type','exit','crossing_point','Synthetic gate 2'))->>'success'='true','scoped crossing updated');
SELECT pg_temp.ok(pg_temp.child('compliance.override','{}')->>'error'='unauthorized','operator cannot override compliance');
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.ob')::uuid)->>'error'='unauthorized','foreign company children denied');
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)::text NOT LIKE '%FINANCIAL_CANARY%','child projections omit existing financial notes');
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)::text NOT LIKE '%external_url%','no legacy raw file URL returned');
SELECT pg_temp.ok(pg_temp.child('crossing.delete',jsonb_build_object('id',current_setting('d.crossing')))->>'success'='true','existing crossing deletion stays audited');
SELECT pg_temp.denied('SELECT * FROM private.c03_child_facts');
SELECT pg_temp.denied('SELECT private.delivery_core_858e88dcd8810a3be8d7(NULL,NULL,NULL,NULL,NULL,NULL)');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=8 FROM private.c03_child_facts WHERE tenant_id=current_setting('d.t')::uuid),'only successful actions record immutable facts');
SELECT pg_temp.ok((SELECT workflow_revision=8 FROM public.operations WHERE id=current_setting('d.op')::uuid),'all successful child actions advance version');
SELECT 'C03_CHILD_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
