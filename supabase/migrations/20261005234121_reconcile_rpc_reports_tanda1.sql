-- Preserve the historical reporting contract; harden only identity, search_path and ACL.
-- SECURITY DEFINER preserves the RPC-first, controlled multitenant aggregation:
-- direct table access is revoked; auth.uid() and tenant membership gate all results.
BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_reports_tanda1(
    p_tenant_id uuid,
    p_date_from text DEFAULT NULL,
    p_date_to text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_start date := COALESCE(NULLIF(p_date_from, '')::date, current_date - 28);
    v_end date := COALESCE(NULLIF(p_date_to, '')::date, current_date);
BEGIN
    IF auth.uid() IS NULL OR NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        WITH scoped_ops AS (
            SELECT
                o.*,
                date_trunc('week', o.created_at)::date AS week_start,
                COALESCE(NULLIF(o.service_type, ''), o.service_catalog_snapshot->>'service_type', 'Sin tipo') AS report_service_type,
                COALESCE(NULLIF(o.service_catalog_snapshot->>'service_class', ''), 'Sin clase') AS report_service_class,
                COALESCE(NULLIF(o.operation_scope, ''), 'national') AS report_scope,
                COALESCE(NULLIF(o.destination_place->>'state', ''), 'Sin estado') AS report_state,
                COALESCE(NULLIF(o.destination_place->>'countryCode', ''), 'MX') AS report_country,
                CASE
                    WHEN (o.cargo_summary->>'pieces') ~ '^[0-9]+(\.[0-9]+)?$' THEN (o.cargo_summary->>'pieces')::numeric
                    ELSE 0
                END AS pieces_num,
                CASE
                    WHEN (o.cargo_summary->>'weightKg') ~ '^[0-9]+(\.[0-9]+)?$' THEN (o.cargo_summary->>'weightKg')::numeric
                    ELSE 0
                END AS weight_kg_num
            FROM public.operations o
            WHERE o.tenant_id = p_tenant_id
              AND o.created_at::date >= v_start
              AND o.created_at::date <= v_end
        )
        SELECT jsonb_build_object(
            'date_from', v_start,
            'date_to', v_end,
            'weekly', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'week_start', week_start,
                        'operations_created', operations_created,
                        'delivered', delivered,
                        'closed', closed,
                        'billed', billed
                    )
                    ORDER BY week_start
                )
                FROM (
                    SELECT
                        week_start,
                        count(*) AS operations_created,
                        count(*) FILTER (WHERE status IN ('delivered', 'closed')) AS delivered,
                        count(*) FILTER (WHERE status = 'closed') AS closed,
                        count(*) FILTER (WHERE public.rpc_get_operation_billing_summary(id)->>'is_billed' = 'true') AS billed
                    FROM scoped_ops
                    GROUP BY week_start
                ) weekly_rows
            ), '[]'::jsonb),
            'volume', COALESCE((
                SELECT jsonb_build_object(
                    'operations', count(*),
                    'pieces', COALESCE(SUM(pieces_num), 0),
                    'weight_kg', COALESCE(SUM(weight_kg_num), 0)
                )
                FROM scoped_ops
            ), jsonb_build_object('operations', 0, 'pieces', 0, 'weight_kg', 0)),
            'by_service_type', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'service_type', report_service_type,
                        'service_class', report_service_class,
                        'operations', operations,
                        'pieces', pieces,
                        'weight_kg', weight_kg
                    )
                    ORDER BY operations DESC, report_service_type
                )
                FROM (
                    SELECT
                        report_service_type,
                        report_service_class,
                        count(*) AS operations,
                        COALESCE(SUM(pieces_num), 0) AS pieces,
                        COALESCE(SUM(weight_kg_num), 0) AS weight_kg
                    FROM scoped_ops
                    GROUP BY report_service_type, report_service_class
                ) service_rows
            ), '[]'::jsonb),
            'by_zone', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'zone', concat_ws(' / ', report_country, report_state),
                        'country_code', report_country,
                        'state', report_state,
                        'operations', operations,
                        'pieces', pieces,
                        'weight_kg', weight_kg
                    )
                    ORDER BY operations DESC, report_country, report_state
                )
                FROM (
                    SELECT
                        report_country,
                        report_state,
                        count(*) AS operations,
                        COALESCE(SUM(pieces_num), 0) AS pieces,
                        COALESCE(SUM(weight_kg_num), 0) AS weight_kg
                    FROM scoped_ops
                    GROUP BY report_country, report_state
                ) zone_rows
            ), '[]'::jsonb),
            'by_scope', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'scope', report_scope,
                        'operations', operations,
                        'pieces', pieces,
                        'weight_kg', weight_kg
                    )
                    ORDER BY report_scope
                )
                FROM (
                    SELECT
                        report_scope,
                        count(*) AS operations,
                        COALESCE(SUM(pieces_num), 0) AS pieces,
                        COALESCE(SUM(weight_kg_num), 0) AS weight_kg
                    FROM scoped_ops
                    GROUP BY report_scope
                ) scope_rows
            ), '[]'::jsonb)
        )
    );
END;
$$;

-- CREATE OR REPLACE retains existing grants, including the historical service_role grant.
-- No versioned service_role consumer requires this RPC.
REVOKE ALL ON FUNCTION public.rpc_reports_tanda1(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_reports_tanda1(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_reports_tanda1(uuid, text, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_reports_tanda1(uuid, text, text) TO authenticated;

COMMIT;
