-- DB.0D forward contract. Synthetic fixtures only; always rolls back.

BEGIN;

DO $db0d_contract$
DECLARE
    v_signature text;
    v_oid oid;
    v_config text[];
    v_tenant_a uuid := gen_random_uuid();
    v_tenant_b uuid := gen_random_uuid();
    v_viewer uuid := gen_random_uuid();
BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN
        IF has_table_privilege('authenticated', 'public.users', 'SELECT') THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: authenticated can still select public.users';
        END IF;
        IF has_table_privilege('service_role', 'public.users', 'SELECT') THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: service_role can still select public.users';
        END IF;
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.tanda1_user_is_member(uuid)',
        'public.tanda1_user_has_role(uuid,text[])'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: missing RBAC helper %', v_signature;
        END IF;

        SELECT p.proconfig INTO v_config FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid;
        IF NOT (v_config @> ARRAY['search_path=pg_catalog, public']) THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: unsafe RBAC search_path for %', v_signature;
        END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR EXISTS (
                SELECT 1
                FROM pg_catalog.aclexplode(COALESCE(
                    (SELECT p.proacl FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid),
                    pg_catalog.acldefault('f', (SELECT p.proowner FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid))
                )) AS acl
                WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
           ) THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: unexpected RBAC grants for %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.tracking_hash_token(text)',
        'public.tracking_validate_token(text,text)',
        'public.rpc_get_public_tracking(text)',
        'public.rpc_get_driver_view(text)',
        'public.rpc_post_driver_event(text,text,text,numeric,numeric,numeric,text,text,character,text,text,timestamp with time zone,boolean)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: missing Tracking helper/RPC %', v_signature;
        END IF;

        SELECT p.proconfig INTO v_config FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid;
        IF NOT (v_config @> ARRAY['search_path=pg_catalog, public, extensions']) THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: unsafe Tracking search_path for %', v_signature;
        END IF;
        IF NOT has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR EXISTS (
                SELECT 1
                FROM pg_catalog.aclexplode(COALESCE(
                    (SELECT p.proacl FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid),
                    pg_catalog.acldefault('f', (SELECT p.proowner FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid))
                )) AS acl
                WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
           ) THEN
            RAISE EXCEPTION 'DB0D TEST FAILED: unexpected Tracking grants for %', v_signature;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'tracking_hash_token', 'tracking_validate_token',
              'rpc_get_public_tracking', 'rpc_get_driver_view', 'rpc_post_driver_event'
          )
          AND pg_catalog.pg_get_functiondef(p.oid) ~* '\mSQLERRM\M'
    ) THEN
        RAISE EXCEPTION 'DB0D TEST FAILED: Tracking function contains SQLERRM';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('rpc_get_public_tracking', 'rpc_get_driver_view', 'rpc_post_driver_event')
          AND pg_catalog.pg_get_functiondef(p.oid) ~* '''token_(hash|prefix)'''
    ) THEN
        RAISE EXCEPTION 'DB0D TEST FAILED: public Tracking response exposes token material';
    END IF;

    IF to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer)') IS NULL
       OR to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,boolean)') IS NULL
       OR to_regprocedure('public.rpc_list_tracking_tokens(uuid)') IS NULL
       OR to_regprocedure('public.rpc_revoke_tracking_token(uuid)') IS NULL THEN
        RAISE EXCEPTION 'DB0D TEST FAILED: M4.1 contract is incomplete';
    END IF;

    IF to_regprocedure('public.rpc_create_invitation(uuid,text,text)') IS NULL
       OR to_regprocedure('public.rpc_accept_invitation(text)') IS NULL
       OR to_regprocedure('public.rpc_list_invitations(uuid)') IS NULL
       OR to_regprocedure('public.rpc_revoke_invitation(uuid)') IS NULL
       OR to_regprocedure('public.rpc_accept_invitation(text,text,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'DB0D TEST FAILED: INV.1 contract drifted';
    END IF;

    INSERT INTO public.tenants (id, name, slug) VALUES
        (v_tenant_a, 'DB0D Tenant A', 'db0d-a-' || substr(v_tenant_a::text, 1, 8)),
        (v_tenant_b, 'DB0D Tenant B', 'db0d-b-' || substr(v_tenant_b::text, 1, 8));
    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES (v_tenant_a, v_viewer, 'viewer');

    PERFORM set_config('request.jwt.claim.sub', v_viewer::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_viewer, 'role', 'authenticated')::text,
        true
    );

    IF NOT public.tanda1_user_is_member(v_tenant_a)
       OR NOT public.tanda1_user_has_role(v_tenant_a, ARRAY['viewer'])
       OR public.tanda1_user_is_member(v_tenant_b)
       OR public.tanda1_user_has_role(v_tenant_b, ARRAY['viewer']) THEN
        RAISE EXCEPTION 'DB0D TEST FAILED: RBAC tenant isolation failed';
    END IF;

    RAISE NOTICE 'DB.0D forward contract passed; synthetic fixtures will roll back';
END;
$db0d_contract$;

ROLLBACK;
