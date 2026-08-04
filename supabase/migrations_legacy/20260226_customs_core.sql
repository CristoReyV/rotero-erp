-- Migration: Customs Core

CREATE TABLE IF NOT EXISTS customs_pedimentos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    pedimento_number text NOT NULL,
    operation_id uuid, -- reference to operations table if needed later
    aduana text,
    regimen text,
    tipo_operacion text DEFAULT 'import' CHECK (tipo_operacion IN ('import', 'export')),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'validating', 'released', 'in_transit', 'closed', 'blocked')),
    fecha_pago timestamptz,
    fecha_entrada timestamptz,
    fecha_salida timestamptz,
    total_value numeric,
    currency text DEFAULT 'MXN',
    descargo_method text NOT NULL DEFAULT 'PEPS' CHECK (descargo_method = 'PEPS'),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Note: In a real app we might want unique on (tenant_id, pedimento_number), 
-- but be careful if the same pedimento can exist repeatedly (unlikely though).
CREATE UNIQUE INDEX IF NOT EXISTS customs_pedimentos_tenant_number_idx ON customs_pedimentos(tenant_id, pedimento_number);
CREATE INDEX IF NOT EXISTS customs_pedimentos_tenant_status_idx ON customs_pedimentos(tenant_id, status);
CREATE INDEX IF NOT EXISTS customs_pedimentos_tenant_created_idx ON customs_pedimentos(tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS customs_descargo_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    pedimento_id uuid NOT NULL REFERENCES customs_pedimentos(id) ON DELETE CASCADE,
    sku text NOT NULL,
    lot_code text,
    qty numeric NOT NULL,
    unit text DEFAULT 'pcs',
    inventory_lot_id uuid REFERENCES inventory_lots(id),
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS customs_descargo_lines_tenant_pedimento_idx ON customs_descargo_lines(tenant_id, pedimento_id);
CREATE INDEX IF NOT EXISTS customs_descargo_lines_tenant_sku_idx ON customs_descargo_lines(tenant_id, sku);

ALTER TABLE customs_pedimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE customs_descargo_lines ENABLE ROW LEVEL SECURITY;

-- Policies for customs_pedimentos
CREATE POLICY "Users can read pedimentos in their tenants"
ON customs_pedimentos FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_pedimentos.tenant_id
    )
);

CREATE POLICY "Users can create pedimentos in their tenants"
ON customs_pedimentos FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_pedimentos.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update pedimentos in their tenants"
ON customs_pedimentos FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_pedimentos.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

-- Policies for customs_descargo_lines
CREATE POLICY "Users can read descargo lines in their tenants"
ON customs_descargo_lines FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_descargo_lines.tenant_id
    )
);

CREATE POLICY "Users can create descargo lines in their tenants"
ON customs_descargo_lines FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_descargo_lines.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update descargo lines in their tenants"
ON customs_descargo_lines FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_descargo_lines.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can delete descargo lines in their tenants"
ON customs_descargo_lines FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = customs_descargo_lines.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);


-- RPC: list pedimentos
CREATE OR REPLACE FUNCTION public.rpc_list_pedimentos(p_tenant_id uuid, p_filters jsonb DEFAULT '{}')
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
                'pedimento_number', pedimento_number,
                'status', status,
                'aduana', aduana,
                'regimen', regimen,
                'fecha_pago', fecha_pago,
                'total_value', total_value,
                'currency', currency,
                'created_at', created_at
            ) ORDER BY created_at DESC
        ), '[]'::jsonb)
        FROM customs_pedimentos
        WHERE tenant_id = p_tenant_id
          AND (p_filters->>'pedimento_number' IS NULL OR pedimento_number ILIKE '%' || (p_filters->>'pedimento_number') || '%')
    );
END;
$$;

