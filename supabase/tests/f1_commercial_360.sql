\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_signature text;
    v_oid oid;
    v_constraint text;
    v_definition text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_customers(uuid,jsonb)',
        'public.rpc_get_customer_360(uuid)',
        'public.rpc_upsert_customer(uuid,uuid,jsonb)',
        'public.rpc_list_providers(uuid,jsonb)',
        'public.rpc_upsert_provider(uuid,uuid,jsonb)',
        'public.rpc_list_quotes(uuid,jsonb)',
        'public.rpc_upsert_quote(uuid,uuid,jsonb)',
        'public.rpc_duplicate_quote(uuid)',
        'public.rpc_return_quote_to_draft(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: missing %', v_signature; END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: unsafe F1 attributes %', v_signature; END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F1 CONTRACT FAILED: unexpected F1 ACL %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_submit_quote_for_review(uuid)',
        'public.rpc_approve_quote(uuid,text)',
        'public.rpc_reject_quote(uuid,text)',
        'public.rpc_convert_quote_to_operation(uuid,text)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: missing canonical %', v_signature; END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc AS p
            WHERE p.oid = v_oid AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: canonical attributes drifted %', v_signature; END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR NOT has_function_privilege('service_role', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F1 CONTRACT FAILED: canonical ACL drifted %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.crm_place_is_complete(jsonb)',
        'public.crm_quote_ready_for_review(jsonb)',
        'public.crm_quote_ready_for_approval(jsonb)',
        'public.crm_generate_operation_reference(uuid)',
        'public.tanda1_service_snapshot(text,text,text,text,text)',
        'public.rpc_seed_checklist_for_deal(uuid)',
        'public.rpc_write_audit(uuid,text,text,uuid,jsonb)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'F1 CONTRACT FAILED: missing canonical helper %', v_signature;
        END IF;
        IF has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F1 CONTRACT FAILED: internal helper exposed %', v_signature;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: helper search_path drifted %', v_signature; END IF;
    END LOOP;

    SELECT pg_get_constraintdef(c.oid, true)
    INTO v_constraint
    FROM pg_constraint AS c
    WHERE c.conrelid = 'public.crm_deals'::regclass
      AND c.conname = 'crm_deals_quote_status_check';

    IF position('''in_review''' IN v_constraint) = 0
       OR position('''review''' IN v_constraint) <> 0 THEN
        RAISE EXCEPTION 'F1 CONTRACT FAILED: noncanonical quote status constraint %', v_constraint;
    END IF;

    IF to_regprocedure('public.rpc_transition_quote_status(uuid,text,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'F1 CONTRACT FAILED: parallel generic lifecycle remains';
    END IF;
    v_definition := pg_get_functiondef('public.rpc_convert_quote_to_operation(uuid,text)'::regprocedure);
    IF v_definition ~ '\mSQLERRM\M' THEN
        RAISE EXCEPTION 'F1 CONTRACT FAILED: converter exposes internal database errors';
    END IF;
    IF v_definition NOT LIKE '%crm_generate_operation_reference%'
       OR v_definition NOT LIKE '%rpc_seed_checklist_for_deal%'
       OR v_definition NOT LIKE '%operation_reference_code%' THEN
        RAISE EXCEPTION 'F1 CONTRACT FAILED: canonical converter behavior removed';
    END IF;
END;
$contract$;

DO $fixtures$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_admin uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid();
    v_viewer uuid := gen_random_uuid();
    v_customer_a uuid;
    v_customer_b uuid;
    v_provider_a uuid;
    v_provider_b uuid;
    v_service uuid;
BEGIN
    INSERT INTO public.tenants (name, slug) VALUES ('F1 A', 'f1-a'), ('F1 B', 'f1-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'f1-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'f1-b';

    INSERT INTO public.memberships (tenant_id, user_id, role) VALUES
        (v_tenant_a, v_admin, 'admin'), (v_tenant_a, v_operator, 'operator'),
        (v_tenant_a, v_finance, 'finance'), (v_tenant_a, v_viewer, 'viewer');
    INSERT INTO public.customers (tenant_id, display_name) VALUES
        (v_tenant_a, 'Cliente A'), (v_tenant_b, 'Cliente B');
    INSERT INTO public.logistics_providers (tenant_id, display_name) VALUES
        (v_tenant_a, 'Proveedor A'), (v_tenant_b, 'Proveedor B');
    INSERT INTO public.service_catalog_items (
        tenant_id, service_type, service_class, presentation, packaging, modality
    ) VALUES (
        v_tenant_a, 'Carga terrestre', 'FTL', 'Seca', 'Caja', 'Puerta a puerta'
    ) RETURNING id INTO v_service;

    SELECT id INTO v_customer_a FROM public.customers WHERE tenant_id = v_tenant_a AND display_name = 'Cliente A';
    SELECT id INTO v_customer_b FROM public.customers WHERE tenant_id = v_tenant_b AND display_name = 'Cliente B';
    SELECT id INTO v_provider_a FROM public.logistics_providers WHERE tenant_id = v_tenant_a AND display_name = 'Proveedor A';
    SELECT id INTO v_provider_b FROM public.logistics_providers WHERE tenant_id = v_tenant_b AND display_name = 'Proveedor B';

    PERFORM set_config('f1.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('f1.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('f1.admin', v_admin::text, true);
    PERFORM set_config('f1.operator', v_operator::text, true);
    PERFORM set_config('f1.finance', v_finance::text, true);
    PERFORM set_config('f1.viewer', v_viewer::text, true);
    PERFORM set_config('f1.customer_a', v_customer_a::text, true);
    PERFORM set_config('f1.customer_b', v_customer_b::text, true);
    PERFORM set_config('f1.provider_a', v_provider_a::text, true);
    PERFORM set_config('f1.provider_b', v_provider_b::text, true);
    PERFORM set_config('f1.service', v_service::text, true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin_vertical_flow$
DECLARE
    v_tenant uuid := current_setting('f1.tenant_a')::uuid;
    v_customer uuid := current_setting('f1.customer_a')::uuid;
    v_provider uuid := current_setting('f1.provider_a')::uuid;
    v_service uuid := current_setting('f1.service')::uuid;
    v_quote jsonb;
    v_quote_id uuid;
    v_result jsonb;
    v_operation_id uuid;
    v_operation jsonb;
    v_duplicate jsonb;
    v_opportunity jsonb;
    v_from_opportunity jsonb;
    v_incomplete jsonb;
    v_incomplete_id uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.admin'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('f1.admin'), 'role', 'authenticated')::text, true);

    IF public.rpc_list_customers(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_customer_360(v_customer) ? 'error'
       OR public.rpc_list_providers(v_tenant, '{}'::jsonb) ? 'error' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: admin catalog read denied';
    END IF;

    v_opportunity := public.rpc_create_deal(v_tenant, jsonb_build_object(
        'title', 'Oportunidad existente', 'value', 350, 'currency', 'MXN'
    ));
    v_from_opportunity := public.rpc_upsert_quote(v_tenant, (v_opportunity ->> 'id')::uuid, jsonb_build_object(
        'title', 'Oportunidad existente', 'customer_id', v_customer,
        'pricing_currency', 'MXN', 'customer_price_amount', 350, 'operation_scope', 'national'
    ));
    IF v_opportunity ? 'error' OR v_from_opportunity ? 'error'
       OR (v_from_opportunity ->> 'id') <> (v_opportunity ->> 'id')
       OR public.rpc_get_deal((v_opportunity ->> 'id')::uuid) ->> 'quote_reference' IS NULL
       OR public.rpc_get_deal((v_opportunity ->> 'id')::uuid) ->> 'quote_status' <> 'draft' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: opportunity quote linkage/status';
    END IF;

    v_incomplete := public.rpc_upsert_quote(v_tenant, NULL, jsonb_build_object(
        'title', 'Pendiente de datos operativos', 'customer_id', v_customer,
        'pricing_currency', 'MXN', 'customer_price_amount', 500,
        'operation_scope', 'national', 'service_type', 'Carga terrestre',
        'origin_place', jsonb_build_object('municipality', 'Monterrey', 'state', 'Nuevo León', 'countryCode', 'MX'),
        'destination_place', jsonb_build_object('municipality', 'Saltillo', 'state', 'Coahuila', 'countryCode', 'MX')
    ));
    v_incomplete_id := (v_incomplete ->> 'id')::uuid;
    v_result := public.rpc_submit_quote_for_review(v_incomplete_id);
    IF v_result ? 'error' OR public.rpc_get_deal(v_incomplete_id) ->> 'quote_status' <> 'in_review' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: review readiness %, %', v_result, public.rpc_get_deal(v_incomplete_id);
    END IF;
    v_result := public.rpc_approve_quote(v_incomplete_id, NULL);
    IF v_result ->> 'error' <> 'quote_payload_not_ready_for_approval' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: incomplete approval accepted %', v_result;
    END IF;
    v_result := public.rpc_reject_quote(v_incomplete_id, 'Faltan datos');
    IF v_result ? 'error' OR public.rpc_get_deal(v_incomplete_id) ->> 'quote_status' <> 'rejected' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: reject lifecycle %, %', v_result, public.rpc_get_deal(v_incomplete_id);
    END IF;

    v_quote := public.rpc_upsert_quote(v_tenant, NULL, jsonb_build_object(
        'title', 'Cruce MX-US', 'customer_id', v_customer, 'provider_id', v_provider,
        'operation_scope', 'international', 'execution_type', 'third_party',
        'service_type', 'Carga terrestre', 'service_catalog_item_id', v_service,
        'service_catalog_snapshot', jsonb_build_object('service_type', 'Carga terrestre', 'service_class', 'FTL', 'source', 'F1 QA'),
        'pricing_currency', 'USD', 'provider_cost_amount', 800, 'customer_price_amount', 1000,
        'origin_place', jsonb_build_object('municipality', 'Monterrey', 'state', 'Nuevo León', 'countryCode', 'MX'),
        'destination_place', jsonb_build_object('municipality', 'Laredo', 'state', 'Texas', 'countryCode', 'US'),
        'operational_window_start', '2026-09-01T15:00:00Z',
        'operational_window_end', '2026-09-01T21:00:00Z',
        'cargo_summary', jsonb_build_object('description', 'Autopartes', 'pieces', 24, 'unit', 'tarimas', 'weightKg', 8200, 'measurements', '53 ft'),
        'external_driver', jsonb_build_object('name', 'Operador proveedor'),
        'external_vehicle', jsonb_build_object('unit', 'EXT-77'),
        'eta', '2026-09-02T04:00:00Z', 'eta_display', '02 sep, 04:00',
        'valid_until', '2026-08-31', 'notes', 'Entrega coordinada'
    ));
    IF v_quote ? 'error' THEN RAISE EXCEPTION 'F1 RUNTIME FAILED: quote create %', v_quote; END IF;
    v_quote_id := (v_quote ->> 'id')::uuid;
    PERFORM set_config('f1.quote', v_quote_id::text, true);
    IF public.rpc_get_deal(v_quote_id) #>> '{quote_payload,pricing_currency}' <> 'USD'
       OR public.rpc_get_deal(v_quote_id) #> '{quote_payload,currency}' IS NOT NULL THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: noncanonical pricing payload %', public.rpc_get_deal(v_quote_id);
    END IF;

    v_duplicate := public.rpc_duplicate_quote(v_quote_id);
    IF v_duplicate ? 'error'
       OR public.rpc_get_deal((v_duplicate ->> 'id')::uuid) ->> 'quote_status' <> 'draft'
       OR public.rpc_get_deal((v_duplicate ->> 'id')::uuid) ->> 'quote_reference' = public.rpc_get_deal(v_quote_id) ->> 'quote_reference' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: safe quote duplication %', v_duplicate;
    END IF;

    v_result := public.rpc_submit_quote_for_review(v_quote_id);
    IF v_result ? 'error' OR public.rpc_get_deal(v_quote_id) ->> 'quote_status' <> 'in_review' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: main submit %, %', v_result, public.rpc_get_deal(v_quote_id);
    END IF;
    v_result := public.rpc_return_quote_to_draft(v_quote_id);
    IF v_result ->> 'status' <> 'draft' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: return draft %', v_result;
    END IF;
    v_result := public.rpc_submit_quote_for_review(v_quote_id);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F1 RUNTIME FAILED: resubmit %', v_result; END IF;
    v_result := public.rpc_approve_quote(v_quote_id, 'Aceptada por cliente');
    IF v_result ? 'error' OR public.rpc_get_deal(v_quote_id) ->> 'quote_status' <> 'approved' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: approval %, %', v_result, public.rpc_get_deal(v_quote_id);
    END IF;

    v_result := public.rpc_convert_quote_to_operation(v_quote_id, 'Handoff comercial');
    IF v_result ? 'error'
       OR COALESCE((v_result ->> 'already_converted')::boolean, true)
       OR v_result ->> 'operation_reference_code' IS NULL THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: conversion %', v_result;
    END IF;
    v_operation_id := (v_result ->> 'operation_id')::uuid;
    PERFORM set_config('f1.operation', v_operation_id::text, true);

    v_operation := public.rpc_get_operation(v_operation_id);
    IF v_operation ? 'error'
       OR (v_operation ->> 'customer_id')::uuid <> v_customer
       OR (v_operation ->> 'provider_id')::uuid <> v_provider
       OR v_operation ->> 'execution_type' <> 'third_party'
       OR (v_operation ->> 'provider_cost_amount')::numeric <> 800
       OR (v_operation ->> 'customer_price_amount')::numeric <> 1000
       OR v_operation ->> 'pricing_currency' <> 'USD'
       OR (v_operation ->> 'source_deal_id')::uuid <> v_quote_id
       OR (v_operation ->> 'service_catalog_item_id')::uuid <> v_service
       OR v_operation #>> '{service_catalog_snapshot,source}' <> 'F1 QA'
       OR v_operation #>> '{cargo_summary,description}' <> 'Autopartes'
       OR (v_operation ->> 'operational_window_start')::timestamptz <> '2026-09-01T15:00:00Z'::timestamptz
       OR (v_operation ->> 'operational_window_end')::timestamptz <> '2026-09-01T21:00:00Z'::timestamptz
       OR v_operation #>> '{external_driver,name}' <> 'Operador proveedor'
       OR v_operation #>> '{external_vehicle,unit}' <> 'EXT-77'
       OR v_operation ->> 'destination_city' <> 'Laredo'
       OR v_operation ->> 'eta_display' <> '02 sep, 04:00' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: incomplete rich operation handoff %', v_operation;
    END IF;

    v_result := public.rpc_convert_quote_to_operation(v_quote_id, NULL);
    IF COALESCE((v_result ->> 'already_converted')::boolean, false) IS NOT TRUE
       OR (v_result ->> 'operation_id')::uuid <> v_operation_id
       OR v_result ->> 'operation_reference_code' IS NULL THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: duplicate conversion was not idempotent %', v_result;
    END IF;
END;
$admin_vertical_flow$;

RESET ROLE;

DO $postgres_regression$
DECLARE
    v_quote uuid := current_setting('f1.quote')::uuid;
    v_operation uuid := current_setting('f1.operation')::uuid;
    v_reference text;
BEGIN
    IF (SELECT count(*) FROM public.operations WHERE source_deal_id = v_quote) <> 1 THEN
        RAISE EXCEPTION 'F1 REGRESSION FAILED: duplicate operation created';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.crm_deal_checklist_items
        WHERE deal_id = v_quote AND stage = 'won'
    ) THEN RAISE EXCEPTION 'F1 REGRESSION FAILED: checklist seeding removed'; END IF;

    SELECT reference_code INTO v_reference FROM public.operations WHERE id = v_operation;
    IF v_reference !~ '^OP-[0-9]{6}-[A-F0-9]{6}$' THEN
        RAISE EXCEPTION 'F1 REGRESSION FAILED: noncanonical reference %', v_reference;
    END IF;
    IF EXISTS (SELECT 1 FROM public.crm_deals WHERE quote_status = 'review') THEN
        RAISE EXCEPTION 'F1 REGRESSION FAILED: persisted review status';
    END IF;

    BEGIN
        UPDATE public.crm_deals SET quote_status = 'review' WHERE id = v_quote;
        RAISE EXCEPTION 'F1 REGRESSION FAILED: constraint accepted review';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END;
$postgres_regression$;

SET LOCAL ROLE authenticated;

DO $ownership_and_invalid_refs$
DECLARE
    v_tenant uuid := current_setting('f1.tenant_a')::uuid;
    v_customer uuid := current_setting('f1.customer_a')::uuid;
    v_cross_customer uuid := current_setting('f1.customer_b')::uuid;
    v_cross_provider uuid := current_setting('f1.provider_b')::uuid;
    v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.admin'), true);
    v_result := public.rpc_upsert_quote(v_tenant, NULL, jsonb_build_object('title', 'Bad customer', 'customer_id', v_cross_customer));
    IF v_result ->> 'error' <> 'invalid_customer' THEN RAISE EXCEPTION 'F1 RUNTIME FAILED: cross-tenant customer accepted'; END IF;
    v_result := public.rpc_upsert_quote(v_tenant, NULL, jsonb_build_object('title', 'Bad provider', 'customer_id', v_customer, 'provider_id', v_cross_provider));
    IF v_result ->> 'error' <> 'invalid_provider' THEN RAISE EXCEPTION 'F1 RUNTIME FAILED: cross-tenant provider accepted'; END IF;
    IF public.rpc_list_customers(current_setting('f1.tenant_b')::uuid, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_providers(current_setting('f1.tenant_b')::uuid, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_quotes(current_setting('f1.tenant_b')::uuid, '{}'::jsonb) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: cross-tenant list access';
    END IF;
END;
$ownership_and_invalid_refs$;

DO $finance_deny$
DECLARE
    v_tenant uuid := current_setting('f1.tenant_a')::uuid;
    v_customer uuid := current_setting('f1.customer_a')::uuid;
    v_quote uuid := current_setting('f1.quote')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.finance'), true);
    IF public.rpc_list_customers(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_get_customer_360(v_customer) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_providers(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_list_quotes(v_tenant, '{}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_upsert_customer(v_tenant, NULL, '{"display_name":"Denied"}'::jsonb) ->> 'error' <> 'unauthorized'
       OR public.rpc_duplicate_quote(v_quote) ->> 'error' <> 'unauthorized'
       OR public.rpc_submit_quote_for_review(v_quote) ->> 'error' <> 'unauthorized'
       OR public.rpc_convert_quote_to_operation(v_quote, NULL) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: finance reached Commercial';
    END IF;
END;
$finance_deny$;

DO $product_roles$
DECLARE
    v_tenant uuid := current_setting('f1.tenant_a')::uuid;
    v_customer uuid := current_setting('f1.customer_a')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.viewer'), true);
    IF public.rpc_list_customers(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_customer_360(v_customer) ? 'error'
       OR public.rpc_list_providers(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_list_quotes(v_tenant, '{}'::jsonb) ? 'error' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: viewer read contract removed';
    END IF;
    IF public.rpc_upsert_customer(v_tenant, NULL, '{"display_name":"Viewer denied"}'::jsonb) ->> 'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: viewer mutation allowed';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.operator'), true);
    IF public.rpc_upsert_customer(v_tenant, NULL, '{"display_name":"Operator allowed"}'::jsonb) ? 'error' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: operator product mutation contract removed';
    END IF;
END;
$product_roles$;

RESET ROLE;
ROLLBACK;
