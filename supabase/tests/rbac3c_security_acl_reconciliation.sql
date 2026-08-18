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
        'public.rpc_reports_operations_summary(uuid)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_get_tenant_settings(uuid)',
        'public.rpc_list_members(uuid)',
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)',
        'public.rpc_list_route_points(uuid,timestamptz,timestamptz,integer)',
        'public.rpc_list_tracking_tokens(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: missing %', v_signature;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN
            RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: unsafe function attributes %', v_signature;
        END IF;

        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR EXISTS (
               SELECT 1
               FROM pg_proc AS p,
                    LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
               WHERE p.oid = v_oid
                 AND acl.grantee = 0
                 AND acl.privilege_type = 'EXECUTE'
           ) THEN
            RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: unexpected ERP grants %', v_signature;
        END IF;
    END LOOP;

    v_definition := pg_get_functiondef('public.rpc_list_members(uuid)'::regprocedure);
    IF v_definition NOT LIKE '%tanda1_user_has_role%'
       OR v_definition NOT LIKE '%admin%operator%'
       OR v_definition LIKE '%finance%'
       OR v_definition LIKE '%viewer%' THEN
        RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: members role gate mismatch';
    END IF;

    v_definition := pg_get_functiondef(
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)'::regprocedure
    );
    IF v_definition NOT LIKE '%tanda1_user_has_role%'
       OR v_definition NOT LIKE '%admin%viewer%'
       OR v_definition LIKE '%finance%'
       OR v_definition LIKE '%operator%' THEN
        RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: audit role gate mismatch';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.tracking_hash_token(text)',
        'public.tracking_validate_token(text,text)',
        'public.rpc_get_public_tracking(text)',
        'public.rpc_get_driver_view(text)',
        'public.rpc_post_driver_event(text,text,text,numeric,numeric,numeric,text,text,character,text,text,timestamptz,boolean)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL
           OR NOT has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: private Tracking grants changed %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_dashboard_overview(uuid)',
        'public.rpc_dashboard_alerts(uuid)',
        'public.rpc_list_audit_log(uuid,integer)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NOT NULL AND (
            has_function_privilege('authenticated', v_oid, 'EXECUTE')
            OR has_function_privilege('anon', v_oid, 'EXECUTE')
            OR has_function_privilege('service_role', v_oid, 'EXECUTE')
        ) THEN
            RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: ambiguous legacy overload remains exposed %', v_signature;
        END IF;
    END LOOP;

    v_oid := to_regprocedure(
        'public.rpc_list_route_points(uuid,timestamptz,timestamptz,integer,integer)'
    );
    IF v_oid IS NOT NULL AND (
        NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
        OR has_function_privilege('anon', v_oid, 'EXECUTE')
        OR has_function_privilege('service_role', v_oid, 'EXECUTE')
    ) THEN
        RAISE EXCEPTION 'RBAC.3C CONTRACT FAILED: legacy route overload grants mismatch';
    END IF;
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
    v_operation uuid;
    v_deal uuid;
    v_pedimento uuid;
    v_cfdi uuid;
