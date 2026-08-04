\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE
    v_signature text;
    v_oid oid;
    v_role text;
BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: public.users exists';
    END IF;
    IF to_regprocedure('public.rpc_accept_invitation(text,text,text)') IS NOT NULL
       OR to_regprocedure('public.rpc_accept_invitation(text)') IS NULL THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: acceptance signature mismatch';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_create_invitation(uuid,text,text)',
        'public.rpc_accept_invitation(text)',
        'public.rpc_list_invitations(uuid)',
        'public.rpc_revoke_invitation(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL
           OR NOT (SELECT p.prosecdef FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid)
           OR NOT EXISTS (
                SELECT 1
                FROM pg_catalog.pg_proc AS p,
                     unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS setting
                WHERE p.oid = v_oid
                  AND setting LIKE 'search_path=pg_catalog, public%'
           ) THEN
            RAISE EXCEPTION 'INVITATION CONTRACT FAILED: unsafe function %', v_signature;
        END IF;

        IF NOT has_function_privilege('authenticated', v_signature, 'EXECUTE') THEN
            RAISE EXCEPTION 'INVITATION CONTRACT FAILED: authenticated grant missing %', v_signature;
        END IF;
        FOREACH v_role IN ARRAY ARRAY['anon', 'service_role'] LOOP
            IF has_function_privilege(v_role, v_signature, 'EXECUTE') THEN
                RAISE EXCEPTION 'INVITATION CONTRACT FAILED: execute leaked to % on %', v_role, v_signature;
            END IF;
        END LOOP;
        IF EXISTS (
            SELECT 1
            FROM pg_catalog.pg_proc AS p
            CROSS JOIN LATERAL pg_catalog.aclexplode(
                COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
            ) AS acl
            WHERE p.oid = v_oid
              AND acl.grantee = 0
              AND acl.privilege_type = 'EXECUTE'
        ) THEN
            RAISE EXCEPTION 'INVITATION CONTRACT FAILED: execute leaked to PUBLIC on %', v_signature;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname LIKE 'rpc_%invitation%'
          AND pg_catalog.pg_get_functiondef(p.oid) ILIKE '%SQLERRM%'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: SQLERRM present';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = 'invitations'
          AND c.column_name = 'accepted_by' AND c.data_type = 'uuid' AND c.is_nullable = 'YES'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = 'invitations'
          AND c.column_name = 'revoked_by' AND c.data_type = 'uuid' AND c.is_nullable = 'YES'
    ) OR NOT EXISTS (
        SELECT 1
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = 'invitations'
          AND c.column_name = 'updated_at' AND c.data_type = 'timestamp with time zone'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: lifecycle columns missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_indexes AS i
        WHERE i.schemaname = 'public'
          AND i.indexname = 'invitations_pending_tenant_email_uidx'
          AND i.indexdef LIKE '%UNIQUE INDEX%'
          AND i.indexdef LIKE '%tenant_id, email%'
          AND i.indexdef LIKE '%accepted_at IS NULL%'
          AND i.indexdef LIKE '%revoked_at IS NULL%'
          AND i.indexdef NOT ILIKE '%now()%'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: pending invitation unique index missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger AS t
        WHERE t.tgrelid = 'public.invitations'::regclass
          AND t.tgname = 'invitations_touch_updated_at'
          AND NOT t.tgisinternal
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_policies AS p
        WHERE p.schemaname = 'public' AND p.tablename = 'invitations'
          AND p.policyname = 'invitations_select_admin'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: trigger/RLS policy missing';
    END IF;

    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF has_table_privilege(v_role, 'public.invitations', 'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'INVITATION CONTRACT FAILED: direct invitation DML leaked to %', v_role;
        END IF;
    END LOOP;

    IF pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) ILIKE '%password%'
       OR pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) ILIKE '%full_name%'
       OR pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) ILIKE '%UPDATE auth.users%'
       OR pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) ILIKE '%INSERT INTO auth.users%'
       OR pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) ILIKE '%email_mismatch%'
       OR pg_catalog.pg_get_functiondef('public.rpc_create_invitation(uuid,text,text)'::regprocedure) NOT ILIKE '%pg_advisory_xact_lock%'
       OR pg_catalog.pg_get_functiondef('public.rpc_accept_invitation(text)'::regprocedure) NOT ILIKE '%FOR UPDATE%' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: unsafe function body';
    END IF;
