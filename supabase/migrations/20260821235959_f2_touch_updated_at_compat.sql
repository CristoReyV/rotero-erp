-- Compatibility bridge for a genuine fresh-reset gap in F2.
-- Historical staging already has this helper; fresh canonical databases do not.
DO $block$
BEGIN
    IF to_regprocedure('public.tanda1_touch_updated_at()') IS NULL THEN
        CREATE FUNCTION public.tanda1_touch_updated_at()
        RETURNS trigger
        LANGUAGE plpgsql
        SET search_path TO pg_catalog, public
        AS $function$
        BEGIN
            NEW.updated_at := now();
            RETURN NEW;
        END;
        $function$;
    END IF;
END;
$block$;

REVOKE ALL ON FUNCTION public.tanda1_touch_updated_at() FROM PUBLIC, anon, authenticated, service_role;