-- RPC: create pedimento
CREATE OR REPLACE FUNCTION public.rpc_create_pedimento(
    p_tenant_id uuid,
    p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
    v_pedimento_number text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    v_pedimento_number := p_payload->>'pedimento_number';
    IF v_pedimento_number IS NULL OR length(v_pedimento_number) < 10 THEN
        RETURN jsonb_build_object('error', 'invalid format for pedimento_number (min length 10)');
    END IF;
    
    INSERT INTO customs_pedimentos (
        tenant_id, 
        pedimento_number, 
        aduana, 
        regimen, 
        tipo_operacion, 
        fecha_pago, 
        total_value, 
        currency, 
        status
    )
    VALUES (
        p_tenant_id, 
        v_pedimento_number,
        p_payload->>'aduana',
        p_payload->>'regimen',
        COALESCE(p_payload->>'tipo_operacion', 'import'),
        (p_payload->>'fecha_pago')::timestamptz,
        (p_payload->>'total_value')::numeric,
        COALESCE(p_payload->>'currency', 'MXN'),
        COALESCE(p_payload->>'status', 'draft')
    )
    RETURNING id INTO new_id;
    
    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: update pedimento
CREATE OR REPLACE FUNCTION public.rpc_update_pedimento(p_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    cur_status text;
    new_status text;
BEGIN
    SELECT tenant_id, status INTO cur_tenant_id, cur_status FROM customs_pedimentos WHERE id = p_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_patch ? 'status' THEN
        new_status := p_patch->>'status';
        -- Very basic transition restrictions (e.g., draft -> validating -> released)
        IF cur_status = 'draft' AND new_status NOT IN ('validating', 'closed', 'blocked') THEN
             RETURN jsonb_build_object('error', 'invalid status transition from draft');
        END IF;
        IF cur_status = 'closed' THEN
             RETURN jsonb_build_object('error', 'cannot update status of closed pedimento');
        END IF;
        
        UPDATE customs_pedimentos SET status = new_status, updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'fecha_pago' THEN
        UPDATE customs_pedimentos SET fecha_pago = (p_patch->>'fecha_pago')::timestamptz, updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'fecha_entrada' THEN
        UPDATE customs_pedimentos SET fecha_entrada = (p_patch->>'fecha_entrada')::timestamptz, updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'fecha_salida' THEN
        UPDATE customs_pedimentos SET fecha_salida = (p_patch->>'fecha_salida')::timestamptz, updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'aduana' THEN
        UPDATE customs_pedimentos SET aduana = p_patch->>'aduana', updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'regimen' THEN
        UPDATE customs_pedimentos SET regimen = p_patch->>'regimen', updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'total_value' THEN
        UPDATE customs_pedimentos SET total_value = (p_patch->>'total_value')::numeric, updated_at = now() WHERE id = p_id;
    END IF;

    IF p_patch ? 'currency' THEN
        UPDATE customs_pedimentos SET currency = p_patch->>'currency', updated_at = now() WHERE id = p_id;
    END IF;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: list descargo lines
CREATE OR REPLACE FUNCTION public.rpc_list_descargo_lines(p_pedimento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM customs_pedimentos WHERE id = p_pedimento_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', id,
                'pedimento_id', pedimento_id,
                'sku', sku,
                'lot_code', lot_code,
                'qty', qty,
                'unit', unit,
                'inventory_lot_id', inventory_lot_id,
                'created_at', created_at
            ) ORDER BY created_at ASC
        ), '[]'::jsonb)
        FROM customs_descargo_lines
        WHERE pedimento_id = p_pedimento_id
    );
END;
$$;

-- RPC: add descargo line
CREATE OR REPLACE FUNCTION public.rpc_add_descargo_line(
    p_pedimento_id uuid,
    p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    new_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM customs_pedimentos WHERE id = p_pedimento_id;
    IF v_tenant_id IS NULL THEN
         RETURN jsonb_build_object('error', 'pedimento not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO customs_descargo_lines (
        tenant_id,
        pedimento_id,
        sku,
        lot_code,
        qty,
        unit,
        inventory_lot_id
    )
    VALUES (
        v_tenant_id,
        p_pedimento_id,
        p_payload->>'sku',
        p_payload->>'lot_code',
        (p_payload->>'qty')::numeric,
        COALESCE(p_payload->>'unit', 'pcs'),
        (p_payload->>'inventory_lot_id')::uuid
    )
    RETURNING id INTO new_id;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
