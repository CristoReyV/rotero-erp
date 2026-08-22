\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE v_signature text; v_oid oid; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_validate_bulk_import(uuid,text,text,jsonb)',
        'public.rpc_start_bulk_import(uuid,text,text,text,text,integer,jsonb)',
        'public.rpc_list_import_batches(uuid,integer)',
        'public.rpc_apply_bulk_import(uuid,uuid,text,jsonb,boolean)',
        'public.rpc_export_data_page(uuid,text,jsonb,jsonb,integer)',
        'public.rpc_list_import_mappings(uuid,text)',
        'public.rpc_save_import_mapping(uuid,jsonb)',
        'public.rpc_delete_import_mapping(uuid,uuid)',
        'public.rpc_bulk_update_operations(uuid,uuid[],text,jsonb)',
        'public.rpc_record_data_action(uuid,text,text,integer,text)'
    ] LOOP
        v_oid:=to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F6 CONTRACT: missing %',v_signature; END IF;
        IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=v_oid AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog, public']::text[]) THEN RAISE EXCEPTION 'F6 CONTRACT: unsafe %',v_signature; END IF;
        IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE') OR has_function_privilege('anon',v_oid,'EXECUTE')
           OR has_function_privilege('service_role',v_oid,'EXECUTE') OR pg_get_functiondef(v_oid)~* '\mSQLERRM\M' THEN RAISE EXCEPTION 'F6 CONTRACT: ACL/error leak %',v_signature; END IF;
    END LOOP;
    FOREACH v_table IN ARRAY ARRAY['data_import_batches','data_import_chunks','data_import_mappings'] LOOP
        IF to_regclass('public.'||v_table) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||v_table) AND relrowsecurity) THEN RAISE EXCEPTION 'F6 CONTRACT: table/RLS %',v_table; END IF;
        IF has_table_privilege('authenticated','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','public.'||v_table,'SELECT') OR has_table_privilege('service_role','public.'||v_table,'SELECT') THEN RAISE EXCEPTION 'F6 CONTRACT: direct privilege %',v_table; END IF;
    END LOOP;
    IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='customers' AND column_name='external_key')
       OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='logistics_providers' AND column_name='external_key')
       OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='operations' AND column_name='external_key') THEN RAISE EXCEPTION 'F6 CONTRACT: external identity missing'; END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='customers_tenant_external_key_uidx')
       OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='logistics_providers_tenant_external_key_uidx')
       OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='operations_tenant_external_key_uidx') THEN RAISE EXCEPTION 'F6 CONTRACT: identity indexes missing'; END IF;
END;
$contract$;

