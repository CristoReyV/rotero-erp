\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE v_signature text; v_oid oid; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_attention_items(uuid)',
        'public.rpc_get_executive_dashboard(uuid,timestamptz,timestamptz)',
        'public.rpc_refresh_internal_notifications(uuid)',
        'public.rpc_list_internal_notifications(uuid,integer,boolean)',
        'public.rpc_get_internal_notification_unread_count(uuid)',
        'public.rpc_mark_internal_notifications_read(uuid,uuid[])',
        'public.rpc_dismiss_internal_notification(uuid)',
        'public.rpc_dismiss_internal_notification(uuid,uuid)',
        'public.rpc_global_search(uuid,text,integer)',
        'public.rpc_list_saved_views(uuid,text)',
        'public.rpc_save_view(uuid,jsonb)',
        'public.rpc_delete_saved_view(uuid,uuid)'
    ] LOOP
        v_oid:=to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F5 CONTRACT FAILED: missing %',v_signature; END IF;
        IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=v_oid AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog, public']::text[]) THEN
            RAISE EXCEPTION 'F5 CONTRACT FAILED: unsafe function %',v_signature;
        END IF;
        IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
           OR has_function_privilege('anon',v_oid,'EXECUTE')
           OR has_function_privilege('service_role',v_oid,'EXECUTE') THEN
            RAISE EXCEPTION 'F5 CONTRACT FAILED: ACL %',v_signature;
        END IF;
        IF pg_get_functiondef(v_oid) ~* '\mSQLERRM\M' THEN RAISE EXCEPTION 'F5 CONTRACT FAILED: raw SQLERRM %',v_signature; END IF;
    END LOOP;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='internal_notifications'
          AND column_name IN ('module','kind','entity_type','entity_id','occurred_at','created_at','updated_at')
    ) THEN RAISE EXCEPTION 'F5 CONTRACT FAILED: parallel notification columns'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='internal_notifications' AND column_name='due_at'
    ) THEN RAISE EXCEPTION 'F5 CONTRACT FAILED: due_at extension missing'; END IF;
    FOREACH v_table IN ARRAY ARRAY['internal_notification_rules','internal_notifications','user_saved_views'] LOOP
        IF to_regclass('public.'||v_table) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||v_table) AND relrowsecurity) THEN
            RAISE EXCEPTION 'F5 CONTRACT FAILED: table/RLS %',v_table;
        END IF;
        IF has_table_privilege('authenticated','public.'||v_table,'SELECT')
           OR has_table_privilege('authenticated','public.'||v_table,'INSERT')
           OR has_table_privilege('authenticated','public.'||v_table,'UPDATE')
           OR has_table_privilege('authenticated','public.'||v_table,'DELETE')
           OR has_table_privilege('anon','public.'||v_table,'SELECT')
           OR has_table_privilege('service_role','public.'||v_table,'SELECT') THEN
            RAISE EXCEPTION 'F5 CONTRACT FAILED: direct table privilege %',v_table;
        END IF;
    END LOOP;
END;
$contract$;

DO $fixtures$
DECLARE
    v_tenant uuid:=gen_random_uuid(); v_other uuid:=gen_random_uuid();
    v_admin uuid:=gen_random_uuid(); v_finance uuid:=gen_random_uuid(); v_finance_b uuid:=gen_random_uuid(); v_outsider uuid:=gen_random_uuid();
    v_customer uuid; v_provider uuid; v_quote_review uuid; v_quote_approved uuid; v_operation uuid; v_planned uuid; v_incident uuid;
    v_ar uuid; v_ap uuid; v_operation_doc uuid; v_commercial_doc uuid;
