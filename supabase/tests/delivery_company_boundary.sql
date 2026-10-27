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

SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;op uuid:=current_setting('d.op')::uuid;t uuid:=current_setting('d.t')::uuid;BEGIN
 r:=public.rpc_delivery_context(t);PERFORM pg_temp.ok(jsonb_array_length(r->'companies')=2,'only explicit companies');
 r:=public.rpc_delivery_operations_page(t);PERFORM pg_temp.ok((r->>'total')::int=3 AND jsonb_array_length(r->'items')=3,'scoped list/count');
 PERFORM pg_temp.ok(r::text NOT LIKE '%12345%' AND r::text NOT LIKE '%54321%' AND r::text NOT LIKE '%FINANCIAL_CANARY%','no financial fields in list');
 r:=public.rpc_delivery_operations_page(t,'A-',NULL,1,true);PERFORM pg_temp.ok((r->>'total')::int=3 AND jsonb_array_length(r->'items')=1 AND r->>'next_cursor' IS NOT NULL,'search pagination export same scope');
 PERFORM pg_temp.ok(public.rpc_delivery_operations_page(t,'',current_setting('d.ob')::uuid)->>'error'='invalid_cursor','foreign cursor');
 r:=public.rpc_get_operation(op);PERFORM pg_temp.ok(r->>'id'=op::text AND NOT(r ?| ARRAY['notes','provider_cost_amount','customer_price_amount','service_catalog_snapshot','cargo_summary']),'safe detail');
 PERFORM pg_temp.ok(public.rpc_get_operation(current_setting('d.ob')::uuid)->>'error'='unauthorized','direct other-company ID');
 PERFORM pg_temp.ok(public.rpc_get_operation(current_setting('d.ox')::uuid)->>'error'='unauthorized','direct other-tenant ID');
 PERFORM pg_temp.ok(public.rpc_get_operation(current_setting('d.pending')::uuid)->>'error'='unauthorized','unclassified denied');
 r:=public.rpc_reports_tanda1(t,NULL,NULL);PERFORM pg_temp.ok((SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(r)key)=ARRAY['by_scope','by_service_type','by_zone','date_from','date_to','volume','weekly'],'Tanda1 seven keys unchanged');
 PERFORM pg_temp.ok((r->'volume'->>'operations')::int=3,'Tanda1 scoped volume');
 r:=public.rpc_reports_operations_summary(t);PERFORM pg_temp.ok((r->>'avg_delivery_time')::numeric=71.4 AND r ? 'active_routes_count','71.4-hour metric retained after classification');
 PERFORM pg_temp.ok(public.rpc_reports_financial_summary(t,'monthly')->>'error'='unauthorized','finance role not full read');
 r:=public.rpc_delivery_receivables_page(t);PERFORM pg_temp.ok((r->>'total')::int=1 AND r->'items'->0->>'amount'='1000.00','AR legitimate monetary projection');
 PERFORM pg_temp.ok(r::text NOT LIKE '%88888%' AND r::text NOT LIKE '%77777%' AND NOT(r->'items'->0 ?| ARRAY['notes','provider_cost_amount','margin','payroll_period_id']),'AR excludes AP/foreign/financial fields');
 PERFORM pg_temp.ok(public.rpc_delivery_receivables_page(t,'',NULL,1,true)->>'total'='1','AR export authorized');
 r:=public.rpc_delivery_operation_files(t,op);PERFORM pg_temp.ok(jsonb_array_length(r->'items')=1,'operation document metadata');
 PERFORM pg_temp.ok(public.rpc_delivery_file_download(t,current_setting('d.file')::uuid)->>'file_name'='synthetic.txt','authorized download locator');
 PERFORM pg_temp.ok(public.rpc_global_search(t,'A',20)->>'error'='company_adoption_pending','legacy broad search cannot bypass');
 PERFORM pg_temp.ok(public.rpc_refresh_internal_notifications(t)->>'error'='company_adoption_pending','materialization not triggered');
 PERFORM pg_temp.ok(public.rpc_evaluate_automations(t)->>'error'='company_adoption_pending','automation denied without scoped adoption');
 PERFORM pg_temp.ok(public.rpc_delivery_notifications(t)->'items'='[]'::jsonb,'read-only notifications exclude unclassified/full data');
 PERFORM pg_temp.denied('SELECT * FROM public.operations');PERFORM pg_temp.denied('SELECT * FROM public.finance_invoices');
 PERFORM pg_temp.denied('SELECT * FROM private.delivery_operations');
 PERFORM pg_temp.denied('INSERT INTO public.membership_company_access DEFAULT VALUES');
 PERFORM pg_temp.denied('INSERT INTO private.delivery_classification_events DEFAULT VALUES');
END $$;
RESET ROLE;

