\set ON_ERROR_STOP on
BEGIN;

DO $contract$
DECLARE signature text; proc_oid oid;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.rpc_list_partner_history_page(uuid,text,uuid,text,jsonb,integer)',
    'public.rpc_list_internal_notifications_page(uuid,boolean,jsonb,integer)'
  ] LOOP
    proc_oid:=to_regprocedure(signature);
    IF proc_oid IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=proc_oid AND prosecdef AND proconfig@>ARRAY['search_path=pg_catalog, public']::text[])
      OR NOT has_function_privilege('authenticated',proc_oid,'EXECUTE')
      OR has_function_privilege('anon',proc_oid,'EXECUTE') OR has_function_privilege('service_role',proc_oid,'EXECUTE')
      OR pg_get_functiondef(proc_oid)~*'\mSQLERRM\M' THEN RAISE EXCEPTION 'BH2 RPC contract failed: %',signature; END IF;
  END LOOP;
  IF to_regprocedure('private.bh2_business_date(uuid,timestamptz)') IS NULL
    OR has_function_privilege('authenticated','private.bh2_business_date(uuid,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'BH2 private helper ACL failed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='business_contacts_customer_primary_uidx' AND indexdef ILIKE '%WHERE%is_primary%is_active%')
    OR pg_get_functiondef('public.rpc_upsert_business_contact(uuid,uuid,jsonb)'::regprocedure)!~*'FOR UPDATE' THEN RAISE EXCEPTION 'BH2 primary concurrency contract failed'; END IF;
END;$contract$;

DO $fixtures$
DECLARE tenant uuid;other_tenant uuid;admin_id uuid:=gen_random_uuid();finance_id uuid:=gen_random_uuid();customer uuid;other_customer uuid;provider uuid;i integer;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','bh2-admin@example.invalid',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',finance_id,'authenticated','authenticated','bh2-finance@example.invalid',now(),'{}','{}',now(),now());
  INSERT INTO public.tenants(name,slug) VALUES('BH2 Tenant','bh2-tenant'),('BH2 Other','bh2-other');
  SELECT id INTO tenant FROM public.tenants WHERE slug='bh2-tenant';SELECT id INTO other_tenant FROM public.tenants WHERE slug='bh2-other';
  INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(tenant,admin_id,'admin'),(tenant,finance_id,'finance');
  INSERT INTO public.tenant_settings(tenant_id,timezone) VALUES(tenant,'America/Mexico_City'),(other_tenant,'UTC') ON CONFLICT(tenant_id) DO UPDATE SET timezone=excluded.timezone;
  INSERT INTO public.customers(tenant_id,display_name,contact_name,contact_email) VALUES(tenant,'Cliente BH2','Fallback BH2','fallback@example.invalid') RETURNING id INTO customer;
  INSERT INTO public.customers(tenant_id,display_name) VALUES(other_tenant,'Cliente ajeno BH2') RETURNING id INTO other_customer;
  INSERT INTO public.logistics_providers(tenant_id,display_name,contact_name) VALUES(tenant,'Proveedor BH2','Fallback proveedor') RETURNING id INTO provider;
  FOR i IN 1..5 LOOP
    INSERT INTO public.crm_deals(tenant_id,customer_id,title,company,value,currency,stage,quote_status,quote_reference,created_at,updated_at)
    VALUES(tenant,customer,'Cotización BH2 '||i,'Cliente BH2',i*100,'MXN','lead','draft','BH2-Q-'||i,'2026-01-01 12:00:00+00'::timestamptz+i*interval '1 minute','2026-01-01 12:00:00+00'::timestamptz+i*interval '1 minute');
  END LOOP;
  PERFORM set_config('bh2.tenant',tenant::text,true);PERFORM set_config('bh2.other_tenant',other_tenant::text,true);PERFORM set_config('bh2.admin',admin_id::text,true);PERFORM set_config('bh2.finance',finance_id::text,true);PERFORM set_config('bh2.customer',customer::text,true);PERFORM set_config('bh2.other_customer',other_customer::text,true);PERFORM set_config('bh2.provider',provider::text,true);
END;$fixtures$;

DO $timezone$
BEGIN
  IF private.bh2_business_date(current_setting('bh2.tenant')::uuid,'2026-01-01 05:30:00+00')<>'2025-12-31'::date
    OR private.bh2_business_date(current_setting('bh2.other_tenant')::uuid,'2026-01-01 05:30:00+00')<>'2026-01-01'::date THEN RAISE EXCEPTION 'BH2 timezone boundary failed'; END IF;
END;$timezone$;

SET LOCAL ROLE authenticated;
DO $page_anchor$
DECLARE page1 jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh2.admin'),'role','authenticated')::text,true);
  page1:=public.rpc_list_partner_history_page(current_setting('bh2.tenant')::uuid,'customer',current_setting('bh2.customer')::uuid,'quotes',NULL,2);
  PERFORM set_config('bh2.page1',page1::text,true);
