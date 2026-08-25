\set ON_ERROR_STOP on
BEGIN;

DO $contract$
DECLARE signature text; proc_oid oid;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='customers' AND column_name='contact_name')
     OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='logistics_providers' AND column_name='contact_name') THEN
    RAISE EXCEPTION 'BH1 contact compatibility surface missing';
  END IF;
  FOREACH signature IN ARRAY ARRAY[
    'public.rpc_create_invitation(uuid,text,text)','public.rpc_list_descargo_lines(uuid)','public.rpc_add_descargo_line(uuid,jsonb)',
    'public.rpc_list_deal_notes(uuid)','public.rpc_list_deal_checklist(uuid)',
    'public.rpc_demo_configure_module(uuid,text)'
  ] LOOP
    proc_oid:=to_regprocedure(signature);
    IF proc_oid IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=proc_oid AND prosecdef)
       OR NOT has_function_privilege('authenticated',proc_oid,'EXECUTE')
       OR has_function_privilege('anon',proc_oid,'EXECUTE')
       OR has_function_privilege('service_role',proc_oid,'EXECUTE')
       OR pg_get_functiondef(proc_oid)~*'\mSQLERRM\M' THEN
      RAISE EXCEPTION 'BH1 reconciled RPC contract failed: %',signature;
    END IF;
  END LOOP;
  FOREACH signature IN ARRAY ARRAY[
    'public.rpc_dashboard_overview(uuid)',
    'public.rpc_dashboard_recent_activity(uuid,integer)',
    'public.rpc_assign_operation(uuid,uuid,uuid,uuid,timestamptz,text,text,text)'
  ] LOOP
    proc_oid:=to_regprocedure(signature);
    IF proc_oid IS NOT NULL AND (
      has_function_privilege('anon',proc_oid,'EXECUTE')
      OR has_function_privilege('authenticated',proc_oid,'EXECUTE')
      OR has_function_privilege('service_role',proc_oid,'EXECUTE')
    ) THEN
      RAISE EXCEPTION 'BH1 obsolete RPC remains executable: %',signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM cron.job WHERE jobname LIKE 'rotero-f7-%')<>2
     OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='rotero-f7-automation-hourly' AND schedule='0 * * * *')
     OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='rotero-f7-daily-digest' AND schedule='15 12 * * *') THEN
    RAISE EXCEPTION 'BH1 cron architecture changed';
  END IF;
  IF pg_get_functiondef('public.rpc_get_public_tracking(text)'::regprocedure)~*'(service_claim|partner_compliance|commercial_rate|provider_cost|finance_invoice|document_files)'
     OR pg_get_functiondef('public.rpc_get_driver_view(text)'::regprocedure)~*'(service_claim|partner_compliance|commercial_rate|provider_cost|finance_invoice|document_files)' THEN
    RAISE EXCEPTION 'BH1 Tracking public capability leak';
  END IF;
END
$contract$;

DO $fixtures$
DECLARE tenant_a uuid;tenant_b uuid;admin_id uuid:=gen_random_uuid();finance_id uuid:=gen_random_uuid();outsider_id uuid:=gen_random_uuid();
  customer_a uuid;customer_b uuid;provider_a uuid;provider_b uuid;operation_a uuid;incident_a uuid;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
   ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','bh1-admin@example.invalid',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',finance_id,'authenticated','authenticated','bh1-finance@example.invalid',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',outsider_id,'authenticated','authenticated','bh1-outsider@example.invalid',now(),'{}','{}',now(),now());
  INSERT INTO public.tenants(name,slug) VALUES('BH1 Tenant A','bh1-a'),('BH1 Tenant B','bh1-b');
  SELECT id INTO tenant_a FROM public.tenants WHERE slug='bh1-a';SELECT id INTO tenant_b FROM public.tenants WHERE slug='bh1-b';
  INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(tenant_a,admin_id,'admin'),(tenant_a,finance_id,'finance');
  INSERT INTO public.customers(tenant_id,display_name,contact_name,preferred_currency) VALUES(tenant_a,'BH1 Cliente A','Contacto A','MXN') RETURNING id INTO customer_a;
  INSERT INTO public.customers(tenant_id,display_name) VALUES(tenant_b,'BH1 Cliente B') RETURNING id INTO customer_b;
  INSERT INTO public.logistics_providers(tenant_id,display_name,contact_name) VALUES(tenant_a,'BH1 Proveedor A','Operaciones A') RETURNING id INTO provider_a;
  INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(tenant_b,'BH1 Proveedor B') RETURNING id INTO provider_b;
  INSERT INTO public.operations(tenant_id,reference_code,status,execution_type,customer_id,provider_id,provider_name,pricing_currency,customer_price_amount,provider_cost_amount)
  VALUES(tenant_a,'OP-BH1-001','planned','third_party',customer_a,provider_a,'BH1 Proveedor A','MXN',1500,1000) RETURNING id INTO operation_a;
  INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,description,is_blocking,reported_by)
  VALUES(tenant_a,operation_a,'delay','Incidente BH1','Debe permanecer independiente',true,admin_id) RETURNING id INTO incident_a;
  PERFORM set_config('bh1.tenant_a',tenant_a::text,true);PERFORM set_config('bh1.tenant_b',tenant_b::text,true);
  PERFORM set_config('bh1.admin',admin_id::text,true);PERFORM set_config('bh1.finance',finance_id::text,true);PERFORM set_config('bh1.outsider',outsider_id::text,true);
  PERFORM set_config('bh1.customer_a',customer_a::text,true);PERFORM set_config('bh1.customer_b',customer_b::text,true);
  PERFORM set_config('bh1.provider_a',provider_a::text,true);PERFORM set_config('bh1.provider_b',provider_b::text,true);
  PERFORM set_config('bh1.operation_a',operation_a::text,true);PERFORM set_config('bh1.incident_a',incident_a::text,true);
