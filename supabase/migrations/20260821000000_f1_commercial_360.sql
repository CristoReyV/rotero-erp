-- F1 Commercial 360: tenant-scoped customer/provider directories, quote
-- lifecycle and the canonical quote -> operation handoff.
--
-- Reuses the baseline customers, logistics_providers, crm_deals and operations
-- tables. No new table, enum, public tracking or Auth contract is introduced.

-- Fresh canonical databases built from the versioned baseline still carried the
-- pre-reconciliation `review` value. Staging already has `in_review`, so this is
-- a no-op there and only corrects the exact stale constraint when it has no data.
DO $quote_status_reconciliation$
DECLARE
    v_definition text;
    v_legacy_rows bigint;
BEGIN
    SELECT pg_get_constraintdef(c.oid, true)
    INTO v_definition
    FROM pg_catalog.pg_constraint AS c
    WHERE c.conrelid = 'public.crm_deals'::regclass
      AND c.conname = 'crm_deals_quote_status_check';

    IF v_definition IS NULL THEN
        RAISE EXCEPTION 'F1 PRECHECK FAILED: quote status constraint missing';
    END IF;

    IF v_definition LIKE '%''review''%' AND v_definition NOT LIKE '%''in_review''%' THEN
        SELECT count(*) INTO v_legacy_rows
        FROM public.crm_deals AS d
        WHERE d.quote_status = 'review';

        IF v_legacy_rows <> 0 THEN
            RAISE EXCEPTION 'F1 PRECHECK FAILED: legacy quote status rows require separate reconciliation';
        END IF;

        ALTER TABLE public.crm_deals DROP CONSTRAINT crm_deals_quote_status_check;
        ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_quote_status_check
            CHECK (quote_status IN ('draft', 'in_review', 'approved', 'rejected', 'converted'));
    ELSIF v_definition NOT LIKE '%''in_review''%' OR v_definition LIKE '%''review''%' THEN
        RAISE EXCEPTION 'F1 PRECHECK FAILED: unexpected quote status constraint';
    END IF;
END;
$quote_status_reconciliation$;

