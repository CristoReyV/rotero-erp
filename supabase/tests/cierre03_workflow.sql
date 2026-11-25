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

-- Synthetic prerequisites are local fixtures, never fabricated staging delivery
-- or fiscal evidence. No provider, public Tracking or Auth HTTP call is made.
INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'flow-'||current_setting('d.u')||'@example.test');
UPDATE public.memberships SET role='operator' WHERE user_id=current_setting('d.u')::uuid;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
SELECT current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,c,'local-C03',current_setting('d.u')::uuid
FROM unnest(ARRAY['operations.capture','operations.edit','operations.plan','operations.assign','operations.transition'])c;
INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(current_setting('d.t')::uuid,'Synthetic workflow carrier');
SELECT set_config('d.provider',(SELECT id::text FROM public.logistics_providers WHERE tenant_id=current_setting('d.t')::uuid LIMIT 1),true);
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
CREATE FUNCTION pg_temp.act(op uuid,action text,payload jsonb) RETURNS jsonb LANGUAGE sql AS $$
SELECT public.rpc_delivery_operation_action(current_setting('d.t')::uuid,op,action,payload,gen_random_uuid(),
 (public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,op)->>'workflow_revision')::bigint);
$$;
SET LOCAL ROLE authenticated;
SELECT set_config('d.createkey',gen_random_uuid()::text,true);
SELECT set_config('d.created',public.rpc_delivery_create_operation_once(current_setting('d.t')::uuid,current_setting('d.createkey')::uuid,'C03-NEW','Synthetic route','Synthetic customer','Synthetic destination')::text,true);
SELECT pg_temp.ok(current_setting('d.created')::jsonb->>'success'='true','create company operation explicitly');
SELECT set_config('d.flow',current_setting('d.created')::jsonb->>'id',true);
SELECT pg_temp.ok(public.rpc_delivery_create_operation_once(current_setting('d.t')::uuid,current_setting('d.createkey')::uuid,'C03-NEW','Synthetic route','Synthetic customer','Synthetic destination')=current_setting('d.created')::jsonb,'create retry reuses one receipt');
SELECT pg_temp.ok(public.rpc_delivery_create_operation_once(current_setting('d.t')::uuid,current_setting('d.createkey')::uuid,'DIFFERENT')->>'error'='request_conflict','create key cannot be reused with different content');
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'plan',jsonb_build_object('service_type','Synthetic general',
 'origin_place',jsonb_build_object('countryCode','MX','state','QA','municipality','A'),'destination_place',jsonb_build_object('countryCode','MX','state','QA','municipality','B'),
 'operational_window_start',now()-interval '5 hours','operational_window_end',now()+interval '5 hours','route_summary','Synthetic route','destination_city','Synthetic destination',
 'operation_scope','national','execution_type','third_party','cargo_summary',jsonb_build_object('description','Synthetic cargo')))->>'success'='true','plan newly captured operation');
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'assign',jsonb_build_object('execution_type','third_party','provider_id',current_setting('d.provider'),
 'planned_departure',now()+interval '1 hour','reason','Local synthetic provider assignment'))->>'success'='true','assign existing provider without mandatory external driver or unit');
SELECT pg_temp.ok(jsonb_array_length(public.rpc_delivery_operation_history(current_setting('d.t')::uuid,current_setting('d.flow')::uuid))=1,'assignment history available in scoped 360');
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"in_transit"}')->>'error'='tracking_not_ready','tracking readiness not bypassed');
RESET ROLE;
INSERT INTO public.tracking_tokens(tenant_id,operation_id,scope,token_hash,created_by,expires_at)
SELECT current_setting('d.t')::uuid,current_setting('d.flow')::uuid,s,encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),current_setting('d.u')::uuid,now()+interval '1 hour'
FROM unnest(ARRAY['driver:write','public:read'])s;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"in_transit"}')->>'success'='true','in-transit transition with local synthetic prerequisites');
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"delivered"}')->>'error'='missing_delivered_event','delivery cannot be asserted without Tracking event');
RESET ROLE;
INSERT INTO public.tracking_events(token_id,tenant_id,operation_id,event_type,source,client_timestamp)
SELECT id,tenant_id,operation_id,'delivered','none',now() FROM public.tracking_tokens WHERE operation_id=current_setting('d.flow')::uuid AND scope='driver:write';
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"delivered"}')->>'success'='true','delivery transition with local synthetic event');
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"closed"}')->>'error'='billing_not_issued','close cannot bypass existing billing contract');
RESET ROLE;
INSERT INTO public.operation_billing(tenant_id,operation_id,status,billing_reference,issued_at,issued_by)
VALUES(current_setting('d.t')::uuid,current_setting('d.flow')::uuid,'issued','LOCAL-SYNTHETIC-NO-CFDI',now(),current_setting('d.u')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.act(current_setting('d.flow')::uuid,'transition','{"to_status":"closed"}')->>'success'='true','close with synthetic local-only billing prerequisite');
SELECT pg_temp.ok(public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.flow')::uuid)->>'status'='closed','final state persisted');
SELECT pg_temp.ok(public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.flow')::uuid)::text NOT LIKE '%LOCAL-SYNTHETIC-NO-CFDI%','operational payload never returns financial document reference');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.operations WHERE tenant_id=current_setting('d.t')::uuid AND reference_code='C03-NEW'),'create idempotency persisted one root');
SELECT 'C03_WORKFLOW_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
