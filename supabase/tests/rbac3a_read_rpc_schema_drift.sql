\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_signature text;
    v_oid oid;
    v_definition text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_dashboard_overview(uuid,timestamptz,timestamptz)',
        'public.rpc_dashboard_alerts(uuid,timestamptz,timestamptz)',
        'public.rpc_reports_pipeline_summary(uuid)',
        'public.rpc_reports_inventory_summary(uuid)',
        'public.rpc_reports_operations_summary(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'RBAC.3A CONTRACT FAILED: missing %', v_signature;
        END IF;

        SELECT pg_get_functiondef(v_oid) INTO v_definition;
        IF NOT EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND p.provolatile = 's'
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN
            RAISE EXCEPTION 'RBAC.3A CONTRACT FAILED: unsafe function attributes %', v_signature;
        END IF;

        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'RBAC.3A CONTRACT FAILED: unexpected grants %', v_signature;
        END IF;
    END LOOP;

    IF pg_get_functiondef('public.rpc_dashboard_overview(uuid,timestamptz,timestamptz)'::regprocedure) ~ '\missue_date\M'
       OR pg_get_functiondef('public.rpc_dashboard_alerts(uuid,timestamptz,timestamptz)'::regprocedure) ~ '\missue_date\M'
       OR pg_get_functiondef('public.rpc_dashboard_alerts(uuid,timestamptz,timestamptz)'::regprocedure) ~ '\mupdated_at\M'
       OR pg_get_functiondef('public.rpc_reports_pipeline_summary(uuid)'::regprocedure) ~ '\mstatus\M'
       OR pg_get_functiondef('public.rpc_reports_inventory_summary(uuid)'::regprocedure) ~ '\mquantity\M'
       OR pg_get_functiondef('public.rpc_reports_operations_summary(uuid)'::regprocedure) ~ '\morigin\M\s*\|\|\s*\mdestination\M' THEN
        RAISE EXCEPTION 'RBAC.3A CONTRACT FAILED: stale column reference remains';
    END IF;