-- An explicit collection grant permits only the authorized AR, preserving F4
-- rounding and balance arithmetic. No fiscal complement is created implicitly.
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
VALUES(current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,'receivables.collect','synthetic-only',current_setting('d.u')::uuid);
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;t uuid:=current_setting('d.t')::uuid;BEGIN
 r:=public.rpc_delivery_record_receivable_payment(t,jsonb_build_object('invoice_id',current_setting('d.invoice'),'amount',100,'currency','MXN'));
 PERFORM pg_temp.ok(r->>'success'='true' AND (r->>'remaining_balance')::numeric=900,'explicit AR collection');
 PERFORM pg_temp.ok(r->>'complement_id' IS NULL,'collection does not implicitly prepare fiscal');
 r:=public.rpc_delivery_receivables_page(t);PERFORM pg_temp.ok((r->'items'->0->>'paid_amount')::numeric=100 AND (r->'items'->0->>'balance_amount')::numeric=900,'AR updated balances');
 PERFORM pg_temp.ok(public.rpc_record_payment(t,jsonb_build_object('invoice_id',current_setting('d.invoice'),'amount',1))->>'error'='unauthorized','AR collector cannot use full writer');
 PERFORM pg_temp.ok(public.rpc_delivery_record_receivable_payment(t,jsonb_build_object('invoice_id',current_setting('d.invoice'),'amount',1,'company_id',current_setting('d.b')))->>'error'='invalid_payload','AR ownership manipulation denied');
END $$;
RESET ROLE;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
VALUES(current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,'operations.capture','synthetic-only',current_setting('d.u')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_create_operation(current_setting('d.t')::uuid,'FINANCE-CAPTURE')->>'error'='unauthorized','finance role cannot inherit operational writer');
RESET ROLE;
UPDATE public.memberships SET role='operator' WHERE tenant_id=current_setting('d.t')::uuid AND user_id=current_setting('d.u')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;t uuid:=current_setting('d.t')::uuid;BEGIN
 r:=public.rpc_delivery_create_operation(t,'NEW-EXPLICIT','A to B','Synthetic customer');
 PERFORM pg_temp.ok(r->>'id' IS NOT NULL AND r->>'company_id'=current_setting('d.a'),'explicit operational capture classified atomically');
 PERFORM pg_temp.ok(public.rpc_get_operation((r->>'id')::uuid)->>'reference_code'='NEW-EXPLICIT','new capture readable in same company');
END $$;
RESET ROLE;
SELECT pg_temp.ok(NOT has_column_privilege('rotero_delivery_capture_owner','public.operations','provider_cost_amount','SELECT')
 AND NOT has_column_privilege('rotero_delivery_capture_owner','public.operations','customer_price_amount','UPDATE'),'capture owner cannot read/write costs');
SELECT pg_temp.ok(NOT pg_has_role('authenticated','rotero_delivery_capture_owner','MEMBER'),'API cannot assume writer');

-- A separate synthetic verified human proves full/consolidated paths locally.
-- This is not the technical QA identity and is never assigned remotely.
DO $$ DECLARE u uuid:=gen_random_uuid();b uuid;t uuid:=current_setting('d.t')::uuid;c uuid;BEGIN
 INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance');
 INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,identity_issuer,approval_reference,verified_by,verified_at)
 VALUES(t,u,'approved_financial_01','verified_human','https://synthetic-access.invalid/auth/v1','local-synthetic-proof',current_setting('d.u')::uuid,now()-interval '1 minute') RETURNING id INTO b;
 FOREACH c IN ARRAY ARRAY[current_setting('d.a')::uuid,current_setting('d.b')::uuid] LOOP
  INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(t,u,c,current_setting('d.u')::uuid);
  INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
  SELECT t,u,c,cap,CASE WHEN cap IN('financial.full.read','export.financial') THEN b END,'local-synthetic-proof',current_setting('d.u')::uuid
  FROM unnest(ARRAY['financial.full.read','export.financial','operations.read','finance.write'])cap;
 END LOOP;
 PERFORM set_config('d.full',u::text,true);PERFORM set_config('d.binding',b::text,true);
END $$;
SELECT pg_temp.actor(current_setting('d.full')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;t uuid:=current_setting('d.t')::uuid;BEGIN
 r:=public.rpc_reports_financial_summary(t,'monthly');
 PERFORM pg_temp.ok((r->>'total_revenue_ytd')::numeric=1000 AND (r->>'total_expenses_ytd')::numeric=88888,'financial formulas scoped to A without unrelated B');
 PERFORM pg_temp.ok(public.rpc_get_operation(current_setting('d.op')::uuid)->>'provider_cost_amount'='12345.00','full authorized operation economics');
 r:=public.rpc_list_finance_invoices(t,'{}'::jsonb);PERFORM pg_temp.ok(jsonb_array_length(r->'items')=2 AND r::text NOT LIKE '%77777%','legacy Finance listing scoped before joins');
 r:=public.rpc_create_finance_invoice(t,jsonb_build_object('direction','ar','counterparty_name','Synthetic new','reference','AR-created','amount',10,'currency','MXN'));
 PERFORM pg_temp.ok(r->>'id' IS NOT NULL AND r->>'error' IS NULL,'full write explicit action');
 PERFORM set_config('d.created_invoice',r->>'id',true);
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT company_id=current_setting('d.a')::uuid AND company_classification_status='resolved'
 FROM public.finance_invoices WHERE id=current_setting('d.created_invoice')::uuid),'new Finance record has evidence-backed company');
