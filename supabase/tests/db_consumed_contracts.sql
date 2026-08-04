\set ON_ERROR_STOP on

BEGIN;

DO $columns$
DECLARE
    v_spec text;
    v_table text;
    v_column text;
    v_type text;
BEGIN
    FOREACH v_spec IN ARRAY ARRAY[
        'operations.provider_cost_amount:numeric',
        'operations.customer_price_amount:numeric',
        'operations.documentation_received_note:text',
        'operations.execution_type:text',
        'operations.provider_id:uuid',
        'operations.provider_name:text',
        'operations.external_driver:jsonb',
        'operations.external_vehicle:jsonb',
        'operations.operation_scope:text',
        'operations.pricing_currency:text',
        'operations.service_catalog_snapshot:jsonb',
        'operations.driver_id:uuid',
        'operations.vehicle_id:uuid',
        'operations.driver_name:text',
        'operations.vehicle_ref:text',
        'billing_cfdis.uuid:text',
        'billing_cfdis.rfc_emisor:text',
        'billing_cfdis.rfc_receptor:text',
        'billing_cfdis.receptor_name:text',
        'billing_cfdis.has_carta_porte:boolean',
        'billing_cfdis.has_complemento_pago:boolean',
        'billing_cfdis.exchange_rate:numeric',
        'billing_cfdis.total_mxn:numeric',
        'billing_carta_porte.trans_type:text',
        'billing_carta_porte.vehicle_plate:text',
        'billing_carta_porte.carrier_name:text',
        'billing_carta_porte.origin:text',
        'billing_carta_porte.destination:text',
        'billing_carta_porte.goods_desc:text',
        'operation_billing.billing_reference:text',
        'operation_billing.admin_close_override:boolean',
        'finance_invoices.direction:text',
        'finance_invoices.counterparty_name:text',
        'finance_invoices.reference:text',
        'finance_invoices.amount:numeric',
        'finance_invoices.linked_cfdi_id:uuid',
        'finance_invoices.operation_id:uuid',
        'finance_payments.invoice_id:uuid',
        'finance_payments.bank_reference:text',
        'finance_payments.created_by:uuid',
        'inventory_lots.qty_on_hand:numeric',
        'inventory_lots.qty_reserved:numeric',
        'inventory_lots.warehouse:text',
        'inventory_lots.lot_code:text',
        'inventory_lots.unit_cost:numeric',
        'customs_pedimentos.aduana:text',
        'customs_pedimentos.regimen:text',
        'customs_pedimentos.tipo_operacion:text',
        'customs_pedimentos.total_value:numeric',
        'customs_descargo_lines.sequence_no:integer',
        'customs_descargo_lines.sku:text',
        'customs_descargo_lines.qty:numeric',
        'customs_descargo_lines.inventory_lot_id:uuid',
        'audit_log.actor_user_id:uuid',
        'audit_log.actor_email:text',
        'audit_log.actor_name:text',
        'audit_log.details:jsonb',
        'tracking_events.country_code:character',
        'tenant_setup_status.module_name:text',
        'tenant_setup_status.config_data:jsonb'
    ] LOOP
        v_table := split_part(split_part(v_spec, ':', 1), '.', 1);
        v_column := split_part(split_part(v_spec, ':', 1), '.', 2);
        v_type := split_part(v_spec, ':', 2);
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns AS c
            WHERE c.table_schema = 'public' AND c.table_name = v_table
              AND c.column_name = v_column AND c.data_type = v_type
        ) THEN
            RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: missing/incompatible %.% (%)', v_table, v_column, v_type;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND (
            (c.table_name = 'operations' AND c.column_name IN ('provider_cost', 'customer_price', 'documentation_note'))
            OR (c.table_name = 'inventory_lots' AND c.column_name IN ('quantity', 'metadata'))
            OR (c.table_name = 'billing_cfdis' AND c.column_name IN ('uuid_fiscal', 'payload'))
        )
    ) THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: alternate legacy columns remain';
    END IF;

    IF (SELECT column_default FROM information_schema.columns
        WHERE table_schema='public' AND table_name='operations' AND column_name='status') NOT LIKE '%planned%'
       OR (SELECT is_nullable FROM information_schema.columns
        WHERE table_schema='public' AND table_name='operations' AND column_name='priority') <> 'YES'
       OR (SELECT is_nullable FROM information_schema.columns
        WHERE table_schema='public' AND table_name='tracking_events' AND column_name='country_code') <> 'YES' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: operation/tracking defaults or nullability differ';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid='public.operation_billing'::regclass
          AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%draft%issued%voided%'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid='public.finance_invoices'::regclass
          AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%ar%ap%'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS c
        WHERE c.conrelid='public.customs_descargo_lines'::regclass AND c.contype='f'
          AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%inventory_lot_id%'
    ) THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: state/FK checks are incomplete';
    END IF;