-- These definitions were captured from staging through read-only catalog calls.
-- Versioning them here makes a fresh reset staging-like instead of inventing a
-- parallel lifecycle. The converter below is the only canonical body extended.
CREATE OR REPLACE FUNCTION public.crm_place_is_complete(p_place jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog, public
AS $function$
    SELECT
        p_place IS NOT NULL
        AND jsonb_typeof(p_place) = 'object'
        AND NULLIF(trim(COALESCE(p_place->>'municipality', '')), '') IS NOT NULL
        AND NULLIF(trim(COALESCE(p_place->>'state', '')), '') IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.crm_quote_ready_for_review(p_payload jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog, public
AS $function$
    SELECT
        jsonb_typeof(COALESCE(p_payload, '{}'::jsonb)) = 'object'
        AND NULLIF(trim(COALESCE(p_payload->>'service_type', '')), '') IS NOT NULL
        AND public.crm_place_is_complete(p_payload->'origin_place')
        AND public.crm_place_is_complete(p_payload->'destination_place');
$function$;

CREATE OR REPLACE FUNCTION public.crm_quote_ready_for_approval(p_payload jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog, public
AS $function$
    SELECT
        public.crm_quote_ready_for_review(p_payload)
        AND NULLIF(COALESCE(p_payload->>'operational_window_start', ''), '') IS NOT NULL
        AND NULLIF(COALESCE(p_payload->>'operational_window_end', ''), '') IS NOT NULL
        AND (p_payload->>'operational_window_end')::timestamptz >= (p_payload->>'operational_window_start')::timestamptz
        AND COALESCE(p_payload->'cargo_summary', '{}'::jsonb) <> '{}'::jsonb;
$function$;

CREATE OR REPLACE FUNCTION public.crm_generate_operation_reference(p_tenant_id uuid)
RETURNS text
LANGUAGE plpgsql
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_reference text;
    v_attempts integer := 0;
BEGIN
    LOOP
        v_attempts := v_attempts + 1;
        v_reference := 'OP-' || to_char(now(), 'YYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

        EXIT WHEN NOT EXISTS (
            SELECT 1
            FROM public.operations AS o
            WHERE o.tenant_id = p_tenant_id
              AND lower(o.reference_code) = lower(v_reference)
        );

        IF v_attempts > 20 THEN
            RAISE EXCEPTION 'reference_code_generation_failed';
        END IF;
    END LOOP;

    RETURN v_reference;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tanda1_service_snapshot(
    p_service_type text,
    p_service_class text DEFAULT NULL,
    p_presentation text DEFAULT NULL,
    p_packaging text DEFAULT NULL,
    p_modality text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog, public
AS $function$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'service_type', NULLIF(trim(COALESCE(p_service_type, '')), ''),
        'service_class', NULLIF(trim(COALESCE(p_service_class, '')), ''),
        'presentation', NULLIF(trim(COALESCE(p_presentation, '')), ''),
        'packaging', NULLIF(trim(COALESCE(p_packaging, '')), ''),
        'modality', NULLIF(trim(COALESCE(p_modality, '')), '')
    ));
$function$;

CREATE OR REPLACE FUNCTION public.rpc_seed_checklist_for_deal(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
    v_stage text;
BEGIN
    SELECT tenant_id, stage INTO v_tenant_id, v_stage FROM crm_deals WHERE id = p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    IF EXISTS (SELECT 1 FROM crm_deal_checklist_items WHERE deal_id = p_deal_id AND stage = v_stage) THEN
        RETURN jsonb_build_object('success', true, 'msg', 'already_exists');
    END IF;

    IF v_stage = 'lead' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'lead', 'Identificar necesidades clave'),
        (v_tenant_id, p_deal_id, 'lead', 'Verificar viabilidad técnica/operativa');
    ELSIF v_stage = 'qualified' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'qualified', 'Enviar cotización formal'),
        (v_tenant_id, p_deal_id, 'qualified', 'Revisar términos comerciales con cliente');
    ELSIF v_stage = 'proposal' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'proposal', 'Realizar presentación ejecutiva'),
        (v_tenant_id, p_deal_id, 'proposal', 'Negociación final de precio y volumen');
    ELSIF v_stage = 'won' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'won', 'Recabar firma de contrato / orden de compra'),
        (v_tenant_id, p_deal_id, 'won', 'Alta de cuenta en sistema ERP');
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_write_audit(
    p_tenant_id uuid,
    p_action text,
    p_entity_type text,
    p_entity_id uuid,
    p_metadata jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (p_tenant_id, auth.uid(), p_action, p_entity_type, p_entity_id, p_metadata);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_submit_quote_for_review(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id;
    IF v_deal.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_deal.tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;

    IF v_deal.quote_status NOT IN ('draft', 'in_review') THEN
        RETURN jsonb_build_object('error', 'invalid_quote_status');
    END IF;
    IF NULLIF(trim(COALESCE(v_deal.title, '')), '') IS NULL
       OR NULLIF(trim(COALESCE(v_deal.company, '')), '') IS NULL
       OR v_deal.value IS NULL
       OR NULLIF(trim(COALESCE(v_deal.currency, '')), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_commercial_data');
    END IF;
    IF NOT public.crm_quote_ready_for_review(v_deal.quote_payload) THEN
        RETURN jsonb_build_object('error', 'quote_payload_not_ready_for_review');
    END IF;

    UPDATE public.crm_deals
    SET quote_status = 'in_review',
        stage = CASE WHEN stage = 'lead' THEN 'qualified' ELSE stage END,
        last_touch_at = now(), updated_at = now()
    WHERE id = p_deal_id;

    PERFORM public.rpc_write_audit(v_deal.tenant_id, 'submit_quote_for_review', 'deal', p_deal_id,
        jsonb_build_object('quote_reference', v_deal.quote_reference));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_approve_quote(p_deal_id uuid, p_approval_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id;
    IF v_deal.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_deal.tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;

    IF v_deal.quote_status <> 'in_review' THEN
        RETURN jsonb_build_object('error', 'invalid_quote_status');
    END IF;
    IF NULLIF(trim(COALESCE(v_deal.title, '')), '') IS NULL
       OR NULLIF(trim(COALESCE(v_deal.company, '')), '') IS NULL
       OR v_deal.value IS NULL
       OR NULLIF(trim(COALESCE(v_deal.currency, '')), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_commercial_data');
    END IF;
    IF NOT public.crm_quote_ready_for_approval(v_deal.quote_payload) THEN
        RETURN jsonb_build_object('error', 'quote_payload_not_ready_for_approval');
    END IF;

    UPDATE public.crm_deals
    SET quote_status = 'approved', stage = 'proposal', approved_at = now(), approved_by = auth.uid(),
        approval_note = NULLIF(trim(COALESCE(p_approval_note, '')), ''), rejected_at = NULL,
        rejected_by = NULL, rejection_note = NULL, last_touch_at = now(), updated_at = now()
    WHERE id = p_deal_id;

    PERFORM public.rpc_write_audit(v_deal.tenant_id, 'approve_quote', 'deal', p_deal_id,
        jsonb_build_object('quote_reference', v_deal.quote_reference));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_reject_quote(p_deal_id uuid, p_rejection_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id;
    IF v_deal.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_deal.tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;

    IF v_deal.quote_status NOT IN ('draft', 'in_review') THEN
        RETURN jsonb_build_object('error', 'invalid_quote_status');
    END IF;

    UPDATE public.crm_deals
    SET quote_status = 'rejected', stage = 'lost', rejected_at = now(), rejected_by = auth.uid(),
        rejection_note = NULLIF(trim(COALESCE(p_rejection_note, '')), ''), approved_at = NULL,
        approved_by = NULL, approval_note = NULL, last_touch_at = now(), updated_at = now()
    WHERE id = p_deal_id;

    PERFORM public.rpc_write_audit(v_deal.tenant_id, 'reject_quote', 'deal', p_deal_id,
        jsonb_build_object('quote_reference', v_deal.quote_reference));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_customers(
    p_tenant_id uuid,
    p_filters jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            to_jsonb(c) || jsonb_build_object(
                'deal_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = c.id),
                'quote_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = c.id AND d.quote_reference IS NOT NULL),
                'operation_count', (SELECT count(*) FROM public.operations o WHERE o.customer_id = c.id),
                'quoted_totals', COALESCE((
                    SELECT jsonb_object_agg(x.currency, x.total)
                    FROM (SELECT d.currency, sum(d.value) AS total FROM public.crm_deals d WHERE d.customer_id = c.id AND d.quote_reference IS NOT NULL GROUP BY d.currency) x
                ), '{}'::jsonb),
                'operation_sell_totals', COALESCE((
                    SELECT jsonb_object_agg(x.currency, x.total)
                    FROM (SELECT o.pricing_currency AS currency, sum(o.customer_price_amount) AS total FROM public.operations o WHERE o.customer_id = c.id GROUP BY o.pricing_currency) x
                ), '{}'::jsonb)
            )
            ORDER BY c.display_name
        )
        FROM public.customers AS c
        WHERE c.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'active') OR c.is_active = (p_filters ->> 'active')::boolean)
          AND (
              NOT (p_filters ? 'searchText')
              OR c.display_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR c.legal_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR c.tax_id ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR c.contact_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR c.contact_email ILIKE '%' || (p_filters ->> 'searchText') || '%'
          )
    ), '[]'::jsonb);
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_360(p_customer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_customer public.customers%ROWTYPE;
BEGIN
    SELECT c.* INTO v_customer FROM public.customers AS c WHERE c.id = p_customer_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_customer.tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN jsonb_build_object(
        'customer', to_jsonb(v_customer) || jsonb_build_object(
            'deal_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = p_customer_id),
            'quote_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = p_customer_id AND d.quote_reference IS NOT NULL),
            'operation_count', (SELECT count(*) FROM public.operations o WHERE o.customer_id = p_customer_id),
            'quoted_totals', COALESCE((
                SELECT jsonb_object_agg(x.currency, x.total)
                FROM (SELECT d.currency, sum(d.value) AS total FROM public.crm_deals d WHERE d.customer_id = p_customer_id AND d.quote_reference IS NOT NULL GROUP BY d.currency) x
            ), '{}'::jsonb),
            'operation_sell_totals', COALESCE((
                SELECT jsonb_object_agg(x.currency, x.total)
                FROM (SELECT o.pricing_currency AS currency, sum(o.customer_price_amount) AS total FROM public.operations o WHERE o.customer_id = p_customer_id GROUP BY o.pricing_currency) x
            ), '{}'::jsonb)
        ),
        'summary', jsonb_build_object(
            'deal_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = p_customer_id),
            'quote_count', (SELECT count(*) FROM public.crm_deals d WHERE d.customer_id = p_customer_id AND d.quote_reference IS NOT NULL),
            'operation_count', (SELECT count(*) FROM public.operations o WHERE o.customer_id = p_customer_id),
            'quoted_totals', COALESCE((
                SELECT jsonb_object_agg(x.currency, x.total)
                FROM (SELECT d.currency, sum(d.value) AS total FROM public.crm_deals d WHERE d.customer_id = p_customer_id AND d.quote_reference IS NOT NULL GROUP BY d.currency) x
            ), '{}'::jsonb),
            'operation_sell_totals', COALESCE((
                SELECT jsonb_object_agg(x.currency, x.total)
                FROM (SELECT o.pricing_currency AS currency, sum(o.customer_price_amount) AS total FROM public.operations o WHERE o.customer_id = p_customer_id GROUP BY o.pricing_currency) x
            ), '{}'::jsonb)
        ),
        'deals', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.updated_at DESC) FROM public.crm_deals d WHERE d.customer_id = p_customer_id), '[]'::jsonb),
        'quotes', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.updated_at DESC) FROM public.crm_deals d WHERE d.customer_id = p_customer_id AND d.quote_reference IS NOT NULL), '[]'::jsonb),
        'operations', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM public.operations o WHERE o.customer_id = p_customer_id), '[]'::jsonb)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_customer(
    p_tenant_id uuid,
    p_customer_id uuid,
    p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_id uuid;
    v_currency text := COALESCE(NULLIF(p_payload ->> 'preferred_currency', ''), 'MXN');
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NULLIF(btrim(p_payload ->> 'display_name'), '') IS NULL OR v_currency NOT IN ('MXN', 'USD') THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;

    IF p_customer_id IS NULL THEN
        INSERT INTO public.customers (
            tenant_id, display_name, legal_name, contact_name, contact_email,
            contact_phone, tax_id, billing_email, notes, is_active, preferred_currency
        ) VALUES (
            p_tenant_id, btrim(p_payload ->> 'display_name'), NULLIF(btrim(p_payload ->> 'legal_name'), ''),
            NULLIF(btrim(p_payload ->> 'contact_name'), ''), NULLIF(btrim(p_payload ->> 'contact_email'), ''),
            NULLIF(btrim(p_payload ->> 'contact_phone'), ''), NULLIF(upper(btrim(p_payload ->> 'tax_id')), ''),
            NULLIF(btrim(p_payload ->> 'billing_email'), ''), NULLIF(btrim(p_payload ->> 'notes'), ''),
            COALESCE((p_payload ->> 'is_active')::boolean, true), v_currency
        ) RETURNING id INTO v_id;
    ELSE
        UPDATE public.customers AS c
        SET display_name = btrim(p_payload ->> 'display_name'),
            legal_name = NULLIF(btrim(p_payload ->> 'legal_name'), ''),
            contact_name = NULLIF(btrim(p_payload ->> 'contact_name'), ''),
            contact_email = NULLIF(btrim(p_payload ->> 'contact_email'), ''),
            contact_phone = NULLIF(btrim(p_payload ->> 'contact_phone'), ''),
            tax_id = NULLIF(upper(btrim(p_payload ->> 'tax_id')), ''),
            billing_email = NULLIF(btrim(p_payload ->> 'billing_email'), ''),
            notes = NULLIF(btrim(p_payload ->> 'notes'), ''),
            is_active = COALESCE((p_payload ->> 'is_active')::boolean, c.is_active),
            preferred_currency = v_currency
        WHERE c.id = p_customer_id AND c.tenant_id = p_tenant_id
        RETURNING c.id INTO v_id;
        IF v_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    END IF;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id)
    VALUES (p_tenant_id, auth.uid(), CASE WHEN p_customer_id IS NULL THEN 'customer_created' ELSE 'customer_updated' END, 'customer', v_id);
    RETURN jsonb_build_object('id', v_id);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'duplicate_name');
    WHEN invalid_text_representation OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_providers(
    p_tenant_id uuid,
    p_filters jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            to_jsonb(p) || jsonb_build_object(
                'quote_count', (SELECT count(*) FROM public.crm_deals d WHERE d.quote_payload ->> 'provider_id' = p.id::text),
                'operation_count', (SELECT count(*) FROM public.operations o WHERE o.provider_id = p.id),
                'contracted_cost_totals', COALESCE((
                    SELECT jsonb_object_agg(x.currency, x.total)
                    FROM (SELECT o.pricing_currency AS currency, sum(o.provider_cost_amount) AS total FROM public.operations o WHERE o.provider_id = p.id GROUP BY o.pricing_currency) x
                ), '{}'::jsonb)
            )
            ORDER BY p.display_name
        )
        FROM public.logistics_providers AS p
        WHERE p.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'active') OR p.is_active = (p_filters ->> 'active')::boolean)
          AND (
              NOT (p_filters ? 'searchText')
              OR p.display_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR p.legal_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR p.tax_id ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR p.contact_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR p.contact_email ILIKE '%' || (p_filters ->> 'searchText') || '%'
          )
    ), '[]'::jsonb);