DO $fixtures$
DECLARE v_tenant uuid; v_other uuid; v_admin uuid:=gen_random_uuid(); v_admin_b uuid:=gen_random_uuid(); v_finance uuid:=gen_random_uuid(); v_operator uuid:=gen_random_uuid(); v_outsider uuid:=gen_random_uuid(); v_provider uuid; v_foreign_operation uuid; v_invoice uuid;
BEGIN
    INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f6-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_admin_b,'authenticated','authenticated','f6-admin-b@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f6-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_operator,'authenticated','authenticated','f6-operator@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_outsider,'authenticated','authenticated','f6-outsider@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES('F6 Tenant','f6-tenant'),('F6 Other','f6-other');
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f6-tenant'; SELECT id INTO v_other FROM public.tenants WHERE slug='f6-other';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(v_tenant,v_admin,'admin'),(v_tenant,v_admin_b,'admin'),(v_tenant,v_finance,'finance'),(v_tenant,v_operator,'operator');
    INSERT INTO public.logistics_providers(tenant_id,external_key,display_name,tax_id) VALUES(v_tenant,'PRV-F6','Proveedor F6','PRF010101AA1') RETURNING id INTO v_provider;
    INSERT INTO public.customers(tenant_id,display_name,tax_id) VALUES(v_tenant,'Cliente ambiguo A','AMB010101AA1'),(v_tenant,'Cliente ambiguo B','AMB010101AA1');
    INSERT INTO public.logistics_providers(tenant_id,display_name,tax_id) VALUES(v_tenant,'Proveedor ambiguo A','AMP010101AA1'),(v_tenant,'Proveedor ambiguo B','AMP010101AA1');
    INSERT INTO public.operations(tenant_id,external_key,reference_code,client_display_name,status) VALUES(v_other,'FOREIGN-F6','OP-FOREIGN-F6','Otro tenant','planned') RETURNING id INTO v_foreign_operation;
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date) VALUES(v_tenant,'ar','Cliente Finance F6','AR-F6',100,'MXN','open',current_date+5) RETURNING id INTO v_invoice;
    PERFORM set_config('f6.tenant',v_tenant::text,true); PERFORM set_config('f6.other',v_other::text,true); PERFORM set_config('f6.admin',v_admin::text,true); PERFORM set_config('f6.admin_b',v_admin_b::text,true); PERFORM set_config('f6.finance',v_finance::text,true); PERFORM set_config('f6.operator',v_operator::text,true); PERFORM set_config('f6.outsider',v_outsider::text,true); PERFORM set_config('f6.foreign_operation',v_foreign_operation::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin$
DECLARE v_tenant uuid:=current_setting('f6.tenant')::uuid; v_rows jsonb; v_provider_rows jsonb; v_result jsonb; v_batch uuid; v_provider_batch uuid; v_operation_batch uuid; v_operation uuid; v_mapping uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.admin'),true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f6.admin'),'role','authenticated')::text,true);
    v_rows:='[{"row_number":2,"external_key":"CLI-F6","display_name":"Cliente F6","tax_id":"CUF010101AA1","contact_email":"persona@example.invalid","notes":"dato transitorio"}]';
    v_result:=public.rpc_validate_bulk_import(v_tenant,'customers','upsert',v_rows);
    IF v_result?'error' OR v_result#>>'{summary,create}'<>'1' OR v_result#>>'{summary,errors}'<>'0' THEN RAISE EXCEPTION 'F6 customer validation failed: %',v_result; END IF;
    v_result:=public.rpc_validate_bulk_import(v_tenant,'customers','upsert','[{"row_number":2,"external_key":"DUP","display_name":"Uno"},{"row_number":3,"external_key":"dup","display_name":"Dos"}]');
    IF v_result#>>'{summary,errors}'<>'2' THEN RAISE EXCEPTION 'F6 duplicate validation failed: %',v_result; END IF;
    v_result:=public.rpc_validate_bulk_import(v_tenant,'customers','upsert','[{"row_number":2,"display_name":"Aviso"}]');
    IF v_result#>>'{summary,warnings}'<>'1' THEN RAISE EXCEPTION 'F6 warning contract failed: %',v_result; END IF;
    v_result:=public.rpc_start_bulk_import(v_tenant,'customers','clientes.csv','upsert','f6-customer-import-0001',1,'{"create":1,"errors":0}'); v_batch:=(v_result->>'id')::uuid;
    v_result:=public.rpc_apply_bulk_import(v_tenant,v_batch,'chunk-0000',v_rows,true);
    IF v_result#>>'{summary,created}'<>'1' OR v_result->>'batch_status'<>'completed' THEN RAISE EXCEPTION 'F6 customer apply failed: %',v_result; END IF;
    v_result:=public.rpc_apply_bulk_import(v_tenant,v_batch,'chunk-0000',v_rows,true);
    IF v_result->>'duplicate_response'<>'true' OR public.rpc_export_data_page(v_tenant,'customers','{"search":"CLI-F6"}',NULL,10)#>>'{page_size}'<>'1' THEN RAISE EXCEPTION 'F6 idempotency failed: %',v_result; END IF;
    IF public.rpc_validate_bulk_import(v_tenant,'customers','upsert',v_rows)#>>'{summary,update}'<>'1' OR public.rpc_validate_bulk_import(v_tenant,'customers','create_only',v_rows)#>>'{summary,skip}'<>'1' THEN RAISE EXCEPTION 'F6 customer update/create-only failed'; END IF;
    v_result:=public.rpc_validate_bulk_import(v_tenant,'customers','upsert','[{"external_key":"BAD-C","display_name":"","tax_id":"NO-RFC","contact_email":"no-email"}]');
    IF v_result#>>'{summary,errors}'<>'1' OR v_result::text NOT LIKE '%missing_display_name%' OR v_result::text NOT LIKE '%invalid_tax_id%' OR v_result::text NOT LIKE '%invalid_email%' THEN RAISE EXCEPTION 'F6 malformed customer failed: %',v_result; END IF;

    v_provider_rows:='[{"row_number":2,"external_key":"PRV-NEW-F6","display_name":"Proveedor nuevo F6","tax_id":"PNF010101AA1","contact_email":"proveedor@example.invalid"}]';
    v_result:=public.rpc_validate_bulk_import(v_tenant,'providers','upsert',v_provider_rows); IF v_result#>>'{summary,create}'<>'1' THEN RAISE EXCEPTION 'F6 provider create validation failed: %',v_result; END IF;
    v_result:=public.rpc_start_bulk_import(v_tenant,'providers','proveedores.csv','upsert','f6-provider-import-0001',1,'{"create":1,"errors":0}'); v_provider_batch:=(v_result->>'id')::uuid;
    v_result:=public.rpc_apply_bulk_import(v_tenant,v_provider_batch,'chunk-0000',v_provider_rows,true);
    IF v_result#>>'{summary,created}'<>'1' OR public.rpc_export_data_page(v_tenant,'providers','{"search":"PRV-NEW-F6"}',NULL,10)#>>'{page_size}'<>'1' THEN RAISE EXCEPTION 'F6 provider apply failed: %',v_result; END IF;
    IF public.rpc_validate_bulk_import(v_tenant,'providers','upsert',v_provider_rows)#>>'{summary,update}'<>'1' OR public.rpc_validate_bulk_import(v_tenant,'providers','create_only',v_provider_rows)#>>'{summary,skip}'<>'1' THEN RAISE EXCEPTION 'F6 provider update/create-only failed'; END IF;
    v_result:=public.rpc_validate_bulk_import(v_tenant,'providers','upsert','[{"external_key":"BAD-P","display_name":"","tax_id":"BAD","billing_email":"invalid"}]');
    IF v_result#>>'{summary,errors}'<>'1' OR v_result::text NOT LIKE '%missing_display_name%' OR v_result::text NOT LIKE '%invalid_tax_id%' OR v_result::text NOT LIKE '%invalid_billing_email%' THEN RAISE EXCEPTION 'F6 malformed provider failed: %',v_result; END IF;

    v_rows:='[{"row_number":2,"external_key":"OP-F6","customer_external_key":"CLI-F6","provider_external_key":"PRV-F6","service_type":"FTL","operation_scope":"national","execution_type":"third_party","origin_municipality":"Monterrey","origin_state":"NL","origin_country_code":"MX","destination_municipality":"Querétaro","destination_state":"QRO","destination_country_code":"MX","operational_window_start":"2026-08-28T09:00:00-06:00","operational_window_end":"2026-08-28T18:00:00-06:00","cargo_description":"Tarimas","pricing_currency":"MXN","provider_cost_amount":"500","customer_price_amount":"800"}]';
    v_result:=public.rpc_validate_bulk_import(v_tenant,'operations','upsert',v_rows);
    IF v_result#>>'{summary,create}'<>'1' OR v_result#>>'{summary,errors}'<>'0' THEN RAISE EXCEPTION 'F6 operation validation failed: %',v_result; END IF;
    v_result:=public.rpc_start_bulk_import(v_tenant,'operations','operaciones.csv','upsert','f6-operation-import-0001',1,'{"create":1,"errors":0}'); v_operation_batch:=(v_result->>'id')::uuid;
    v_result:=public.rpc_apply_bulk_import(v_tenant,v_operation_batch,'chunk-0000',v_rows,true);
    v_operation:=(v_result#>>'{items,0,applied_entity_id}')::uuid;
    v_result:=public.rpc_export_data_page(v_tenant,'operations','{"search":"OP-F6"}',NULL,10);
    IF v_operation IS NULL OR v_result#>>'{items,0,status}'<>'planned' OR v_result#>>'{items,0,execution_type}'<>'third_party' OR (v_result#>>'{items,0,customer_price_amount}')::numeric<>800 OR (v_result#>>'{items,0,provider_cost_amount}')::numeric<>500 THEN RAISE EXCEPTION 'F6 broker-first apply failed: %',v_result; END IF;
    v_result:=public.rpc_validate_bulk_import(v_tenant,'operations','upsert','[
      {"external_key":"OP-BAD-DATE","customer_external_key":"CLI-F6","service_type":"FTL","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-02T10:00:00Z","operational_window_end":"2026-09-01T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-BAD-SCOPE","customer_external_key":"CLI-F6","service_type":"FTL","operation_scope":"planetary","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-BAD-CURRENCY","customer_external_key":"CLI-F6","service_type":"FTL","pricing_currency":"EUR","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-BAD-MONEY","customer_external_key":"CLI-F6","service_type":"FTL","provider_cost_amount":"-1","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-BAD-STATUS","customer_external_key":"CLI-F6","service_type":"FTL","status":"delivered","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-BAD-EXEC","customer_external_key":"CLI-F6","service_type":"FTL","execution_type":"own_fleet","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"},
      {"external_key":"OP-AMB","customer_tax_id":"AMB010101AA1","provider_tax_id":"AMP010101AA1","service_type":"FTL","origin_municipality":"A","origin_state":"NL","destination_municipality":"B","destination_state":"QRO","operational_window_start":"2026-09-01T10:00:00Z","operational_window_end":"2026-09-02T10:00:00Z","cargo_description":"Carga"}
    ]');
    IF v_result#>>'{summary,errors}'<>'7' OR v_result::text NOT LIKE '%invalid_operational_window%' OR v_result::text NOT LIKE '%invalid_operation_scope%' OR v_result::text NOT LIKE '%invalid_currency%' OR v_result::text NOT LIKE '%negative_economics%' OR v_result::text NOT LIKE '%unsafe_status%' OR v_result::text NOT LIKE '%invalid_execution_type%' OR v_result::text NOT LIKE '%ambiguous_customer%' OR v_result::text NOT LIKE '%ambiguous_provider%' THEN RAISE EXCEPTION 'F6 operation rejection matrix failed: %',v_result; END IF;

    v_result:=public.rpc_bulk_update_operations(v_tenant,ARRAY[v_operation],'set_priority','{"priority":"high"}');
    IF v_result->>'updated'<>'1' THEN RAISE EXCEPTION 'F6 bulk priority failed: %',v_result; END IF;
    IF public.rpc_bulk_update_operations(v_tenant,ARRAY[v_operation],'close','{}')->>'error'<>'invalid_payload' OR public.rpc_bulk_update_operations(v_tenant,ARRAY[v_operation],'cancel','{}')->>'error'<>'invalid_payload' THEN RAISE EXCEPTION 'F6 dangerous bulk action boundary failed'; END IF;
    IF public.rpc_bulk_update_operations(v_tenant,ARRAY[current_setting('f6.foreign_operation')::uuid],'add_note','{"note":"No"}')->>'error'<>'cross_tenant_or_missing' THEN RAISE EXCEPTION 'F6 bulk tenant boundary failed'; END IF;

    v_result:=public.rpc_save_import_mapping(v_tenant,'{"entity_type":"operations","name":"Mapeo ERP","mapping":{"external_key":"clave"}}'); v_mapping:=(v_result->>'id')::uuid;
    IF v_mapping IS NULL OR jsonb_array_length(public.rpc_list_import_mappings(v_tenant,'operations')->'items')<>1 THEN RAISE EXCEPTION 'F6 mapping failed'; END IF;
    IF public.rpc_export_data_page(v_tenant,'customers','{"search":"CLI-F6"}',NULL,500)#>>'{page_size}'<>'1' OR public.rpc_export_data_page(v_tenant,'operations','{"status":"planned","search":"OP-F6"}',NULL,500)#>>'{page_size}'<>'1' OR public.rpc_export_data_page(v_tenant,'operations','{"date_from":"2099-01-01"}',NULL,500)#>>'{page_size}'<>'0' OR public.rpc_export_data_page(v_tenant,'finance_ar','{}',NULL,500)#>>'{page_size}'<>'1' THEN RAISE EXCEPTION 'F6 export filters failed'; END IF;
    PERFORM set_config('f6.mapping',v_mapping::text,true); PERFORM set_config('f6.operation',v_operation::text,true); PERFORM set_config('f6.customer_batch',v_batch::text,true);
END;
$admin$;

DO $mapping_owner$
DECLARE v_tenant uuid:=current_setting('f6.tenant')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.admin_b'),true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f6.admin_b'),'role','authenticated')::text,true);
    IF jsonb_array_length(public.rpc_list_import_mappings(v_tenant,'operations')->'items')<>0 OR public.rpc_delete_import_mapping(v_tenant,current_setting('f6.mapping')::uuid)->>'error'<>'not_found' THEN RAISE EXCEPTION 'F6 mapping ownership failed'; END IF;
