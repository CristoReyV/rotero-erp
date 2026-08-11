-- Contract for the disposable staging-like DB after applying only DB.0D.

BEGIN;

DO $db0d_staging_like_contract$
DECLARE
    v_signature text;
    v_oid oid;
    v_config text[];
BEGIN
    IF to_regclass('public.users') IS NULL
       OR has_table_privilege('authenticated', 'public.users', 'SELECT')
       OR has_table_privilege('service_role', 'public.users', 'SELECT') THEN
        RAISE EXCEPTION 'DB0D STAGING-LIKE TEST FAILED: public.users grants';
    END IF;

    IF to_regclass('public.daily_work_items') IS NULL THEN
        RAISE EXCEPTION 'DB0D STAGING-LIKE TEST FAILED: class-D object removed';
    END IF;

    IF to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'DB0D STAGING-LIKE TEST FAILED: M4.1 was applied';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.tanda1_user_is_member(uuid)',
        'public.tanda1_user_has_role(uuid,text[])'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        SELECT p.proconfig INTO v_config FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid;
        IF NOT (v_config @> ARRAY['search_path=pg_catalog, public'])
           OR NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'DB0D STAGING-LIKE TEST FAILED: RBAC helper %', v_signature;
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
        SELECT p.proconfig INTO v_config FROM pg_catalog.pg_proc AS p WHERE p.oid = v_oid;
        IF NOT (v_config @> ARRAY['search_path=pg_catalog, public, extensions'])
           OR NOT has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'DB0D STAGING-LIKE TEST FAILED: Tracking helper/RPC %', v_signature;
        END IF;
    END LOOP;

    RAISE NOTICE 'DB.0D staging-like contract passed; no rows were read or written';
END;
$db0d_staging_like_contract$;

ROLLBACK;
