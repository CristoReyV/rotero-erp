-- F4 — ROTERO Finance 360
-- Forward-only and additive. Reconstructs reviewed Finance/Billing handoff
-- contracts locally and hardens the same contracts when already present.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.f4_user_can_manage_finance(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT (SELECT auth.uid()) IS NOT NULL
       AND public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']);
$function$;

CREATE OR REPLACE FUNCTION private.f4_amount_mxn(
    p_amount numeric, p_currency text, p_exchange_rate numeric
)
RETURNS numeric
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT CASE
        WHEN upper(COALESCE(p_currency, 'MXN')) = 'MXN' THEN round(p_amount, 2)
        WHEN p_exchange_rate IS NOT NULL AND p_exchange_rate > 0 THEN round(p_amount * p_exchange_rate, 2)
        ELSE NULL
    END;
$function$;

-- Staging retains these historical Billing contracts. The canonical reset has
-- history markers, so F4 reconstructs only the Finance-consumed subset.
CREATE TABLE IF NOT EXISTS public.billing_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    linked_cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    document_direction text NOT NULL DEFAULT 'ingreso',
    document_type text NOT NULL DEFAULT 'cfdi_ingreso',
    status text NOT NULL DEFAULT 'draft',
    serie text, folio text, fiscal_uuid text,
    currency text NOT NULL DEFAULT 'MXN', exchange_rate numeric(18,6), exchange_rate_date date,
    subtotal numeric(14,2) NOT NULL DEFAULT 0, total numeric(14,2) NOT NULL DEFAULT 0,
    total_mxn numeric(14,2), notes text, created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_documents_direction_check CHECK (document_direction IN ('ingreso', 'egreso')),
    CONSTRAINT billing_documents_status_check CHECK (status IN ('draft', 'ready_for_api', 'queued', 'api_error', 'stamped', 'cancelled', 'voided'))
);

CREATE TABLE IF NOT EXISTS public.billing_credit_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    note_type text NOT NULL DEFAULT 'customer_credit',
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    finance_invoice_id uuid REFERENCES public.finance_invoices(id) ON DELETE SET NULL,
    cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    source_billing_document_id uuid REFERENCES public.billing_documents(id) ON DELETE SET NULL,
    credit_billing_document_id uuid REFERENCES public.billing_documents(id) ON DELETE SET NULL,
    folio text, provider_note_reference text, issue_date date NOT NULL DEFAULT current_date,
    received_at timestamptz, reason text, subtotal numeric(14,2) NOT NULL DEFAULT 0,
    iva numeric(14,2) NOT NULL DEFAULT 0, total numeric(14,2) NOT NULL DEFAULT 0,
    currency text NOT NULL DEFAULT 'MXN', exchange_rate numeric(18,6), exchange_rate_date date,
    total_mxn numeric(14,2), status text NOT NULL DEFAULT 'draft', notes text, created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_credit_notes_type_check CHECK (note_type IN ('customer_credit', 'provider_credit')),
    CONSTRAINT billing_credit_notes_status_check CHECK (status IN ('draft', 'applied', 'cancelled')),
    CONSTRAINT billing_credit_notes_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT billing_credit_notes_amounts_check CHECK (subtotal >= 0 AND iva >= 0 AND total >= 0)
);

