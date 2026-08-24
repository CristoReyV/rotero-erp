\set ON_ERROR_STOP on
BEGIN;

DO $contract$
DECLARE s text; o oid; t text;
BEGIN
 FOREACH s IN ARRAY ARRAY['public.rpc_list_rate_reference_data(uuid)','public.rpc_upsert_lane(uuid,uuid,jsonb)','public.rpc_create_rate(uuid,jsonb)','public.rpc_create_rate_version(uuid,jsonb)','public.rpc_list_rates(uuid,jsonb)','public.rpc_get_rate_360(uuid)','public.rpc_compare_provider_rates(uuid,jsonb)','public.rpc_apply_rate_to_quote(uuid,uuid)','public.rpc_archive_rate(uuid)','public.rpc_duplicate_rate(uuid)','public.rpc_upsert_business_contact(uuid,uuid,jsonb)','public.rpc_list_partner_contacts(uuid,text,uuid)','public.rpc_update_partner_terms(uuid,text,uuid,integer)','public.rpc_get_customer_partner_360(uuid)','public.rpc_get_provider_360(uuid)','public.rpc_export_rates(uuid,jsonb)'] LOOP
  o:=to_regprocedure(s); IF o IS NULL THEN RAISE EXCEPTION 'F8 missing %',s; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=o AND prosecdef AND proconfig@>ARRAY['search_path=pg_catalog, public']::text[]) THEN RAISE EXCEPTION 'F8 unsafe %',s; END IF;
  IF NOT has_function_privilege('authenticated',o,'EXECUTE') OR has_function_privilege('anon',o,'EXECUTE') OR has_function_privilege('service_role',o,'EXECUTE') THEN RAISE EXCEPTION 'F8 ACL %',s; END IF;
  IF pg_get_functiondef(o)~*'\mSQLERRM\M' THEN RAISE EXCEPTION 'F8 SQLERRM %',s; END IF;
 END LOOP;
 FOREACH t IN ARRAY ARRAY['commercial_lanes','commercial_rate_cards','commercial_rate_versions','commercial_rate_charges','crm_quote_rate_snapshots','business_contacts'] LOOP
  IF to_regclass('public.'||t) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||t) AND relrowsecurity) THEN RAISE EXCEPTION 'F8 table/RLS %',t; END IF;
  IF has_table_privilege('authenticated','public.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','public.'||t,'SELECT') OR has_table_privilege('service_role','public.'||t,'SELECT') THEN RAISE EXCEPTION 'F8 table ACL %',t; END IF;
 END LOOP;
 IF pg_get_functiondef('public.rpc_get_public_tracking(text)'::regprocedure)~*'(commercial_rate|business_contact|provider_cost)' OR pg_get_functiondef('public.rpc_get_driver_view(text)'::regprocedure)~*'(commercial_rate|business_contact|provider_cost)' THEN RAISE EXCEPTION 'F8 sensitive tracking leak'; END IF;
END;$contract$;

DO $fixtures$
DECLARE tenant uuid; other_tenant uuid; admin_id uuid:=gen_random_uuid(); finance_id uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); customer uuid; provider uuid; other_provider uuid; service uuid; quote uuid;
BEGIN
 INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','f8-admin@example.invalid',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',finance_id,'authenticated','authenticated','f8-finance@example.invalid',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f8-outsider@example.invalid',now(),'{}','{}',now(),now());
 INSERT INTO public.tenants(name,slug) VALUES('F8 Tenant','f8-tenant'),('F8 Other','f8-other');SELECT id INTO tenant FROM public.tenants WHERE slug='f8-tenant';SELECT id INTO other_tenant FROM public.tenants WHERE slug='f8-other';
 INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(tenant,admin_id,'admin'),(tenant,finance_id,'finance');
 INSERT INTO public.customers(tenant_id,display_name) VALUES(tenant,'Cliente F8') RETURNING id INTO customer;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(tenant,'Proveedor F8') RETURNING id INTO provider;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(other_tenant,'Proveedor ajeno') RETURNING id INTO other_provider;
 INSERT INTO public.service_catalog_items(tenant_id,service_type,service_class) VALUES(tenant,'FTL','Caja seca') RETURNING id INTO service;
 INSERT INTO public.crm_deals(tenant_id,customer_id,title,company,value,currency,stage,quote_status,quote_reference,quote_payload) VALUES(tenant,customer,'Cotización F8','Cliente F8',1500,'MXN','proposal','draft','Q-F8-001',jsonb_build_object('operational_window_start',(current_date+2)::text,'operation_scope','national')) RETURNING id INTO quote;
 PERFORM set_config('f8.tenant',tenant::text,true);PERFORM set_config('f8.other',other_tenant::text,true);PERFORM set_config('f8.admin',admin_id::text,true);PERFORM set_config('f8.finance',finance_id::text,true);PERFORM set_config('f8.outsider',outsider::text,true);PERFORM set_config('f8.customer',customer::text,true);PERFORM set_config('f8.provider',provider::text,true);PERFORM set_config('f8.other_provider',other_provider::text,true);PERFORM set_config('f8.service',service::text,true);PERFORM set_config('f8.quote',quote::text,true);