END;$page_anchor$;
RESET ROLE;
INSERT INTO public.crm_deals(tenant_id,customer_id,title,company,value,currency,stage,quote_status,quote_reference,created_at,updated_at)
VALUES(current_setting('bh2.tenant')::uuid,current_setting('bh2.customer')::uuid,'Cotización concurrente','Cliente BH2',900,'MXN','lead','draft','BH2-Q-NEW','2026-01-02 12:00:00+00','2026-01-02 12:00:00+00');
SET LOCAL ROLE authenticated;
DO $admin$
DECLARE tenant uuid:=current_setting('bh2.tenant')::uuid;customer uuid:=current_setting('bh2.customer')::uuid;provider uuid:=current_setting('bh2.provider')::uuid;summary jsonb;page1 jsonb;page2 jsonb;page3 jsonb;empty_page jsonb;bad jsonb;first_contact uuid;second_contact uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh2.admin'),'role','authenticated')::text,true);
  summary:=public.rpc_get_customer_partner_360(customer);
  IF jsonb_array_length(summary->'quotes')<>0 OR summary#>>'{history_counts,quotes}'<>'6' OR summary#>>'{primary_contact,source}'<>'canonical_fallback' THEN RAISE EXCEPTION 'BH2 bounded summary/fallback failed'; END IF;
  page1:=current_setting('bh2.page1')::jsonb;
  page2:=public.rpc_list_partner_history_page(tenant,'customer',customer,'quotes',page1->'next_cursor',2);
  page3:=public.rpc_list_partner_history_page(tenant,'customer',customer,'quotes',page2->'next_cursor',2);
  empty_page:=public.rpc_list_partner_history_page(tenant,'provider',provider,'claims',NULL,2);
  IF jsonb_array_length(page1->'items')<>2 OR NOT (page1->>'has_more')::boolean OR jsonb_array_length(page2->'items')<>2
    OR jsonb_array_length(page3->'items')<>1 OR (page3->>'has_more')::boolean OR jsonb_array_length(empty_page->'items')<>0
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(page1->'items')a JOIN jsonb_array_elements(page2->'items')b ON a->>'id'=b->>'id')
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(page2->'items') WHERE value->>'quote_reference'='BH2-Q-NEW') THEN RAISE EXCEPTION 'BH2 stable pagination failed'; END IF;
  bad:=public.rpc_list_partner_history_page(tenant,'customer',customer,'quotes',(page1->'next_cursor')||jsonb_build_object('tenant_id',current_setting('bh2.other_tenant')),2);
  IF bad->>'error'<>'invalid_cursor' THEN RAISE EXCEPTION 'BH2 cross-tenant cursor accepted'; END IF;
  bad:=public.rpc_list_partner_history_page(tenant,'customer',customer,'quotes',jsonb_build_object('tenant_id',tenant,'entity_type','customer','entity_id',customer,'history_type','quotes','sort_at','bad','id','bad'),2);
  IF bad->>'error'<>'invalid_cursor' THEN RAISE EXCEPTION 'BH2 malformed cursor accepted'; END IF;
  first_contact:=(public.rpc_upsert_business_contact(tenant,NULL,jsonb_build_object('customer_id',customer,'name','Contacto Uno','contact_role','commercial'))->>'id')::uuid;
  second_contact:=(public.rpc_upsert_business_contact(tenant,NULL,jsonb_build_object('customer_id',customer,'name','Contacto Dos','contact_role','billing','is_primary',true))->>'id')::uuid;
  summary:=public.rpc_get_customer_partner_360(customer);
  IF (SELECT count(*) FROM jsonb_array_elements(summary->'contacts')x WHERE (x->>'is_primary')::boolean)<>1
    OR summary#>>'{primary_contact,id}'<>second_contact::text OR summary#>>'{customer,contact_name}'<>'Contacto Dos' THEN RAISE EXCEPTION 'BH2 primary projection failed'; END IF;
  PERFORM public.rpc_upsert_business_contact(tenant,second_contact,jsonb_build_object('customer_id',customer,'name','Contacto Dos','contact_role','billing','is_active',false));
  summary:=public.rpc_get_customer_partner_360(customer);
  IF summary#>>'{primary_contact,id}'<>first_contact::text OR summary#>>'{customer,contact_name}'<>'Contacto Uno' THEN RAISE EXCEPTION 'BH2 deterministic primary promotion failed'; END IF;
  IF public.rpc_list_partner_history_page(tenant,'customer',current_setting('bh2.other_customer')::uuid,'quotes',NULL,2)->>'error'<>'not_found' THEN RAISE EXCEPTION 'BH2 entity tenant isolation failed'; END IF;
  IF public.rpc_get_provider_360(provider)#>>'{primary_contact,source}'<>'canonical_fallback' THEN RAISE EXCEPTION 'BH2 provider fallback failed'; END IF;
END;$admin$;

DO $finance_denial$
DECLARE result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bh2.finance'),'role','authenticated')::text,true);
  result:=public.rpc_list_partner_history_page(current_setting('bh2.tenant')::uuid,'customer',current_setting('bh2.customer')::uuid,'quotes',NULL,2);
  IF result->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'BH2 Finance Partner360 leak'; END IF;
END;$finance_denial$;
RESET ROLE;
ROLLBACK;