BEGIN
    INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f5-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f5-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance_b,'authenticated','authenticated','f5-finance-b@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_outsider,'authenticated','authenticated','f5-outsider@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES('F5 Tenant','f5-tenant'),('F5 Other','f5-other');
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f5-tenant'; SELECT id INTO v_other FROM public.tenants WHERE slug='f5-other';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(v_tenant,v_admin,'admin'),(v_tenant,v_finance,'finance'),(v_tenant,v_finance_b,'finance');
    INSERT INTO public.customers(tenant_id,display_name,legal_name,tax_id) VALUES(v_tenant,'Cliente F5','Cliente Ejecutivo F5','CEF010101AA1') RETURNING id INTO v_customer;
    INSERT INTO public.logistics_providers(tenant_id,display_name,legal_name,tax_id) VALUES(v_tenant,'Proveedor F5','Proveedor Ejecutivo F5','PEF010101AA1') RETURNING id INTO v_provider;
    INSERT INTO public.crm_deals(tenant_id,customer_id,title,company,stage,quote_status,quote_reference,quote_payload)
      VALUES(v_tenant,v_customer,'Cotización F5 revisión','Cliente F5','proposal','in_review','Q-F5-REVIEW','{}') RETURNING id INTO v_quote_review;
    INSERT INTO public.crm_deals(tenant_id,customer_id,title,company,stage,quote_status,quote_reference,quote_payload,approved_at,approved_by)
      VALUES(v_tenant,v_customer,'Cotización F5 aprobada','Cliente F5','won','approved','Q-F5-APPROVED','{}',now(),v_admin) RETURNING id INTO v_quote_approved;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,destination_city,status,customer_id,provider_id,service_type,origin_place,destination_place,operational_window_start,operational_window_end,provider_cost_amount,customer_price_amount)
      VALUES(v_tenant,'OP-F5-DELIVERED','Cliente F5','Monterrey','delivered',v_customer,v_provider,'Carga terrestre','{"municipality":"CDMX","state":"CDMX"}','{"municipality":"Monterrey","state":"NL"}',now()-interval '2 days',now()-interval '1 day',500,800) RETURNING id INTO v_operation;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,status)
      VALUES(v_tenant,'OP-F5-BLOCKED','Cliente F5','planned') RETURNING id INTO v_planned;
    INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,description,is_blocking,reported_by)
      VALUES(v_tenant,v_operation,'documents_issue','POD retenido F5','Falta evidencia firmada',true,v_admin) RETURNING id INTO v_incident;
    INSERT INTO public.operation_documents(tenant_id,operation_id,document_type,requirement_level,status,updated_by)
      VALUES(v_tenant,v_operation,'proof_of_delivery','required','missing',v_admin) RETURNING id INTO v_operation_doc;
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,customer_id,operation_id)
      VALUES(v_tenant,'ar','Cliente Finanzas F5','AR-F5',1000,'MXN','open',current_date-5,v_customer,v_operation) RETURNING id INTO v_ar;
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,provider_id,operation_id)
      VALUES(v_tenant,'ap','Proveedor Finanzas F5','AP-F5',600,'MXN','open',current_date+3,v_provider,v_operation) RETURNING id INTO v_ap;
    INSERT INTO public.document_files(tenant_id,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,source_module,source_entity_type,source_entity_id,uploaded_by)
      VALUES(v_tenant,v_tenant||'/operations/operation/'||v_operation||'/'||gen_random_uuid()||'.pdf','operation-f5.pdf','application/pdf',100,repeat('a',64),'supporting_file','operations','operation',v_operation,v_admin) RETURNING id INTO v_operation_doc;
    INSERT INTO public.document_files(tenant_id,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,source_module,source_entity_type,source_entity_id,uploaded_by)
      VALUES(v_tenant,v_tenant||'/commercial/quote/'||v_quote_review||'/'||gen_random_uuid()||'.pdf','commercial-f5.pdf','application/pdf',100,repeat('b',64),'supporting_file','commercial','quote',v_quote_review,v_admin) RETURNING id INTO v_commercial_doc;
    INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES
      (v_tenant,v_admin,'finance_invoice_created','finance_invoice',v_ar),
      (v_tenant,v_admin,'operation_updated','operation',v_operation),
      (v_tenant,v_admin,'quote_approved','quote',v_quote_approved);
    PERFORM set_config('f5.tenant',v_tenant::text,true); PERFORM set_config('f5.other',v_other::text,true);
    PERFORM set_config('f5.admin',v_admin::text,true); PERFORM set_config('f5.finance',v_finance::text,true);
    PERFORM set_config('f5.finance_b',v_finance_b::text,true); PERFORM set_config('f5.outsider',v_outsider::text,true);
    PERFORM set_config('f5.operation',v_operation::text,true); PERFORM set_config('f5.ar',v_ar::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin$
DECLARE v_tenant uuid:=current_setting('f5.tenant')::uuid; v_result jsonb; v_result_2 jsonb; v_view jsonb; v_notification uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f5.admin'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f5.admin'),'role','authenticated')::text,true);
    v_result:=public.rpc_get_executive_dashboard(v_tenant,now()-interval '30 days',now()+interval '1 day');
    IF v_result?'error' OR NOT v_result?'commercial' OR NOT v_result?'operations' OR NOT v_result?'finance' OR NOT v_result?'documents' THEN RAISE EXCEPTION 'F5 ADMIN DASHBOARD FAILED: %',v_result; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='commercial')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='operations')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='finance')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='documents') THEN
        RAISE EXCEPTION 'F5 ADMIN ATTENTION FAILED: %',v_result->'attention';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'recent_activity') x WHERE x->>'module'='commercial') THEN RAISE EXCEPTION 'F5 ADMIN ACTIVITY FAILED'; END IF;
    v_result:=public.rpc_global_search(v_tenant,'F5',5);
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='operation')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='customer')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='provider')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='quote')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='document')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='finance_invoice') THEN RAISE EXCEPTION 'F5 ADMIN SEARCH FAILED: %',v_result; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE NULLIF(x->>'route','') IS NULL) THEN RAISE EXCEPTION 'F5 DEEP LINK FAILED'; END IF;
    IF public.rpc_refresh_internal_notifications(v_tenant)?'error' THEN RAISE EXCEPTION 'F5 ADMIN NOTIFICATION REFRESH FAILED'; END IF;
    v_result:=public.rpc_list_internal_notifications(v_tenant,100,false);
    IF jsonb_array_length(v_result->'items')<4 OR (v_result->>'unread_count')::integer<4 THEN RAISE EXCEPTION 'F5 ADMIN NOTIFICATIONS FAILED: %',v_result; END IF;
    v_notification:=(v_result#>>'{items,0,id}')::uuid; PERFORM set_config('f5.admin_notification',v_notification::text,true);
    PERFORM public.rpc_refresh_internal_notifications(v_tenant); v_result_2:=public.rpc_list_internal_notifications(v_tenant,100,false);
    IF jsonb_array_length(v_result->'items')<>jsonb_array_length(v_result_2->'items') THEN RAISE EXCEPTION 'F5 DUPLICATE NOTIFICATION FAILED'; END IF;
    IF public.rpc_mark_internal_notifications_read(v_tenant,ARRAY[v_notification])->>'success'<>'true' THEN RAISE EXCEPTION 'F5 MARK READ FAILED'; END IF;
    IF (public.rpc_get_internal_notification_unread_count(v_tenant)->>'count')::integer<>(v_result->>'unread_count')::integer-1 THEN RAISE EXCEPTION 'F5 UNREAD COUNT FAILED'; END IF;
    v_view:=public.rpc_save_view(v_tenant,jsonb_build_object('module','operations','name','Bloqueadas','filters',jsonb_build_object('view','all','status','planned'),'is_default',true));
    IF v_view?'error' THEN RAISE EXCEPTION 'F5 SAVE VIEW FAILED: %',v_view; END IF; PERFORM set_config('f5.admin_view',v_view->>'id',true);
    v_view:=public.rpc_save_view(v_tenant,v_view||jsonb_build_object('name','Bloqueadas renombradas'));
    IF v_view->>'name'<>'Bloqueadas renombradas' OR jsonb_array_length(public.rpc_list_saved_views(v_tenant,'operations')->'items')<>1 THEN RAISE EXCEPTION 'F5 RENAME/LIST VIEW FAILED'; END IF;
END;
$admin$;

DO $finance$
DECLARE v_tenant uuid:=current_setting('f5.tenant')::uuid; v_result jsonb; v_view jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f5.finance'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f5.finance'),'role','authenticated')::text,true);
    v_result:=public.rpc_get_executive_dashboard(v_tenant,now()-interval '30 days',now()+interval '1 day');
    IF v_result?'error' OR v_result?'commercial' THEN RAISE EXCEPTION 'F5 FINANCE DASHBOARD LEAK: %',v_result; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='commercial')
       OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'recent_activity') x WHERE x->>'module'='commercial') THEN RAISE EXCEPTION 'F5 FINANCE ATTENTION/ACTIVITY LEAK'; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='finance')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'attention') x WHERE x->>'module'='operations') THEN RAISE EXCEPTION 'F5 FINANCE APPROVED CONTEXT MISSING'; END IF;
    v_result:=public.rpc_global_search(v_tenant,'F5',10);
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type' IN ('quote','customer','provider'))
       OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='document' AND x->>'primary_label'='commercial-f5.pdf') THEN RAISE EXCEPTION 'F5 FINANCE SEARCH LEAK: %',v_result; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='operation')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='finance_invoice')
       OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'type'='document') THEN RAISE EXCEPTION 'F5 FINANCE SEARCH MISSING: %',v_result; END IF;
    PERFORM public.rpc_refresh_internal_notifications(v_tenant); v_result:=public.rpc_list_internal_notifications(v_tenant,100,false);
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'module'='commercial') THEN RAISE EXCEPTION 'F5 FINANCE NOTIFICATION LEAK'; END IF;
    IF public.rpc_list_saved_views(v_tenant,'commercial')->>'error'<>'unauthorized'
       OR public.rpc_save_view(v_tenant,'{"module":"commercial","name":"No","filters":{}}')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F5 FINANCE COMMERCIAL VIEW FAILED'; END IF;
    v_view:=public.rpc_save_view(v_tenant,'{"module":"finance","name":"AR vencida","filters":{"view":"ar","status":"overdue"}}');
    IF v_view?'error' THEN RAISE EXCEPTION 'F5 FINANCE SAVE VIEW FAILED: %',v_view; END IF;
