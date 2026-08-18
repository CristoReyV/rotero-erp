-- RBAC.3A: align the frontend-consumed read RPCs with the canonical schema.
-- CREATE OR REPLACE preserves the signatures while the explicit ACLs retain
-- authenticated ERP access and remove implicit/default execution paths.

CREATE OR REPLACE FUNCTION public.rpc_dashboard_overview(
    p_tenant_id uuid,
    p_start_date timestamptz DEFAULT NULL,
    p_end_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'ops_total', (
                SELECT count(*)
                FROM public.operations AS o
                WHERE o.tenant_id = p_tenant_id
                  AND (p_start_date IS NULL OR o.created_at >= p_start_date)
                  AND (p_end_date IS NULL OR o.created_at <= p_end_date)
            ),
            'ops_in_transit', (
                SELECT count(*)
                FROM public.operations AS o
                WHERE o.tenant_id = p_tenant_id
                  AND o.status = 'in_transit'
                  AND (p_start_date IS NULL OR o.created_at >= p_start_date)
                  AND (p_end_date IS NULL OR o.created_at <= p_end_date)
            ),
            'billing_total', COALESCE((
                SELECT sum(c.total)
                FROM public.billing_cfdis AS c
                WHERE c.tenant_id = p_tenant_id
                  AND c.status = 'timbrado'
                  AND (p_start_date IS NULL OR c.created_at >= p_start_date)
                  AND (p_end_date IS NULL OR c.created_at <= p_end_date)
            ), 0),
            'inventory_value', COALESCE((
                SELECT sum(i.qty_on_hand * COALESCE(i.unit_cost, 0))
                FROM public.inventory_lots AS i
                WHERE i.tenant_id = p_tenant_id
            ), 0)
        ),
        'chart', jsonb_build_object(
            'data', '[]'::jsonb,
            'labels', '[]'::jsonb
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_alerts(
    p_tenant_id uuid,
    p_start_date timestamptz DEFAULT NULL,
    p_end_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_alerts jsonb := '[]'::jsonb;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.finance_invoices AS i
        WHERE i.tenant_id = p_tenant_id
          AND i.status = 'overdue'
    ) THEN
        v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
            'type', 'warning',
            'title', 'Facturas vencidas',
            'description', 'Hay cuentas vencidas por revisar'
        ));
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.inventory_lots AS i
        WHERE i.tenant_id = p_tenant_id
          AND i.qty_on_hand - i.qty_reserved <= 10
    ) THEN
        v_alerts := v_alerts || jsonb_build_array(jsonb_build_object(
            'type', 'info',
            'title', 'Stock bajo',
            'description', 'Hay lotes con disponibilidad baja'
        ));
    END IF;

    RETURN v_alerts;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_reports_pipeline_summary(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_total bigint;
    v_won bigint;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT count(*), count(*) FILTER (WHERE d.stage = 'won')
    INTO v_total, v_won
    FROM public.crm_deals AS d
    WHERE d.tenant_id = p_tenant_id;

    RETURN jsonb_build_object(
        'deals_by_stage', jsonb_build_object(
            'lead', (
                SELECT count(*)
                FROM public.crm_deals AS d
                WHERE d.tenant_id = p_tenant_id AND d.stage = 'lead'
            ),
            'contacted', (
                SELECT count(*)
                FROM public.crm_deals AS d
                WHERE d.tenant_id = p_tenant_id AND d.stage = 'qualified'
            ),
            'proposal', (
                SELECT count(*)
                FROM public.crm_deals AS d
                WHERE d.tenant_id = p_tenant_id AND d.stage = 'proposal'
            ),
            'won', v_won
        ),
        'total_pipeline_value', COALESCE((
            SELECT sum(d.value)
            FROM public.crm_deals AS d
            WHERE d.tenant_id = p_tenant_id AND d.stage <> 'lost'
        ), 0),
        'conversion_rate', CASE
            WHEN v_total = 0 THEN 0
            ELSE round(v_won::numeric * 100 / v_total, 2)
        END
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_reports_inventory_summary(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN jsonb_build_object(
        'inventory_total_value', COALESCE((
            SELECT sum(i.qty_on_hand * COALESCE(i.unit_cost, 0))
            FROM public.inventory_lots AS i
            WHERE i.tenant_id = p_tenant_id
        ), 0),
        'blocked_count', (
            SELECT count(*)
            FROM public.inventory_lots AS i
            WHERE i.tenant_id = p_tenant_id AND i.status = 'blocked'
        ),
        'low_stock_count', (
            SELECT count(*)
            FROM public.inventory_lots AS i
            WHERE i.tenant_id = p_tenant_id
              AND i.qty_on_hand - i.qty_reserved <= 10
        ),
        'top_skus_by_value', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object('sku', x.sku, 'value', x.value)
                ORDER BY x.value DESC
            )
            FROM (
                SELECT i.sku,
                       sum(i.qty_on_hand * COALESCE(i.unit_cost, 0)) AS value
                FROM public.inventory_lots AS i
                WHERE i.tenant_id = p_tenant_id
                GROUP BY i.sku
                ORDER BY value DESC
                LIMIT 5
            ) AS x
        ), '[]'::jsonb)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_reports_operations_summary(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN jsonb_build_object(
        'operations_per_month', '[]'::jsonb,
        'avg_delivery_time', COALESCE((
            SELECT avg(extract(epoch FROM (o.updated_at - o.created_at)) / 3600)
            FROM public.operations AS o
            WHERE o.tenant_id = p_tenant_id
              AND o.status IN ('delivered', 'closed')
        ), 0),
        'active_routes_count', (
            SELECT count(*)
            FROM public.operations AS o
            WHERE o.tenant_id = p_tenant_id
              AND o.status IN ('assigned', 'in_transit')
        )
    );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_pipeline_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_inventory_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_operations_summary(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_pipeline_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_inventory_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_operations_summary(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