CREATE TABLE IF NOT EXISTS public.billing_payment_complements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    finance_invoice_id uuid NOT NULL REFERENCES public.finance_invoices(id) ON DELETE CASCADE,
    finance_payment_id uuid REFERENCES public.finance_payments(id) ON DELETE SET NULL,
    cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    invoice_billing_document_id uuid REFERENCES public.billing_documents(id) ON DELETE SET NULL,
    complement_billing_document_id uuid REFERENCES public.billing_documents(id) ON DELETE SET NULL,
    payment_date timestamptz NOT NULL DEFAULT now(), method text NOT NULL DEFAULT 'transfer',
    bank_reference text, currency text NOT NULL DEFAULT 'MXN', amount numeric(14,2) NOT NULL,
    exchange_rate numeric(18,6), exchange_rate_date date, amount_mxn numeric(14,2),
    status text NOT NULL DEFAULT 'ready', notes text, created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_payment_complements_amount_check CHECK (amount > 0),
    CONSTRAINT billing_payment_complements_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT billing_payment_complements_method_check CHECK (method IN ('transfer', 'cash', 'card', 'other')),
    CONSTRAINT billing_payment_complements_status_check CHECK (status IN ('draft', 'ready', 'issued', 'cancelled'))
);

ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS exchange_rate_source text NOT NULL DEFAULT 'manual';
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS voided_at timestamptz;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS voided_by uuid;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS void_reason text;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS over_registration_override boolean NOT NULL DEFAULT false;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS over_registration_reason text;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.finance_invoices ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.finance_payments ADD COLUMN IF NOT EXISTS exchange_rate_source text NOT NULL DEFAULT 'manual';
ALTER TABLE public.finance_payments ADD COLUMN IF NOT EXISTS created_by uuid;

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.finance_invoices'::regclass AND conname = 'finance_invoices_f4_currency_check') THEN
        ALTER TABLE public.finance_invoices ADD CONSTRAINT finance_invoices_f4_currency_check CHECK (currency IN ('MXN', 'USD')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.finance_invoices'::regclass AND conname = 'finance_invoices_f4_fx_check') THEN
        ALTER TABLE public.finance_invoices ADD CONSTRAINT finance_invoices_f4_fx_check CHECK (
            (currency = 'MXN' AND exchange_rate = 1 AND amount_mxn = round(amount, 2))
            OR (currency = 'USD' AND (status = 'draft' OR (exchange_rate > 0 AND exchange_rate_date IS NOT NULL AND amount_mxn IS NOT NULL)))
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.finance_invoices'::regclass AND conname = 'finance_invoices_f4_void_check') THEN
        ALTER TABLE public.finance_invoices ADD CONSTRAINT finance_invoices_f4_void_check CHECK (
            status <> 'void' OR (voided_at IS NOT NULL AND voided_by IS NOT NULL AND NULLIF(trim(void_reason), '') IS NOT NULL)
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.finance_invoices'::regclass AND conname = 'finance_invoices_f4_override_check') THEN
        ALTER TABLE public.finance_invoices ADD CONSTRAINT finance_invoices_f4_override_check CHECK (
            NOT over_registration_override OR NULLIF(trim(over_registration_reason), '') IS NOT NULL
        ) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.finance_payments'::regclass AND conname = 'finance_payments_f4_currency_check') THEN
        ALTER TABLE public.finance_payments ADD CONSTRAINT finance_payments_f4_currency_check CHECK (currency IN ('MXN', 'USD')) NOT VALID;
    END IF;
END;
$block$;

CREATE INDEX IF NOT EXISTS finance_invoices_f4_workspace_idx ON public.finance_invoices (tenant_id, direction, status, due_date, created_at DESC);
CREATE INDEX IF NOT EXISTS finance_invoices_f4_operation_idx ON public.finance_invoices (tenant_id, operation_id, direction) WHERE operation_id IS NOT NULL AND status <> 'void';
CREATE INDEX IF NOT EXISTS finance_invoices_f4_customer_idx ON public.finance_invoices (tenant_id, customer_id, created_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS finance_invoices_f4_provider_idx ON public.finance_invoices (tenant_id, provider_id, created_at DESC) WHERE provider_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS finance_invoices_f4_cfdi_idx ON public.finance_invoices (linked_cfdi_id) WHERE linked_cfdi_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS finance_payments_f4_activity_idx ON public.finance_payments (tenant_id, paid_at DESC, invoice_id);
CREATE INDEX IF NOT EXISTS billing_credit_notes_invoice_idx ON public.billing_credit_notes (tenant_id, finance_invoice_id) WHERE finance_invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_documents_operation_idx ON public.billing_documents (tenant_id, operation_id) WHERE operation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_documents_customer_idx ON public.billing_documents (tenant_id, customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_documents_provider_idx ON public.billing_documents (tenant_id, provider_id) WHERE provider_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_documents_cfdi_idx ON public.billing_documents (linked_cfdi_id) WHERE linked_cfdi_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_customer_idx ON public.billing_credit_notes (tenant_id, customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_provider_idx ON public.billing_credit_notes (tenant_id, provider_id) WHERE provider_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_operation_idx ON public.billing_credit_notes (tenant_id, operation_id) WHERE operation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_cfdi_idx ON public.billing_credit_notes (cfdi_id) WHERE cfdi_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_source_document_idx ON public.billing_credit_notes (source_billing_document_id) WHERE source_billing_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_credit_notes_credit_document_idx ON public.billing_credit_notes (credit_billing_document_id) WHERE credit_billing_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_payment_complements_invoice_idx ON public.billing_payment_complements (tenant_id, finance_invoice_id);
CREATE INDEX IF NOT EXISTS billing_payment_complements_cfdi_idx ON public.billing_payment_complements (cfdi_id) WHERE cfdi_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_payment_complements_invoice_document_idx ON public.billing_payment_complements (invoice_billing_document_id) WHERE invoice_billing_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_payment_complements_complement_document_idx ON public.billing_payment_complements (complement_billing_document_id) WHERE complement_billing_document_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS billing_payment_complements_payment_uidx ON public.billing_payment_complements (finance_payment_id) WHERE finance_payment_id IS NOT NULL AND status <> 'cancelled';

CREATE OR REPLACE FUNCTION private.f4_normalize_invoice()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    NEW.currency := upper(COALESCE(NULLIF(trim(NEW.currency), ''), 'MXN'));
    NEW.exchange_rate_source := COALESCE(NULLIF(trim(NEW.exchange_rate_source), ''), 'manual');
    IF TG_OP = 'UPDATE' AND OLD.status <> 'draft' AND (
        NEW.amount IS DISTINCT FROM OLD.amount OR NEW.currency IS DISTINCT FROM OLD.currency
        OR NEW.exchange_rate IS DISTINCT FROM OLD.exchange_rate
        OR NEW.exchange_rate_date IS DISTINCT FROM OLD.exchange_rate_date
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'immutable_finance_terms';
    END IF;
    IF NEW.currency = 'MXN' THEN
        NEW.exchange_rate := 1;
        NEW.exchange_rate_date := COALESCE(NEW.exchange_rate_date, NEW.received_at::date, current_date);
    ELSIF NEW.currency = 'USD' THEN
        IF NEW.status <> 'draft' AND (NEW.exchange_rate IS NULL OR NEW.exchange_rate <= 0 OR NEW.exchange_rate_date IS NULL) THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'exchange_rate_required_for_usd';
        END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_currency';
    END IF;
    NEW.amount_mxn := private.f4_amount_mxn(NEW.amount, NEW.currency, NEW.exchange_rate);
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.f4_normalize_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    NEW.currency := upper(COALESCE(NULLIF(trim(NEW.currency), ''), 'MXN'));
    NEW.method := lower(COALESCE(NULLIF(trim(NEW.method), ''), 'transfer'));
    NEW.exchange_rate_source := COALESCE(NULLIF(trim(NEW.exchange_rate_source), ''), 'manual');
    IF NEW.currency = 'MXN' THEN
        NEW.exchange_rate := 1;
        NEW.exchange_rate_date := COALESCE(NEW.exchange_rate_date, NEW.paid_at::date);
    ELSIF NEW.currency = 'USD' THEN
        IF NEW.exchange_rate IS NULL OR NEW.exchange_rate <= 0 OR NEW.exchange_rate_date IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'exchange_rate_required_for_usd';
        END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid_currency';
    END IF;
    NEW.amount_mxn := private.f4_amount_mxn(NEW.amount, NEW.currency, NEW.exchange_rate);
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS finance_invoices_f4_normalize ON public.finance_invoices;
CREATE TRIGGER finance_invoices_f4_normalize BEFORE INSERT OR UPDATE ON public.finance_invoices
FOR EACH ROW EXECUTE FUNCTION private.f4_normalize_invoice();
DROP TRIGGER IF EXISTS finance_payments_f4_normalize ON public.finance_payments;
CREATE TRIGGER finance_payments_f4_normalize BEFORE INSERT OR UPDATE ON public.finance_payments
FOR EACH ROW EXECUTE FUNCTION private.f4_normalize_payment();

-- Documents 360: Finance files are first-class private files on the account.
ALTER TABLE public.document_files DROP CONSTRAINT IF EXISTS document_files_source_type_check;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_type_check CHECK (
    source_entity_type IN ('operation', 'quote', 'customer', 'provider', 'billing_document', 'generated_document', 'finance_invoice')
) NOT VALID;
ALTER TABLE public.document_files VALIDATE CONSTRAINT document_files_source_type_check;

CREATE OR REPLACE FUNCTION private.f3_entity_belongs_to_tenant(
    p_tenant_id uuid, p_entity_type text, p_entity_id uuid
)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_exists boolean := false;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN RETURN false; END IF;
    CASE p_entity_type
        WHEN 'operation' THEN SELECT EXISTS (SELECT 1 FROM public.operations WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'quote' THEN SELECT EXISTS (SELECT 1 FROM public.crm_deals WHERE id = p_entity_id AND tenant_id = p_tenant_id AND quote_reference IS NOT NULL) INTO v_exists;
        WHEN 'customer' THEN SELECT EXISTS (SELECT 1 FROM public.customers WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'provider' THEN SELECT EXISTS (SELECT 1 FROM public.logistics_providers WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'finance_invoice' THEN SELECT EXISTS (SELECT 1 FROM public.finance_invoices WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'generated_document' THEN SELECT EXISTS (SELECT 1 FROM public.generated_documents WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'billing_document' THEN SELECT EXISTS (SELECT 1 FROM public.billing_documents WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        ELSE v_exists := false;
    END CASE;
    RETURN v_exists;
END;
$function$;

CREATE OR REPLACE FUNCTION private.f3_entity_reference(p_tenant_id uuid, p_entity_type text, p_entity_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_reference text;
BEGIN
    CASE p_entity_type
        WHEN 'operation' THEN SELECT reference_code INTO v_reference FROM public.operations WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'quote' THEN SELECT COALESCE(quote_reference, title) INTO v_reference FROM public.crm_deals WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'customer' THEN SELECT display_name INTO v_reference FROM public.customers WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'provider' THEN SELECT display_name INTO v_reference FROM public.logistics_providers WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'finance_invoice' THEN SELECT COALESCE(reference, counterparty_name, id::text) INTO v_reference FROM public.finance_invoices WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'generated_document' THEN SELECT document_number INTO v_reference FROM public.generated_documents WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'billing_document' THEN SELECT COALESCE(NULLIF(concat_ws('-', serie, folio), ''), fiscal_uuid, id::text) INTO v_reference FROM public.billing_documents WHERE id = p_entity_id AND tenant_id = p_tenant_id;
    END CASE;
    RETURN COALESCE(v_reference, 'Referencia no disponible');
END;
$function$;

REVOKE ALL ON FUNCTION private.f4_user_can_manage_finance(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f4_amount_mxn(numeric, text, numeric) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f4_normalize_invoice() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f4_normalize_payment() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f3_entity_belongs_to_tenant(uuid, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f3_entity_reference(uuid, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.f3_entity_belongs_to_tenant(uuid, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.f4_invoice_totals(p_invoice_id uuid)
RETURNS TABLE(paid_amount numeric, credit_amount numeric, balance_amount numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT
        COALESCE((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id = i.id), 0)::numeric,
        COALESCE((SELECT sum(c.total) FROM public.billing_credit_notes c WHERE c.finance_invoice_id = i.id AND c.status = 'applied'), 0)::numeric,
        GREATEST(i.amount
            - COALESCE((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id = i.id), 0)
            - COALESCE((SELECT sum(c.total) FROM public.billing_credit_notes c WHERE c.finance_invoice_id = i.id AND c.status = 'applied'), 0), 0)::numeric
    FROM public.finance_invoices i
    WHERE i.id = p_invoice_id;
$function$;
REVOKE ALL ON FUNCTION private.f4_invoice_totals(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid, p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_start date; v_end date; v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    BEGIN
        v_start := NULLIF(p_filters->>'date_from', '')::date;
        v_end := NULLIF(p_filters->>'date_to', '')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_filters'); END;

    WITH invoice_totals AS (
        SELECT i.*, t.paid_amount, t.credit_amount, t.balance_amount,
            CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END AS effective_status
        FROM public.finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        WHERE i.tenant_id = p_tenant_id
          AND (v_start IS NULL OR i.created_at::date >= v_start)
          AND (v_end IS NULL OR i.created_at::date <= v_end)
    ), by_currency AS (
        SELECT currency,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ar' AND effective_status IN ('open','overdue')), 0) ar_open,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ap' AND effective_status IN ('open','overdue')), 0) ap_open,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ar' AND effective_status = 'overdue'), 0) ar_overdue,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ap' AND effective_status = 'overdue'), 0) ap_overdue,
            count(*) FILTER (WHERE effective_status IN ('open','overdue')) open_count
        FROM invoice_totals GROUP BY currency
    )
    SELECT jsonb_build_object(
        'currencies', COALESCE(jsonb_agg(to_jsonb(by_currency) ORDER BY currency), '[]'::jsonb),
        'total_ar_open', COALESCE(sum(ar_open) FILTER (WHERE currency = 'MXN'), 0),
        'total_ap_open', COALESCE(sum(ap_open) FILTER (WHERE currency = 'MXN'), 0),
        'total_overdue', COALESCE(sum(ar_overdue) FILTER (WHERE currency = 'MXN'), 0),
        'count_open_invoices', COALESCE(sum(open_count), 0),
        'paid_this_month', COALESCE((SELECT sum(amount) FROM public.finance_payments WHERE tenant_id = p_tenant_id AND currency = 'MXN' AND paid_at >= date_trunc('month', now())), 0),
        'chart', jsonb_build_object('labels', '[]'::jsonb, 'values', '[]'::jsonb)
    ) INTO v_result FROM by_currency;
    RETURN COALESCE(v_result, jsonb_build_object('currencies','[]'::jsonb,'total_ar_open',0,'total_ap_open',0,'total_overdue',0,'paid_this_month',0,'count_open_invoices',0,'chart',jsonb_build_object('labels','[]'::jsonb,'values','[]'::jsonb)));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_finance_overview(p_tenant_id, '{}'::jsonb); $function$;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_limit integer := LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit','')::integer, 100), 1), 200);
    v_status text := NULLIF(p_filters->>'status',''); v_direction text := NULLIF(p_filters->>'direction','');
    v_currency text := NULLIF(upper(p_filters->>'currency'),''); v_search text := NULLIF(lower(trim(p_filters->>'search')),'');
    v_operation uuid; v_customer uuid; v_provider uuid; v_due_from date; v_due_to date; v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN
        v_operation := NULLIF(p_filters->>'operation_id','')::uuid;
        v_customer := NULLIF(p_filters->>'customer_id','')::uuid;
        v_provider := NULLIF(p_filters->>'provider_id','')::uuid;
        v_due_from := NULLIF(p_filters->>'due_from','')::date;
        v_due_to := NULLIF(p_filters->>'due_to','')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters'); END;
    IF v_status IS NOT NULL AND v_status NOT IN ('draft','open','paid','overdue','void') THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
    IF v_direction IS NOT NULL AND v_direction NOT IN ('ar','ap') THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;

    WITH rows AS (
        SELECT i.*, t.paid_amount, t.credit_amount,
            t.balance_amount,
            CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END effective_status,
            o.reference_code operation_reference,
            bd.fiscal_uuid billing_fiscal_uuid,
            COALESCE(NULLIF(concat_ws('-', bd.serie, bd.folio), ''), bd.fiscal_uuid) billing_reference
        FROM public.finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN public.operations o ON o.id = i.operation_id AND o.tenant_id = i.tenant_id
        LEFT JOIN public.billing_documents bd ON bd.id = i.billing_document_id AND bd.tenant_id = i.tenant_id
        WHERE i.tenant_id = p_tenant_id
          AND (v_direction IS NULL OR i.direction = v_direction)
          AND (v_currency IS NULL OR i.currency = v_currency)
          AND (v_operation IS NULL OR i.operation_id = v_operation)
          AND (v_customer IS NULL OR i.customer_id = v_customer)
          AND (v_provider IS NULL OR i.provider_id = v_provider)
          AND (v_due_from IS NULL OR i.due_date >= v_due_from)
          AND (v_due_to IS NULL OR i.due_date <= v_due_to)
          AND (v_status IS NULL OR (CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END) = v_status)
          AND (v_search IS NULL OR lower(concat_ws(' ', i.counterparty_name, i.reference, o.reference_code, bd.fiscal_uuid, bd.serie, bd.folio)) LIKE '%' || v_search || '%')
        ORDER BY i.created_at DESC LIMIT v_limit
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(rows) ORDER BY created_at DESC), '[]'::jsonb) INTO v_items FROM rows;
    RETURN jsonb_build_object('items', v_items, 'count', jsonb_array_length(v_items));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(
    p_tenant_id uuid, p_limit integer DEFAULT 50, p_status text DEFAULT NULL, p_direction text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_list_finance_invoices(p_tenant_id, jsonb_strip_nulls(jsonb_build_object(
        'limit', p_limit, 'status', p_status, 'direction', p_direction
    ))) -> 'items';
$function$;

CREATE OR REPLACE FUNCTION public.rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_id uuid; v_direction text; v_status text; v_currency text; v_amount numeric;
    v_customer_id uuid; v_provider_id uuid; v_operation_id uuid; v_billing_document_id uuid; v_cfdi_id uuid;
    v_customer_name text; v_provider_name text; v_counterparty text; v_operation public.operations%ROWTYPE;
    v_expected numeric; v_registered numeric := 0; v_override boolean := false; v_override_reason text;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN
        v_direction := lower(NULLIF(trim(p_payload->>'direction'),''));
        v_status := lower(COALESCE(NULLIF(trim(p_payload->>'status'),''),'open'));
        v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'currency'),''),'MXN'));
        v_amount := NULLIF(p_payload->>'amount','')::numeric;
        v_customer_id := NULLIF(p_payload->>'customer_id','')::uuid;
        v_provider_id := NULLIF(p_payload->>'provider_id','')::uuid;
        v_operation_id := NULLIF(p_payload->>'operation_id','')::uuid;
        v_billing_document_id := NULLIF(p_payload->>'billing_document_id','')::uuid;
        v_cfdi_id := NULLIF(p_payload->>'linked_cfdi_id','')::uuid;
        v_override := COALESCE(NULLIF(p_payload->>'over_registration_override','')::boolean, false);
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    IF v_direction NOT IN ('ar','ap') OR v_status NOT IN ('draft','open') OR v_currency NOT IN ('MXN','USD') OR v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    IF v_customer_id IS NOT NULL THEN SELECT display_name INTO v_customer_name FROM public.customers WHERE id = v_customer_id AND tenant_id = p_tenant_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_customer'); END IF; END IF;
    IF v_provider_id IS NOT NULL THEN SELECT display_name INTO v_provider_name FROM public.logistics_providers WHERE id = v_provider_id AND tenant_id = p_tenant_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_provider'); END IF; END IF;
    IF v_operation_id IS NOT NULL THEN
        SELECT * INTO v_operation FROM public.operations WHERE id = v_operation_id AND tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_operation'); END IF;
        IF v_operation.pricing_currency <> v_currency THEN RETURN jsonb_build_object('error','operation_currency_mismatch'); END IF;
        IF v_direction = 'ar' THEN
            v_expected := v_operation.customer_price_amount;
            IF v_operation.customer_id IS NOT NULL AND v_customer_id IS NOT NULL AND v_operation.customer_id <> v_customer_id THEN RETURN jsonb_build_object('error','operation_counterparty_mismatch'); END IF;
            v_customer_id := COALESCE(v_customer_id, v_operation.customer_id);
            IF v_customer_id IS NOT NULL THEN SELECT display_name INTO v_customer_name FROM public.customers WHERE id = v_customer_id AND tenant_id = p_tenant_id; END IF;
        ELSE
            v_expected := v_operation.provider_cost_amount;
            IF v_operation.provider_id IS NOT NULL AND v_provider_id IS NOT NULL AND v_operation.provider_id <> v_provider_id THEN RETURN jsonb_build_object('error','operation_counterparty_mismatch'); END IF;
            v_provider_id := COALESCE(v_provider_id, v_operation.provider_id);
            IF v_provider_id IS NOT NULL THEN SELECT display_name INTO v_provider_name FROM public.logistics_providers WHERE id = v_provider_id AND tenant_id = p_tenant_id; END IF;
        END IF;
        SELECT COALESCE(sum(amount),0) INTO v_registered FROM public.finance_invoices
        WHERE tenant_id = p_tenant_id AND operation_id = v_operation_id AND direction = v_direction AND currency = v_currency AND status <> 'void';
        v_override_reason := NULLIF(trim(p_payload->>'over_registration_reason'),'');
        IF v_expected IS NOT NULL AND v_registered + v_amount > v_expected AND (NOT v_override OR v_override_reason IS NULL) THEN
            RETURN jsonb_build_object('error','operation_amount_exceeded','expected_amount',v_expected,'registered_amount',v_registered);
        END IF;
    END IF;
    IF v_billing_document_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.billing_documents WHERE id=v_billing_document_id AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_billing_document'); END IF;
    IF v_cfdi_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.billing_cfdis WHERE id=v_cfdi_id AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_cfdi'); END IF;
    v_counterparty := CASE WHEN v_direction='ar' THEN v_customer_name ELSE v_provider_name END;
    v_counterparty := COALESCE(v_counterparty, NULLIF(trim(p_payload->>'counterparty_name'),''));
    IF v_counterparty IS NULL THEN RETURN jsonb_build_object('error','counterparty_required'); END IF;

    INSERT INTO public.finance_invoices (
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,received_at,notes,
        customer_id,provider_id,operation_id,billing_document_id,linked_cfdi_id,
        exchange_rate,exchange_rate_date,exchange_rate_source,over_registration_override,over_registration_reason,created_by
    ) VALUES (
        p_tenant_id,v_direction,v_counterparty,NULLIF(trim(p_payload->>'reference'),''),v_amount,v_currency,v_status,
        NULLIF(p_payload->>'due_date','')::date,NULLIF(p_payload->>'received_at','')::timestamptz,NULLIF(trim(p_payload->>'notes'),''),
        v_customer_id,v_provider_id,v_operation_id,v_billing_document_id,v_cfdi_id,
        NULLIF(p_payload->>'exchange_rate','')::numeric,NULLIF(p_payload->>'exchange_rate_date','')::date,
        COALESCE(NULLIF(trim(p_payload->>'exchange_rate_source'),''),'manual'),v_override,v_override_reason,(SELECT auth.uid())
    ) RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_created','finance_invoice',v_id,
        jsonb_build_object('direction',v_direction,'amount',v_amount,'currency',v_currency,'operation_id',v_operation_id,'over_registration_override',v_override));
    RETURN jsonb_build_object('id',v_id,'success',true);
EXCEPTION
    WHEN check_violation OR foreign_key_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_record_payment(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_invoice public.finance_invoices%ROWTYPE; v_invoice_id uuid; v_id uuid; v_complement_id uuid;
    v_amount numeric; v_balance numeric; v_currency text; v_paid_at timestamptz;
    v_prepare boolean; v_method text; v_exchange_rate numeric; v_exchange_rate_date date;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN
        v_invoice_id := NULLIF(p_payload->>'invoice_id','')::uuid;
        v_amount := NULLIF(p_payload->>'amount','')::numeric;
        v_paid_at := COALESCE(NULLIF(p_payload->>'paid_at','')::timestamptz, now());
        v_exchange_rate := NULLIF(p_payload->>'exchange_rate','')::numeric;
        v_exchange_rate_date := NULLIF(p_payload->>'exchange_rate_date','')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    SELECT * INTO v_invoice FROM public.finance_invoices WHERE id=v_invoice_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','invoice_not_found'); END IF;
    IF v_invoice.status IN ('draft','void') THEN RETURN jsonb_build_object('error','invoice_not_payable'); END IF;
    IF v_amount IS NULL OR v_amount <= 0 THEN RETURN jsonb_build_object('error','invalid_payment_amount'); END IF;
    SELECT balance_amount INTO v_balance FROM private.f4_invoice_totals(v_invoice.id);
    IF v_balance <= 0 OR v_invoice.status='paid' THEN RETURN jsonb_build_object('error','invoice_already_settled'); END IF;
    IF round(v_amount,2) > round(v_balance,2) THEN RETURN jsonb_build_object('error','payment_exceeds_balance','balance',v_balance); END IF;
    v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'currency'),''),v_invoice.currency));
    IF v_currency <> v_invoice.currency THEN RETURN jsonb_build_object('error','payment_currency_mismatch'); END IF;
    v_method := lower(COALESCE(NULLIF(trim(p_payload->>'method'),''),'transfer'));
    IF v_method NOT IN ('transfer','cash','card','other') THEN RETURN jsonb_build_object('error','invalid_payment_method'); END IF;
    IF v_currency='USD' THEN
        v_exchange_rate := COALESCE(v_exchange_rate,v_invoice.exchange_rate);
        v_exchange_rate_date := COALESCE(v_exchange_rate_date,v_invoice.exchange_rate_date);
        IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 OR v_exchange_rate_date IS NULL THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd'); END IF;
    END IF;
    INSERT INTO public.finance_payments (tenant_id,invoice_id,amount,paid_at,method,note,bank_reference,currency,exchange_rate,exchange_rate_date,exchange_rate_source,created_by)
    VALUES (p_tenant_id,v_invoice.id,round(v_amount,2),v_paid_at,v_method,NULLIF(trim(p_payload->>'note'),''),NULLIF(trim(p_payload->>'bank_reference'),''),
        v_currency,v_exchange_rate,v_exchange_rate_date,COALESCE(NULLIF(trim(p_payload->>'exchange_rate_source'),''),'manual'),(SELECT auth.uid()))
    RETURNING id INTO v_id;
    v_prepare := COALESCE(NULLIF(p_payload->>'prepare_complement','')::boolean,v_invoice.direction='ar');
    IF v_prepare AND v_invoice.direction='ar' THEN
        INSERT INTO public.billing_payment_complements (tenant_id,finance_invoice_id,finance_payment_id,cfdi_id,invoice_billing_document_id,
            payment_date,method,bank_reference,currency,amount,exchange_rate,exchange_rate_date,amount_mxn,status,notes,created_by)
        SELECT p_tenant_id,v_invoice.id,p.id,v_invoice.linked_cfdi_id,v_invoice.billing_document_id,p.paid_at,p.method,p.bank_reference,p.currency,
            p.amount,p.exchange_rate,p.exchange_rate_date,p.amount_mxn,'ready',p.note,(SELECT auth.uid()) FROM public.finance_payments p WHERE p.id=v_id
        RETURNING id INTO v_complement_id;
    END IF;
    v_balance := round(v_balance-v_amount,2);
    IF v_balance <= 0 THEN UPDATE public.finance_invoices SET status='paid',paid_at=v_paid_at WHERE id=v_invoice.id; END IF;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_payment_recorded','finance_payment',v_id,
        jsonb_build_object('invoice_id',v_invoice.id,'amount',v_amount,'currency',v_currency,'remaining_balance',GREATEST(v_balance,0),'complement_id',v_complement_id));
    RETURN jsonb_build_object('id',v_id,'complement_id',v_complement_id,'remaining_balance',GREATEST(v_balance,0),'success',true);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error','payment_already_registered');
    WHEN check_violation OR foreign_key_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_update_finance_invoice_status(p_tenant_id uuid,p_id uuid,p_status text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_invoice public.finance_invoices%ROWTYPE;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT * INTO v_invoice FROM public.finance_invoices WHERE id=p_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF p_status IN ('paid','overdue') THEN RETURN jsonb_build_object('error','payment_driven_status'); END IF;
    IF p_status='void' THEN RETURN jsonb_build_object('error','void_reason_required'); END IF;
    IF NOT (v_invoice.status='draft' AND p_status='open') THEN RETURN jsonb_build_object('error','invalid_status_transition'); END IF;
    UPDATE public.finance_invoices SET status='open' WHERE id=p_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_opened','finance_invoice',p_id,'{}'::jsonb);
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_void_finance_invoice(p_tenant_id uuid,p_id uuid,p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_invoice public.finance_invoices%ROWTYPE; v_paid numeric; v_credit numeric;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF NULLIF(trim(p_reason),'') IS NULL THEN RETURN jsonb_build_object('error','void_reason_required'); END IF;
    SELECT * INTO v_invoice FROM public.finance_invoices WHERE id=p_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT paid_amount,credit_amount INTO v_paid,v_credit FROM private.f4_invoice_totals(p_id);
    IF v_invoice.status IN ('paid','void') OR v_paid > 0 OR v_credit > 0 THEN RETURN jsonb_build_object('error','invoice_cannot_be_voided'); END IF;
    UPDATE public.finance_invoices SET status='void',voided_at=now(),voided_by=(SELECT auth.uid()),void_reason=trim(p_reason) WHERE id=p_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_voided','finance_invoice',p_id,jsonb_build_object('reason',trim(p_reason)));
    RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_finance_invoice_detail(p_tenant_id uuid,p_invoice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_invoice jsonb; v_payments jsonb; v_credits jsonb; v_complements jsonb; v_timeline jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT to_jsonb(x) INTO v_invoice FROM (
        SELECT i.*,t.paid_amount,t.credit_amount,t.balance_amount,
            CASE WHEN i.status='open' AND i.due_date<current_date THEN 'overdue' ELSE i.status END effective_status,
            o.reference_code operation_reference,
            COALESCE(NULLIF(concat_ws('-',bd.serie,bd.folio),''),bd.fiscal_uuid) billing_reference,
            bd.fiscal_uuid billing_fiscal_uuid
        FROM public.finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
        LEFT JOIN public.billing_documents bd ON bd.id=i.billing_document_id AND bd.tenant_id=i.tenant_id
        WHERE i.id=p_invoice_id AND i.tenant_id=p_tenant_id
    ) x;
    IF v_invoice IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.paid_at DESC),'[]'::jsonb) INTO v_payments FROM public.finance_payments p WHERE p.invoice_id=p_invoice_id AND p.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.issue_date DESC,c.created_at DESC),'[]'::jsonb) INTO v_credits FROM public.billing_credit_notes c WHERE c.finance_invoice_id=p_invoice_id AND c.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.payment_date DESC),'[]'::jsonb) INTO v_complements FROM public.billing_payment_complements c WHERE c.finance_invoice_id=p_invoice_id AND c.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.occurred_at DESC),'[]'::jsonb) INTO v_timeline FROM (
        SELECT 'invoice_created'::text event_type,i.created_at occurred_at,jsonb_build_object('status',i.status,'amount',i.amount,'currency',i.currency) details FROM public.finance_invoices i WHERE i.id=p_invoice_id
        UNION ALL SELECT 'payment_recorded',p.paid_at,jsonb_build_object('payment_id',p.id,'amount',p.amount,'method',p.method) FROM public.finance_payments p WHERE p.invoice_id=p_invoice_id
        UNION ALL SELECT 'credit_note_'||c.status,c.created_at,jsonb_build_object('credit_note_id',c.id,'total',c.total,'folio',c.folio) FROM public.billing_credit_notes c WHERE c.finance_invoice_id=p_invoice_id
        UNION ALL SELECT 'complement_'||c.status,c.created_at,jsonb_build_object('complement_id',c.id,'payment_id',c.finance_payment_id) FROM public.billing_payment_complements c WHERE c.finance_invoice_id=p_invoice_id
    ) e;
    RETURN jsonb_build_object('invoice',v_invoice,'payments',v_payments,'credit_notes',v_credits,'payment_complements',v_complements,'timeline',v_timeline);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_payments(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_direction text:=NULLIF(p_filters->>'direction',''); v_method text:=NULLIF(p_filters->>'method',''); v_limit integer:=LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit','')::integer,100),1),200); v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.paid_at DESC),'[]'::jsonb) INTO v_items FROM (
        SELECT p.*,i.direction,i.counterparty_name,i.reference,i.operation_id,i.status invoice_status
        FROM public.finance_payments p JOIN public.finance_invoices i ON i.id=p.invoice_id AND i.tenant_id=p.tenant_id
        WHERE p.tenant_id=p_tenant_id AND (v_direction IS NULL OR i.direction=v_direction) AND (v_method IS NULL OR p.method=v_method)
        ORDER BY p.paid_at DESC LIMIT v_limit
    ) x;
    RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_due_alerts(p_tenant_id uuid,p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_days integer:=LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'days_ahead','')::integer,14),0),90); v_direction text:=NULLIF(p_filters->>'direction',''); v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.due_date,x.direction,x.counterparty_name),'[]'::jsonb) INTO v_items FROM (
        SELECT i.id,i.direction,i.counterparty_name,i.reference,i.amount,i.currency,i.due_date,t.balance_amount,
            CASE WHEN i.due_date<current_date THEN 'overdue' ELSE 'due_soon' END alert_type,
            i.due_date-current_date days_to_due,i.operation_id,o.reference_code operation_reference
        FROM public.finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN public.operations o ON o.id=i.operation_id
        WHERE i.tenant_id=p_tenant_id AND i.status='open' AND t.balance_amount>0 AND i.due_date IS NOT NULL
          AND i.due_date<=current_date+v_days AND (v_direction IS NULL OR i.direction=v_direction)
    ) x;
    RETURN jsonb_build_object('items',v_items,'days_ahead',v_days);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_due_alerts(p_tenant_id uuid,p_days_ahead integer DEFAULT 7)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_list_finance_due_alerts(p_tenant_id,jsonb_build_object('days_ahead',p_days_ahead))->'items'; $function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_finance_summary(p_tenant_id uuid,p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT jsonb_build_object(
        'operation_id',o.id,'operation_reference',o.reference_code,'currency',o.pricing_currency,
        'expected_revenue',COALESCE(o.customer_price_amount,0),'expected_cost',COALESCE(o.provider_cost_amount,0),
        'expected_margin',COALESCE(o.customer_price_amount,0)-COALESCE(o.provider_cost_amount,0),
        'registered_ar',COALESCE(sum(i.amount) FILTER(WHERE i.direction='ar' AND i.status<>'void'),0),
        'registered_ap',COALESCE(sum(i.amount) FILTER(WHERE i.direction='ap' AND i.status<>'void'),0),
        'remaining_ar_to_register',GREATEST(COALESCE(o.customer_price_amount,0)-COALESCE(sum(i.amount) FILTER(WHERE i.direction='ar' AND i.status<>'void'),0),0),
        'remaining_ap_to_register',GREATEST(COALESCE(o.provider_cost_amount,0)-COALESCE(sum(i.amount) FILTER(WHERE i.direction='ap' AND i.status<>'void'),0),0)
    ) INTO v_result FROM public.operations o LEFT JOIN public.finance_invoices i ON i.operation_id=o.id AND i.tenant_id=o.tenant_id
    WHERE o.id=p_operation_id AND o.tenant_id=p_tenant_id GROUP BY o.id;
    RETURN COALESCE(v_result,jsonb_build_object('error','not_found'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_finance_profitability(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb; v_customers jsonb; v_providers jsonb; v_currency text:=NULLIF(upper(p_filters->>'currency'),'');
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    WITH per_operation AS (
        SELECT o.id operation_id,o.reference_code,o.customer_id,o.provider_id,o.pricing_currency currency,
            COALESCE(o.customer_price_amount,0) expected_revenue,COALESCE(o.provider_cost_amount,0) expected_cost,
            COALESCE(i.registered_ar,0) registered_ar,COALESCE(i.registered_ap,0) registered_ap,
            COALESCE(c.cash_in,0) cash_in,COALESCE(c.cash_out,0) cash_out,
            COALESCE(n.credit_ar,0) credit_ar,COALESCE(n.credit_ap,0) credit_ap
        FROM public.operations o
        LEFT JOIN LATERAL (
            SELECT sum(amount) FILTER(WHERE direction='ar' AND status<>'void') registered_ar,
                   sum(amount) FILTER(WHERE direction='ap' AND status<>'void') registered_ap
            FROM public.finance_invoices WHERE operation_id=o.id AND tenant_id=o.tenant_id
        ) i ON true
        LEFT JOIN LATERAL (
            SELECT sum(fp.amount) FILTER(WHERE fi.direction='ar') cash_in,
                   sum(fp.amount) FILTER(WHERE fi.direction='ap') cash_out
            FROM public.finance_payments fp JOIN public.finance_invoices fi ON fi.id=fp.invoice_id AND fi.tenant_id=fp.tenant_id
            WHERE fi.operation_id=o.id AND fi.tenant_id=o.tenant_id
        ) c ON true
        LEFT JOIN LATERAL (
            SELECT sum(cn.total) FILTER(WHERE fi.direction='ar') credit_ar,
                   sum(cn.total) FILTER(WHERE fi.direction='ap') credit_ap
            FROM public.billing_credit_notes cn JOIN public.finance_invoices fi ON fi.id=cn.finance_invoice_id AND fi.tenant_id=cn.tenant_id
            WHERE fi.operation_id=o.id AND fi.tenant_id=o.tenant_id AND cn.status='applied'
        ) n ON true
        WHERE o.tenant_id=p_tenant_id AND (v_currency IS NULL OR o.pricing_currency=v_currency)
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.reference_code),'[]'::jsonb) INTO v_items FROM (
        SELECT *,expected_revenue-expected_cost expected_margin,registered_ar-registered_ap registered_margin,
            cash_in-cash_out cash_margin,GREATEST(registered_ar-cash_in-credit_ar,0) outstanding_ar,GREATEST(registered_ap-cash_out-credit_ap,0) outstanding_ap
        FROM per_operation
    ) x;
    WITH totals AS (
        SELECT c.id,c.display_name,o.currency,o.operations,o.expected_revenue,COALESCE(i.registered_ar,0) registered_ar
        FROM public.customers c
        JOIN LATERAL (
            SELECT pricing_currency currency,count(*) operations,COALESCE(sum(customer_price_amount),0) expected_revenue
            FROM public.operations WHERE tenant_id=c.tenant_id AND customer_id=c.id
              AND (v_currency IS NULL OR pricing_currency=v_currency) GROUP BY pricing_currency
        ) o ON true
        LEFT JOIN LATERAL (
            SELECT COALESCE(sum(fi.amount),0) registered_ar FROM public.finance_invoices fi
            WHERE fi.tenant_id=c.tenant_id AND fi.customer_id=c.id AND fi.direction='ar' AND fi.status<>'void' AND fi.currency=o.currency
        ) i ON true
        WHERE c.tenant_id=p_tenant_id
    ) SELECT COALESCE(jsonb_agg(to_jsonb(totals) ORDER BY display_name,currency),'[]'::jsonb) INTO v_customers FROM totals;
    WITH totals AS (
        SELECT p.id,p.display_name,o.currency,o.operations,o.expected_cost,COALESCE(i.registered_ap,0) registered_ap
        FROM public.logistics_providers p
        JOIN LATERAL (
            SELECT pricing_currency currency,count(*) operations,COALESCE(sum(provider_cost_amount),0) expected_cost
            FROM public.operations WHERE tenant_id=p.tenant_id AND provider_id=p.id
              AND (v_currency IS NULL OR pricing_currency=v_currency) GROUP BY pricing_currency
        ) o ON true
        LEFT JOIN LATERAL (
            SELECT COALESCE(sum(fi.amount),0) registered_ap FROM public.finance_invoices fi
            WHERE fi.tenant_id=p.tenant_id AND fi.provider_id=p.id AND fi.direction='ap' AND fi.status<>'void' AND fi.currency=o.currency
        ) i ON true
        WHERE p.tenant_id=p_tenant_id
    ) SELECT COALESCE(jsonb_agg(to_jsonb(totals) ORDER BY display_name,currency),'[]'::jsonb) INTO v_providers FROM totals;
    RETURN jsonb_build_object('operations',v_items,'customers',v_customers,'providers',v_providers,'currency_policy','separate');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_export_finance_ledger(p_tenant_id uuid,p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'reference',i.reference,'direction',i.direction,'counterparty',i.counterparty_name,'operation_reference',o.reference_code,
        'currency',i.currency,'amount',i.amount,'paid_amount',t.paid_amount,'credit_amount',t.credit_amount,'balance',t.balance_amount,
        'status',CASE WHEN i.status='open' AND i.due_date<current_date THEN 'overdue' ELSE i.status END,'due_date',i.due_date,'created_at',i.created_at
    ) ORDER BY i.created_at DESC),'[]'::jsonb) INTO v_result
    FROM public.finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t LEFT JOIN public.operations o ON o.id=i.operation_id
    WHERE i.tenant_id=p_tenant_id
      AND (NULLIF(p_filters->>'direction','') IS NULL OR i.direction=p_filters->>'direction')
      AND (NULLIF(p_filters->>'currency','') IS NULL OR i.currency=upper(p_filters->>'currency'))
      AND (NULLIF(p_filters->>'date_from','') IS NULL OR i.created_at::date >= (p_filters->>'date_from')::date)
      AND (NULLIF(p_filters->>'date_to','') IS NULL OR i.created_at::date <= (p_filters->>'date_to')::date);
    RETURN v_result;
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

DROP FUNCTION IF EXISTS public.rpc_export_finance_ledger(uuid,text,text);
CREATE FUNCTION public.rpc_export_finance_ledger(p_tenant_id uuid,p_date_from text,p_date_to text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_export_finance_ledger(p_tenant_id,jsonb_strip_nulls(jsonb_build_object('date_from',p_date_from,'date_to',p_date_to))); $function$;

CREATE OR REPLACE FUNCTION public.rpc_create_payment_complement(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_payment public.finance_payments%ROWTYPE; v_invoice public.finance_invoices%ROWTYPE; v_id uuid; v_payment_id uuid;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN v_payment_id:=NULLIF(p_payload->>'finance_payment_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    SELECT * INTO v_payment FROM public.finance_payments WHERE id=v_payment_id AND tenant_id=p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','payment_not_found'); END IF;
    SELECT * INTO v_invoice FROM public.finance_invoices WHERE id=v_payment.invoice_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF v_invoice.direction<>'ar' THEN RETURN jsonb_build_object('error','complement_only_for_ar'); END IF;
    IF EXISTS(SELECT 1 FROM public.billing_payment_complements WHERE finance_payment_id=v_payment.id AND status<>'cancelled') THEN RETURN jsonb_build_object('error','complement_already_exists'); END IF;
    INSERT INTO public.billing_payment_complements(tenant_id,finance_invoice_id,finance_payment_id,cfdi_id,invoice_billing_document_id,payment_date,method,
        bank_reference,currency,amount,exchange_rate,exchange_rate_date,amount_mxn,status,notes,created_by)
    VALUES(p_tenant_id,v_invoice.id,v_payment.id,v_invoice.linked_cfdi_id,v_invoice.billing_document_id,v_payment.paid_at,v_payment.method,
        v_payment.bank_reference,v_payment.currency,v_payment.amount,v_payment.exchange_rate,v_payment.exchange_rate_date,v_payment.amount_mxn,'ready',v_payment.note,(SELECT auth.uid()))
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'payment_complement_prepared','payment_complement',v_id,jsonb_build_object('payment_id',v_payment.id));
    RETURN jsonb_build_object('id',v_id,'status','ready','handoff','billing','success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_payment_complements(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.payment_date DESC),'[]'::jsonb) INTO v_items FROM (
        SELECT c.*,i.counterparty_name,i.reference,i.operation_id FROM public.billing_payment_complements c
        JOIN public.finance_invoices i ON i.id=c.finance_invoice_id AND i.tenant_id=c.tenant_id
        WHERE c.tenant_id=p_tenant_id AND (NULLIF(p_filters->>'status','') IS NULL OR c.status=p_filters->>'status')
    ) x;
    RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items),'handoff','billing');