END;
$mapping_owner$;

DO $finance$
DECLARE v_tenant uuid:=current_setting('f6.tenant')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.finance'),true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f6.finance'),'role','authenticated')::text,true);
    IF public.rpc_validate_bulk_import(v_tenant,'customers','upsert','[{"display_name":"No"}]')->>'error'<>'unauthorized'
       OR public.rpc_start_bulk_import(v_tenant,'customers','no.csv','upsert','f6-finance-denied-0001',1,'{}')->>'error'<>'unauthorized'
       OR public.rpc_export_data_page(v_tenant,'customers','{}',NULL,10)->>'error'<>'unauthorized'
       OR public.rpc_export_data_page(v_tenant,'quotes','{}',NULL,10)->>'error'<>'unauthorized'
       OR public.rpc_export_data_page(v_tenant,'finance_ar','{}',NULL,10)#>>'{page_size}'<>'1' THEN RAISE EXCEPTION 'F6 finance boundary failed'; END IF;
END;
$finance$;

DO $operator_outsider$
DECLARE v_tenant uuid:=current_setting('f6.tenant')::uuid; v_other uuid:=current_setting('f6.other')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.operator'),true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f6.operator'),'role','authenticated')::text,true);
    IF public.rpc_start_bulk_import(v_tenant,'customers','no.csv','upsert','f6-operator-denied-0001',1,'{}')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F6 operator write boundary failed'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.outsider'),true); PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f6.outsider'),'role','authenticated')::text,true);
    IF public.rpc_export_data_page(v_tenant,'operations','{}',NULL,10)->>'error'<>'unauthorized' OR public.rpc_list_import_batches(v_tenant,10)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F6 outsider boundary failed'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f6.admin'),true);
    IF public.rpc_list_import_batches(v_other,10)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F6 cross-tenant boundary failed'; END IF;
END;
$operator_outsider$;

RESET ROLE;

DO $audit$
BEGIN
    IF EXISTS(SELECT 1 FROM public.data_import_chunks WHERE batch_id=current_setting('f6.customer_batch')::uuid AND (result::text LIKE '%persona@example.invalid%' OR result::text LIKE '%dato transitorio%' OR result::text LIKE '%normalized%')) THEN RAISE EXCEPTION 'F6 raw/sensitive retention failed'; END IF;
    IF (SELECT priority FROM public.operations WHERE id=current_setting('f6.operation')::uuid)<>'high' THEN RAISE EXCEPTION 'F6 bulk priority persistence failed'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='data_import_validated') OR NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='data_import_applied') OR NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='data_export_requested') OR NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='data_bulk_action') THEN RAISE EXCEPTION 'F6 audit coverage failed'; END IF;
END;
$audit$;

ROLLBACK;
