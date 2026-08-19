\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_signature text;
    v_oid oid;
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
        'public.rpc_transition_quote_status(uuid,text,text)',
        'public.rpc_convert_quote_to_operation(uuid,text)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: missing %', v_signature; END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p
            WHERE p.oid = v_oid AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN RAISE EXCEPTION 'F1 CONTRACT FAILED: unsafe attributes %', v_signature; END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F1 CONTRACT FAILED: unexpected ACL %', v_signature;
        END IF;
    END LOOP;
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
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin_vertical_flow$
DECLARE
    v_tenant uuid := current_setting('f1.tenant_a')::uuid;
    v_customer uuid := current_setting('f1.customer_a')::uuid;
    v_provider uuid := current_setting('f1.provider_a')::uuid;
    v_quote jsonb;
    v_quote_id uuid;
    v_result jsonb;
    v_operation_id uuid;
    v_operation jsonb;
    v_duplicate jsonb;
    v_opportunity jsonb;
    v_from_opportunity jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('f1.admin'), true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('f1.admin'), 'role', 'authenticated')::text, true);

    IF public.rpc_list_customers(v_tenant, '{}'::jsonb) ? 'error'
       OR public.rpc_get_customer_360(v_customer) ? 'error'
       OR public.rpc_list_providers(v_tenant, '{}'::jsonb) ? 'error' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: admin catalog read denied';
    END IF;

    v_opportunity := public.rpc_create_deal(v_tenant, jsonb_build_object('title', 'Oportunidad existente', 'customer_id', v_customer));
    v_from_opportunity := public.rpc_upsert_quote(v_tenant, (v_opportunity ->> 'id')::uuid, jsonb_build_object(
        'title', 'Oportunidad existente', 'customer_id', v_customer, 'currency', 'MXN', 'operation_scope', 'national'
    ));
    IF v_opportunity ? 'error' OR v_from_opportunity ? 'error'
       OR (v_from_opportunity ->> 'id') <> (v_opportunity ->> 'id')
       OR public.rpc_get_deal((v_opportunity ->> 'id')::uuid) ->> 'quote_reference' IS NULL THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: opportunity was disconnected from quote';
    END IF;

    v_quote := public.rpc_upsert_quote(v_tenant, NULL, jsonb_build_object(
        'title', 'Cruce MX-US', 'customer_id', v_customer, 'provider_id', v_provider,
        'operation_scope', 'international', 'service_type', 'Carga terrestre',
        'currency', 'USD', 'provider_cost_amount', 800, 'customer_price_amount', 1000,
        'origin_place', jsonb_build_object('municipality', 'Monterrey', 'state', 'Nuevo León', 'countryCode', 'MX'),
        'destination_place', jsonb_build_object('municipality', 'Laredo', 'state', 'Texas', 'countryCode', 'US'),
        'requested_date', '2026-09-01T15:00:00Z', 'valid_until', '2026-08-31'
    ));
    IF v_quote ? 'error' THEN RAISE EXCEPTION 'F1 RUNTIME FAILED: quote create %', v_quote; END IF;
    v_quote_id := (v_quote ->> 'id')::uuid;
    PERFORM set_config('f1.quote', v_quote_id::text, true);

    v_duplicate := public.rpc_duplicate_quote(v_quote_id);
    IF v_duplicate ? 'error'
       OR public.rpc_get_deal((v_duplicate ->> 'id')::uuid) ->> 'quote_status' <> 'draft'
       OR public.rpc_get_deal((v_duplicate ->> 'id')::uuid) ->> 'quote_reference' = public.rpc_get_deal(v_quote_id) ->> 'quote_reference' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: safe quote duplication %', v_duplicate;
    END IF;

    IF public.rpc_transition_quote_status(v_quote_id, 'review', NULL) ->> 'status' <> 'review'
       OR public.rpc_transition_quote_status(v_quote_id, 'draft', NULL) ->> 'status' <> 'draft'
       OR public.rpc_transition_quote_status(v_quote_id, 'review', NULL) ->> 'status' <> 'review'
       OR public.rpc_transition_quote_status(v_quote_id, 'approved', 'Aceptada por cliente') ->> 'status' <> 'approved' THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: quote lifecycle';
    END IF;

    v_result := public.rpc_convert_quote_to_operation(v_quote_id, 'Handoff comercial');
    IF v_result ? 'error' OR COALESCE((v_result ->> 'already_converted')::boolean, true) THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: conversion %', v_result;
    END IF;
    v_operation_id := (v_result ->> 'operation_id')::uuid;

    v_operation := public.rpc_get_operation(v_operation_id);
    IF v_operation ? 'error'
       OR (v_operation ->> 'customer_id')::uuid <> v_customer
       OR (v_operation ->> 'provider_id')::uuid <> v_provider
       OR v_operation ->> 'execution_type' <> 'third_party'
       OR (v_operation ->> 'provider_cost_amount')::numeric <> 800
       OR (v_operation ->> 'customer_price_amount')::numeric <> 1000
       OR v_operation ->> 'pricing_currency' <> 'USD'
       OR (v_operation ->> 'source_deal_id')::uuid <> v_quote_id THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: incomplete operation handoff %', v_operation;
    END IF;

    v_result := public.rpc_convert_quote_to_operation(v_quote_id, NULL);
    IF COALESCE((v_result ->> 'already_converted')::boolean, false) IS NOT TRUE
       OR (v_result ->> 'operation_id')::uuid <> v_operation_id THEN
        RAISE EXCEPTION 'F1 RUNTIME FAILED: duplicate conversion was not idempotent %', v_result;
    END IF;
END;
$admin_vertical_flow$;

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
