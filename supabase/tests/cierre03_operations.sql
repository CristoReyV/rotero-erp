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

-- Additional CIERRE-03 fixtures remain local and roll back with the base fixture.
UPDATE public.memberships SET role='operator' WHERE user_id=current_setting('d.u')::uuid AND tenant_id=current_setting('d.t')::uuid;
INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'c03-'||current_setting('d.u')||'@example.test'),(current_setting('d.ng')::uuid,'c03-'||current_setting('d.ng')||'@example.test');
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
SELECT current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,c,'local-synthetic-C03',current_setting('d.ng')::uuid
FROM unnest(ARRAY['operations.edit','operations.plan','operations.assign','operations.transition'])c;
DO $$DECLARE p uuid;x uuid;BEGIN
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(current_setting('d.t')::uuid,'C03 Synthetic carrier') RETURNING id INTO p;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(current_setting('d.x')::uuid,'C03 Foreign carrier') RETURNING id INTO x;
 PERFORM set_config('c03.p',p::text,true);PERFORM set_config('c03.xp',x::text,true);
END $$;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
CREATE FUNCTION pg_temp.command(action text,payload jsonb,request uuid,rev bigint,operation uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.rpc_delivery_operation_action(current_setting('d.t')::uuid,COALESCE(operation,current_setting('d.op')::uuid),action,payload,request,rev);$$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;req uuid:=gen_random_uuid();payload jsonb;BEGIN
 r:=public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.op')::uuid);
 PERFORM pg_temp.ok(r ? 'workflow_revision' AND NOT(r ?| ARRAY['provider_cost_amount','customer_price_amount','notes','service_catalog_snapshot']),'C03 partial workflow DTO excludes economics');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"company_id":"00000000-0000-0000-0000-000000000000"}',gen_random_uuid(),0)->>'error'='invalid_payload','C03 ownership identifier cannot be patched');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"provider_cost_amount":1}',gen_random_uuid(),0)->>'error'='financial_write_forbidden','C03 partial cannot change cost');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"route_summary":"C03"}',gen_random_uuid(),0,current_setting('d.ob')::uuid)->>'error'='unauthorized','C03 foreign company direct ID');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"route_summary":"C03"}',gen_random_uuid(),0,current_setting('d.ox')::uuid)->>'error'='unauthorized','C03 foreign tenant direct ID');
 PERFORM pg_temp.ok(pg_temp.command('control','{"cargo_summary":{"description":{"provider_cost_amount":1}}}',gen_random_uuid(),0)->>'error'='invalid_cargo_summary','C03 nested economic container rejected');
 PERFORM pg_temp.ok(public.rpc_update_operation_details(current_setting('d.op')::uuid,'{"route_summary":"bypass"}')->>'error'='company_adoption_pending','C03 old mutation remains closed');
 payload:=jsonb_build_object('service_type','C03 synthetic freight','origin_place',jsonb_build_object('countryCode','MX','state','Synthetic','municipality','QA A'),
 'destination_place',jsonb_build_object('countryCode','MX','state','Synthetic','municipality','QA B'),
 'operational_window_start',now()+interval '1 hour','operational_window_end',now()+interval '3 hours','cargo_summary',jsonb_build_object('description','Synthetic freight'),
 'route_summary','C03 A to B','operation_scope','national','execution_type','third_party');
 -- The base op is delivered to test reports; use a separately created draft for
 -- planning, preserving the base fixture's business preconditions.
 PERFORM set_config('c03.plan',payload::text,true);
