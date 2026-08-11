-- DB.0D: forward-only reconciliation for the existing staging catalog.
--
-- This migration intentionally does not recreate the canonical baseline and
-- does not modify data. It hardens only catalog objects whose deployed state
-- was confirmed read-only during DB.0D2.

DO $db0d_precheck$
DECLARE
    v_missing_functions text[];
    v_missing_roles text[];
    v_users_kind "char";
BEGIN
    SELECT array_agg(required_signature ORDER BY required_signature)
    INTO v_missing_functions
    FROM unnest(ARRAY[
        'public.tanda1_user_is_member(uuid)',
        'public.tanda1_user_has_role(uuid,text[])',
        'public.tracking_hash_token(text)',
        'public.tracking_validate_token(text,text)',
        'public.rpc_get_public_tracking(text)',
        'public.rpc_get_driver_view(text)',
        'public.rpc_post_driver_event(text,text,text,numeric,numeric,numeric,text,text,character,text,text,timestamp with time zone,boolean)'
    ]) AS required(required_signature)
    WHERE to_regprocedure(required_signature) IS NULL;

    IF v_missing_functions IS NOT NULL THEN
        RAISE EXCEPTION 'DB.0D precheck failed: required function signatures are missing: %',
            array_to_string(v_missing_functions, ', ');
    END IF;

    SELECT array_agg(required_role ORDER BY required_role)
    INTO v_missing_roles
    FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS required(required_role)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles AS roles
        WHERE roles.rolname = required.required_role
    );

    IF v_missing_roles IS NOT NULL THEN
        RAISE EXCEPTION 'DB.0D precheck failed: required database roles are missing: %',
            array_to_string(v_missing_roles, ', ');
    END IF;

    IF to_regclass('public.users') IS NOT NULL THEN
        SELECT catalog.relkind
        INTO v_users_kind
        FROM pg_catalog.pg_class AS catalog
        WHERE catalog.oid = 'public.users'::regclass;

        IF v_users_kind IS DISTINCT FROM 'v'::"char" THEN
            RAISE EXCEPTION 'DB.0D precheck failed: public.users exists but is not a view';
        END IF;
    END IF;
END;
$db0d_precheck$;

-- public.users is absent from the canonical fresh baseline. Staging still has
-- the legacy view, so revoke both known direct consumers without dropping it.
-- Keeping the view makes this phase reversible and avoids guessing about
-- unversioned external clients. A later removal requires separate QA.
DO $db0d_public_users$
BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN
        EXECUTE 'REVOKE SELECT ON TABLE public.users FROM authenticated, service_role';
    END IF;
END;
$db0d_public_users$;

-- RBAC helpers are ERP-internal. Their SECURITY DEFINER bodies remain intact;
-- only the search path and execution surface are reconciled.
ALTER FUNCTION public.tanda1_user_is_member(uuid)
    SET search_path TO pg_catalog, public;
ALTER FUNCTION public.tanda1_user_has_role(uuid, text[])
    SET search_path TO pg_catalog, public;

REVOKE ALL ON FUNCTION public.tanda1_user_is_member(uuid)
    FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.tanda1_user_has_role(uuid, text[])
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_is_member(uuid)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.tanda1_user_has_role(uuid, text[])
    TO authenticated;

-- Capability-token helpers are private to the service-role Edge surface.
-- No function body or token semantics change in DB.0D.
ALTER FUNCTION public.tracking_hash_token(text)
    SET search_path TO pg_catalog, public, extensions;
ALTER FUNCTION public.tracking_validate_token(text, text)
    SET search_path TO pg_catalog, public, extensions;

REVOKE ALL ON FUNCTION public.tracking_hash_token(text)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tracking_validate_token(text, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tracking_hash_token(text)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.tracking_validate_token(text, text)
    TO service_role;

-- These three RPCs are called by driver-view, track-public and track-driver
-- through service_role. Direct anon/authenticated execution is unnecessary.
ALTER FUNCTION public.rpc_get_public_tracking(text)
    SET search_path TO pg_catalog, public, extensions;
ALTER FUNCTION public.rpc_get_driver_view(text)
    SET search_path TO pg_catalog, public, extensions;
ALTER FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    SET search_path TO pg_catalog, public, extensions;

REVOKE ALL ON FUNCTION public.rpc_get_public_tracking(text)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_get_driver_view(text)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_public_tracking(text)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_driver_view(text)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    TO service_role;

NOTIFY pgrst, 'reload schema';
