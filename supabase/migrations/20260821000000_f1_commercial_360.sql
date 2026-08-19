-- F1 Commercial 360: tenant-scoped customer/provider directories, quote
-- lifecycle and the canonical quote -> operation handoff.
--
-- Reuses the baseline customers, logistics_providers, crm_deals and operations
-- tables. No new table, enum, public tracking or Auth contract is introduced.

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
    v_id uuid;
    v_customer_id uuid;
    v_provider_id uuid;
    v_currency text := COALESCE(NULLIF(p_payload ->> 'currency', ''), 'MXN');
    v_scope text := COALESCE(NULLIF(p_payload ->> 'operation_scope', ''), 'national');
    v_cost numeric;
    v_sell numeric;
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

    IF NULLIF(p_payload ->> 'provider_cost_amount', '') IS NOT NULL THEN
        v_cost := (p_payload ->> 'provider_cost_amount')::numeric;
    END IF;
    IF NULLIF(p_payload ->> 'customer_price_amount', '') IS NOT NULL THEN
        v_sell := (p_payload ->> 'customer_price_amount')::numeric;
    END IF;
    IF COALESCE(v_cost, 0) < 0 OR COALESCE(v_sell, 0) < 0 THEN
        RETURN jsonb_build_object('error', 'invalid_amount');
    END IF;

    v_quote_payload := jsonb_strip_nulls(jsonb_build_object(
        'provider_id', v_provider_id,
        'provider_name', v_provider.display_name,
        'origin_place', p_payload -> 'origin_place',
        'destination_place', p_payload -> 'destination_place',
        'operation_scope', v_scope,
        'service_type', NULLIF(btrim(p_payload ->> 'service_type'), ''),
        'provider_cost_amount', v_cost,
        'customer_price_amount', v_sell,
        'currency', v_currency,
        'requested_date', NULLIF(p_payload ->> 'requested_date', ''),
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

CREATE OR REPLACE FUNCTION public.rpc_transition_quote_status(
    p_deal_id uuid,
    p_to_status text,
    p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_provider_id uuid;
BEGIN
    SELECT d.* INTO v_deal FROM public.crm_deals AS d WHERE d.id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_deal.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_deal.quote_reference IS NULL THEN RETURN jsonb_build_object('error', 'not_a_quote'); END IF;
    IF p_to_status NOT IN ('draft', 'review', 'approved', 'rejected') THEN
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;
    IF NOT (
        (v_deal.quote_status = 'draft' AND p_to_status = 'review')
        OR (v_deal.quote_status = 'review' AND p_to_status IN ('draft', 'approved', 'rejected'))
    ) THEN
        RETURN jsonb_build_object('error', 'invalid_transition');
    END IF;

    IF p_to_status IN ('review', 'approved') THEN
        IF v_deal.customer_id IS NULL
           OR jsonb_typeof(v_deal.quote_payload -> 'origin_place') IS DISTINCT FROM 'object'
           OR jsonb_typeof(v_deal.quote_payload -> 'destination_place') IS DISTINCT FROM 'object'
           OR NULLIF(btrim(v_deal.quote_payload #>> '{origin_place,municipality}'), '') IS NULL
           OR NULLIF(btrim(v_deal.quote_payload #>> '{origin_place,state}'), '') IS NULL
           OR COALESCE(v_deal.quote_payload #>> '{origin_place,countryCode}', '') NOT IN ('MX', 'US')
           OR NULLIF(btrim(v_deal.quote_payload #>> '{destination_place,municipality}'), '') IS NULL
           OR NULLIF(btrim(v_deal.quote_payload #>> '{destination_place,state}'), '') IS NULL
           OR COALESCE(v_deal.quote_payload #>> '{destination_place,countryCode}', '') NOT IN ('MX', 'US')
           OR NULLIF(v_deal.quote_payload ->> 'provider_id', '') IS NULL
           OR NULLIF(v_deal.quote_payload ->> 'provider_cost_amount', '') IS NULL
           OR NULLIF(v_deal.quote_payload ->> 'customer_price_amount', '') IS NULL THEN
            RETURN jsonb_build_object('error', 'quote_incomplete');
        END IF;
        v_provider_id := (v_deal.quote_payload ->> 'provider_id')::uuid;
        IF NOT EXISTS (
            SELECT 1 FROM public.logistics_providers p
            WHERE p.id = v_provider_id AND p.tenant_id = v_deal.tenant_id
        ) THEN RETURN jsonb_build_object('error', 'invalid_provider'); END IF;
    END IF;

    UPDATE public.crm_deals
    SET quote_status = p_to_status,
        stage = CASE p_to_status WHEN 'draft' THEN 'qualified' WHEN 'review' THEN 'proposal' WHEN 'approved' THEN 'won' WHEN 'rejected' THEN 'lost' END,
        approved_at = CASE WHEN p_to_status = 'approved' THEN now() ELSE approved_at END,
        approved_by = CASE WHEN p_to_status = 'approved' THEN auth.uid() ELSE approved_by END,
        approval_note = CASE WHEN p_to_status = 'approved' THEN NULLIF(btrim(p_note), '') ELSE approval_note END,
        rejected_at = CASE WHEN p_to_status = 'rejected' THEN now() ELSE rejected_at END,
        rejected_by = CASE WHEN p_to_status = 'rejected' THEN auth.uid() ELSE rejected_by END,
        rejection_note = CASE WHEN p_to_status = 'rejected' THEN NULLIF(btrim(p_note), '') ELSE rejection_note END,
        last_touch_at = now()
    WHERE id = p_deal_id;

    INSERT INTO public.crm_deal_activity (tenant_id, deal_id, type, body, created_by)
    VALUES (v_deal.tenant_id, p_deal_id, 'status_change', 'Cotización: ' || v_deal.quote_status || ' → ' || p_to_status, auth.uid());
    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (v_deal.tenant_id, auth.uid(), 'quote_status_changed', 'quote', p_deal_id,
        jsonb_build_object('from_status', v_deal.quote_status, 'to_status', p_to_status));
    RETURN jsonb_build_object('success', true, 'status', p_to_status);
EXCEPTION
    WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_payload');
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
    v_customer public.customers%ROWTYPE;
    v_provider public.logistics_providers%ROWTYPE;
    v_operation_id uuid := gen_random_uuid();
    v_reference text;
    v_provider_id uuid;
    v_origin jsonb;
    v_destination jsonb;
    v_cost numeric;
    v_sell numeric;
    v_currency text;
    v_scope text;
BEGIN
    SELECT d.* INTO v_deal FROM public.crm_deals AS d WHERE d.id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_deal.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_deal.converted_operation_id IS NOT NULL THEN
        RETURN (
            SELECT jsonb_build_object('operation_id', o.id, 'operation_reference', o.reference_code, 'already_converted', true)
            FROM public.operations o WHERE o.id = v_deal.converted_operation_id AND o.tenant_id = v_deal.tenant_id
        );
    END IF;
    IF v_deal.quote_status <> 'approved' THEN RETURN jsonb_build_object('error', 'quote_not_approved'); END IF;

    SELECT c.* INTO v_customer FROM public.customers c
    WHERE c.id = v_deal.customer_id AND c.tenant_id = v_deal.tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_customer'); END IF;

    v_provider_id := (v_deal.quote_payload ->> 'provider_id')::uuid;
    SELECT p.* INTO v_provider FROM public.logistics_providers p
    WHERE p.id = v_provider_id AND p.tenant_id = v_deal.tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_provider'); END IF;

    v_origin := v_deal.quote_payload -> 'origin_place';
    v_destination := v_deal.quote_payload -> 'destination_place';
    v_cost := (v_deal.quote_payload ->> 'provider_cost_amount')::numeric;
    v_sell := (v_deal.quote_payload ->> 'customer_price_amount')::numeric;
    v_currency := v_deal.quote_payload ->> 'currency';
    v_scope := v_deal.quote_payload ->> 'operation_scope';
    IF jsonb_typeof(v_origin) IS DISTINCT FROM 'object' OR jsonb_typeof(v_destination) IS DISTINCT FROM 'object'
       OR NULLIF(btrim(v_origin ->> 'municipality'), '') IS NULL OR NULLIF(btrim(v_origin ->> 'state'), '') IS NULL
       OR COALESCE(v_origin ->> 'countryCode', '') NOT IN ('MX', 'US')
       OR NULLIF(btrim(v_destination ->> 'municipality'), '') IS NULL OR NULLIF(btrim(v_destination ->> 'state'), '') IS NULL
       OR COALESCE(v_destination ->> 'countryCode', '') NOT IN ('MX', 'US')
       OR v_currency NOT IN ('MXN', 'USD') OR v_scope NOT IN ('national', 'international')
       OR v_cost < 0 OR v_sell < 0 THEN
        RETURN jsonb_build_object('error', 'quote_incomplete');
    END IF;

    v_reference := 'OP-' || to_char(clock_timestamp(), 'YYYYMMDD') || '-' || upper(substr(replace(v_operation_id::text, '-', ''), 1, 6));
    INSERT INTO public.operations (
        id, tenant_id, reference_code, route_summary, client_display_name,
        destination_city, status, origin_place, destination_place, planned_departure,
        service_type, operational_window_start, notes, source_deal_id, customer_id,
        operation_scope, execution_type, provider_id, provider_name,
        provider_cost_amount, customer_price_amount, pricing_currency
    ) VALUES (
        v_operation_id, v_deal.tenant_id, v_reference,
        concat_ws(' → ', NULLIF(v_origin ->> 'municipality', ''), NULLIF(v_destination ->> 'municipality', '')),
        v_customer.display_name, v_destination ->> 'municipality', 'planned', v_origin, v_destination,
        NULLIF(v_deal.quote_payload ->> 'requested_date', '')::timestamptz,
        NULLIF(v_deal.quote_payload ->> 'service_type', ''),
        NULLIF(v_deal.quote_payload ->> 'requested_date', '')::timestamptz,
        COALESCE(NULLIF(v_deal.quote_payload ->> 'notes', ''), v_deal.notes),
        v_deal.id, v_customer.id, v_scope, 'third_party', v_provider.id, v_provider.display_name,
        v_cost, v_sell, v_currency
    );

    UPDATE public.crm_deals
    SET quote_status = 'converted', converted_operation_id = v_operation_id,
        converted_at = now(), converted_by = auth.uid(),
        conversion_note = NULLIF(btrim(p_conversion_note), ''), last_touch_at = now()
    WHERE id = p_deal_id;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (v_deal.tenant_id, auth.uid(), 'quote_converted', 'quote', p_deal_id,
        jsonb_build_object('operation_id', v_operation_id));
    RETURN jsonb_build_object('operation_id', v_operation_id, 'operation_reference', v_reference, 'already_converted', false);
EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range OR not_null_violation OR check_violation THEN
        RETURN jsonb_build_object('error', 'quote_incomplete');
    WHEN unique_violation THEN
        RETURN jsonb_build_object('error', 'already_converted');
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
REVOKE EXECUTE ON FUNCTION public.rpc_transition_quote_status(uuid, text, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_convert_quote_to_operation(uuid, text) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.rpc_list_customers(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_customer_360(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_customer(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_providers(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_provider(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_quotes(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_quote(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_duplicate_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_transition_quote_status(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_convert_quote_to_operation(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
