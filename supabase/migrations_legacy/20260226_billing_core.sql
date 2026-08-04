-- Migration: Billing Core (CFDI & Carta Porte)

CREATE TABLE IF NOT EXISTS billing_cfdis (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    uuid text NOT NULL, -- The fiscal UUID, usually 36 chars but we allow any string for flexibility
    serie text,
    folio text,
    rfc_emisor text NOT NULL,
    rfc_receptor text NOT NULL,
    receptor_name text,
    subtotal numeric,
    total numeric NOT NULL,
    currency text DEFAULT 'MXN',
    status text NOT NULL DEFAULT 'timbrado' CHECK (status IN ('draft', 'timbrado', 'cancelado', 'error')),
    has_carta_porte boolean NOT NULL DEFAULT false,
    has_complemento_pago boolean NOT NULL DEFAULT false,
    issued_at timestamptz,
    cancelled_at timestamptz,
    pac_provider text,
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Unique constraint on tenant_id and uuid because a tenant can't have duplicate fiscal UUIDs
CREATE UNIQUE INDEX IF NOT EXISTS billing_cfdis_tenant_uuid_idx ON billing_cfdis(tenant_id, uuid);
CREATE INDEX IF NOT EXISTS billing_cfdis_tenant_status_idx ON billing_cfdis(tenant_id, status);
CREATE INDEX IF NOT EXISTS billing_cfdis_tenant_issued_idx ON billing_cfdis(tenant_id, issued_at DESC);
CREATE INDEX IF NOT EXISTS billing_cfdis_tenant_rfc_receptor_idx ON billing_cfdis(tenant_id, rfc_receptor);
CREATE INDEX IF NOT EXISTS billing_cfdis_tenant_rfc_emisor_idx ON billing_cfdis(tenant_id, rfc_emisor);

CREATE TABLE IF NOT EXISTS billing_carta_porte (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    cfdi_id uuid NOT NULL REFERENCES billing_cfdis(id) ON DELETE CASCADE,
    trans_type text,
    vehicle_plate text,
    carrier_name text,
    origin text,
    destination text,
    goods_desc text,
    created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS billing_carta_porte_cfdi_idx ON billing_carta_porte(tenant_id, cfdi_id);

ALTER TABLE billing_cfdis ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_carta_porte ENABLE ROW LEVEL SECURITY;

-- RLS for billing_cfdis
CREATE POLICY "Users can read billing_cfdis in their tenants"
ON billing_cfdis FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_cfdis.tenant_id
    )
);

CREATE POLICY "Users can insert billing_cfdis in their tenants"
ON billing_cfdis FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_cfdis.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update billing_cfdis in their tenants"
ON billing_cfdis FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_cfdis.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

-- RLS for billing_carta_porte
CREATE POLICY "Users can read billing_carta_porte in their tenants"
ON billing_carta_porte FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_carta_porte.tenant_id
    )
);

CREATE POLICY "Users can insert billing_carta_porte in their tenants"
ON billing_carta_porte FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_carta_porte.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update billing_carta_porte in their tenants"
ON billing_carta_porte FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = billing_carta_porte.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);


-- RPC: rpc_list_cfdis
CREATE OR REPLACE FUNCTION public.rpc_list_cfdis(p_tenant_id uuid, p_filters jsonb DEFAULT '{}')
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
                'uuid', uuid,
                'serie', serie,
                'folio', folio,
                'rfc_emisor', rfc_emisor,
                'rfc_receptor', rfc_receptor,
                'receptor_name', receptor_name,
                'subtotal', subtotal,
                'total', total,
                'currency', currency,
                'status', status,
                'has_carta_porte', has_carta_porte,
                'has_complemento_pago', has_complemento_pago,
                'issued_at', issued_at,
                'cancelled_at', cancelled_at,
                'pac_provider', pac_provider,
                'notes', notes,
                'created_at', created_at,
                'updated_at', updated_at
            ) ORDER BY issued_at DESC, created_at DESC
        ), '[]'::jsonb)
        FROM billing_cfdis
        WHERE tenant_id = p_tenant_id
          AND (p_filters->>'status' IS NULL OR status = (p_filters->>'status'))
          AND (p_filters->>'rfc' IS NULL OR rfc_receptor ILIKE '%' || (p_filters->>'rfc') || '%' OR rfc_emisor ILIKE '%' || (p_filters->>'rfc') || '%')
          AND (p_filters->>'searchText' IS NULL OR uuid ILIKE '%' || (p_filters->>'searchText') || '%' OR folio ILIKE '%' || (p_filters->>'searchText') || '%')
    );
END;
$$;