END;
$catalog$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_admin_a uuid := gen_random_uuid();
    v_admin_b uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid();
    v_viewer uuid := gen_random_uuid();
    v_invitee uuid := gen_random_uuid();
    v_wrong_user uuid := gen_random_uuid();
    v_expired_user uuid := gen_random_uuid();
    v_revoked_user uuid := gen_random_uuid();
    v_existing_user uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants (name, slug) VALUES
        ('INV1 tenant A', 'inv1-tenant-a'),
        ('INV1 tenant B', 'inv1-tenant-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'inv1-tenant-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'inv1-tenant-b';

    INSERT INTO public.memberships (tenant_id, user_id, role) VALUES
        (v_tenant_a, v_admin_a, 'admin'),
        (v_tenant_b, v_admin_b, 'admin'),
        (v_tenant_a, v_operator, 'operator'),
        (v_tenant_a, v_finance, 'finance'),
        (v_tenant_a, v_viewer, 'viewer'),
        (v_tenant_a, v_existing_user, 'viewer');

    -- Synthetic local identities exist only inside this transaction and are
    -- rolled back; the production contract never writes auth.users.
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES
        ('00000000-0000-0000-0000-000000000000', v_invitee, 'authenticated', 'authenticated', 'inv1-invitee@example.invalid', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_wrong_user, 'authenticated', 'authenticated', 'inv1-wrong@example.invalid', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_expired_user, 'authenticated', 'authenticated', 'inv1-expired@example.invalid', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_revoked_user, 'authenticated', 'authenticated', 'inv1-revoked@example.invalid', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
        ('00000000-0000-0000-0000-000000000000', v_existing_user, 'authenticated', 'authenticated', 'inv1-existing@example.invalid', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

    PERFORM set_config('inv1.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('inv1.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('inv1.admin_a', v_admin_a::text, true);
    PERFORM set_config('inv1.admin_b', v_admin_b::text, true);
    PERFORM set_config('inv1.operator', v_operator::text, true);
    PERFORM set_config('inv1.finance', v_finance::text, true);
    PERFORM set_config('inv1.viewer', v_viewer::text, true);
    PERFORM set_config('inv1.invitee', v_invitee::text, true);
    PERFORM set_config('inv1.wrong_user', v_wrong_user::text, true);
    PERFORM set_config('inv1.expired_user', v_expired_user::text, true);
    PERFORM set_config('inv1.revoked_user', v_revoked_user::text, true);
    PERFORM set_config('inv1.existing_user', v_existing_user::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $create_contract$
DECLARE
    v_tenant_a uuid := current_setting('inv1.tenant_a')::uuid;
    v_tenant_b uuid := current_setting('inv1.tenant_b')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.operator'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.operator'), 'role', 'authenticated')::text, true);
    IF public.rpc_create_invitation(v_tenant_a, 'inv1-denied-operator@example.invalid', 'viewer')->>'state' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: operator created invitation';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.finance'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.finance'), 'role', 'authenticated')::text, true);
    IF public.rpc_create_invitation(v_tenant_a, 'inv1-denied-finance@example.invalid', 'viewer')->>'state' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: finance created invitation';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.viewer'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.viewer'), 'role', 'authenticated')::text, true);
    IF public.rpc_create_invitation(v_tenant_a, 'inv1-denied-viewer@example.invalid', 'viewer')->>'state' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: viewer created invitation';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.admin_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.admin_a'), 'role', 'authenticated')::text, true);
    IF public.rpc_create_invitation(v_tenant_b, 'inv1-cross@example.invalid', 'viewer')->>'state' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: cross-tenant create allowed';
    END IF;
    IF public.rpc_create_invitation(v_tenant_a, 'invalid-email', 'viewer')->>'error' <> 'invalid_payload'
       OR public.rpc_create_invitation(v_tenant_a, 'inv1-invalid-role@example.invalid', 'owner')->>'error' <> 'invalid_payload' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: invalid payload accepted';
    END IF;

    v_result := public.rpc_create_invitation(v_tenant_a, '  INV1-INVITEE@example.invalid  ', 'operator');
    IF v_result->>'state' <> 'created' OR length(v_result->>'token') <> 48 THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: admin create failed';
    END IF;
    PERFORM set_config('inv1.first_id', v_result->>'invitation_id', true);
    PERFORM set_config('inv1.first_token', v_result->>'token', true);

    v_result := public.rpc_create_invitation(v_tenant_a, 'inv1-invitee@example.invalid', 'finance');
    IF v_result->>'state' <> 'created' OR length(v_result->>'token') <> 48 THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: resend/create failed';
    END IF;
    PERFORM set_config('inv1.accept_id', v_result->>'invitation_id', true);
    PERFORM set_config('inv1.accept_token', v_result->>'token', true);

    v_result := public.rpc_create_invitation(v_tenant_a, 'inv1-expired@example.invalid', 'viewer');
    PERFORM set_config('inv1.expired_id', v_result->>'invitation_id', true);
    PERFORM set_config('inv1.expired_token', v_result->>'token', true);

    v_result := public.rpc_create_invitation(v_tenant_a, 'inv1-revoked@example.invalid', 'operator');
    PERFORM set_config('inv1.revoked_id', v_result->>'invitation_id', true);
    PERFORM set_config('inv1.revoked_token', v_result->>'token', true);

    v_result := public.rpc_create_invitation(v_tenant_a, 'inv1-existing@example.invalid', 'admin');
    PERFORM set_config('inv1.existing_id', v_result->>'invitation_id', true);
    PERFORM set_config('inv1.existing_token', v_result->>'token', true);

    v_result := public.rpc_create_invitation(v_tenant_a, 'inv1-pending@example.invalid', 'viewer');
    PERFORM set_config('inv1.pending_id', v_result->>'invitation_id', true);