EXCEPTION
    WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_provider(
    p_tenant_id uuid,
    p_provider_id uuid,
    p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NULLIF(btrim(p_payload ->> 'display_name'), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;

    IF p_provider_id IS NULL THEN
        INSERT INTO public.logistics_providers (
            tenant_id, display_name, legal_name, tax_id, contact_name,
            contact_email, contact_phone, billing_email, notes, is_active
        ) VALUES (
            p_tenant_id, btrim(p_payload ->> 'display_name'), NULLIF(btrim(p_payload ->> 'legal_name'), ''),
            NULLIF(upper(btrim(p_payload ->> 'tax_id')), ''), NULLIF(btrim(p_payload ->> 'contact_name'), ''),
            NULLIF(btrim(p_payload ->> 'contact_email'), ''), NULLIF(btrim(p_payload ->> 'contact_phone'), ''),
            NULLIF(btrim(p_payload ->> 'billing_email'), ''), NULLIF(btrim(p_payload ->> 'notes'), ''),
            COALESCE((p_payload ->> 'is_active')::boolean, true)
        ) RETURNING id INTO v_id;
    ELSE
        UPDATE public.logistics_providers AS p
        SET display_name = btrim(p_payload ->> 'display_name'),
            legal_name = NULLIF(btrim(p_payload ->> 'legal_name'), ''),
            tax_id = NULLIF(upper(btrim(p_payload ->> 'tax_id')), ''),
            contact_name = NULLIF(btrim(p_payload ->> 'contact_name'), ''),
            contact_email = NULLIF(btrim(p_payload ->> 'contact_email'), ''),
            contact_phone = NULLIF(btrim(p_payload ->> 'contact_phone'), ''),
            billing_email = NULLIF(btrim(p_payload ->> 'billing_email'), ''),
            notes = NULLIF(btrim(p_payload ->> 'notes'), ''),
            is_active = COALESCE((p_payload ->> 'is_active')::boolean, p.is_active)
        WHERE p.id = p_provider_id AND p.tenant_id = p_tenant_id
        RETURNING p.id INTO v_id;
        IF v_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    END IF;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id)
    VALUES (p_tenant_id, auth.uid(), CASE WHEN p_provider_id IS NULL THEN 'provider_created' ELSE 'provider_updated' END, 'provider', v_id);
    RETURN jsonb_build_object('id', v_id);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'duplicate_name');
    WHEN invalid_text_representation OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_quotes(
    p_tenant_id uuid,
    p_filters jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            to_jsonb(d) || jsonb_build_object(
                'customer_name', c.display_name,
                'provider_name', COALESCE(p.display_name, d.quote_payload ->> 'provider_name'),
                'converted_operation_reference', o.reference_code
            )
            ORDER BY d.updated_at DESC
        )
        FROM public.crm_deals AS d
        LEFT JOIN public.customers AS c ON c.id = d.customer_id AND c.tenant_id = d.tenant_id
        LEFT JOIN public.logistics_providers AS p
          ON p.id = CASE
              WHEN d.quote_payload ->> 'provider_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              THEN (d.quote_payload ->> 'provider_id')::uuid
              ELSE NULL
          END
         AND p.tenant_id = d.tenant_id
        LEFT JOIN public.operations AS o ON o.id = d.converted_operation_id AND o.tenant_id = d.tenant_id
        WHERE d.tenant_id = p_tenant_id
          AND d.quote_reference IS NOT NULL
          AND (NOT (p_filters ? 'status') OR d.quote_status = p_filters ->> 'status')
          AND (NOT (p_filters ? 'customer_id') OR d.customer_id = (p_filters ->> 'customer_id')::uuid)
          AND (NOT (p_filters ? 'provider_id') OR d.quote_payload ->> 'provider_id' = p_filters ->> 'provider_id')
          AND (
              NOT (p_filters ? 'searchText')
              OR d.quote_reference ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR d.title ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR c.display_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR p.display_name ILIKE '%' || (p_filters ->> 'searchText') || '%'
          )
    ), '[]'::jsonb);