SELECT set_config('request.headers',jsonb_build_object('x-rotero-scope','consolidated','x-rotero-company-ids',jsonb_build_array(current_setting('d.a'),current_setting('d.b'))::text)::text,true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_reports_financial_summary(current_setting('d.t')::uuid,'monthly')->>'error'='unauthorized','two full grants do not imply consolidation');
RESET ROLE;
DO $$ DECLARE g uuid;t uuid:=current_setting('d.t')::uuid;u uuid:=current_setting('d.full')::uuid;BEGIN
 INSERT INTO public.membership_consolidation_grants(tenant_id,user_id,financial_binding_id,approval_reference,granted_by)
 VALUES(t,u,current_setting('d.binding')::uuid,'local-synthetic-proof',current_setting('d.u')::uuid) RETURNING id INTO g;
 INSERT INTO public.consolidation_grant_companies(tenant_id,user_id,consolidation_grant_id,company_id)
 VALUES(t,u,g,current_setting('d.a')::uuid),(t,u,g,current_setting('d.b')::uuid);
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok((public.rpc_reports_financial_summary(current_setting('d.t')::uuid,'monthly')->>'total_revenue_ytd')::numeric=78787,'explicit exact consolidated set');
SELECT pg_temp.ok(jsonb_array_length(public.rpc_delivery_context(current_setting('d.t')::uuid)->'consolidations')=1,'only authorized consolidation advertised');
RESET ROLE;
UPDATE private.financial_principal_bindings SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.u')::uuid
WHERE id=current_setting('d.binding')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_reports_financial_summary(current_setting('d.t')::uuid,'monthly')->>'error'='unauthorized','binding revocation closes consolidation');
RESET ROLE;
SELECT pg_temp.ok(private.f7_materialize_automation_notifications(current_setting('d.t')::uuid,current_setting('d.u')::uuid,'manual',now())->>'reason'='company_job_authorization_pending','job skipped before materialization');
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.internal_notifications WHERE tenant_id=current_setting('d.t')::uuid),'no protected tenant job notification writes');

-- A temporary SELECT grant cannot defeat restrictive RLS, even with a valid scope.
GRANT SELECT ON public.operations,public.finance_invoices TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok((SELECT count(*)=0 FROM public.operations),'direct operations RLS');
-- Its existing private finance policy also denies EXECUTE to the API role.
SELECT pg_temp.denied('SELECT count(*) FROM public.finance_invoices');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,NULL);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_list_operations(current_setting('d.t')::uuid)->>'error'='unauthorized','removing headers cannot bypass cutover');
SELECT pg_temp.ok(public.rpc_get_operation(current_setting('d.op')::uuid)->>'error'='unauthorized','ID call cannot strip scope');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.ng')::uuid,current_setting('d.a')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_operations_page(current_setting('d.t')::uuid)->>'error'='unauthorized','admin without grants');
SELECT pg_temp.ok(public.rpc_reports_financial_summary(current_setting('d.t')::uuid,'monthly')->>'error'='unauthorized','admin without financial binding');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.b')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_operations_page(current_setting('d.t')::uuid)->>'error'='unauthorized','company access alone no capability');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.xc')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_operations_page(current_setting('d.t')::uuid)->>'error'='unauthorized','tenant company mismatch');
RESET ROLE;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by=current_setting('d.u')::uuid
WHERE tenant_id=current_setting('d.t')::uuid AND company_id=current_setting('d.a')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(public.rpc_delivery_operations_page(current_setting('d.t')::uuid)->>'error'='unauthorized','revoked access immediately effective');
SELECT pg_temp.ok(public.rpc_delivery_file_download(current_setting('d.t')::uuid,current_setting('d.file')::uuid)->>'error'='unauthorized','revoked file access');
RESET ROLE;
SELECT pg_temp.actor(NULL,NULL);
SET LOCAL ROLE anon;
SELECT pg_temp.denied('SELECT public.rpc_delivery_operations_page(NULL)');
RESET ROLE;
SELECT 'PASS: company boundary, legacy denials, minimal DTO, AR amounts, document authorization, effective RLS/ACL, revocation';
SELECT 'Assertions executed: '||current_setting('d.assertions');
ROLLBACK;
