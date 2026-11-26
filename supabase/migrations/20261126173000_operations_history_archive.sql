BEGIN;

SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES (tenant_id, id) ON public.companies TO postgres;
SET LOCAL ROLE postgres;

CREATE TABLE private.operation_history_archive (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    reference_code text NOT NULL CHECK (length(btrim(reference_code)) BETWEEN 1 AND 160),
    source_customer_name text CHECK (length(source_customer_name) <= 500),
    source_carrier_name text CHECK (length(source_carrier_name) <= 500),
    source_dispatch_crossing_date text CHECK (length(source_dispatch_crossing_date) <= 1000),
    source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    source_sheet text NOT NULL CHECK (length(btrim(source_sheet)) BETWEEN 1 AND 31),
    source_row integer NOT NULL CHECK (source_row BETWEEN 2 AND 1048576),
    FOREIGN KEY (tenant_id, company_id) REFERENCES public.companies (tenant_id, id),
    UNIQUE (tenant_id, source_sha256, source_sheet, source_row)
);

SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES (tenant_id, id) ON public.companies FROM postgres;
SET LOCAL ROLE postgres;

COMMENT ON TABLE private.operation_history_archive IS
    'Source-only archive. A row carries no operational status or links to workflow and financial entities.';
COMMENT ON COLUMN private.operation_history_archive.source_dispatch_crossing_date IS
    'Literal source evidence labeled Fecha de Despacho / Cruce, including an unsplit sequence of dates.';

CREATE UNIQUE INDEX operation_history_archive_company_folio_idx
    ON private.operation_history_archive (tenant_id, company_id, lower(btrim(reference_code)));
CREATE INDEX operation_history_archive_company_page_idx
    ON private.operation_history_archive (tenant_id, company_id, id);

ALTER TABLE private.operation_history_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.operation_history_archive FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON private.operation_history_archive TO rotero_delivery_scope_owner;
CREATE POLICY operation_history_archive_read_owner ON private.operation_history_archive
    FOR SELECT TO rotero_delivery_scope_owner USING (true);

CREATE FUNCTION public.rpc_delivery_operations_history_page(
    p_tenant_id uuid,
    p_search text DEFAULT '',
    p_after_id uuid DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_export boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    companies uuid[] := private.delivery_company_ids();
    selected_company uuid;
    items jsonb;
    total bigint;
    next_id uuid;
BEGIN
    IF (private.delivery_headers()->>'x-rotero-scope') IS DISTINCT FROM 'company'
       OR cardinality(companies) IS DISTINCT FROM 1
       OR NOT private.delivery_cap(p_tenant_id, 'operations.read')
       OR p_export IS NULL
       OR (p_export AND NOT private.delivery_cap(p_tenant_id, 'export.operational'))
    THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF p_search IS NULL OR length(p_search) > 160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
    THEN
        RETURN jsonb_build_object('error', 'invalid_filters');
    END IF;

    selected_company := companies[1];
    IF p_after_id IS NOT NULL AND NOT EXISTS (
        SELECT FROM private.operation_history_archive h
        WHERE h.tenant_id = p_tenant_id AND h.company_id = selected_company AND h.id = p_after_id
    ) THEN
        RETURN jsonb_build_object('error', 'invalid_cursor');
    END IF;

    WITH scoped AS MATERIALIZED (
        SELECT h.id, h.reference_code, h.source_customer_name, h.source_carrier_name,
               h.source_dispatch_crossing_date, h.source_sheet, h.source_row
        FROM private.operation_history_archive h
        WHERE h.tenant_id = p_tenant_id AND h.company_id = selected_company
          AND (p_search = '' OR strpos(lower(concat_ws(' ', h.reference_code, h.source_customer_name,
                                      h.source_carrier_name)), lower(p_search)) > 0)
    ), page AS (
        SELECT * FROM scoped
        WHERE p_after_id IS NULL OR id > p_after_id
        ORDER BY id LIMIT p_limit
    ), last_id AS (
        SELECT id FROM page ORDER BY id DESC LIMIT 1
    )
    SELECT (SELECT count(*) FROM scoped),
           (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id), '[]') FROM page p),
           (SELECT l.id FROM last_id l WHERE EXISTS (SELECT FROM scoped WHERE id > l.id))
    INTO total, items, next_id;

    RETURN jsonb_build_object('items', items, 'total', total, 'next_cursor', next_id,
                              'company_ids', companies);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_delivery_operations_history_page(uuid, text, uuid, integer, boolean)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operations_history_page(uuid, text, uuid, integer, boolean)
    TO authenticated;
DO $owner$
DECLARE had_create boolean := has_schema_privilege('rotero_delivery_scope_owner', 'public', 'CREATE');
BEGIN
    IF NOT had_create THEN
        GRANT CREATE ON SCHEMA public TO rotero_delivery_scope_owner;
    END IF;
    ALTER FUNCTION public.rpc_delivery_operations_history_page(uuid, text, uuid, integer, boolean)
        OWNER TO rotero_delivery_scope_owner;
    IF NOT had_create THEN
        REVOKE CREATE ON SCHEMA public FROM rotero_delivery_scope_owner;
    END IF;
END $owner$;

COMMIT;