BEGIN
    INSERT INTO public.tenants (name, slug)
    VALUES ('RBAC3C A', 'rbac3c-a'), ('RBAC3C B', 'rbac3c-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'rbac3c-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'rbac3c-b';

    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES
        (v_tenant_a, v_admin, 'admin'),
        (v_tenant_a, v_operator, 'operator'),
        (v_tenant_a, v_finance, 'finance'),
        (v_tenant_a, v_viewer, 'viewer');

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES (v_tenant_a, 'RBAC3C-OP', 'planned')
    RETURNING id INTO v_operation;

    INSERT INTO public.crm_deals (tenant_id, title, stage)
    VALUES (v_tenant_a, 'RBAC3C Deal', 'lead')
    RETURNING id INTO v_deal;

    INSERT INTO public.customs_pedimentos (tenant_id, pedimento_number, status)
    VALUES (v_tenant_a, 'RBAC3C-PED', 'draft')
    RETURNING id INTO v_pedimento;

    INSERT INTO public.billing_cfdis (tenant_id, rfc_emisor, rfc_receptor, total, status)
    VALUES (v_tenant_a, 'AAA010101AAA', 'BBB010101BBB', 116, 'draft')
    RETURNING id INTO v_cfdi;

    PERFORM set_config('rbac3c.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('rbac3c.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('rbac3c.admin', v_admin::text, true);
    PERFORM set_config('rbac3c.operator', v_operator::text, true);
    PERFORM set_config('rbac3c.finance', v_finance::text, true);
    PERFORM set_config('rbac3c.viewer', v_viewer::text, true);
    PERFORM set_config('rbac3c.operation', v_operation::text, true);
    PERFORM set_config('rbac3c.deal', v_deal::text, true);
    PERFORM set_config('rbac3c.pedimento', v_pedimento::text, true);
    PERFORM set_config('rbac3c.cfdi', v_cfdi::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $role_matrix$
DECLARE
    v_tenant uuid := current_setting('rbac3c.tenant_a')::uuid;
    v_other uuid := current_setting('rbac3c.tenant_b')::uuid;
    v_operation uuid := current_setting('rbac3c.operation')::uuid;
    v_deal uuid := current_setting('rbac3c.deal')::uuid;
    v_pedimento uuid := current_setting('rbac3c.pedimento')::uuid;
    v_cfdi uuid := current_setting('rbac3c.cfdi')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3c.admin'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('rbac3c.admin'), 'role', 'authenticated'
    )::text, true);

    v_result := public.rpc_list_members(v_tenant);
    IF jsonb_typeof(v_result) <> 'array' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: members response shape changed';
    END IF;
    v_result := public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL);
    IF v_result ? 'error'
       OR NOT (v_result ?& ARRAY['items', 'total', 'distinct_entities', 'distinct_actions']) THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: audit response shape changed';
    END IF;
    IF public.rpc_dashboard_overview(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_dashboard_alerts(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_reports_pipeline_summary(v_tenant) ? 'error'
       OR public.rpc_reports_inventory_summary(v_tenant) ? 'error'
       OR public.rpc_reports_operations_summary(v_tenant) ? 'error'
       OR public.rpc_list_inventory_lots(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_list_pedimentos(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_list_descargo_lines(v_pedimento) ? 'error'
       OR public.rpc_list_deals(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_deal(v_deal) ? 'error'
       OR public.rpc_list_deal_activities(v_deal) ? 'error'
       OR public.rpc_list_deal_notes(v_deal) ? 'error'
       OR public.rpc_list_deal_checklist(v_deal) ? 'error'
       OR public.rpc_get_tenant_settings(v_tenant) ? 'error' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: admin read denied';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3c.finance'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('rbac3c.finance'), 'role', 'authenticated'
    )::text, true);

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
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: finance reached denied read';
    END IF;

    IF public.rpc_dashboard_overview(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_dashboard_alerts(v_tenant, NULL, NULL) ? 'error'
       OR public.rpc_list_operations(v_tenant) ? 'error'
       OR public.rpc_get_operation(v_operation) ? 'error'
       OR public.rpc_list_route_points(v_operation, NULL, NULL, 500) ? 'error'
       OR public.rpc_list_cfdis(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_cfdi_detail(v_cfdi) ? 'error'
       OR public.rpc_finance_overview(v_tenant) ? 'error'
       OR public.rpc_list_finance_invoices(v_tenant, 50, NULL, NULL) ? 'error'
       OR public.rpc_reports_financial_summary(v_tenant, 'monthly') ? 'error'
       OR public.rpc_reports_pipeline_summary(v_tenant) ? 'error'
       OR public.rpc_reports_inventory_summary(v_tenant) ? 'error'
       OR public.rpc_reports_operations_summary(v_tenant) ? 'error' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: finance approved read denied';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3c.operator'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('rbac3c.operator'), 'role', 'authenticated'
    )::text, true);
    IF public.rpc_list_members(v_tenant) ? 'error'
       OR public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: operator Security contract mismatch';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3c.viewer'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('rbac3c.viewer'), 'role', 'authenticated'
    )::text, true);
    IF public.rpc_list_members(v_tenant) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL) ? 'error' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: viewer Security contract mismatch';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3c.admin'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('rbac3c.admin'), 'role', 'authenticated'
    )::text, true);
    IF public.rpc_list_members(v_other) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_other, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: cross-tenant Security access';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated'
    )::text, true);
    IF public.rpc_list_members(v_tenant) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_audit_log(v_tenant, 50, 0, NULL, NULL, NULL, NULL) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'RBAC.3C RUNTIME FAILED: non-member Security access';
    END IF;
END;
$role_matrix$;

RESET ROLE;

DO $done$
BEGIN
    RAISE NOTICE 'RBAC.3C Security authorization and ACL reconciliation passed; fixtures will roll back';
END;
$done$;

ROLLBACK;
