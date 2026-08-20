\set ON_ERROR_STOP on

-- Test-only staging fixture applied after F1 and before the pending F2 migration.
-- Staging already has this canonical helper; fresh local uses the equivalent
-- baseline helper name, so rename it without changing its body or trigger OID.
DO $helper_fixture$
BEGIN
    IF to_regprocedure('public.tanda1_touch_updated_at()') IS NULL THEN
        IF to_regprocedure('public.touch_updated_at()') IS NULL THEN
            RAISE EXCEPTION 'F2 STAGING FIXTURE FAILED: no local touch helper available';
        END IF;
        ALTER FUNCTION public.touch_updated_at() RENAME TO tanda1_touch_updated_at;
    END IF;
END;
$helper_fixture$;

-- Staging already owns operation_crossings before F2. Reproduce that exact
-- dependency so F2 must preserve the existing canonical trigger.
CREATE TABLE IF NOT EXISTS public.operation_crossings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    crossed_at timestamptz NOT NULL DEFAULT now(),
    crossing_point text NOT NULL,
    crossing_type text NOT NULL DEFAULT 'other',
    note text,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_crossings_type_check CHECK (crossing_type IN ('entry', 'exit', 'other'))
);

DO $crossing_trigger_fixture$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.operation_crossings'::regclass
          AND tgname = 'trg_operation_crossings_touch_updated_at'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_operation_crossings_touch_updated_at
        BEFORE UPDATE ON public.operation_crossings
        FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
    END IF;
END;
$crossing_trigger_fixture$;

COMMENT ON TRIGGER trg_operation_crossings_touch_updated_at ON public.operation_crossings
    IS 'F2_STAGING_LIKE_PREEXISTING';
