-- Migration: Finance Core (AR/AP + Cashflow)

CREATE TABLE IF NOT EXISTS finance_invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    direction text NOT NULL CHECK (direction IN ('ar', 'ap')),
    counterparty_name text NOT NULL,
    reference text,
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    currency text DEFAULT 'MXN',
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('draft', 'open', 'paid', 'overdue', 'void')),
    due_date date,
    paid_at timestamptz,
    linked_cfdi_id uuid REFERENCES billing_cfdis(id) ON DELETE SET NULL,
    notes text
);

CREATE INDEX IF NOT EXISTS finance_invoices_tenant_idx ON finance_invoices(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS finance_invoices_status_idx ON finance_invoices(tenant_id, status);

CREATE TABLE IF NOT EXISTS finance_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    invoice_id uuid NOT NULL REFERENCES finance_invoices(id) ON DELETE CASCADE,
    amount numeric(14,2) NOT NULL CHECK (amount > 0),
    paid_at timestamptz NOT NULL,
    method text DEFAULT 'transfer' CHECK (method IN ('transfer', 'cash', 'card', 'other')),
    note text
);

CREATE INDEX IF NOT EXISTS finance_payments_tenant_idx ON finance_payments(tenant_id, invoice_id);

ALTER TABLE finance_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_payments ENABLE ROW LEVEL SECURITY;

-- RLS: Invoices
CREATE POLICY "Users can read finance_invoices in their tenants"
ON finance_invoices FOR SELECT
USING (
    EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = finance_invoices.tenant_id)
);

CREATE POLICY "Users can insert finance_invoices in their tenants"
ON finance_invoices FOR INSERT
WITH CHECK (
    EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = finance_invoices.tenant_id AND m.role IN ('admin', 'operator'))
);

CREATE POLICY "Users can update finance_invoices in their tenants"
ON finance_invoices FOR UPDATE
USING (
    EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = finance_invoices.tenant_id AND m.role IN ('admin', 'operator'))
);

-- RLS: Payments
CREATE POLICY "Users can read finance_payments in their tenants"
ON finance_payments FOR SELECT
USING (
    EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = finance_payments.tenant_id)
);

CREATE POLICY "Users can insert finance_payments in their tenants"
ON finance_payments FOR INSERT
WITH CHECK (
    EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = finance_payments.tenant_id AND m.role IN ('admin', 'operator'))
);

-- RPC Overview
CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_ar_open numeric;
    v_total_ap_open numeric;
    v_total_overdue numeric;
    v_paid_this_month numeric;
    v_count_open int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO v_total_ar_open FROM finance_invoices WHERE tenant_id = p_tenant_id AND direction = 'ar' AND status IN ('open', 'overdue');
    SELECT COALESCE(SUM(amount), 0) INTO v_total_ap_open FROM finance_invoices WHERE tenant_id = p_tenant_id AND direction = 'ap' AND status IN ('open', 'overdue');
    SELECT COALESCE(SUM(amount), 0) INTO v_total_overdue FROM finance_invoices WHERE tenant_id = p_tenant_id AND direction = 'ar' AND status = 'overdue';
    
    SELECT COALESCE(SUM(amount), 0) INTO v_paid_this_month 
    FROM finance_payments 
    WHERE tenant_id = p_tenant_id 
      AND EXTRACT(MONTH FROM paid_at) = EXTRACT(MONTH FROM now())
      AND EXTRACT(YEAR FROM paid_at) = EXTRACT(YEAR FROM now());
      
    SELECT COUNT(*) INTO v_count_open FROM finance_invoices WHERE tenant_id = p_tenant_id AND status IN ('open', 'overdue');

    RETURN jsonb_build_object(
        'total_ar_open', v_total_ar_open,
        'total_ap_open', v_total_ap_open,
        'total_overdue', v_total_overdue,
        'paid_this_month', v_paid_this_month,
        'count_open_invoices', v_count_open,
        'chart', jsonb_build_object(
            'labels', jsonb_build_array('Sem 1', 'Sem 2', 'Sem 3', 'Sem 4'),
            'values', jsonb_build_array(v_paid_this_month * 0.2, v_paid_this_month * 0.5, v_paid_this_month * 0.1, v_paid_this_month * 0.2)
        )
    );
END;
$$;

-- RPC List Invoices
CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(
    p_tenant_id uuid,
    p_limit int DEFAULT 50,
    p_status text DEFAULT NULL,
    p_direction text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', id,
                'direction', direction,
                'counterparty_name', counterparty_name,
                'reference', reference,
                'amount', amount,
                'currency', currency,
                'status', status,
                'due_date', due_date,
                'created_at', created_at
            ) ORDER BY created_at DESC
        ), '[]'::jsonb)
        FROM (
            SELECT * FROM finance_invoices
            WHERE tenant_id = p_tenant_id
              AND (p_status IS NULL OR status = p_status)
              AND (p_direction IS NULL OR direction = p_direction)
            ORDER BY created_at DESC
            LIMIT p_limit
        ) sub
    );
END;
$$;

-- RPC Create Invoice
CREATE OR REPLACE FUNCTION public.rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role IN ('admin', 'operator')) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO finance_invoices (
        tenant_id,
        direction,
        counterparty_name,
        reference,
        amount,
        currency,
        status,
        due_date,
        notes
    ) VALUES (
        p_tenant_id,
        p_payload->>'direction',
        p_payload->>'counterparty_name',
        p_payload->>'reference',
        (p_payload->>'amount')::numeric,
        COALESCE(p_payload->>'currency', 'MXN'),
        COALESCE(p_payload->>'status', 'open'),
        (p_payload->>'due_date')::date,
        p_payload->>'notes'
    ) RETURNING id INTO new_id;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC Record Payment
CREATE OR REPLACE FUNCTION public.rpc_record_payment(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
    v_invoice_id uuid := (p_payload->>'invoice_id')::uuid;
    v_amount numeric := (p_payload->>'amount')::numeric;
    v_total_paid numeric;
    v_inv_amount numeric;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role IN ('admin', 'operator')) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT amount INTO v_inv_amount FROM finance_invoices WHERE id = v_invoice_id AND tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invoice_not_found'); END IF;

    INSERT INTO finance_payments (
        tenant_id,
        invoice_id,
        amount,
        paid_at,
        method,
        note
    ) VALUES (
        p_tenant_id,
        v_invoice_id,
        v_amount,
        COALESCE((p_payload->>'paid_at')::timestamptz, now()),
        COALESCE(p_payload->>'method', 'transfer'),
        p_payload->>'note'
    ) RETURNING id INTO new_id;

    -- Check if fully paid
    SELECT COALESCE(SUM(amount), 0) INTO v_total_paid FROM finance_payments WHERE invoice_id = v_invoice_id;
    IF v_total_paid >= v_inv_amount THEN
        UPDATE finance_invoices SET status = 'paid', paid_at = now() WHERE id = v_invoice_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC Update Invoice Status
CREATE OR REPLACE FUNCTION public.rpc_update_finance_invoice_status(p_tenant_id uuid, p_id uuid, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role IN ('admin', 'operator')) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    UPDATE finance_invoices SET status = p_status WHERE id = p_id AND tenant_id = p_tenant_id;
    RETURN jsonb_build_object('success', true);
END;
$$;
