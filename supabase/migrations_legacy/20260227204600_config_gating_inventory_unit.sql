-- Migration: Inventory unit
ALTER TABLE public.inventory_lots 
ADD COLUMN IF NOT EXISTS unit text DEFAULT 'Piezas';

-- Update RPC list
CREATE OR REPLACE FUNCTION public.rpc_list_inventory_lots(p_tenant_id uuid, p_filters jsonb DEFAULT '{}')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
                'id', id,
                'sku', sku,
                'description', description,
                'warehouse', warehouse,
                'lot_code', lot_code,
                'qty_on_hand', qty_on_hand,
                'qty_reserved', qty_reserved,
                'unit_cost', unit_cost,
                'currency', currency,
                'received_at', received_at,
                'pedimento_ref', pedimento_ref,
                'status', status,
                'unit', unit,
                'created_at', created_at
            ) ORDER BY received_at ASC
        ), '[]'::jsonb)
        FROM inventory_lots
        WHERE tenant_id = p_tenant_id
          AND (p_filters->>'sku' IS NULL OR sku ILIKE '%' || (p_filters->>'sku') || '%')
    );
END;
$$;

-- Update RPC create
CREATE OR REPLACE FUNCTION public.rpc_create_inventory_lot(
    p_tenant_id uuid,
    p_sku text,
    p_lot_code text,
    p_qty_on_hand numeric,
    p_warehouse text DEFAULT NULL,
    p_received_at timestamptz DEFAULT now(),
    p_unit_cost numeric DEFAULT NULL,
    p_currency text DEFAULT 'MXN',
    p_pedimento_ref text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_unit text DEFAULT 'Piezas'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    
    INSERT INTO inventory_lots (
        tenant_id, sku, lot_code, qty_on_hand, warehouse, 
        received_at, unit_cost, currency, pedimento_ref, description, unit
    )
    VALUES (
        p_tenant_id, p_sku, p_lot_code, p_qty_on_hand, p_warehouse,
        p_received_at, p_unit_cost, p_currency, p_pedimento_ref, p_description, COALESCE(p_unit, 'Piezas')
    )
    RETURNING id INTO new_id;
    
    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