END;
$columns$;

DO $rpcs$
DECLARE
    v_signature text;
    v_oid oid;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_get_my_context()',
        'public.rpc_get_tenant_settings(uuid)',
        'public.rpc_update_tenant_settings(uuid,jsonb)',
        'public.rpc_list_members(uuid)',
        'public.rpc_update_member_role(uuid,uuid,text)',
        'public.rpc_deactivate_member(uuid,uuid)',
        'public.rpc_create_invitation(uuid,text,text)',
        'public.rpc_accept_invitation(text,text,text)',
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)',
        'public.rpc_validate_module_access(uuid,text)',
        'public.rpc_demo_configure_module(uuid,text)',
        'public.rpc_list_operations(uuid)',
        'public.rpc_create_operation(uuid,text,text,text,text,text,text,jsonb,jsonb,timestamptz)',
        'public.rpc_get_operation(uuid)',
        'public.rpc_assign_operation(uuid,uuid,uuid,uuid,timestamptz,text)',
        'public.rpc_assign_operation_v2(uuid,uuid,uuid,text,uuid,text,timestamptz,text)',
        'public.rpc_update_operation_details(uuid,jsonb)',
        'public.rpc_transition_operation_status(uuid,text)',
        'public.rpc_override_operation_status(uuid,text,text)',
        'public.rpc_get_operation_requirements(uuid)',
        'public.rpc_create_tracking_token(uuid,uuid,text)',
        'public.rpc_create_tracking_token(uuid,uuid,text,integer)',
        'public.rpc_create_tracking_token(uuid,uuid,text,boolean)',
        'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)',
        'public.rpc_revoke_tracking_token(uuid)',
        'public.rpc_list_tracking_tokens(uuid)',
        'public.rpc_list_route_points(uuid,timestamptz,timestamptz,integer)',
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_create_deal(uuid,jsonb)',
        'public.rpc_update_deal(uuid,jsonb)',
        'public.rpc_move_deal(uuid,text)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_add_deal_activity(uuid,jsonb)',
        'public.rpc_add_deal_note(uuid,text)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_toggle_deal_checklist_item(uuid,boolean)',
        'public.rpc_list_cfdis(uuid,jsonb)',
        'public.rpc_get_cfdi_detail(uuid)',
        'public.rpc_create_cfdi(uuid,jsonb)',
        'public.rpc_update_cfdi(uuid,jsonb)',
        'public.rpc_upsert_carta_porte(uuid,jsonb)',
        'public.rpc_finance_overview(uuid)',
        'public.rpc_list_finance_invoices(uuid,integer,text,text)',
        'public.rpc_create_finance_invoice(uuid,jsonb)',
        'public.rpc_record_payment(uuid,jsonb)',
        'public.rpc_update_finance_invoice_status(uuid,uuid,text)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_create_inventory_lot(uuid,text,text,numeric,text,timestamptz,text,text,text,text)',
        'public.rpc_update_inventory_lot(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_create_pedimento(uuid,jsonb)',
        'public.rpc_update_pedimento(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_add_descargo_line(uuid,jsonb)',
        'public.rpc_dashboard_overview(uuid,timestamptz,timestamptz)',
        'public.rpc_dashboard_recent_activity(uuid,timestamptz,timestamptz)',
        'public.rpc_dashboard_alerts(uuid,timestamptz,timestamptz)',
        'public.rpc_reports_financial_summary(uuid,text)',
        'public.rpc_reports_pipeline_summary(uuid)',
        'public.rpc_reports_inventory_summary(uuid)',
        'public.rpc_reports_operations_summary(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: missing RPC %', v_signature; END IF;
        IF NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid=v_oid) THEN
            RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: RPC is not SECURITY DEFINER: %', v_signature;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc AS p, unnest(COALESCE(p.proconfig,ARRAY[]::text[])) AS setting
            WHERE p.oid=v_oid AND setting LIKE 'search_path=pg_catalog, public%'
        ) THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: unsafe search_path: %', v_signature; END IF;
        IF NOT has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
            RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: authenticated grant missing: %', v_signature;
        END IF;
        IF has_function_privilege('anon',v_signature,'EXECUTE') OR has_function_privilege('service_role',v_signature,'EXECUTE') THEN
            RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: internal RPC leaked: %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_get_public_tracking(text)',
        'public.rpc_get_driver_view(text)',
        'public.rpc_post_driver_event(text,text,text,numeric,numeric,numeric,text,text,character,text,text,timestamptz,boolean)'
    ] LOOP
        IF to_regprocedure(v_signature) IS NULL OR NOT has_function_privilege('service_role',v_signature,'EXECUTE')
           OR has_function_privilege('anon',v_signature,'EXECUTE') OR has_function_privilege('authenticated',v_signature,'EXECUTE') THEN
            RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: Edge grant/signature mismatch: %',v_signature;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname LIKE 'rpc_%'
          AND pg_catalog.pg_get_functiondef(p.oid) ILIKE '%SQLERRM%'
    ) THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: SQLERRM exposed by canonical RPC'; END IF;