-- RPC: rpc_get_cfdi_detail
CREATE OR REPLACE FUNCTION public.rpc_get_cfdi_detail(p_cfdi_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    res jsonb;
    cp jsonb;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM billing_cfdis WHERE id = p_cfdi_id;
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

    -- Fetch CFDI detail without exposing tenant_id explicitly
    SELECT jsonb_build_object(
        'id', id,
        'uuid', uuid,
        'serie', serie,
        'folio', folio,
        'rfc_emisor', rfc_emisor,
        'rfc_receptor', rfc_receptor,
        'receptor_name', receptor_name,
        'subtotal', subtotal,
        'total', total,
        'currency', currency,
        'status', status,
        'has_carta_porte', has_carta_porte,
        'has_complemento_pago', has_complemento_pago,
        'issued_at', issued_at,
        'cancelled_at', cancelled_at,
        'pac_provider', pac_provider,
        'notes', notes,
        'created_at', created_at,
        'updated_at', updated_at
    ) INTO res FROM billing_cfdis WHERE id = p_cfdi_id;

    -- Fetch Carta Porte if exists
    SELECT jsonb_build_object(
        'id', id,
        'trans_type', trans_type,
        'vehicle_plate', vehicle_plate,
        'carrier_name', carrier_name,
        'origin', origin,
        'destination', destination,
        'goods_desc', goods_desc,
        'created_at', created_at
    ) INTO cp FROM billing_carta_porte WHERE cfdi_id = p_cfdi_id;

    IF cp IS NOT NULL THEN
        res := jsonb_set(res, '{carta_porte}', cp);
    END IF;

    RETURN res;
END;
$$;

-- RPC: rpc_create_cfdi
CREATE OR REPLACE FUNCTION public.rpc_create_cfdi(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
    v_uuid text;
    v_status text;
    v_total numeric;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    v_uuid := p_payload->>'uuid';
    v_status := COALESCE(p_payload->>'status', 'timbrado');
    v_total := (p_payload->>'total')::numeric;

    IF v_status != 'draft' AND (v_uuid IS NULL OR trim(v_uuid) = '') THEN
        RETURN jsonb_build_object('error', 'UUID is required unless status is draft');
    END IF;

    IF v_status != 'draft' AND (v_total IS NULL OR v_total <= 0) THEN
        RETURN jsonb_build_object('error', 'total must be > 0 unless status is draft');
    END IF;

    INSERT INTO billing_cfdis (
        tenant_id,
        uuid,
        serie,
        folio,
        rfc_emisor,
        rfc_receptor,
        receptor_name,
        subtotal,
        total,
        currency,
        status,
        has_carta_porte,
        has_complemento_pago,
        issued_at,
        pac_provider,
        notes
    ) VALUES (
        p_tenant_id,
        COALESCE(v_uuid, 'draft-' || gen_random_uuid()::text),
        p_payload->>'serie',
        p_payload->>'folio',
        p_payload->>'rfc_emisor',
        p_payload->>'rfc_receptor',
        p_payload->>'receptor_name',
        (p_payload->>'subtotal')::numeric,
        COALESCE(v_total, 0),
        COALESCE(p_payload->>'currency', 'MXN'),
        v_status,
        COALESCE((p_payload->>'has_carta_porte')::boolean, false),
        COALESCE((p_payload->>'has_complemento_pago')::boolean, false),
        (p_payload->>'issued_at')::timestamptz,
        p_payload->>'pac_provider',
        p_payload->>'notes'
    ) RETURNING id INTO new_id;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: rpc_update_cfdi
CREATE OR REPLACE FUNCTION public.rpc_update_cfdi(p_cfdi_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    cur_status text;
    new_status text;
BEGIN
    SELECT tenant_id, status INTO cur_tenant_id, cur_status FROM billing_cfdis WHERE id = p_cfdi_id;
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
        IF cur_status = 'cancelado' AND new_status = 'timbrado' THEN
            RETURN jsonb_build_object('error', 'cannot un-cancel CFDI');
        END IF;

        UPDATE billing_cfdis SET status = new_status, updated_at = now() WHERE id = p_cfdi_id;
        
        IF new_status = 'cancelado' THEN
            UPDATE billing_cfdis SET cancelled_at = COALESCE((p_patch->>'cancelled_at')::timestamptz, now()) WHERE id = p_cfdi_id;
        END IF;
    END IF;

    IF p_patch ? 'notes' THEN
        UPDATE billing_cfdis SET notes = p_patch->>'notes', updated_at = now() WHERE id = p_cfdi_id;
    END IF;

    IF p_patch ? 'has_carta_porte' THEN
        UPDATE billing_cfdis SET has_carta_porte = (p_patch->>'has_carta_porte')::boolean, updated_at = now() WHERE id = p_cfdi_id;
    END IF;

    IF p_patch ? 'has_complemento_pago' THEN
        UPDATE billing_cfdis SET has_complemento_pago = (p_patch->>'has_complemento_pago')::boolean, updated_at = now() WHERE id = p_cfdi_id;
    END IF;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: rpc_upsert_carta_porte
CREATE OR REPLACE FUNCTION public.rpc_upsert_carta_porte(p_cfdi_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    cp_id uuid;
BEGIN
    SELECT tenant_id INTO cur_tenant_id FROM billing_cfdis WHERE id = p_cfdi_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'cfdi_not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO billing_carta_porte (
        tenant_id,
        cfdi_id,
        trans_type,
        vehicle_plate,
        carrier_name,
        origin,
        destination,
        goods_desc
    ) VALUES (
        cur_tenant_id,
        p_cfdi_id,
        p_payload->>'trans_type',
        p_payload->>'vehicle_plate',
        p_payload->>'carrier_name',
        p_payload->>'origin',
        p_payload->>'destination',
        p_payload->>'goods_desc'
    )
    ON CONFLICT (tenant_id, cfdi_id) DO UPDATE SET
        trans_type = EXCLUDED.trans_type,
        vehicle_plate = EXCLUDED.vehicle_plate,
        carrier_name = EXCLUDED.carrier_name,
        origin = EXCLUDED.origin,
        destination = EXCLUDED.destination,
        goods_desc = EXCLUDED.goods_desc
    RETURNING id INTO cp_id;

    -- Update billing_cfdis to reflect that it has carta porte
    UPDATE billing_cfdis SET has_carta_porte = true, updated_at = now() WHERE id = p_cfdi_id;

    RETURN jsonb_build_object('success', true, 'id', cp_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
