-- Migration: Inventory Core Real

CREATE TABLE IF NOT EXISTS inventory_lots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    sku text NOT NULL,
    description text,
    warehouse text,
    lot_code text,
    qty_on_hand numeric NOT NULL DEFAULT 0 CHECK (qty_on_hand >= 0),
    qty_reserved numeric NOT NULL DEFAULT 0 CHECK (qty_reserved >= 0),
    unit_cost numeric,
    currency text DEFAULT 'MXN',
    received_at timestamptz NOT NULL DEFAULT now(),
    pedimento_ref text,
    status text NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'reserved', 'damaged', 'blocked')),
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS inventory_lots_tenant_sku_idx ON inventory_lots(tenant_id, sku);
CREATE INDEX IF NOT EXISTS inventory_lots_tenant_received_at_idx ON inventory_lots(tenant_id, received_at DESC);
CREATE INDEX IF NOT EXISTS inventory_lots_tenant_status_idx ON inventory_lots(tenant_id, status);

ALTER TABLE inventory_lots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read inventory in their tenants" ON inventory_lots;
DROP POLICY IF EXISTS "Users can create inventory in their tenants" ON inventory_lots;
DROP POLICY IF EXISTS "Users can update inventory in their tenants" ON inventory_lots;

CREATE POLICY "Users can read inventory in their tenants"
ON inventory_lots FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = inventory_lots.tenant_id
    )
);

CREATE POLICY "Users can create inventory in their tenants"
ON inventory_lots FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = inventory_lots.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update inventory in their tenants"
ON inventory_lots FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = inventory_lots.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

-- RPC for list inventory lots
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
                'created_at', created_at
            ) ORDER BY received_at ASC
        ), '[]'::jsonb)
        FROM inventory_lots
        WHERE tenant_id = p_tenant_id
          AND (p_filters->>'sku' IS NULL OR sku ILIKE '%' || (p_filters->>'sku') || '%')
    );
END;
$$;

-- RPC for create inventory lot
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
    p_description text DEFAULT NULL
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
        received_at, unit_cost, currency, pedimento_ref, description
    )
    VALUES (
        p_tenant_id, p_sku, p_lot_code, p_qty_on_hand, p_warehouse,
        p_received_at, p_unit_cost, p_currency, p_pedimento_ref, p_description
    )
    RETURNING id INTO new_id;
    
    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC for update inventory lot
CREATE OR REPLACE FUNCTION public.rpc_update_inventory_lot(p_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    lot_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO lot_tenant_id FROM inventory_lots WHERE id = p_id;
    IF lot_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = lot_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -----------------------------------
    -- Validate patch keys explicitly.
    -- Allowed: qty_reserved, status, warehouse, description
    -----------------------------------
    IF p_patch ? 'qty_reserved' THEN
        UPDATE inventory_lots SET qty_reserved = (p_patch->>'qty_reserved')::numeric WHERE id = p_id;
    END IF;

    IF p_patch ? 'status' THEN
        UPDATE inventory_lots SET status = p_patch->>'status' WHERE id = p_id;
    END IF;

    IF p_patch ? 'warehouse' THEN
        UPDATE inventory_lots SET warehouse = p_patch->>'warehouse' WHERE id = p_id;
    END IF;

    IF p_patch ? 'description' THEN
        UPDATE inventory_lots SET description = p_patch->>'description' WHERE id = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