END;
$create_contract$;

RESET ROLE;

DO $create_storage$
DECLARE
    v_tenant uuid := current_setting('inv1.tenant_a')::uuid;
    v_first public.invitations%ROWTYPE;
    v_current public.invitations%ROWTYPE;
BEGIN
    SELECT * INTO v_first FROM public.invitations WHERE id = current_setting('inv1.first_id')::uuid;
    SELECT * INTO v_current FROM public.invitations WHERE id = current_setting('inv1.accept_id')::uuid;
    IF v_first.revoked_at IS NULL OR v_first.revoked_by <> current_setting('inv1.admin_a')::uuid THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: prior pending invitation not revoked';
    END IF;
    IF v_current.email <> 'inv1-invitee@example.invalid'
       OR v_current.token_hash = current_setting('inv1.accept_token')
       OR v_current.token_hash <> encode(extensions.digest(current_setting('inv1.accept_token'), 'sha256'), 'hex') THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: token/email storage unsafe';
    END IF;
    IF (SELECT count(*) FROM public.invitations AS i
        WHERE i.tenant_id = v_tenant AND i.email = 'inv1-invitee@example.invalid'
          AND i.accepted_at IS NULL AND i.revoked_at IS NULL) <> 1 THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: active invitation uniqueness broken';
    END IF;

    UPDATE public.invitations
    SET expires_at = now() - interval '1 minute'
    WHERE id = current_setting('inv1.expired_id')::uuid;
END;
$create_storage$;

SET LOCAL ROLE authenticated;

DO $revoke_authorization$
DECLARE
    v_id uuid := current_setting('inv1.revoked_id')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.operator'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.operator'), 'role', 'authenticated')::text, true);
    IF public.rpc_revoke_invitation(v_id)->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: operator revoked invitation';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.finance'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.finance'), 'role', 'authenticated')::text, true);
    IF public.rpc_revoke_invitation(v_id)->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: finance revoked invitation';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.viewer'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.viewer'), 'role', 'authenticated')::text, true);
    IF public.rpc_revoke_invitation(v_id)->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: viewer revoked invitation';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.admin_b'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.admin_b'), 'role', 'authenticated')::text, true);
    IF public.rpc_revoke_invitation(v_id)->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: cross-tenant revoke disclosed invitation';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.admin_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.admin_a'), 'role', 'authenticated')::text, true);
    v_result := public.rpc_revoke_invitation(v_id);
    IF v_result->>'state' <> 'revoked'
       OR public.rpc_revoke_invitation(v_id)->>'state' <> 'already_revoked' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: revoke is not idempotent';
    END IF;
END;
$revoke_authorization$;