END $$;
RESET ROLE;
DO $$DECLARE op uuid;BEGIN
 INSERT INTO public.operations(tenant_id,reference_code,status,provider_cost_amount,customer_price_amount,pricing_currency,notes,service_catalog_snapshot,cargo_summary)
 VALUES(current_setting('d.t')::uuid,'C03-WORKFLOW','draft',12345,54321,'USD','C03_FINANCIAL_CANARY','{"internal_cost":12345}','{"internal_cost":9876,"description":"Synthetic"}') RETURNING id INTO op;
 PERFORM pg_temp.resolve('operations',op,current_setting('d.a')::uuid);PERFORM set_config('c03.op',op::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;again jsonb;req uuid:=gen_random_uuid();op uuid:=current_setting('c03.op')::uuid;BEGIN
 r:=pg_temp.command('plan',current_setting('c03.plan')::jsonb,req,0,op);
 PERFORM pg_temp.ok(r->>'success'='true' AND r->>'workflow_revision'='1','C03 operator plans with explicit grant');
 PERFORM pg_temp.ok(NOT(r ?| ARRAY['provider_cost_amount','customer_price_amount','notes','service_catalog_snapshot']),'C03 write response is minimal');
 again:=pg_temp.command('plan',current_setting('c03.plan')::jsonb,req,0,op);
 PERFORM pg_temp.ok(again=r,'C03 same request id replays exactly one result');
 PERFORM pg_temp.ok(pg_temp.command('plan',current_setting('c03.plan')::jsonb||'{"route_summary":"changed"}',req,0,op)->>'error'='request_conflict','C03 request id cannot change payload');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"route_summary":"stale"}',gen_random_uuid(),0,op)->>'error'='stale_operation','C03 stale UI cannot overwrite');
 PERFORM pg_temp.ok(pg_temp.command('plan',current_setting('c03.plan')::jsonb||jsonb_build_object('operational_window_end',now()),gen_random_uuid(),1,op)->>'error'='invalid_operational_window','C03 invalid plan business rule retained');
 PERFORM pg_temp.ok(pg_temp.command('assign',jsonb_build_object('provider_id',current_setting('c03.xp'),'planned_departure',now()+interval '1 hour'),gen_random_uuid(),1,op)->>'error'='invalid_provider','C03 provider from another tenant denied');
 r:=pg_temp.command('assign',jsonb_build_object('provider_id',current_setting('c03.p'),'planned_departure',now()+interval '1 hour'),gen_random_uuid(),1,op);
 PERFORM pg_temp.ok(r->>'success'='true','C03 third-party assignment requires provider; driver/unit optional');
 PERFORM pg_temp.ok(pg_temp.command('transition','{"to_status":"closed"}',gen_random_uuid(),2,op)->>'error'='invalid_transition','C03 cannot skip transition prerequisites');
 PERFORM pg_temp.ok(pg_temp.command('transition','{"to_status":"in_transit"}',gen_random_uuid(),2,op)->>'error'='tracking_not_ready','C03 missing Tracking remains a denial');
 PERFORM pg_temp.ok(pg_temp.command('edit','{"route_summary":"C03 edited"}',gen_random_uuid(),2,op)->>'success'='true','C03 explicit edit succeeds');
 PERFORM pg_temp.denied('SELECT * FROM private.c03_operation_commands');
 PERFORM pg_temp.denied('SELECT private.c03_core_edit(NULL,''{}'')');
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT provider_cost_amount=12345 AND customer_price_amount=54321 AND pricing_currency='USD' AND notes='C03_FINANCIAL_CANARY'
 AND service_catalog_snapshot='{"internal_cost":12345}' AND cargo_summary->>'internal_cost'='9876' FROM public.operations WHERE id=current_setting('c03.op')::uuid),'C03 partial plan preserves all prior economics and notes');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private.c03_operation_commands WHERE operation_id=current_setting('c03.op')::uuid AND action='plan' AND outcome->>'success'='true'),'C03 retry does not duplicate receipt/effect');
SELECT pg_temp.actor(current_setting('d.ng')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.command('edit','{"route_summary":"denied"}',gen_random_uuid(),3,current_setting('c03.op')::uuid)->>'error'='unauthorized','C03 admin without grants denied');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.ng')::uuid
WHERE tenant_id=current_setting('d.t')::uuid AND user_id=current_setting('d.u')::uuid AND capability_code='operations.edit';
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.command('edit','{"route_summary":"revoked"}',gen_random_uuid(),3,current_setting('c03.op')::uuid)->>'error'='unauthorized','C03 work grant revocation effective');
RESET ROLE;
UPDATE public.companies SET status='inactive' WHERE id=current_setting('d.a')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.command('plan',current_setting('c03.plan')::jsonb,gen_random_uuid(),3,current_setting('c03.op')::uuid)->>'error'='unauthorized','C03 inactive company denies action');
RESET ROLE;
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.rpc_delivery_operation_action(uuid,uuid,text,jsonb,uuid,bigint)','EXECUTE'),'C03 anonymous denied by ACL');
DO $$DECLARE op uuid;clock_before timestamptz:=now()-interval '2 hours';BEGIN
 INSERT INTO public.operations(tenant_id,reference_code,created_at,updated_at)
 VALUES(current_setting('d.t')::uuid,'C03-CLOCK-ONLY',now()-interval '72 hours',clock_before) RETURNING id INTO op;
 UPDATE public.operations SET workflow_revision=workflow_revision+1 WHERE id=op;
 PERFORM pg_temp.ok((SELECT updated_at=clock_before AND workflow_revision=1 FROM public.operations WHERE id=op),'revision bookkeeping preserves approved business duration clock');
END $$;
SELECT 'PASS CIERRE03 operational commands; assertions='||current_setting('d.assertions');
ROLLBACK;