EXCEPTION
    WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_quote(
    p_tenant_id uuid,
    p_deal_id uuid,
    p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_customer public.customers%ROWTYPE;
    v_provider public.logistics_providers%ROWTYPE;
    v_service public.service_catalog_items%ROWTYPE;
    v_id uuid;
    v_customer_id uuid;
    v_provider_id uuid;
    v_currency text := COALESCE(NULLIF(p_payload ->> 'pricing_currency', ''), NULLIF(p_payload ->> 'currency', ''), 'MXN');
    v_scope text := COALESCE(NULLIF(p_payload ->> 'operation_scope', ''), 'national');
    v_cost numeric;
    v_sell numeric;
    v_service_catalog_item_id uuid;
    v_service_catalog_snapshot jsonb;
    v_quote_payload jsonb;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NULLIF(btrim(p_payload ->> 'title'), '') IS NULL
       OR NULLIF(p_payload ->> 'customer_id', '') IS NULL
       OR v_currency NOT IN ('MXN', 'USD')
       OR v_scope NOT IN ('national', 'international') THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;

    v_customer_id := (p_payload ->> 'customer_id')::uuid;
    SELECT c.* INTO v_customer FROM public.customers AS c
    WHERE c.id = v_customer_id AND c.tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_customer'); END IF;

    IF NULLIF(p_payload ->> 'provider_id', '') IS NOT NULL THEN
        v_provider_id := (p_payload ->> 'provider_id')::uuid;
        SELECT p.* INTO v_provider FROM public.logistics_providers AS p
        WHERE p.id = v_provider_id AND p.tenant_id = p_tenant_id;
        IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_provider'); END IF;
    END IF;

    IF NULLIF(p_payload ->> 'service_catalog_item_id', '') IS NOT NULL THEN
        v_service_catalog_item_id := (p_payload ->> 'service_catalog_item_id')::uuid;
        SELECT s.* INTO v_service FROM public.service_catalog_items AS s
        WHERE s.id = v_service_catalog_item_id AND s.tenant_id = p_tenant_id AND s.is_active;
        IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_service_catalog_item'); END IF;
    END IF;

    IF NULLIF(p_payload ->> 'provider_cost_amount', '') IS NOT NULL THEN
        v_cost := (p_payload ->> 'provider_cost_amount')::numeric;
    END IF;
    IF NULLIF(p_payload ->> 'customer_price_amount', '') IS NOT NULL THEN
        v_sell := (p_payload ->> 'customer_price_amount')::numeric;
    END IF;
    IF COALESCE(v_cost, 0) < 0 OR COALESCE(v_sell, 0) < 0 THEN
        RETURN jsonb_build_object('error', 'invalid_amount');
    END IF;
    IF p_payload ? 'cargo_summary'
       AND jsonb_typeof(p_payload -> 'cargo_summary') IS DISTINCT FROM 'object' THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;
    IF NULLIF(p_payload ->> 'operational_window_start', '') IS NOT NULL
       AND NULLIF(p_payload ->> 'operational_window_end', '') IS NOT NULL
       AND (p_payload ->> 'operational_window_end')::timestamptz < (p_payload ->> 'operational_window_start')::timestamptz THEN
        RETURN jsonb_build_object('error', 'invalid_operational_window');
    END IF;

    v_service_catalog_snapshot := COALESCE(
        NULLIF(p_payload -> 'service_catalog_snapshot', 'null'::jsonb),
        public.tanda1_service_snapshot(
            COALESCE(NULLIF(btrim(p_payload ->> 'service_type'), ''), v_service.service_type),
            v_service.service_class,
            v_service.presentation,
            v_service.packaging,
            v_service.modality
        )
    );

    v_quote_payload := jsonb_strip_nulls(jsonb_build_object(
        'provider_id', v_provider_id,
        'provider_name', v_provider.display_name,
        'origin_place', p_payload -> 'origin_place',
        'destination_place', p_payload -> 'destination_place',
        'operation_scope', v_scope,
        'execution_type', 'third_party',
        'service_type', COALESCE(NULLIF(btrim(p_payload ->> 'service_type'), ''), v_service.service_type),
        'service_class', NULLIF(btrim(p_payload ->> 'service_class'), ''),
        'presentation', NULLIF(btrim(p_payload ->> 'presentation'), ''),
        'packaging', NULLIF(btrim(p_payload ->> 'packaging'), ''),
        'modality', NULLIF(btrim(p_payload ->> 'modality'), ''),
        'service_catalog_item_id', v_service_catalog_item_id,
        'service_catalog_snapshot', v_service_catalog_snapshot,
        'external_driver', p_payload -> 'external_driver',
        'external_vehicle', p_payload -> 'external_vehicle',
        'provider_cost_amount', v_cost,
        'customer_price_amount', v_sell,
        'pricing_currency', v_currency,
        'operational_window_start', NULLIF(p_payload ->> 'operational_window_start', ''),
        'operational_window_end', NULLIF(p_payload ->> 'operational_window_end', ''),
        'cargo_summary', p_payload -> 'cargo_summary',
        'eta', NULLIF(p_payload ->> 'eta', ''),
        'eta_display', NULLIF(btrim(p_payload ->> 'eta_display'), ''),
        'valid_until', NULLIF(p_payload ->> 'valid_until', ''),
        'notes', NULLIF(btrim(p_payload ->> 'notes'), '')
    ));

    IF p_deal_id IS NULL THEN
        v_id := gen_random_uuid();
        INSERT INTO public.crm_deals (
            id, tenant_id, customer_id, title, company, contact_name, contact_email,
            contact_phone, value, currency, stage, priority, notes, quote_status,
            quote_reference, quote_payload, last_touch_at
        ) VALUES (
            v_id, p_tenant_id, v_customer.id, btrim(p_payload ->> 'title'), v_customer.display_name,
            v_customer.contact_name, v_customer.contact_email, v_customer.contact_phone,
            v_sell, v_currency, 'qualified', COALESCE(NULLIF(p_payload ->> 'priority', ''), 'medium'),
            NULLIF(btrim(p_payload ->> 'notes'), ''), 'draft',
            'COT-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || upper(substr(replace(v_id::text, '-', ''), 1, 6)),
            v_quote_payload, now()
        );
    ELSE
        SELECT d.* INTO v_deal FROM public.crm_deals AS d
        WHERE d.id = p_deal_id AND d.tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
        IF v_deal.quote_status <> 'draft' THEN RETURN jsonb_build_object('error', 'quote_not_editable'); END IF;

        v_quote_payload := (COALESCE(v_deal.quote_payload, '{}'::jsonb) - 'origin' - 'destination' - 'currency') || v_quote_payload;

        UPDATE public.crm_deals AS d
        SET customer_id = v_customer.id,
            title = btrim(p_payload ->> 'title'),
            company = v_customer.display_name,
            contact_name = v_customer.contact_name,
            contact_email = v_customer.contact_email,
            contact_phone = v_customer.contact_phone,
            value = v_sell,
            currency = v_currency,
            stage = 'qualified',
            priority = COALESCE(NULLIF(p_payload ->> 'priority', ''), d.priority),
            notes = NULLIF(btrim(p_payload ->> 'notes'), ''),
            quote_status = 'draft',
            quote_reference = COALESCE(d.quote_reference, 'COT-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || upper(substr(replace(d.id::text, '-', ''), 1, 6))),
            quote_payload = v_quote_payload,
            last_touch_at = now()
        WHERE d.id = p_deal_id
        RETURNING d.id INTO v_id;
    END IF;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id)
    VALUES (p_tenant_id, auth.uid(), CASE WHEN p_deal_id IS NULL OR v_deal.quote_reference IS NULL THEN 'quote_created' ELSE 'quote_updated' END, 'quote', v_id);
    RETURN jsonb_build_object('id', v_id);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'reference_conflict');
    WHEN invalid_text_representation OR numeric_value_out_of_range OR not_null_violation OR check_violation THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_duplicate_quote(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_source public.crm_deals%ROWTYPE;
    v_id uuid := gen_random_uuid();
BEGIN
    SELECT d.* INTO v_source FROM public.crm_deals AS d WHERE d.id = p_deal_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_source.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_source.quote_reference IS NULL THEN RETURN jsonb_build_object('error', 'not_a_quote'); END IF;

    INSERT INTO public.crm_deals (
        id, tenant_id, customer_id, title, company, contact_name, contact_email,
        contact_phone, value, currency, stage, priority, notes, quote_status,
        quote_reference, quote_payload, last_touch_at
    ) VALUES (
        v_id, v_source.tenant_id, v_source.customer_id, v_source.title || ' (copia)', v_source.company,
        v_source.contact_name, v_source.contact_email, v_source.contact_phone, v_source.value,
        v_source.currency, 'qualified', v_source.priority, v_source.notes, 'draft',
        'COT-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || upper(substr(replace(v_id::text, '-', ''), 1, 6)),
        v_source.quote_payload, now()
    );

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (v_source.tenant_id, auth.uid(), 'quote_duplicated', 'quote', v_id, jsonb_build_object('source_quote_id', p_deal_id));
    RETURN jsonb_build_object('id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_return_quote_to_draft(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    SELECT d.* INTO v_deal FROM public.crm_deals AS d WHERE d.id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_deal.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_deal.quote_reference IS NULL THEN RETURN jsonb_build_object('error', 'not_a_quote'); END IF;
    IF v_deal.quote_status <> 'in_review' THEN
        RETURN jsonb_build_object('error', 'invalid_quote_status');
    END IF;

    UPDATE public.crm_deals
    SET quote_status = 'draft', stage = 'qualified', last_touch_at = now(), updated_at = now()
    WHERE id = p_deal_id;

    PERFORM public.rpc_write_audit(v_deal.tenant_id, 'return_quote_to_draft', 'deal', p_deal_id,
        jsonb_build_object('quote_reference', v_deal.quote_reference));
    RETURN jsonb_build_object('success', true, 'status', 'draft');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_convert_quote_to_operation(
    p_deal_id uuid,
    p_conversion_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_payload jsonb;
    v_reference_code text;
    v_operation_id uuid;
    v_origin_raw jsonb;
    v_destination_raw jsonb;
    v_origin jsonb;
    v_destination jsonb;
    v_cargo jsonb;
    v_route_summary text;
    v_destination_city text;
    v_scope text;
    v_execution_type text;
    v_provider_id uuid;
    v_provider public.logistics_providers%ROWTYPE;
    v_provider_name text;
    v_customer_price numeric;
    v_provider_cost numeric;
    v_pricing_currency text;
    v_origin_label text;
    v_destination_label text;
    v_service_catalog_item_id uuid;
    v_service_catalog_snapshot jsonb;
BEGIN
    SELECT * INTO v_deal
    FROM public.crm_deals
    WHERE id = p_deal_id
    FOR UPDATE;

    IF v_deal.id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT public.tanda1_user_has_role(v_deal.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Narrow F1 extension: resolve the previous handoff before checking the
    -- status, because a successful first conversion persists `converted`.
    IF v_deal.converted_operation_id IS NOT NULL THEN
        SELECT o.id, o.reference_code
        INTO v_operation_id, v_reference_code
        FROM public.operations AS o
        WHERE o.id = v_deal.converted_operation_id
          AND o.tenant_id = v_deal.tenant_id;

        IF v_operation_id IS NULL THEN
            RETURN jsonb_build_object('error', 'converted_operation_not_found');
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'operation_id', v_operation_id,
            'operation_reference_code', v_reference_code,
            'already_converted', true
        );
    END IF;

    IF v_deal.quote_status <> 'approved' THEN
        RETURN jsonb_build_object('error', 'quote_not_approved');
    END IF;

    IF NOT public.crm_quote_ready_for_approval(v_deal.quote_payload) THEN
        RETURN jsonb_build_object('error', 'quote_payload_not_ready_for_conversion');
    END IF;

    v_payload := COALESCE(v_deal.quote_payload, '{}'::jsonb);
    v_origin_raw := COALESCE(v_payload->'origin_place', '{}'::jsonb);
    v_destination_raw := COALESCE(v_payload->'destination_place', '{}'::jsonb);
    v_cargo := v_payload->'cargo_summary';

    v_scope := COALESCE(NULLIF(trim(v_payload->>'operation_scope'), ''), '');
    IF v_scope NOT IN ('national', 'international') THEN
        v_scope := CASE
            WHEN COALESCE(v_origin_raw->>'countryCode', 'MX') = 'US'
              OR COALESCE(v_destination_raw->>'countryCode', 'MX') = 'US'
                THEN 'international'
            ELSE 'national'
        END;
    END IF;

    v_execution_type := COALESCE(NULLIF(trim(v_payload->>'execution_type'), ''), 'third_party');
    IF v_execution_type NOT IN ('third_party', 'own_fleet') THEN
        v_execution_type := 'third_party';
    END IF;

    v_provider_id := NULLIF(v_payload->>'provider_id', '')::uuid;
    IF v_provider_id IS NOT NULL THEN
        SELECT * INTO v_provider
        FROM public.logistics_providers
        WHERE id = v_provider_id
          AND tenant_id = v_deal.tenant_id;

        IF v_provider.id IS NULL THEN
            v_provider_id := NULL;
        END IF;
    END IF;

    v_service_catalog_item_id := NULLIF(v_payload->>'service_catalog_item_id', '')::uuid;
    IF v_service_catalog_item_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.service_catalog_items AS s
        WHERE s.id = v_service_catalog_item_id
          AND s.tenant_id = v_deal.tenant_id
    ) THEN
        v_service_catalog_item_id := NULL;
    END IF;

    v_service_catalog_snapshot := COALESCE(
        v_payload->'service_catalog_snapshot',
        public.tanda1_service_snapshot(
            v_payload->>'service_type',
            v_payload->>'service_class',
            v_payload->>'presentation',
            v_payload->>'packaging',
            v_payload->>'modality'
        )
    );

    v_provider_name := COALESCE(NULLIF(trim(v_payload->>'provider_name'), ''), v_provider.display_name);
    v_provider_cost := NULLIF(v_payload->>'provider_cost_amount', '')::numeric;
    v_customer_price := COALESCE(NULLIF(v_payload->>'customer_price_amount', '')::numeric, v_deal.value);
    v_pricing_currency := COALESCE(NULLIF(upper(trim(v_payload->>'pricing_currency')), ''), v_deal.currency, 'MXN');

    v_origin := v_origin_raw || jsonb_build_object(
        'countryCode', COALESCE(NULLIF(trim(v_origin_raw->>'countryCode'), ''), 'MX'),
        'countryName', CASE COALESCE(NULLIF(trim(v_origin_raw->>'countryCode'), ''), 'MX') WHEN 'US' THEN 'USA' ELSE 'Mexico' END
    );
    v_destination := v_destination_raw || jsonb_build_object(
        'countryCode', COALESCE(NULLIF(trim(v_destination_raw->>'countryCode'), ''), 'MX'),
        'countryName', CASE COALESCE(NULLIF(trim(v_destination_raw->>'countryCode'), ''), 'MX') WHEN 'US' THEN 'USA' ELSE 'Mexico' END
    );

    v_origin_label := COALESCE(
        NULLIF(trim(v_origin->>'label'), ''),
        concat_ws(', ', NULLIF(trim(COALESCE(v_origin->>'municipality', '')), ''), NULLIF(trim(COALESCE(v_origin->>'state', '')), ''), NULLIF(trim(COALESCE(v_origin->>'countryCode', '')), ''))
    );
    v_destination_label := COALESCE(
        NULLIF(trim(v_destination->>'label'), ''),
        concat_ws(', ', NULLIF(trim(COALESCE(v_destination->>'municipality', '')), ''), NULLIF(trim(COALESCE(v_destination->>'state', '')), ''), NULLIF(trim(COALESCE(v_destination->>'countryCode', '')), ''))
    );

    v_origin := v_origin || jsonb_build_object('label', v_origin_label);
    v_destination := v_destination || jsonb_build_object('label', v_destination_label);
    v_route_summary := concat_ws(' -> ', NULLIF(trim(v_origin_label), ''), NULLIF(trim(v_destination_label), ''));
    v_destination_city := NULLIF(trim(COALESCE(v_destination->>'municipality', '')), '');
    v_reference_code := public.crm_generate_operation_reference(v_deal.tenant_id);

    INSERT INTO public.operations (
        tenant_id, reference_code, client_display_name, customer_id, operation_scope,
        execution_type, provider_id, provider_name, external_driver, external_vehicle,
        provider_cost_amount, customer_price_amount, pricing_currency, status, source_deal_id,
        service_catalog_item_id, service_catalog_snapshot, service_type, origin_place,
        destination_place, operational_window_start, operational_window_end, notes,
        cargo_summary, route_summary, destination_city, eta, eta_display
    ) VALUES (
        v_deal.tenant_id, v_reference_code, v_deal.company, v_deal.customer_id, v_scope,
        v_execution_type,
        CASE WHEN v_execution_type = 'third_party' THEN v_provider_id ELSE NULL END,
        CASE WHEN v_execution_type = 'third_party' THEN v_provider_name ELSE NULL END,
        CASE WHEN v_execution_type = 'third_party' THEN COALESCE(v_payload->'external_driver', '{}'::jsonb) ELSE '{}'::jsonb END,
        CASE WHEN v_execution_type = 'third_party' THEN COALESCE(v_payload->'external_vehicle', '{}'::jsonb) ELSE '{}'::jsonb END,
        v_provider_cost, v_customer_price, v_pricing_currency, 'planned', v_deal.id,
        v_service_catalog_item_id, v_service_catalog_snapshot, trim(v_payload->>'service_type'),
        v_origin, v_destination,
        (v_payload->>'operational_window_start')::timestamptz,
        (v_payload->>'operational_window_end')::timestamptz,
        COALESCE(NULLIF(trim(COALESCE(v_payload->>'notes', '')), ''), v_deal.notes),
        v_cargo, NULLIF(trim(COALESCE(v_route_summary, '')), ''), v_destination_city,
        NULLIF(v_payload->>'eta', '')::timestamptz,
        NULLIF(trim(COALESCE(v_payload->>'eta_display', '')), '')
    )
    RETURNING id INTO v_operation_id;

    UPDATE public.crm_deals
    SET quote_status = 'converted', stage = 'won', converted_operation_id = v_operation_id,
        converted_at = now(), converted_by = auth.uid(), conversion_note = NULLIF(trim(COALESCE(p_conversion_note, '')), ''),
        last_touch_at = now(), updated_at = now()
    WHERE id = p_deal_id;

    PERFORM public.rpc_seed_checklist_for_deal(p_deal_id);
    PERFORM public.rpc_write_audit(
        v_deal.tenant_id, 'convert_quote_to_operation', 'deal', p_deal_id,
        jsonb_build_object(
            'quote_reference', v_deal.quote_reference,
            'operation_id', v_operation_id,
            'operation_reference_code', v_reference_code,
            'customer_id', v_deal.customer_id,
            'operation_scope', v_scope,
            'execution_type', v_execution_type,
            'provider_id', v_provider_id,
            'service_catalog_item_id', v_service_catalog_item_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'operation_id', v_operation_id,
        'operation_reference_code', v_reference_code,
        'already_converted', false
    );
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'quote_conversion_conflict');
WHEN OTHERS THEN
    RETURN jsonb_build_object('error', 'internal_error');
END;
$function$;

-- Defense in depth: direct table grants are currently revoked, but Commercial
-- RLS also excludes Finance if table privileges are ever changed later.
DROP POLICY IF EXISTS customers_select_members ON public.customers;
CREATE POLICY customers_select_commercial_roles ON public.customers
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

DROP POLICY IF EXISTS providers_select_members ON public.logistics_providers;
CREATE POLICY providers_select_commercial_roles ON public.logistics_providers
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

DROP POLICY IF EXISTS crm_deals_select_members ON public.crm_deals;
CREATE POLICY crm_deals_select_commercial_roles ON public.crm_deals
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

DROP POLICY IF EXISTS crm_activity_select_members ON public.crm_deal_activity;
CREATE POLICY crm_activity_select_commercial_roles ON public.crm_deal_activity
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

DROP POLICY IF EXISTS crm_notes_select_members ON public.crm_deal_notes;
CREATE POLICY crm_notes_select_commercial_roles ON public.crm_deal_notes
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

DROP POLICY IF EXISTS crm_checklist_select_members ON public.crm_deal_checklist_items;
CREATE POLICY crm_checklist_select_commercial_roles ON public.crm_deal_checklist_items
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator', 'viewer']));

REVOKE EXECUTE ON FUNCTION public.rpc_list_customers(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_customer_360(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_upsert_customer(uuid, uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_providers(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_upsert_provider(uuid, uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_quotes(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_upsert_quote(uuid, uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_duplicate_quote(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_return_quote_to_draft(uuid) FROM PUBLIC, anon, service_role;

REVOKE EXECUTE ON FUNCTION public.crm_place_is_complete(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crm_quote_ready_for_review(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crm_quote_ready_for_approval(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.crm_generate_operation_reference(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.tanda1_service_snapshot(text, text, text, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_seed_checklist_for_deal(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_write_audit(uuid, text, text, uuid, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- Existing staging lifecycle ACL is preserved: authenticated and service_role,
-- never PUBLIC/anon. New F1 contracts remain authenticated-only.
REVOKE EXECUTE ON FUNCTION public.rpc_submit_quote_for_review(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rpc_approve_quote(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rpc_reject_quote(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rpc_convert_quote_to_operation(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.rpc_list_customers(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_customer_360(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_customer(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_providers(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_provider(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_quotes(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_quote(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_duplicate_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_return_quote_to_draft(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_submit_quote_for_review(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_approve_quote(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_reject_quote(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_convert_quote_to_operation(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
