\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_missing text[];
    v_count bigint;
BEGIN
    SELECT array_agg(name ORDER BY name)
    INTO v_missing
    FROM unnest(ARRAY[
        'tenants', 'memberships', 'operations', 'customers',
        'logistics_providers', 'service_catalog_items', 'crm_deals',
        'tracking_tokens', 'tracking_events', 'tracking_route_points',
        'billing_cfdis', 'billing_carta_porte', 'operation_billing',
        'finance_invoices', 'finance_payments', 'audit_log',
        'invitations', 'tenant_settings', 'tenant_setup_status',
        'inventory_lots', 'customs_pedimentos', 'customs_descargo_lines'
    ]) AS required(name)
    WHERE to_regclass('public.' || name) IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: missing tables: %', array_to_string(v_missing, ', ');
    END IF;

    IF to_regclass('public.users') IS NOT NULL THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: unsafe public.users relation exists';
    END IF;

    SELECT count(*) INTO v_count FROM public.tenants;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: tenants is not empty on fresh baseline';
    END IF;
    SELECT count(*) INTO v_count FROM public.memberships;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: memberships is not empty on fresh baseline';
    END IF;
    SELECT count(*) INTO v_count FROM public.operations;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: operations is not empty on fresh baseline';
    END IF;
    SELECT count(*) INTO v_count FROM public.tracking_tokens;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: tracking_tokens is not empty on fresh baseline';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'operations'
          AND column_name = 'execution_type' AND data_type = 'text'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'operations'
          AND column_name = 'provider_cost_amount' AND data_type = 'numeric'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tracking_tokens'
          AND column_name = 'token_hash' AND is_nullable = 'NO'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invitations'
          AND column_name = 'accepted_by' AND data_type = 'uuid' AND is_nullable = 'YES'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invitations'
          AND column_name = 'revoked_by' AND data_type = 'uuid' AND is_nullable = 'YES'
    ) OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invitations'
          AND column_name = 'updated_at' AND data_type = 'timestamp with time zone' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: fundamental column contract is incomplete';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.memberships'::regclass
          AND conname = 'memberships_user_tenant_key'
          AND contype = 'u'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.operations'::regclass
          AND conname = 'operations_execution_type_check'
          AND contype = 'c'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.operations'::regclass
          AND conname = 'operations_source_deal_fk'
          AND contype = 'f'
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: PK/FK/unique/check contract is incomplete';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_indexes
        WHERE schemaname = 'public' AND indexname = 'tracking_tokens_active_operation_scope_uidx'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_indexes
        WHERE schemaname = 'public' AND indexname = 'operations_tenant_status_idx'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_indexes
        WHERE schemaname = 'public' AND indexname = 'invitations_pending_tenant_email_uidx'
          AND indexdef LIKE '%UNIQUE INDEX%WHERE ((accepted_at IS NULL) AND (revoked_at IS NULL))%'
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: essential indexes are missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(ARRAY[
            'tenants', 'memberships', 'operations', 'customers',
            'logistics_providers', 'tracking_tokens', 'tracking_events',
            'tracking_route_points', 'billing_cfdis', 'operation_billing',
            'finance_invoices', 'finance_payments', 'invitations'
        ]) AS required(name)
        JOIN pg_catalog.pg_class AS c ON c.oid = ('public.' || required.name)::regclass
        WHERE NOT c.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: RLS is disabled on an essential table';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'operations'
          AND policyname = 'operations_select_members'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'operations'
          AND policyname = 'operations_delete_admin'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'tracking_tokens'
          AND policyname = 'tracking_tokens_select_members'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'invitations'
          AND policyname = 'invitations_select_admin'
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: essential policies are missing';
    END IF;

    IF to_regprocedure('public.tanda1_user_is_member(uuid)') IS NULL
       OR to_regprocedure('public.tanda1_user_has_role(uuid,text[])') IS NULL
       OR to_regprocedure('public.rpc_get_my_context()') IS NULL
       OR to_regprocedure('public.rpc_list_members(uuid)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,boolean)') IS NULL
       OR to_regprocedure('public.rpc_revoke_tracking_token(uuid)') IS NULL
       OR to_regprocedure('public.rpc_list_tracking_tokens(uuid)') IS NULL
       OR to_regprocedure('public.rpc_create_invitation(uuid,text,text)') IS NULL
       OR to_regprocedure('public.rpc_accept_invitation(text)') IS NULL
       OR to_regprocedure('public.rpc_list_invitations(uuid)') IS NULL
       OR to_regprocedure('public.rpc_revoke_invitation(uuid)') IS NULL
       OR to_regprocedure('public.rpc_accept_invitation(text,text,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: helper/RPC signatures are incomplete';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prosecdef
          AND NOT EXISTS (
              SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS setting
              WHERE setting LIKE 'search_path=pg_catalog, public%'
          )
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: SECURITY DEFINER without safe search_path';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.operations'::regclass
          AND tgname = 'operations_touch_updated_at'
          AND NOT tgisinternal
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.invitations'::regclass
          AND tgname = 'invitations_touch_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: updated_at trigger is missing';
    END IF;
END;
$contract$;

DO $grants$
DECLARE
    v_role text;
    v_table text;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        FOREACH v_table IN ARRAY ARRAY[
            'public.tenants', 'public.memberships', 'public.operations',
            'public.tracking_tokens', 'public.tracking_events',
            'public.billing_cfdis', 'public.finance_invoices', 'public.invitations'
        ] LOOP
            IF has_table_privilege(v_role, v_table, 'SELECT,INSERT,UPDATE,DELETE') THEN
                RAISE EXCEPTION 'DB BASELINE TEST FAILED: role % has direct DML on %', v_role, v_table;
            END IF;
        END LOOP;
    END LOOP;

    IF NOT has_function_privilege('authenticated', 'public.rpc_get_my_context()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_list_operations(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_create_tracking_token(uuid,uuid,text,boolean)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_list_tracking_tokens(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_create_invitation(uuid,text,text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_accept_invitation(text)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_list_invitations(uuid)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'public.rpc_revoke_invitation(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: authenticated RPC grants are incomplete';
    END IF;

    IF has_function_privilege('anon', 'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_list_members(uuid)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_list_members(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_accept_invitation(text)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_accept_invitation(text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_list_invitations(uuid)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_list_invitations(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: internal RPC grant leaked';
    END IF;

    IF NOT has_function_privilege('service_role', 'public.rpc_get_public_tracking(text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_get_public_tracking(text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.rpc_get_public_tracking(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: Edge tracking RPC grants are incorrect';
    END IF;
END;
$grants$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_operation_a uuid;
    v_admin_a uuid := gen_random_uuid();
    v_operator_a uuid := gen_random_uuid();
    v_finance_a uuid := gen_random_uuid();
    v_viewer_a uuid := gen_random_uuid();
    v_admin_b uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants (name, slug) VALUES
        ('DB baseline tenant A', 'db-baseline-a'),
        ('DB baseline tenant B', 'db-baseline-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'db-baseline-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'db-baseline-b';

    INSERT INTO public.memberships (tenant_id, user_id, role) VALUES
        (v_tenant_a, v_admin_a, 'admin'),
        (v_tenant_a, v_operator_a, 'operator'),
        (v_tenant_a, v_finance_a, 'finance'),
        (v_tenant_a, v_viewer_a, 'viewer'),
        (v_tenant_b, v_admin_b, 'admin');

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES (v_tenant_a, 'DB-BASELINE-A', 'draft')
    RETURNING id INTO v_operation_a;

    PERFORM set_config('db_test.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('db_test.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('db_test.operation_a', v_operation_a::text, true);
    PERFORM set_config('db_test.admin_a', v_admin_a::text, true);
    PERFORM set_config('db_test.operator_a', v_operator_a::text, true);
    PERFORM set_config('db_test.finance_a', v_finance_a::text, true);
    PERFORM set_config('db_test.viewer_a', v_viewer_a::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $role_matrix$
DECLARE
    v_tenant_a uuid := current_setting('db_test.tenant_a')::uuid;
    v_tenant_b uuid := current_setting('db_test.tenant_b')::uuid;
    v_operation_a uuid := current_setting('db_test.operation_a')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('db_test.admin_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('db_test.admin_a'), 'role', 'authenticated'
    )::text, true);
    IF NOT public.tanda1_user_has_role(v_tenant_a, ARRAY['admin'])
       OR public.tanda1_user_is_member(v_tenant_b) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: admin tenant isolation failed';
    END IF;
    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'public:read', 1, false);
    IF v_result ? 'error' OR NOT (v_result ? 'token_id') THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: admin tracking create failed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('db_test.operator_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('db_test.operator_a'), 'role', 'authenticated'
    )::text, true);
    v_result := public.rpc_list_tracking_tokens(v_tenant_a);
    IF jsonb_typeof(v_result) <> 'array' THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: operator list failed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('db_test.viewer_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('db_test.viewer_a'), 'role', 'authenticated'
    )::text, true);
    v_result := public.rpc_list_tracking_tokens(v_tenant_a);
    IF jsonb_typeof(v_result) <> 'array' THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: viewer list failed';
    END IF;
    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'driver:write', 1, false);
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: viewer could create tracking token';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('db_test.finance_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', current_setting('db_test.finance_a'), 'role', 'authenticated'
    )::text, true);
    IF NOT public.tanda1_user_has_role(v_tenant_a, ARRAY['finance']) THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: finance role is not recognized';
    END IF;
    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'driver:write', 1, false);
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: finance could create tracking token';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);
    v_result := public.rpc_list_operations(v_tenant_a);
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: no-session operations list was accepted';
    END IF;
END;
$role_matrix$;

RESET ROLE;

DO $residue_guard$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE slug = 'db-baseline-a') THEN
        RAISE EXCEPTION 'DB BASELINE TEST FAILED: fixture transaction was lost unexpectedly';
    END IF;
    RAISE NOTICE 'DB baseline contract passed; all synthetic fixtures will roll back';
END;
$residue_guard$;

ROLLBACK;
