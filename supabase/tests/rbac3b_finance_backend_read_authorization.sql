\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_signature text;
    v_oid oid;
    v_definition text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_get_tenant_settings(uuid)',
        'public.rpc_list_members(uuid)',
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)',
        'public.rpc_list_tracking_tokens(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: missing %', v_signature;
        END IF;

        SELECT pg_get_functiondef(v_oid) INTO v_definition;
        IF NOT EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: unsafe function attributes %', v_signature;
        END IF;

        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: unexpected grants %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_get_tenant_settings(uuid)'
    ] LOOP
        v_definition := pg_get_functiondef(v_signature::regprocedure);
        IF v_definition NOT LIKE '%tanda1_user_has_role%'
           OR v_definition NOT LIKE '%admin%operator%viewer%'
           OR v_definition LIKE '%admin%operator%finance%viewer%' THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: deployment read gate mismatch %', v_signature;
        END IF;
    END LOOP;
END;
$contract$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_admin uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid();
    v_viewer uuid := gen_random_uuid();
    v_operation_a uuid;
    v_operation_b uuid;
    v_deal_a uuid;
    v_deal_b uuid;
    v_pedimento_a uuid;
    v_pedimento_b uuid;
    v_cfdi_a uuid;
BEGIN
    INSERT INTO public.tenants (name, slug)
    VALUES ('RBAC3B A', 'rbac3b-a'), ('RBAC3B B', 'rbac3b-b');

    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'rbac3b-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'rbac3b-b';

    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES
        (v_tenant_a, v_admin, 'admin'),
        (v_tenant_a, v_operator, 'operator'),
        (v_tenant_a, v_finance, 'finance'),
        (v_tenant_a, v_viewer, 'viewer');

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES
        (v_tenant_a, 'RBAC3B-A', 'planned'),
        (v_tenant_b, 'RBAC3B-B', 'planned');

    SELECT id INTO v_operation_a FROM public.operations WHERE reference_code = 'RBAC3B-A';
    SELECT id INTO v_operation_b FROM public.operations WHERE reference_code = 'RBAC3B-B';

    INSERT INTO public.crm_deals (tenant_id, title, stage)
    VALUES
        (v_tenant_a, 'RBAC3B Deal A', 'lead'),
        (v_tenant_b, 'RBAC3B Deal B', 'lead');
    SELECT id INTO v_deal_a FROM public.crm_deals WHERE title = 'RBAC3B Deal A';
    SELECT id INTO v_deal_b FROM public.crm_deals WHERE title = 'RBAC3B Deal B';

    INSERT INTO public.customs_pedimentos (tenant_id, pedimento_number, status)
    VALUES
        (v_tenant_a, 'RBAC3B-PED-A', 'draft'),
        (v_tenant_b, 'RBAC3B-PED-B', 'draft');
    SELECT id INTO v_pedimento_a FROM public.customs_pedimentos WHERE pedimento_number = 'RBAC3B-PED-A';
    SELECT id INTO v_pedimento_b FROM public.customs_pedimentos WHERE pedimento_number = 'RBAC3B-PED-B';

    INSERT INTO public.billing_cfdis (tenant_id, rfc_emisor, rfc_receptor, total, status)
    VALUES (v_tenant_a, 'AAA010101AAA', 'BBB010101BBB', 116, 'draft')
    RETURNING id INTO v_cfdi_a;

    PERFORM set_config('rbac3b.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('rbac3b.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('rbac3b.admin', v_admin::text, true);
    PERFORM set_config('rbac3b.operator', v_operator::text, true);
    PERFORM set_config('rbac3b.finance', v_finance::text, true);
    PERFORM set_config('rbac3b.viewer', v_viewer::text, true);
    PERFORM set_config('rbac3b.operation_a', v_operation_a::text, true);
    PERFORM set_config('rbac3b.operation_b', v_operation_b::text, true);
    PERFORM set_config('rbac3b.deal_a', v_deal_a::text, true);
    PERFORM set_config('rbac3b.deal_b', v_deal_b::text, true);
    PERFORM set_config('rbac3b.pedimento_a', v_pedimento_a::text, true);
    PERFORM set_config('rbac3b.pedimento_b', v_pedimento_b::text, true);
    PERFORM set_config('rbac3b.cfdi_a', v_cfdi_a::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin_allow$
DECLARE
    v_tenant uuid := current_setting('rbac3b.tenant_a')::uuid;
    v_deal uuid := current_setting('rbac3b.deal_a')::uuid;
    v_pedimento uuid := current_setting('rbac3b.pedimento_a')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3b.admin'), true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('rbac3b.admin'), 'role', 'authenticated')::text,
        true
    );

    IF public.rpc_list_inventory_lots(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_list_pedimentos(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_list_descargo_lines(v_pedimento) ? 'error'
       OR public.rpc_list_deals(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_deal(v_deal) ? 'error'
       OR public.rpc_list_deal_activities(v_deal) ? 'error'
       OR public.rpc_list_deal_notes(v_deal) ? 'error'
       OR public.rpc_list_deal_checklist(v_deal) ? 'error'
       OR public.rpc_get_tenant_settings(v_tenant) ? 'error'
       OR public.rpc_list_members(v_tenant) ? 'error'
       OR public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL) ? 'error'
       OR public.rpc_list_tracking_tokens(v_tenant) ? 'error' THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: admin denied an administrative read';
    END IF;
END;
$admin_allow$;

DO $finance_deny_and_allow$
DECLARE
    v_tenant uuid := current_setting('rbac3b.tenant_a')::uuid;
    v_operation uuid := current_setting('rbac3b.operation_a')::uuid;
    v_deal uuid := current_setting('rbac3b.deal_a')::uuid;
    v_pedimento uuid := current_setting('rbac3b.pedimento_a')::uuid;
    v_cfdi uuid := current_setting('rbac3b.cfdi_a')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3b.finance'), true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('rbac3b.finance'), 'role', 'authenticated')::text,
        true
    );

    IF public.rpc_list_inventory_lots(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_pedimentos(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_descargo_lines(v_pedimento) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deals(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_deal(v_deal) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_activities(v_deal) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_notes(v_deal) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_checklist(v_deal) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_tenant_settings(v_tenant) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_members(v_tenant) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_tracking_tokens(v_tenant) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: finance reached a denied administrative read';
    END IF;

    IF public.rpc_dashboard_overview(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_dashboard_recent_activity(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_dashboard_alerts(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_list_operations(v_tenant) ? 'error'
       OR public.rpc_get_operation(v_operation) ? 'error'
       OR public.rpc_get_operation_requirements(v_operation) ? 'error'
       OR public.rpc_list_route_points(v_operation, NULL, NULL, 500) ? 'error'
       OR public.rpc_list_cfdis(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_cfdi_detail(v_cfdi) ? 'error'
       OR public.rpc_finance_overview(v_tenant) ? 'error'
       OR public.rpc_list_finance_invoices(v_tenant, 50, NULL, NULL) ? 'error'
       OR public.rpc_reports_financial_summary(v_tenant, 'monthly') ? 'error'
       OR public.rpc_reports_pipeline_summary(v_tenant) ? 'error'
       OR public.rpc_reports_inventory_summary(v_tenant) ? 'error'
       OR public.rpc_reports_operations_summary(v_tenant) ? 'error' THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: finance denied an approved read';
    END IF;
END;
$finance_deny_and_allow$;

DO $product_roles_preserved$
DECLARE
    v_tenant uuid := current_setting('rbac3b.tenant_a')::uuid;
    v_deal uuid := current_setting('rbac3b.deal_a')::uuid;
    v_pedimento uuid := current_setting('rbac3b.pedimento_a')::uuid;
    v_user text;
BEGIN
    FOREACH v_user IN ARRAY ARRAY[current_setting('rbac3b.operator'), current_setting('rbac3b.viewer')] LOOP
        PERFORM set_config('request.jwt.claim.sub', v_user, true);
        PERFORM set_config(
            'request.jwt.claims',
            jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
            true
        );

        IF public.rpc_list_inventory_lots(v_tenant, '{}'::jsonb) ? 'error'
           OR public.rpc_list_pedimentos(v_tenant, '{}'::jsonb) ? 'error'
           OR public.rpc_list_descargo_lines(v_pedimento) ? 'error'
           OR public.rpc_list_deals(v_tenant, '{}'::jsonb) ? 'error'
           OR public.rpc_get_deal(v_deal) ? 'error'
           OR public.rpc_list_deal_activities(v_deal) ? 'error'
           OR public.rpc_list_deal_notes(v_deal) ? 'error'
           OR public.rpc_list_deal_checklist(v_deal) ? 'error'
           OR public.rpc_get_tenant_settings(v_tenant) ? 'error' THEN
            RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: product role read contract removed';
        END IF;
    END LOOP;
END;
$product_roles_preserved$;

DO $isolation$
DECLARE
    v_tenant_a uuid := current_setting('rbac3b.tenant_a')::uuid;
    v_tenant_b uuid := current_setting('rbac3b.tenant_b')::uuid;
    v_deal_b uuid := current_setting('rbac3b.deal_b')::uuid;
    v_pedimento_b uuid := current_setting('rbac3b.pedimento_b')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3b.admin'), true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('rbac3b.admin'), 'role', 'authenticated')::text,
        true
    );

    IF public.rpc_list_inventory_lots(v_tenant_b, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_pedimentos(v_tenant_b, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_descargo_lines(v_pedimento_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deals(v_tenant_b, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_deal(v_deal_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_activities(v_deal_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_notes(v_deal_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deal_checklist(v_deal_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_tenant_settings(v_tenant_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_members(v_tenant_b) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_tenant_b, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_tracking_tokens(v_tenant_b) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: cross-tenant isolation weakened';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text,
        true
    );

    IF public.rpc_list_inventory_lots(v_tenant_a, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_deals(v_tenant_a, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_tenant_settings(v_tenant_a) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_members(v_tenant_a) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_tenant_a, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_tracking_tokens(v_tenant_a) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: non-member access weakened';
    END IF;
END;
$isolation$;

RESET ROLE;

DO $done$
BEGIN
    RAISE NOTICE 'RBAC.3B Finance backend read authorization passed; fixtures will roll back';
END;
$done$;

ROLLBACK;
