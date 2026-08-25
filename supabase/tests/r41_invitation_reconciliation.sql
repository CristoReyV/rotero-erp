\set ON_ERROR_STOP on

DO $catalog$
DECLARE
    v_role text;
    v_snapshot record;
    v_definition text;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            ('accepted_by', 'uuid', 'YES'),
            ('revoked_at', 'timestamp with time zone', 'YES'),
            ('revoked_by', 'uuid', 'YES'),
            ('updated_at', 'timestamp with time zone', 'NO')
        ) AS expected(column_name, data_type, is_nullable)
        LEFT JOIN information_schema.columns AS actual
          ON actual.table_schema = 'public'
         AND actual.table_name = 'invitations'
         AND actual.column_name = expected.column_name
         AND actual.data_type = expected.data_type
         AND actual.is_nullable = expected.is_nullable
        WHERE actual.column_name IS NULL
    ) THEN
        RAISE EXCEPTION 'R4.1 invitation lifecycle column contract mismatch';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invitations'
          AND column_name IN ('role', 'created_at', 'updated_at')
          AND column_default IS NULL
    ) OR EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'invitations'
          AND column_name IN ('created_by', 'created_at', 'updated_at')
          AND is_nullable <> 'NO'
    ) THEN
        RAISE EXCEPTION 'R4.1 invitation defaults/nullability mismatch';
    END IF;

    IF EXISTS (
        SELECT expected.name
        FROM unnest(ARRAY[
            'invitations_role_check',
            'invitations_email_check',
            'invitations_acceptance_pair_check',
            'invitations_revocation_pair_check',
            'invitations_terminal_state_check',
            'invitations_token_hash_key'
        ]) AS expected(name)
        LEFT JOIN pg_catalog.pg_constraint AS c
          ON c.conrelid = 'public.invitations'::regclass
         AND c.conname = expected.name
        WHERE c.oid IS NULL
    ) THEN
        RAISE EXCEPTION 'R4.1 canonical invitation constraint missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::regclass
          AND conname IN ('unique_tenant_email', 'invitations_created_by_fkey')
    ) OR to_regclass('public.idx_invitations_token_hash') IS NOT NULL THEN
        RAISE EXCEPTION 'R4.1 legacy invitation constraint/index remains';
    END IF;

    IF to_regclass('public.invitations_pending_tenant_email_uidx') IS NULL
       OR pg_catalog.pg_get_indexdef('public.invitations_pending_tenant_email_uidx'::regclass)
            NOT ILIKE '%WHERE ((accepted_at IS NULL) AND (revoked_at IS NULL))%'
       OR to_regclass('public.invitations_tenant_created_idx') IS NULL THEN
        RAISE EXCEPTION 'R4.1 canonical invitation indexes missing or malformed';
    END IF;

    IF (SELECT count(*) FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.invitations'::regclass
          AND tgname = 'invitations_touch_updated_at'
          AND NOT tgisinternal) <> 1 THEN
        RAISE EXCEPTION 'R4.1 invitation updated_at trigger mismatch';
    END IF;

    IF (SELECT count(*) FROM pg_catalog.pg_policies
        WHERE schemaname = 'public' AND tablename = 'invitations') <> 1
       OR NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_policies
           WHERE schemaname = 'public' AND tablename = 'invitations'
             AND policyname = 'invitations_select_admin'
             AND roles = ARRAY['authenticated']::name[]
       ) THEN
        RAISE EXCEPTION 'R4.1 invitation RLS policy mismatch';
    END IF;

    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF has_table_privilege(v_role, 'public.invitations', 'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'R4.1 direct invitation table access leaked to %', v_role;
        END IF;
    END LOOP;
    IF has_table_privilege('public', 'public.invitations', 'SELECT,INSERT,UPDATE,DELETE') THEN
        RAISE EXCEPTION 'R4.1 direct invitation table access leaked to PUBLIC';
    END IF;

    FOR v_snapshot IN SELECT * FROM private.r41_invitation_rpc_snapshot LOOP
        IF to_regprocedure(v_snapshot.identity)::oid IS DISTINCT FROM v_snapshot.function_oid THEN
            RAISE EXCEPTION 'R4.1 RPC OID changed for %', v_snapshot.identity;
        END IF;
        IF (SELECT proargnames FROM pg_catalog.pg_proc WHERE oid = v_snapshot.function_oid)
              IS DISTINCT FROM v_snapshot.arg_names
           OR pg_catalog.pg_get_function_result(v_snapshot.function_oid) <> v_snapshot.result_type THEN
            RAISE EXCEPTION 'R4.1 RPC signature changed for %', v_snapshot.identity;
        END IF;
    END LOOP;

    IF NOT (SELECT prosecdef FROM pg_catalog.pg_proc
            WHERE oid = 'public.rpc_create_invitation(uuid,text,text)'::regprocedure)
       OR (SELECT proconfig FROM pg_catalog.pg_proc
           WHERE oid = 'public.rpc_create_invitation(uuid,text,text)'::regprocedure)
            IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, extensions']::text[]
       OR NOT has_function_privilege('authenticated', 'public.rpc_create_invitation(uuid,text,text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_create_invitation(uuid,text,text)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_create_invitation(uuid,text,text)', 'EXECUTE')
       OR has_function_privilege('public', 'public.rpc_create_invitation(uuid,text,text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'R4.1 create invitation security contract mismatch';
    END IF;

    v_definition := pg_catalog.pg_get_functiondef('public.rpc_create_invitation(uuid,text,text)'::regprocedure);
    IF v_definition NOT ILIKE '%lower(btrim(p_email))%'
       OR v_definition NOT ILIKE '%tanda1_user_has_role%admin%'
       OR v_definition NOT ILIKE '%pg_advisory_xact_lock%'
       OR v_definition NOT ILIKE '%revoked_at%'
       OR v_definition NOT ILIKE '%digest(v_token%sha256%'
       OR v_definition NOT ILIKE '%invitation_created%'
       OR v_definition ILIKE '%SQLERRM%' THEN
        RAISE EXCEPTION 'R4.1 create invitation body contract mismatch';
    END IF;

    FOREACH v_definition IN ARRAY ARRAY[
        'public.rpc_accept_invitation(text,text,text)',
        'public.rpc_revoke_invitation(uuid,uuid)'
    ] LOOP
        IF has_function_privilege('public', v_definition, 'EXECUTE')
           OR has_function_privilege('anon', v_definition, 'EXECUTE')
           OR has_function_privilege('authenticated', v_definition, 'EXECUTE')
           OR has_function_privilege('service_role', v_definition, 'EXECUTE') THEN
            RAISE EXCEPTION 'R4.1 disabled legacy RPC remains reachable: %', v_definition;
        END IF;
        IF pg_catalog.pg_get_functiondef(v_definition::regprocedure) NOT ILIKE '%state%disabled%'
           OR pg_catalog.pg_get_functiondef(v_definition::regprocedure) ILIKE '%auth.users%'
           OR pg_catalog.pg_get_functiondef(v_definition::regprocedure) ILIKE '%DELETE FROM%'
           OR (SELECT proconfig FROM pg_catalog.pg_proc WHERE oid = v_definition::regprocedure)
                IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']::text[] THEN
            RAISE EXCEPTION 'R4.1 disabled legacy RPC body/search_path unsafe: %', v_definition;
        END IF;
    END LOOP;
END
$catalog$;

-- Exercise create authorization and storage without creating or changing any
-- Auth user. All rows below are synthetic and rolled back.
BEGIN;
DO $context$
DECLARE
    v_tenant uuid := gen_random_uuid();
    v_admin uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants(id, name, slug)
    VALUES (v_tenant, 'R4.1 invitation test', 'r41-invitation-test');
    INSERT INTO public.memberships(tenant_id, user_id, role)
    VALUES (v_tenant, v_admin, 'admin'), (v_tenant, v_operator, 'operator');
    PERFORM set_config('r41.tenant', v_tenant::text, true);
    PERFORM set_config('r41.admin', v_admin::text, true);
    PERFORM set_config('r41.operator', v_operator::text, true);
END
$context$;

SET LOCAL ROLE authenticated;
DO $behavior$
DECLARE
    v_tenant uuid := current_setting('r41.tenant')::uuid;
    v_admin uuid := current_setting('r41.admin')::uuid;
    v_operator uuid := current_setting('r41.operator')::uuid;
    v_result jsonb;
    v_token text;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_operator::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_operator, 'role', 'authenticated')::text, true);
    IF public.rpc_create_invitation(v_tenant, 'operator@example.invalid', 'viewer')->>'state' <> 'unauthorized' THEN
        RAISE EXCEPTION 'R4.1 non-admin invitation creation was allowed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    v_result := public.rpc_create_invitation(v_tenant, '  R41@example.invalid  ', 'viewer');
    IF v_result->>'state' <> 'created' THEN
        RAISE EXCEPTION 'R4.1 admin invitation creation failed: %', v_result;
    END IF;
    v_token := v_result->>'token';
    IF v_token IS NULL THEN RAISE EXCEPTION 'R4.1 transient token missing'; END IF;
    PERFORM set_config('r41.first_id', v_result->>'invitation_id', true);
    PERFORM set_config('r41.first_token', v_token, true);

    v_result := public.rpc_create_invitation(v_tenant, 'r41@example.invalid', 'operator');
    IF v_result->>'state' <> 'created' THEN
        RAISE EXCEPTION 'R4.1 pending invitation rotation failed: %', v_result;
    END IF;
END
$behavior$;

RESET ROLE;
DO $storage$
DECLARE
    v_tenant uuid := current_setting('r41.tenant')::uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.invitations AS i
        WHERE i.id = current_setting('r41.first_id')::uuid
          AND i.email = 'r41@example.invalid'
          AND i.token_hash <> current_setting('r41.first_token')
          AND i.revoked_at IS NOT NULL
          AND i.revoked_by = current_setting('r41.admin')::uuid
    ) THEN
        RAISE EXCEPTION 'R4.1 invitation normalization/hash/revocation storage mismatch';
    END IF;
    IF (SELECT count(*) FROM public.invitations AS i
        WHERE i.tenant_id = v_tenant AND i.email = 'r41@example.invalid'
          AND i.accepted_at IS NULL AND i.revoked_at IS NULL) <> 1 THEN
        RAISE EXCEPTION 'R4.1 pending invitation uniqueness failed';
    END IF;
END
$storage$;
ROLLBACK;

DROP TABLE private.r41_invitation_rpc_snapshot;