END;$fixtures$;

SET LOCAL ROLE authenticated;
DO $admin$
DECLARE tenant uuid:=current_setting('f8.tenant')::uuid; customer uuid:=current_setting('f8.customer')::uuid; provider uuid:=current_setting('f8.provider')::uuid; service uuid:=current_setting('f8.service')::uuid; quote uuid:=current_setting('f8.quote')::uuid; lane uuid; buy uuid; buy_v uuid; sell uuid; sell_v uuid; r jsonb; version2 uuid; contact uuid;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f8.admin'),'role','authenticated')::text,true);
 r:=public.rpc_upsert_lane(tenant,NULL,jsonb_build_object('scope','national','origin_place',jsonb_build_object('municipality','Monterrey','state','NL','country','MX'),'destination_place',jsonb_build_object('municipality','Querétaro','state','QRO','country','MX')));lane:=(r->>'id')::uuid;IF lane IS NULL THEN RAISE EXCEPTION 'lane create %',r;END IF;
 r:=public.rpc_upsert_lane(tenant,NULL,jsonb_build_object('scope','national','origin_place',jsonb_build_object('municipality',' monterrey ','state','nl','country','mx'),'destination_place',jsonb_build_object('municipality','querétaro','state','qro','country','mx')));IF r->>'error'<>'duplicate_lane' THEN RAISE EXCEPTION 'lane normalization %',r;END IF;
 r:=public.rpc_create_rate(tenant,jsonb_build_object('rate_type','BUY','provider_id',provider,'lane_id',lane,'service_catalog_item_id',service,'reference','BUY-F8','status','active','currency','MXN','valid_from',current_date,'valid_to',current_date+30,'charges',jsonb_build_array(jsonb_build_object('charge_type','base','description','Flete base','amount',1000),jsonb_build_object('charge_type','fuel','description','Combustible','amount',100))));buy:=(r->>'id')::uuid;buy_v:=(r->>'version_id')::uuid;IF buy IS NULL OR (public.rpc_get_rate_360(buy)->'versions'->0->>'total_amount')::numeric<>1100 THEN RAISE EXCEPTION 'BUY create/total %',r;END IF;
 r:=public.rpc_create_rate(tenant,jsonb_build_object('rate_type','SELL','customer_id',customer,'lane_id',lane,'service_catalog_item_id',service,'reference','SELL-F8','status','active','currency','MXN','valid_from',current_date,'valid_to',current_date+30,'charges',jsonb_build_array(jsonb_build_object('charge_type','base','description','Venta','amount',1500))));sell:=(r->>'id')::uuid;sell_v:=(r->>'version_id')::uuid;IF sell IS NULL THEN RAISE EXCEPTION 'SELL create %',r;END IF;
 r:=public.rpc_create_rate(tenant,jsonb_build_object('rate_type','BUY','provider_id',current_setting('f8.other_provider')::uuid,'lane_id',lane,'service_catalog_item_id',service,'currency','MXN','valid_from',current_date,'charges',jsonb_build_array(jsonb_build_object('charge_type','base','description','x','amount',1))));IF r->>'error'<>'invalid_provider' THEN RAISE EXCEPTION 'cross tenant provider %',r;END IF;
 r:=public.rpc_compare_provider_rates(tenant,jsonb_build_object('lane_id',lane,'service_catalog_item_id',service,'operational_date',current_date+2,'currency','MXN'));IF jsonb_array_length(r)<>1 OR (r->0->>'total_amount')::numeric<>1100 THEN RAISE EXCEPTION 'exact comparison %',r;END IF;
 r:=public.rpc_apply_rate_to_quote(quote,buy_v);IF NOT coalesce((r->>'success')::boolean,false) OR (r->>'total_amount')::numeric<>1100 OR jsonb_array_length(public.rpc_get_rate_360(buy)->'usage')<>1 THEN RAISE EXCEPTION 'BUY apply/snapshot %',r;END IF;
 r:=public.rpc_create_rate_version(buy,jsonb_build_object('currency','MXN','valid_from',current_date+31,'charges',jsonb_build_array(jsonb_build_object('charge_type','base','description','Nueva','amount',1200))));version2:=(r->>'version_id')::uuid;IF version2 IS NULL OR (r->>'version')::int<>2 OR jsonb_array_length(public.rpc_get_rate_360(buy)->'versions')<>2 THEN RAISE EXCEPTION 'versioning %',r;END IF;
 PERFORM public.rpc_submit_quote_for_review(quote);r:=public.rpc_apply_rate_to_quote(quote,sell_v);IF r->>'error'<>'quote_not_editable' THEN RAISE EXCEPTION 'lifecycle %',r;END IF;
 r:=public.rpc_upsert_business_contact(tenant,NULL,jsonb_build_object('customer_id',customer,'name','Ana Compras','contact_role','commercial','is_primary',true));contact:=(r->>'id')::uuid;IF contact IS NULL THEN RAISE EXCEPTION 'contact %',r;END IF;
 r:=public.rpc_upsert_business_contact(tenant,NULL,jsonb_build_object('customer_id',customer,'provider_id',provider,'name','Inválido','contact_role','other'));IF r->>'error'<>'invalid_payload' THEN RAISE EXCEPTION 'contact owner check %',r;END IF;
 r:=public.rpc_update_partner_terms(tenant,'customer',customer,30);IF NOT coalesce((r->>'success')::boolean,false) OR (public.rpc_get_customer_partner_360(customer)->'customer'->>'payment_terms_days')::int<>30 THEN RAISE EXCEPTION 'terms %',r;END IF;
 IF public.rpc_get_customer_partner_360(customer)->>'error' IS NOT NULL OR public.rpc_get_provider_360(provider)->>'error' IS NOT NULL THEN RAISE EXCEPTION 'partner 360';END IF;PERFORM set_config('f8.buy_version',buy_v::text,true);
END;$admin$;

RESET ROLE;
DO $immutability$ BEGIN
 BEGIN UPDATE public.commercial_rate_versions SET notes='illegal' WHERE id=current_setting('f8.buy_version')::uuid;RAISE EXCEPTION 'used version mutated';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'used_rate_version_is_immutable' THEN RAISE;END IF;END;
END;$immutability$;
SET LOCAL ROLE authenticated;

DO $denials$
DECLARE tenant uuid:=current_setting('f8.tenant')::uuid;r jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f8.finance'),'role','authenticated')::text,true);r:=public.rpc_list_rates(tenant,'{}');IF r->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'finance rates leak %',r;END IF;r:=public.rpc_get_customer_partner_360(current_setting('f8.customer')::uuid);IF r->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'finance customer leak %',r;END IF;r:=public.rpc_get_provider_360(current_setting('f8.provider')::uuid);IF r->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'finance provider leak %',r;END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f8.outsider'),'role','authenticated')::text,true);r:=public.rpc_export_rates(tenant,'{}');IF r->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'outsider leak %',r;END IF;
END;$denials$;
RESET ROLE;ROLLBACK;