DO $accept_contract$
DECLARE
    v_tenant uuid := current_setting('inv1.tenant_a')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.accept_token'))->>'state' <> 'authentication_required' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: acceptance did not require session';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.wrong_user'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.wrong_user'), 'role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.accept_token'))->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: wrong identity accepted';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.invitee'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.invitee'), 'role', 'authenticated')::text, true);
    v_result := public.rpc_accept_invitation(current_setting('inv1.accept_token'));
    IF v_result->>'state' <> 'accepted'
       OR public.rpc_accept_invitation(current_setting('inv1.accept_token'))->>'state' <> 'already_accepted' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: acceptance/idempotency failed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.wrong_user'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.wrong_user'), 'role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.accept_token'))->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: accepted token reused by other identity';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.expired_user'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.expired_user'), 'role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.expired_token'))->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: expired invitation accepted';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.revoked_user'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.revoked_user'), 'role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.revoked_token'))->>'state' <> 'invalid_invitation' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: revoked invitation accepted';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.existing_user'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.existing_user'), 'role', 'authenticated')::text, true);
    IF public.rpc_accept_invitation(current_setting('inv1.existing_token'))->>'state' <> 'already_member' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: existing membership result mismatch';
    END IF;
END;
$accept_contract$;

RESET ROLE;

DO $accept_storage$
DECLARE
    v_invitation public.invitations%ROWTYPE;
BEGIN
    SELECT * INTO v_invitation FROM public.invitations WHERE id = current_setting('inv1.accept_id')::uuid;
    IF v_invitation.accepted_at IS NULL OR v_invitation.accepted_by <> current_setting('inv1.invitee')::uuid THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: acceptance actor/time missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.memberships AS m
        WHERE m.tenant_id = current_setting('inv1.tenant_a')::uuid
          AND m.user_id = current_setting('inv1.invitee')::uuid
          AND m.role = 'finance'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: role did not come from invitation';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.memberships AS m
        WHERE m.tenant_id = current_setting('inv1.tenant_a')::uuid
          AND m.user_id = current_setting('inv1.existing_user')::uuid
          AND m.role = 'viewer'
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: existing role changed';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.invitations AS i
        WHERE i.id = current_setting('inv1.revoked_id')::uuid
          AND (i.revoked_at IS NULL OR i.revoked_by <> current_setting('inv1.admin_a')::uuid)
    ) THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: revocation actor/time missing';
    END IF;
END;
$accept_storage$;

SET LOCAL ROLE authenticated;

DO $list_and_terminal_revoke$
DECLARE
    v_tenant uuid := current_setting('inv1.tenant_a')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.operator'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.operator'), 'role', 'authenticated')::text, true);
    IF public.rpc_list_invitations(v_tenant)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: operator listed invitations';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.finance'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.finance'), 'role', 'authenticated')::text, true);
    IF public.rpc_list_invitations(v_tenant)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: finance listed invitations';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.viewer'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.viewer'), 'role', 'authenticated')::text, true);
    IF public.rpc_list_invitations(v_tenant)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: viewer listed invitations';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.admin_b'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.admin_b'), 'role', 'authenticated')::text, true);
    IF public.rpc_list_invitations(v_tenant)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: cross-tenant list allowed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('inv1.admin_a'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('inv1.admin_a'), 'role', 'authenticated')::text, true);
    v_result := public.rpc_list_invitations(v_tenant);
    IF jsonb_typeof(v_result) <> 'array'
       OR v_result::text LIKE '%token_hash%'
       OR v_result::text LIKE '%"token"%'
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_result) AS item WHERE item->>'state' = 'pending')
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_result) AS item WHERE item->>'state' = 'expired')
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_result) AS item WHERE item->>'state' = 'accepted')
       OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_result) AS item WHERE item->>'state' = 'revoked') THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: admin list shape/state mismatch';
    END IF;

    IF public.rpc_revoke_invitation(current_setting('inv1.accept_id')::uuid)->>'state' <> 'already_accepted' THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: accepted invitation revoked';
    END IF;
END;
$list_and_terminal_revoke$;

RESET ROLE;

DO $residue_before_rollback$
BEGIN
    IF (SELECT count(*) FROM public.invitations AS i
        WHERE i.tenant_id = current_setting('inv1.tenant_a')::uuid
          AND i.accepted_at IS NULL AND i.revoked_at IS NULL
          AND i.email = 'inv1-invitee@example.invalid') > 1 THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: more than one pending invitation';
    END IF;
END;
$residue_before_rollback$;

ROLLBACK;

DO $rolled_back$
BEGIN
    IF EXISTS (SELECT 1 FROM public.tenants WHERE slug LIKE 'inv1-%')
       OR EXISTS (SELECT 1 FROM auth.users WHERE email LIKE 'inv1-%@example.invalid') THEN
        RAISE EXCEPTION 'INVITATION CONTRACT FAILED: synthetic fixtures survived rollback';
    END IF;
END;
$rolled_back$;
