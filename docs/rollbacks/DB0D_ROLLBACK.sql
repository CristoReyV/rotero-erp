-- DB.0D rollback for a controlled staging rollback only.
--
-- This restores the metadata/grants observed read-only before DB.0D. It does
-- not recreate dropped data or objects because DB.0D drops neither. Do not run
-- against a canonical fresh database: the historical staging grants restored
-- here are intentionally broader than the canonical contract.

DO $db0d_rollback_precheck$
DECLARE
    v_missing_functions text[];
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
        RAISE EXCEPTION 'DB.0D rollback precheck failed: required functions are missing: %',
            array_to_string(v_missing_functions, ', ');
    END IF;
END;
$db0d_rollback_precheck$;

DO $db0d_restore_public_users$
BEGIN
    IF to_regclass('public.users') IS NOT NULL THEN
        EXECUTE 'GRANT SELECT ON TABLE public.users TO authenticated, service_role';
    END IF;
END;
$db0d_restore_public_users$;

ALTER FUNCTION public.tanda1_user_is_member(uuid)
    SET search_path TO public;
ALTER FUNCTION public.tanda1_user_has_role(uuid, text[])
    SET search_path TO public;

REVOKE ALL ON FUNCTION public.tanda1_user_is_member(uuid)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.tanda1_user_has_role(uuid, text[])
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_is_member(uuid)
    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_has_role(uuid, text[])
    TO authenticated, service_role;

ALTER FUNCTION public.tracking_hash_token(text) RESET search_path;
ALTER FUNCTION public.tracking_validate_token(text, text)
    SET search_path TO public;

REVOKE ALL ON FUNCTION public.tracking_hash_token(text)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.tracking_validate_token(text, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.tracking_hash_token(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.tracking_validate_token(text, text) TO PUBLIC;

ALTER FUNCTION public.rpc_get_public_tracking(text)
    SET search_path TO public;
ALTER FUNCTION public.rpc_get_driver_view(text)
    SET search_path TO public;
ALTER FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    SET search_path TO public;

REVOKE ALL ON FUNCTION public.rpc_get_public_tracking(text)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.rpc_get_driver_view(text)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_public_tracking(text)
    TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_driver_view(text)
    TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_post_driver_event(
    text, text, text, numeric, numeric, numeric, text, text, character,
    text, text, timestamp with time zone, boolean
)
    TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
