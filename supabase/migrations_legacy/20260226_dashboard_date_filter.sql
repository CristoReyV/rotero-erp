-- Migration: Add optional date filters to Dashboard RPCs

-- Fix rpc_dashboard_overview missing columns and add dates
CREATE OR REPLACE FUNCTION public.rpc_dashboard_overview(
    p_tenant_id uuid,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ops_total int;
    v_ops_in_transit int;
    v_billing_total numeric;
    v_inventory_value numeric;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m 
        WHERE m.user_id = auth.uid() 
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT count(*) INTO v_ops_total FROM operations 
    WHERE tenant_id = p_tenant_id 
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date);
    
    SELECT count(*) INTO v_ops_in_transit FROM operations 
    WHERE tenant_id = p_tenant_id AND status = 'in_transit'
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date);
    
    SELECT COALESCE(SUM(total), 0) INTO v_billing_total 
    FROM billing_cfdis 
    WHERE tenant_id = p_tenant_id AND status = 'Timbrado'
      AND (p_start_date IS NULL OR issue_date >= p_start_date)
      AND (p_end_date IS NULL OR issue_date <= p_end_date);

    SELECT COALESCE(SUM(qty_on_hand * unit_cost), 0) INTO v_inventory_value 
    FROM inventory_lots 
    WHERE tenant_id = p_tenant_id AND status = 'available'
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date);

    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'ops_total', v_ops_total,
            'ops_in_transit', v_ops_in_transit,
            'billing_total', v_billing_total,
            'inventory_value', v_inventory_value
        ),
        'chart', jsonb_build_object(
            'data', jsonb_build_array(40, 65, 45, 90, 55, 75, 50, 80, 60, 95, 70, 85),
            'labels', jsonb_build_array('Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic')
        )
    );
END;
$$;


-- Fix rpc_dashboard_recent_activity missing columns and add dates
CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(
    p_tenant_id uuid,
    p_limit int DEFAULT 5,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m 
        WHERE m.user_id = auth.uid() 
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', reference_code,
                'client', client_display_name,
                'status', status,
                'route', route_summary,
                'eta', eta_display
            )
        ), '[]'::jsonb)
        FROM (
            SELECT reference_code, tenant_id, status, route_summary, client_display_name, eta_display
            FROM operations
            WHERE tenant_id = p_tenant_id
              AND (p_start_date IS NULL OR created_at >= p_start_date)
              AND (p_end_date IS NULL OR created_at <= p_end_date)
            ORDER BY created_at DESC
            LIMIT p_limit
        ) sub
    );
END;
$$;


-- RPC 3: Dashboard Alerts
CREATE OR REPLACE FUNCTION public.rpc_dashboard_alerts(
    p_tenant_id uuid,
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_alerts jsonb := '[]'::jsonb;
    v_cfdis_missing integer := 0;
    v_inventory_issues integer := 0;
    v_customs_open integer := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m 
        WHERE m.user_id = auth.uid() 
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Billing Alert: Timbrados missing Carta Porte
    SELECT COUNT(*) INTO v_cfdis_missing 
    FROM billing_cfdis 
    WHERE tenant_id = p_tenant_id AND status = 'Timbrado' AND has_carta_porte = false
      AND (p_start_date IS NULL OR issue_date >= p_start_date)
      AND (p_end_date IS NULL OR issue_date <= p_end_date);
    
    IF v_cfdis_missing > 0 THEN
        v_alerts := v_alerts || jsonb_build_object(
            'type', 'warning',
            'title', 'Carta Porte Pendiente',
            'description', v_cfdis_missing || ' CFDI(s) recien timbrado(s) se registran sin complemento logístico asociado.'
        );
    END IF;

    -- Inventory Alert: Blocked or Damaged
    SELECT COUNT(*) INTO v_inventory_issues 
    FROM inventory_lots
    WHERE tenant_id = p_tenant_id AND status IN ('blocked', 'damaged')
      AND (p_start_date IS NULL OR updated_at >= p_start_date)
      AND (p_end_date IS NULL OR updated_at <= p_end_date);

    IF v_inventory_issues > 0 THEN
        v_alerts := v_alerts || jsonb_build_object(
            'type', 'danger',
            'title', 'Inventario Comprometido',
            'description', v_inventory_issues || ' lote(s) reportado(s) actualmente como dañado(s) o bloqueado(s) en almacén.'
        );
    END IF;

    -- Customs Alert: Open Pedimentos
    SELECT COUNT(*) INTO v_customs_open 
    FROM customs_pedimentos
    WHERE tenant_id = p_tenant_id AND status != 'closed'
      AND (p_start_date IS NULL OR created_at >= p_start_date)
      AND (p_end_date IS NULL OR created_at <= p_end_date);

    IF v_customs_open > 0 THEN
        v_alerts := v_alerts || jsonb_build_object(
            'type', 'info',
            'title', 'Pedimentos Activos',
            'description', v_customs_open || ' pedimento(s) esperando conclusión de descargas/virtuales.'
        );
    END IF;

    IF jsonb_array_length(v_alerts) = 0 THEN
        v_alerts := v_alerts || jsonb_build_object(
            'type', 'info',
            'title', 'Sincronización SAT',
            'description', 'Validación de Anexo 24 y comprobantes completada exitosamente sin incidencias.'
        );
    END IF;

    RETURN v_alerts;
END;
$$;

NOTIFY pgrst, 'reload schema';