END;
$rpcs$;

DO $privileges$
DECLARE v_role text; v_table text;
BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: public.users exists'; END IF;
    IF has_table_privilege('authenticated','auth.users','SELECT') THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: authenticated can read auth.users globally';
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        FOREACH v_table IN ARRAY ARRAY['public.operations','public.billing_cfdis','public.finance_invoices','public.inventory_lots','public.customs_pedimentos'] LOOP
            IF has_table_privilege(v_role,v_table,'SELECT,INSERT,UPDATE,DELETE') THEN
                RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: direct DML leaked: % %',v_role,v_table;
            END IF;
        END LOOP;
    END LOOP;
    IF NOT has_column_privilege('service_role','public.tracking_access_log','token_hash','INSERT')
       OR NOT has_column_privilege('service_role','public.tracking_access_log','ip_hash','INSERT')
       OR has_column_privilege('authenticated','public.tracking_access_log','token_hash','INSERT')
       OR has_column_privilege('anon','public.tracking_access_log','token_hash','INSERT') THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: access-log exception is not minimal';
    END IF;
END;
$privileges$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_admin uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid();
    v_viewer uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants(name,slug) VALUES ('Consumed A','consumed-a'),('Consumed B','consumed-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug='consumed-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug='consumed-b';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES
        (v_tenant_a,v_admin,'admin'),(v_tenant_a,v_operator,'operator'),(v_tenant_a,v_finance,'finance'),(v_tenant_a,v_viewer,'viewer');
    PERFORM set_config('consumed.tenant_a',v_tenant_a::text,true);
    PERFORM set_config('consumed.tenant_b',v_tenant_b::text,true);
    PERFORM set_config('consumed.admin',v_admin::text,true);
    PERFORM set_config('consumed.operator',v_operator::text,true);
    PERFORM set_config('consumed.finance',v_finance::text,true);
    PERFORM set_config('consumed.viewer',v_viewer::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $smoke$
DECLARE
    v_tenant uuid := current_setting('consumed.tenant_a')::uuid;
    v_other uuid := current_setting('consumed.tenant_b')::uuid;
    v_result jsonb;
    v_operation uuid;
    v_invoice uuid;
    v_pedimento uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('consumed.admin'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('consumed.admin'),'role','authenticated')::text,true);
    v_result:=public.rpc_create_operation(v_tenant,'CONSUMED-001','MTY-SAL','Cliente QA','Saltillo',NULL,'planned',NULL,NULL,NULL);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: create operation %',v_result; END IF;
    v_operation:=(v_result->>'id')::uuid;
    v_result:=public.rpc_create_deal(v_tenant,'{"title":"Contrato QA","company":"Cliente QA","value":1000}'::jsonb);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: CRM %',v_result; END IF;
    v_result:=public.rpc_create_inventory_lot(v_tenant,'SKU-QA','LOT-QA',25,'QA',now(),'MXN',NULL,'Sintetico','Piezas');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: inventory %',v_result; END IF;
    v_result:=public.rpc_create_pedimento(v_tenant,'{"pedimento_number":"PED-QA","status":"draft","total_value":100}'::jsonb);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: customs %',v_result; END IF;
    v_pedimento:=(v_result->>'id')::uuid;
    v_result:=public.rpc_add_descargo_line(v_pedimento,'{"sku":"SKU-QA","qty":1,"unit":"Piezas"}'::jsonb);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: descargo %',v_result; END IF;
    IF jsonb_typeof(public.rpc_dashboard_recent_activity(v_tenant,NULL,NULL))<>'array'
       OR jsonb_typeof(public.rpc_reports_pipeline_summary(v_tenant)->'deals_by_stage')<>'object' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: dashboard/report return mismatch';
    END IF;
    IF public.rpc_list_operations(v_other)->>'error'<>'unauthorized' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: tenant isolation failed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub',current_setting('consumed.operator'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('consumed.operator'),'role','authenticated')::text,true);
    v_result:=public.rpc_create_tracking_token(v_tenant,v_operation,'driver:write',false);
    IF jsonb_typeof(public.rpc_list_operations(v_tenant))<>'array' OR v_result ? 'error' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: operator contract failed';
    END IF;
    PERFORM set_config('consumed.driver_token',v_result->>'token',true);
    v_result:=public.rpc_create_tracking_token(v_tenant,v_operation,'public:read',false);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: public token create failed'; END IF;
    PERFORM set_config('consumed.public_token',v_result->>'token',true);

    PERFORM set_config('request.jwt.claim.sub',current_setting('consumed.finance'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('consumed.finance'),'role','authenticated')::text,true);
    v_result:=public.rpc_create_cfdi(v_tenant,'{"uuid":"00000000-0000-0000-0000-000000000001","folio":"QA-1","rfc_emisor":"AAA010101AAA","rfc_receptor":"BBB010101BBB","total":116,"status":"draft"}'::jsonb);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: billing %',v_result; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','counterparty_name','Cliente QA','reference','QA-1','amount',116,'operation_id',v_operation));
    IF v_result ? 'error' THEN RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: finance %',v_result; END IF;
    v_invoice:=(v_result->>'id')::uuid;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_invoice,'amount',116,'method','transfer'));
    IF v_result ? 'error' OR public.rpc_finance_overview(v_tenant)->>'total_ar_open' IS NULL THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: payment/overview %',v_result;
    END IF;

    PERFORM set_config('request.jwt.claim.sub',current_setting('consumed.viewer'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('consumed.viewer'),'role','authenticated')::text,true);
    IF jsonb_typeof(public.rpc_list_operations(v_tenant))<>'array'
       OR public.rpc_list_finance_invoices(v_tenant,50,NULL,NULL)->>'error'<>'unauthorized'
       OR public.rpc_create_tracking_token(v_tenant,v_operation,'driver:write',false)->>'error'<>'unauthorized' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: viewer role matrix failed';
    END IF;
END;
$smoke$;

RESET ROLE;

SET LOCAL ROLE service_role;

DO $edge_shapes$
DECLARE v_public jsonb; v_driver jsonb;
BEGIN
    v_public:=public.rpc_get_public_tracking(current_setting('consumed.public_token'));
    v_driver:=public.rpc_get_driver_view(current_setting('consumed.driver_token'));
    IF v_public->>'status'<>'success' OR jsonb_typeof(v_public->'data'->'events')<>'array'
       OR v_public->'data'->>'orderRef'<>'CONSUMED-001' OR v_public::text LIKE '%token_hash%'
       OR v_driver->>'status'<>'success' OR v_driver->'data'->>'currentStatus'<>'assigned'
       OR v_driver->'data'->>'orderRef'<>'CONSUMED-001' OR v_driver::text LIKE '%token_hash%' THEN
        RAISE EXCEPTION 'CONSUMED CONTRACT TEST FAILED: Edge response shape mismatch';
    END IF;
END;
$edge_shapes$;

RESET ROLE;

DO $done$
BEGIN
    RAISE NOTICE 'Consumed contracts passed; all synthetic fixtures will roll back';
END;
$done$;

ROLLBACK;
