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

INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'job-'||current_setting('d.u')||'@example.test');
INSERT INTO public.operation_incidents(tenant_id,operation_id,title,description,category,is_blocking,status,reported_by)
VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,
 'FINANCIAL_CANARY_HISTORICAL_TITLE','FINANCIAL_CANARY_HISTORICAL_DETAIL','general',true,'open',current_setting('d.u')::uuid);
UPDATE public.memberships SET role='admin' WHERE user_id=current_setting('d.u')::uuid;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
VALUES(current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,'automations.manage','local-C03',current_setting('d.u')::uuid);
UPDATE public.automation_rules SET is_enabled=(code IN('operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale')) WHERE tenant_id=current_setting('d.t')::uuid;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT set_config('d.scope',public.rpc_delivery_prepare_automation(current_setting('d.t')::uuid,gen_random_uuid(),ARRAY[current_setting('d.u')::uuid])::text,true);
SELECT pg_temp.ok(current_setting('d.scope')::jsonb->>'id' IS NOT NULL,'explicit admin scope prepared');
SELECT pg_temp.ok(public.rpc_delivery_prepare_automation(current_setting('d.t')::uuid,gen_random_uuid(),ARRAY[current_setting('d.ng')::uuid])->>'error'='unauthorized','recipient without enterprise grant denied');
SELECT pg_temp.denied('SELECT private.c03_run_operational_scope(NULL,NULL,now())');
SELECT pg_temp.denied('SELECT * FROM private.c03_automation_scopes');
RESET ROLE;
SELECT set_config('d.run_request',gen_random_uuid()::text,true);
SELECT set_config('d.run',private.c03_run_operational_scope((current_setting('d.scope')::jsonb->>'id')::uuid,current_setting('d.run_request')::uuid,now()+interval '2 days')::text,true);
SELECT pg_temp.ok((current_setting('d.run')::jsonb->>'created')::int>0,'controlled clock creates bounded operational notifications');
SELECT pg_temp.ok(private.c03_run_operational_scope((current_setting('d.scope')::jsonb->>'id')::uuid,current_setting('d.run_request')::uuid,now()+interval '3 days')=current_setting('d.run')::jsonb,'same job request has one effect regardless of clock');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid AND company_id IS DISTINCT FROM current_setting('d.a')::uuid),'job never materializes other company');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.internal_notifications WHERE tenant_id=current_setting('d.x')::uuid),'job never touches other tenant');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid AND (area='finance' OR body LIKE '%54321%' OR body LIKE '%12345%' OR body LIKE '%FINANCIAL_CANARY%')),'worker has no financial candidates or payload');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid AND title LIKE '%FINANCIAL_CANARY%'),'worker never echoes unclassified historical incident title');
SELECT pg_temp.ok(NOT private.c03_operational_grant(current_setting('d.t')::uuid,current_setting('d.a')::uuid,current_setting('d.u')::uuid,'financial.full.read'),'worker helper cannot grant finance authority');
SELECT set_config('d.ncount',(SELECT count(*)::text FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid),true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(jsonb_array_length(public.rpc_delivery_notifications(current_setting('d.t')::uuid)->'items')>0,'partial operational notifications readable');
SELECT public.rpc_delivery_notifications(current_setting('d.t')::uuid)->>'unread_count';
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)::text FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid)=current_setting('d.ncount'),'automatic read does not materialize notifications');
SELECT pg_temp.ok((private.c03_run_operational_scope((current_setting('d.scope')::jsonb->>'id')::uuid,gen_random_uuid(),now()+interval '3 days')->>'created')::int=0,'new evaluation deduplicates logical notifications');
SELECT pg_temp.ok((SELECT count(*)::text FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid)=current_setting('d.ncount'),'notification count stable after retry');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_notification_action(current_setting('d.t')::uuid,'read',ARRAY[gen_random_uuid()])->>'error'='unauthorized','foreign notification ID denied');
SELECT pg_temp.ok(public.rpc_delivery_notification_action(current_setting('d.t')::uuid,'read',NULL)->>'success'='true','explicit read marking scoped to actor');
SELECT pg_temp.ok(public.rpc_delivery_notifications(current_setting('d.t')::uuid)->>'unread_count'='0','read status persists without rematerialization');
DO $$DECLARE r record;result jsonb;BEGIN
 FOR r IN SELECT * FROM jsonb_to_recordset(public.rpc_delivery_automation_status(current_setting('d.t')::uuid)->'rules')
 AS q(id uuid,target_role text,severity text,threshold_value int,threshold_unit text,escalation_delay_value int,escalation_delay_unit text,escalation_severity text,digest_enabled boolean) LOOP
  result:=public.rpc_delivery_update_automation(current_setting('d.t')::uuid,r.id,to_jsonb(r)-'id'||jsonb_build_object('is_enabled',false));
  PERFORM pg_temp.ok(result->>'success'='true','company rule override saved');
 END LOOP;
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=6 FROM private.c03_operational_rules(current_setting('d.t')::uuid,current_setting('d.b')::uuid) WHERE is_enabled),'company A overrides cannot disable company B rules');
SELECT pg_temp.ok((SELECT count(*)=6 FROM public.automation_rules WHERE tenant_id=current_setting('d.t')::uuid AND code LIKE 'operation_%' AND is_enabled),'tenant-wide settings preserved');
SELECT pg_temp.ok((private.c03_run_operational_scope((current_setting('d.scope')::jsonb->>'id')::uuid,gen_random_uuid(),now()+interval '3 days')->>'resolved')::int>0,'disabled scoped candidates resolve only own alerts');
UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.u')::uuid WHERE tenant_id=current_setting('d.t')::uuid AND company_id=current_setting('d.a')::uuid;
SELECT pg_temp.ok(private.c03_run_operational_scope((current_setting('d.scope')::jsonb->>'id')::uuid,gen_random_uuid(),now())->>'error'='scope_unavailable','scope stops after access revocation');
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_notifications(current_setting('d.t')::uuid)->>'error'='unauthorized','revocation invalidates notification reads');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=3 FROM private.c03_automation_runs WHERE scope_id=(current_setting('d.scope')::jsonb->>'id')::uuid),'only successful distinct runs audited');
SELECT pg_temp.ok(NOT has_function_privilege('service_role','public.rpc_delivery_run_automation(uuid,uuid,uuid)','EXECUTE'),'technical API has no unlimited job access');
SELECT 'C03_JOB_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