END;
$function$;

-- Preserve the richer historical overloads while routing them through F4.
DROP FUNCTION IF EXISTS public.rpc_finance_overview(uuid,text,text);
CREATE FUNCTION public.rpc_finance_overview(p_tenant_id uuid,p_start_date text,p_end_date text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_finance_overview(p_tenant_id,jsonb_strip_nulls(jsonb_build_object('date_from',p_start_date,'date_to',p_end_date))); $function$;

DROP FUNCTION IF EXISTS public.rpc_list_finance_invoices(uuid,integer,text,text,text,text);
CREATE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid,p_limit integer,p_status text,p_direction text,p_start_date text,p_end_date text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_list_finance_invoices(p_tenant_id,jsonb_strip_nulls(jsonb_build_object('limit',p_limit,'status',p_status,'direction',p_direction,'date_from',p_start_date,'date_to',p_end_date)))->'items'; $function$;

ALTER TABLE public.finance_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_credit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_payment_complements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.finance_invoices,public.finance_payments,public.billing_documents,public.billing_credit_notes,public.billing_payment_complements FROM PUBLIC,anon,authenticated,service_role;

DROP POLICY IF EXISTS finance_invoices_select_f4 ON public.finance_invoices;
DROP POLICY IF EXISTS finance_invoices_manage_f4 ON public.finance_invoices;
DROP POLICY IF EXISTS finance_payments_select_f4 ON public.finance_payments;
DROP POLICY IF EXISTS finance_payments_manage_f4 ON public.finance_payments;
DROP POLICY IF EXISTS billing_credit_notes_f4 ON public.billing_credit_notes;
DROP POLICY IF EXISTS billing_payment_complements_f4 ON public.billing_payment_complements;
CREATE POLICY finance_invoices_select_f4 ON public.finance_invoices FOR SELECT TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id)));
CREATE POLICY finance_invoices_manage_f4 ON public.finance_invoices FOR ALL TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id))) WITH CHECK ((SELECT private.f4_user_can_manage_finance(tenant_id)));
CREATE POLICY finance_payments_select_f4 ON public.finance_payments FOR SELECT TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id)));
CREATE POLICY finance_payments_manage_f4 ON public.finance_payments FOR ALL TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id))) WITH CHECK ((SELECT private.f4_user_can_manage_finance(tenant_id)));
CREATE POLICY billing_credit_notes_f4 ON public.billing_credit_notes FOR ALL TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id))) WITH CHECK ((SELECT private.f4_user_can_manage_finance(tenant_id)));
CREATE POLICY billing_payment_complements_f4 ON public.billing_payment_complements FOR ALL TO authenticated USING ((SELECT private.f4_user_can_manage_finance(tenant_id))) WITH CHECK ((SELECT private.f4_user_can_manage_finance(tenant_id)));

