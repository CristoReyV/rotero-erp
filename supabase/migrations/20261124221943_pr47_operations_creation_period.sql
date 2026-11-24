-- Apply only after a separate staging review. Keep the existing RPC signature and grants.
BEGIN;

DO $guard$
DECLARE
    existing pg_catalog.pg_proc%ROWTYPE;
BEGIN
    SELECT * INTO STRICT existing
    FROM pg_catalog.pg_proc
    WHERE oid = 'public.rpc_delivery_operations_page(uuid,text,uuid,integer,boolean)'::regprocedure;

    IF existing.proowner <> 'postgres'::regrole
       OR NOT existing.prosecdef
       OR existing.provolatile <> 's'
       OR existing.proconfig IS DISTINCT FROM ARRAY['search_path=""']
       OR md5(replace(existing.prosrc, E'\r\n', E'\n')) <> '634e55342ff29bf0093360287f53d614'
       OR has_function_privilege('anon', existing.oid, 'EXECUTE')
       OR NOT has_function_privilege('authenticated', existing.oid, 'EXECUTE')
       OR has_function_privilege('service_role', existing.oid, 'EXECUTE')
    THEN
        RAISE EXCEPTION 'pr47_operations_page_source_drift';
    END IF;
END $guard$;

CREATE FUNCTION private.pr47_operations_page(
    p_tenant_id uuid, p_search text, p_after_id uuid, p_limit integer, p_export boolean,
    p_created_from date, p_created_to date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = '' AS $body$
DECLARE
    items jsonb;
    total bigint;
    next_id uuid;
    business_timezone text;
    start_at timestamptz;
    end_at timestamptz;
BEGIN
    IF NOT private.delivery_cap(p_tenant_id, 'operations.read') OR p_export IS NULL
       OR (p_export AND NOT private.delivery_cap(p_tenant_id, 'export.operational'))
    THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_search IS NULL OR length(p_search) > 160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
       OR p_created_from NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
       OR p_created_to NOT BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
       OR p_created_from > p_created_to
    THEN
        RETURN jsonb_build_object('error', 'invalid_filters');
    END IF;

    IF p_after_id IS NOT NULL AND NOT EXISTS (
        SELECT FROM private.delivery_operations
        WHERE tenant_id = p_tenant_id AND id = p_after_id
    ) THEN
        RETURN jsonb_build_object('error', 'invalid_cursor');
    END IF;

    SELECT s.timezone INTO business_timezone
    FROM public.tenant_settings s
    WHERE s.tenant_id = p_tenant_id;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_timezone_names WHERE name = business_timezone) THEN
        business_timezone := 'America/Mexico_City';
    END IF;

    -- Convert each local midnight independently so short or long days remain inclusive.
    start_at := p_created_from::timestamp AT TIME ZONE business_timezone;
    end_at := (p_created_to + 1)::timestamp AT TIME ZONE business_timezone;

    WITH scoped AS MATERIALIZED (
        SELECT o.* FROM private.delivery_operations o
        WHERE o.tenant_id = p_tenant_id
          AND (start_at IS NULL OR o.created_at >= start_at)
          AND (end_at IS NULL OR o.created_at < end_at)
          AND (p_search = '' OR position(lower(p_search) IN lower(
              concat_ws(' ', o.reference_code, o.route_summary, o.client_display_name, o.provider_name)
          )) > 0)
    ), page AS (
        SELECT * FROM scoped WHERE p_after_id IS NULL OR id > p_after_id ORDER BY id LIMIT p_limit
    )
    SELECT
        (SELECT count(*) FROM scoped),
        (SELECT COALESCE(jsonb_agg(private.delivery_operation_dto(to_jsonb(p)) ORDER BY p.id), '[]') FROM page p),
        CASE WHEN EXISTS (SELECT FROM scoped WHERE id > (SELECT id FROM page ORDER BY id DESC LIMIT 1))
             THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO total, items, next_id;

    RETURN jsonb_build_object(
        'items', items, 'total', total, 'next_cursor', next_id,
        'company_ids', private.delivery_company_ids(),
        'classification_notice', 'resolved_only; unclassified history requires reviewed reconciliation',
        'creation_date_timezone', business_timezone
    );
END $body$;

REVOKE ALL ON FUNCTION private.pr47_operations_page(uuid,text,uuid,integer,boolean,date,date)
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rpc_delivery_operations_page(
    p_tenant_id uuid, p_search text DEFAULT '', p_after_id uuid DEFAULT NULL,
    p_limit integer DEFAULT 50, p_export boolean DEFAULT false
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $body$
    SELECT private.pr47_operations_page(p_tenant_id, p_search, p_after_id, p_limit, p_export, NULL, NULL);
$body$;

CREATE FUNCTION public.rpc_delivery_operations_page_by_creation(
    p_tenant_id uuid, p_search text, p_after_id uuid, p_limit integer, p_export boolean,
    p_created_from date, p_created_to date
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $body$
    SELECT private.pr47_operations_page(
        p_tenant_id, p_search, p_after_id, p_limit, p_export, p_created_from, p_created_to
    );
$body$;

REVOKE ALL ON FUNCTION public.rpc_delivery_operations_page_by_creation(uuid,text,uuid,integer,boolean,date,date)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operations_page_by_creation(uuid,text,uuid,integer,boolean,date,date)
TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