END;
$finance$;

DO $ownership$
DECLARE v_tenant uuid:=current_setting('f5.tenant')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f5.finance_b'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f5.finance_b'),'role','authenticated')::text,true);
    IF public.rpc_dismiss_internal_notification(v_tenant,current_setting('f5.admin_notification')::uuid)->>'error'<>'not_found'
       OR public.rpc_delete_saved_view(v_tenant,current_setting('f5.admin_view')::uuid)->>'error'<>'not_found' THEN RAISE EXCEPTION 'F5 OWNER ISOLATION FAILED'; END IF;
    IF public.rpc_refresh_internal_notifications(v_tenant)?'error' THEN RAISE EXCEPTION 'F5 SECOND USER REFRESH FAILED'; END IF;
END;
$ownership$;

DO $nonmember$
DECLARE v_tenant uuid:=current_setting('f5.tenant')::uuid; v_other uuid:=current_setting('f5.other')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f5.outsider'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f5.outsider'),'role','authenticated')::text,true);
    IF public.rpc_get_executive_dashboard(v_tenant,NULL,NULL)->>'error'<>'unauthorized'
       OR public.rpc_global_search(v_tenant,'F5',5)->>'error'<>'unauthorized'
       OR public.rpc_list_internal_notifications(v_tenant,10,false)->>'error'<>'unauthorized'
       OR public.rpc_save_view(v_tenant,'{"module":"operations","name":"No","filters":{}}')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F5 NONMEMBER FAILED'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f5.finance'),true);
    IF public.rpc_get_executive_dashboard(v_other,NULL,NULL)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F5 CROSS TENANT FAILED'; END IF;
END;
$nonmember$;

RESET ROLE;

DO $cleanup_contract$
BEGIN
    IF EXISTS(SELECT 1 FROM public.internal_notifications GROUP BY tenant_id,user_id,fingerprint HAVING count(*)>1) THEN RAISE EXCEPTION 'F5 DUPLICATE FINGERPRINT'; END IF;
END;
$cleanup_contract$;

ROLLBACK;