REVOKE EXECUTE ON FUNCTION public.rpc_finance_overview(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_finance_overview(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_finance_overview(uuid,text,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_invoices(uuid,integer,text,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_invoices(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_invoices(uuid,integer,text,text,text,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_create_finance_invoice(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_record_payment(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_update_finance_invoice_status(uuid,uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_void_finance_invoice(uuid,uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_finance_invoice_detail(uuid,uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_payments(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_due_alerts(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_finance_due_alerts(uuid,integer) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_finance_summary(uuid,uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_finance_profitability(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_export_finance_ledger(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_export_finance_ledger(uuid,text,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_create_payment_complement(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_payment_complements(uuid,jsonb) FROM PUBLIC,anon,service_role;

GRANT EXECUTE ON FUNCTION public.rpc_finance_overview(uuid),public.rpc_finance_overview(uuid,jsonb),public.rpc_finance_overview(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_finance_invoices(uuid,integer,text,text),public.rpc_list_finance_invoices(uuid,jsonb),public.rpc_list_finance_invoices(uuid,integer,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_finance_invoice(uuid,jsonb),public.rpc_record_payment(uuid,jsonb),public.rpc_update_finance_invoice_status(uuid,uuid,text),public.rpc_void_finance_invoice(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_finance_invoice_detail(uuid,uuid),public.rpc_list_finance_payments(uuid,jsonb),public.rpc_list_finance_due_alerts(uuid,jsonb),public.rpc_list_finance_due_alerts(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_finance_summary(uuid,uuid),public.rpc_finance_profitability(uuid,jsonb),public.rpc_export_finance_ledger(uuid,jsonb),public.rpc_export_finance_ledger(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_payment_complement(uuid,jsonb),public.rpc_list_payment_complements(uuid,jsonb) TO authenticated;