END
$fixtures$;

SET LOCAL ROLE authenticated;
DO $admin$
DECLARE tenant_a uuid:=current_setting('bh1.tenant_a')::uuid;operation_a uuid:=current_setting('bh1.operation_a')::uuid;
  incident_a uuid:=current_setting('bh1.incident_a')::uuid;claim_id uuid;result jsonb;finance_before jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh1.admin'),'role','authenticated')::text,true);
  IF public.rpc_upsert_customer(tenant_a,NULL,jsonb_build_object('display_name','Cruce BH1','preferred_currency','MXN'))->>'id' IS NULL THEN
    RAISE EXCEPTION 'BH1 canonical customer RPC unavailable';
  END IF;
  IF public.rpc_create_service_claim(tenant_a,jsonb_build_object('customer_id',current_setting('bh1.customer_b'),'claim_type','other','subject','Cruce','description','Cruce tenant'))->>'error'<>'invalid_customer' THEN
    RAISE EXCEPTION 'BH1 cross-tenant claim accepted';
  END IF;
  finance_before:=public.rpc_get_operation_finance_summary(tenant_a,operation_a);
  result:=public.rpc_create_service_claim_from_incident(incident_a,'{"claim_type":"delay","priority":"high"}'::jsonb);
  claim_id:=(result->>'id')::uuid;
  result:=public.rpc_get_service_claim(claim_id);
  IF claim_id IS NULL OR result#>>'{source_incident,status}'<>'open' OR (result#>>'{source_incident,id}')::uuid<>incident_a THEN
    RAISE EXCEPTION 'BH1 incident-to-claim separation failed: %',result;
  END IF;
  IF public.rpc_get_operation_finance_summary(tenant_a,operation_a) IS DISTINCT FROM finance_before
     OR (public.rpc_get_claim_finance_handoff(claim_id)->>'accounting_mutated')::boolean THEN
    RAISE EXCEPTION 'BH1 claim mutated Finance truth';
  END IF;
  result:=public.rpc_get_provider_360(current_setting('bh1.provider_a')::uuid);
  IF result->>'error' IS NOT NULL OR jsonb_array_length(public.rpc_list_partner_claims('provider',current_setting('bh1.provider_a')::uuid,50))<>1 THEN
    RAISE EXCEPTION 'BH1 Provider360 claim aggregation mismatch: %',result;
  END IF;
  PERFORM set_config('bh1.claim',claim_id::text,true);
END
$admin$;

DO $finance$
DECLARE tenant_a uuid:=current_setting('bh1.tenant_a')::uuid;claim_id uuid:=current_setting('bh1.claim')::uuid;notifications jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh1.finance'),'role','authenticated')::text,true);
  IF public.rpc_get_service_claim(claim_id)->>'error'<>'unauthorized'
     OR public.rpc_search_claims(tenant_a,'BH1',10)->>'error'<>'unauthorized'
     OR public.rpc_get_provider_360(current_setting('bh1.provider_a')::uuid)->>'error'<>'unauthorized' THEN
    RAISE EXCEPTION 'BH1 Finance Commercial/Claims isolation failed';
  END IF;
  notifications:=public.rpc_list_internal_notifications(tenant_a,100,false);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(notifications->'items','[]'::jsonb)) item WHERE item->>'module' IN ('claims','commercial','compliance')) THEN
    RAISE EXCEPTION 'BH1 Finance notification leak';
  END IF;
END
$finance$;

DO $outsider$
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh1.outsider'),'role','authenticated')::text,true);
  IF public.rpc_list_customers(current_setting('bh1.tenant_a')::uuid,'{}')->>'error'<>'unauthorized'
     OR public.rpc_list_service_claims(current_setting('bh1.tenant_a')::uuid,'{}')->>'error'<>'unauthorized' THEN
    RAISE EXCEPTION 'BH1 outsider tenant isolation failed';
  END IF;
END
$outsider$;
RESET ROLE;

ROLLBACK;
\echo 'BH1 cross-module invariants passed'
