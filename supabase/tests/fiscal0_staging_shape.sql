\set ON_ERROR_STOP on

DO $staging_shape$
BEGIN
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> 37
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations) <> '20260902000000' THEN
    RAISE EXCEPTION 'FISCAL0 staging-shape fixture must start from the 37-migration BH2 history';
  END IF;
  IF to_regclass('public.fiscal_requests') IS NULL
     OR to_regclass('public.fiscal_provider_attempts') IS NULL
     OR to_regprocedure('private.fiscal0_snapshot(public.billing_cfdis)') IS NULL THEN
    RAISE EXCEPTION 'FISCAL0 corrected migration did not compile on the BH2 staging shape';
  END IF;
END $staging_shape$;

\ir fiscal0_composite_parameter_regression.sql