END;
$contract$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_admin uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants (name, slug)
    VALUES ('RBAC3A A', 'rbac3a-a'), ('RBAC3A B', 'rbac3a-b');

    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'rbac3a-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'rbac3a-b';

    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES
        (v_tenant_a, v_admin, 'admin'),
        (v_tenant_a, v_finance, 'finance');

    INSERT INTO public.billing_cfdis (
        tenant_id, rfc_emisor, rfc_receptor, total, status, created_at
    ) VALUES
        (v_tenant_a, 'AAA010101AAA', 'BBB010101BBB', 116, 'timbrado', '2026-08-01T12:00:00Z'),
        (v_tenant_b, 'AAA010101AAA', 'BBB010101BBB', 999, 'timbrado', '2026-08-01T12:00:00Z');

    INSERT INTO public.finance_invoices (
        tenant_id, direction, counterparty_name, reference, amount, status
    ) VALUES
        (v_tenant_a, 'ar', 'Synthetic A', 'RBAC3A-AR', 100, 'overdue'),
        (v_tenant_b, 'ar', 'Synthetic B', 'RBAC3A-B', 999, 'overdue');

    INSERT INTO public.inventory_lots (
        tenant_id, sku, lot_code, qty_on_hand, qty_reserved, unit_cost, status
    ) VALUES
        (v_tenant_a, 'SKU-A', 'LOT-A', 8, 1, 10, 'available'),
        (v_tenant_a, 'SKU-B', 'LOT-B', 20, 0, 5, 'blocked'),
        (v_tenant_b, 'SKU-X', 'LOT-X', 99, 0, 99, 'available');

    INSERT INTO public.crm_deals (tenant_id, title, value, stage)
    VALUES
        (v_tenant_a, 'Lead', 100, 'lead'),
        (v_tenant_a, 'Qualified', 200, 'qualified'),
        (v_tenant_a, 'Proposal', 300, 'proposal'),
        (v_tenant_a, 'Won', 400, 'won'),
        (v_tenant_a, 'Lost', 500, 'lost'),
        (v_tenant_b, 'Other tenant', 999, 'won');

    INSERT INTO public.operations (
        tenant_id, reference_code, status, created_at, updated_at
    ) VALUES
        (v_tenant_a, 'RBAC3A-ASSIGNED', 'assigned', '2026-08-01T00:00:00Z', '2026-08-01T01:00:00Z'),
        (v_tenant_a, 'RBAC3A-TRANSIT', 'in_transit', '2026-08-02T00:00:00Z', '2026-08-02T01:00:00Z'),
        (v_tenant_a, 'RBAC3A-CLOSED', 'closed', '2026-08-03T00:00:00Z', '2026-08-05T00:00:00Z'),
        (v_tenant_b, 'RBAC3A-OTHER', 'in_transit', '2026-08-01T00:00:00Z', '2026-08-01T01:00:00Z');

    PERFORM set_config('rbac3a.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('rbac3a.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('rbac3a.admin', v_admin::text, true);
    PERFORM set_config('rbac3a.finance', v_finance::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $runtime$
DECLARE
    v_tenant uuid := current_setting('rbac3a.tenant_a')::uuid;
    v_other uuid := current_setting('rbac3a.tenant_b')::uuid;
    v_result jsonb;
    v_user text;
BEGIN
    FOREACH v_user IN ARRAY ARRAY[
        current_setting('rbac3a.admin'),
        current_setting('rbac3a.finance')
    ] LOOP
        PERFORM set_config('request.jwt.claim.sub', v_user, true);
        PERFORM set_config(
            'request.jwt.claims',
            jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
            true
        );

        v_result := public.rpc_dashboard_overview(
            v_tenant,
            '2026-08-01T00:00:00Z',
            '2026-08-31T23:59:59Z'
        );
        IF v_result ? 'error'
           OR jsonb_typeof(v_result->'kpis') <> 'object'
           OR jsonb_typeof(v_result->'chart'->'data') <> 'array'
           OR (v_result->'kpis'->>'ops_total')::integer <> 3
           OR (v_result->'kpis'->>'billing_total')::numeric <> 116
           OR (v_result->'kpis'->>'inventory_value')::numeric <> 180 THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: dashboard overview shape/value';
        END IF;

        v_result := public.rpc_dashboard_alerts(v_tenant, NULL, NULL);
        IF jsonb_typeof(v_result) <> 'array'
           OR jsonb_array_length(v_result) <> 2
           OR EXISTS (
               SELECT 1
               FROM jsonb_array_elements(v_result) AS alert
               WHERE NOT (alert ?& ARRAY['type', 'title', 'description'])
           ) THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: dashboard alerts shape/value';
        END IF;

        v_result := public.rpc_reports_pipeline_summary(v_tenant);
        IF v_result ? 'error'
           OR jsonb_typeof(v_result->'deals_by_stage') <> 'object'
           OR (v_result->'deals_by_stage'->>'lead')::integer <> 1
           OR (v_result->'deals_by_stage'->>'contacted')::integer <> 1
           OR (v_result->'deals_by_stage'->>'proposal')::integer <> 1
           OR (v_result->'deals_by_stage'->>'won')::integer <> 1
           OR (v_result->>'total_pipeline_value')::numeric <> 1000
           OR (v_result->>'conversion_rate')::numeric <> 20 THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: pipeline shape/value';
        END IF;

        v_result := public.rpc_reports_inventory_summary(v_tenant);
        IF v_result ? 'error'
           OR jsonb_typeof(v_result->'top_skus_by_value') <> 'array'
           OR (v_result->>'inventory_total_value')::numeric <> 180
           OR (v_result->>'blocked_count')::integer <> 1
           OR (v_result->>'low_stock_count')::integer <> 1
           OR jsonb_array_length(v_result->'top_skus_by_value') <> 2 THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: inventory shape/value';
        END IF;

        v_result := public.rpc_reports_operations_summary(v_tenant);
        IF v_result ? 'error'
           OR jsonb_typeof(v_result->'operations_per_month') <> 'array'
           OR (v_result->>'avg_delivery_time')::numeric <> 48
           OR (v_result->>'active_routes_count')::integer <> 2 THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: operations shape/value';
        END IF;

        IF public.rpc_dashboard_overview(v_other, NULL, NULL)->>'error' <> 'unauthorized'
           OR public.rpc_dashboard_alerts(v_other, NULL, NULL)->>'error' <> 'unauthorized'
           OR public.rpc_reports_pipeline_summary(v_other)->>'error' <> 'unauthorized'
           OR public.rpc_reports_inventory_summary(v_other)->>'error' <> 'unauthorized'
           OR public.rpc_reports_operations_summary(v_other)->>'error' <> 'unauthorized' THEN
            RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: cross-tenant access weakened';
        END IF;
    END LOOP;

    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text,
        true
    );
    IF public.rpc_dashboard_overview(v_tenant, NULL, NULL)->>'error' <> 'unauthorized'
       OR public.rpc_dashboard_alerts(v_tenant, NULL, NULL)->>'error' <> 'unauthorized'
       OR public.rpc_reports_pipeline_summary(v_tenant)->>'error' <> 'unauthorized'
       OR public.rpc_reports_inventory_summary(v_tenant)->>'error' <> 'unauthorized'
       OR public.rpc_reports_operations_summary(v_tenant)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3A RUNTIME FAILED: non-member access weakened';
    END IF;
END;
$runtime$;

RESET ROLE;
ROLLBACK;
