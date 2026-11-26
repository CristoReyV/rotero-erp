-- Keep invoice list and view CSV on the same scoped query.

CREATE OR REPLACE FUNCTION private.delivery_scoped_908fd958c5cc1a223706(p_tenant_id uuid, p_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
        FROM private.delivery_finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        -- Look up optional references by key after the invoice's scope check.
        LEFT JOIN LATERAL (
            SELECT candidate.reference_code
            FROM private.delivery_operations candidate
            WHERE candidate.id = i.operation_id AND candidate.tenant_id = i.tenant_id
            LIMIT 1
        ) o ON true
        LEFT JOIN LATERAL (
            SELECT candidate.fiscal_uuid, candidate.serie, candidate.folio
            FROM private.delivery_billing_documents candidate
            WHERE candidate.id = i.billing_document_id AND candidate.tenant_id = i.tenant_id
            LIMIT 1
        ) bd ON true
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
