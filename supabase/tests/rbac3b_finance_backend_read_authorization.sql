\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE
    v_signature text;
    v_oid oid;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_get_tenant_settings(uuid)',
        'public.rpc_list_members(uuid)',
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)',
        'public.rpc_list_tracking_tokens(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: missing %', v_signature;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_proc AS p
            WHERE p.oid = v_oid
              AND p.prosecdef
              AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: unsafe function attributes %', v_signature;
        END IF;

        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'RBAC.3B CONTRACT FAILED: unexpected grants %', v_signature;
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
    v_operation_a uuid;
    v_operation_b uuid;
    v_deal_a uuid;
    v_deal_b uuid;
    v_pedimento_a uuid;
    v_pedimento_b uuid;
    v_cfdi_a uuid;
BEGIN
    INSERT INTO public.tenants (name, slug)
    VALUES ('RBAC3B A', 'rbac3b-a'), ('RBAC3B B', 'rbac3b-b');

    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug = 'rbac3b-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug = 'rbac3b-b';

    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES
        (v_tenant_a, v_admin, 'admin'),
        (v_tenant_a, v_operator, 'operator'),
        (v_tenant_a, v_finance, 'finance'),
        (v_tenant_a, v_viewer, 'viewer');

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES
        (v_tenant_a, 'RBAC3B-A', 'planned'),
        (v_tenant_b, 'RBAC3B-B', 'planned');

    SELECT id INTO v_operation_a FROM public.operations WHERE reference_code = 'RBAC3B-A';
    SELECT id INTO v_operation_b FROM public.operations WHERE reference_code = 'RBAC3B-B';

    INSERT INTO public.crm_deals (tenant_id, title, stage)
    VALUES
        (v_tenant_a, 'RBAC3B Deal A', 'lead'),
        (v_tenant_b, 'RBAC3B Deal B', 'lead');
    SELECT id INTO v_deal_a FROM public.crm_deals WHERE title = 'RBAC3B Deal A';
    SELECT id INTO v_deal_b FROM public.crm_deals WHERE title = 'RBAC3B Deal B';

    INSERT INTO public.customs_pedimentos (tenant_id, pedimento_number, status)
    VALUES
        (v_tenant_a, 'RBAC3B-PED-A', 'draft'),
        (v_tenant_b, 'RBAC3B-PED-B', 'draft');
    SELECT id INTO v_pedimento_a FROM public.customs_pedimentos WHERE pedimento_number = 'RBAC3B-PED-A';
    SELECT id INTO v_pedimento_b FROM public.customs_pedimentos WHERE pedimento_number = 'RBAC3B-PED-B';

    INSERT INTO public.billing_cfdis (tenant_id, rfc_emisor, rfc_receptor, total, status)
    VALUES (v_tenant_a, 'AAA010101AAA', 'BBB010101BBB', 116, 'draft')
    RETURNING id INTO v_cfdi_a;

    PERFORM set_config('rbac3b.tenant_a', v_tenant_a::text, true);
    PERFORM set_config('rbac3b.tenant_b', v_tenant_b::text, true);
    PERFORM set_config('rbac3b.admin', v_admin::text, true);
    PERFORM set_config('rbac3b.operator', v_operator::text, true);
    PERFORM set_config('rbac3b.finance', v_finance::text, true);
    PERFORM set_config('rbac3b.viewer', v_viewer::text, true);
    PERFORM set_config('rbac3b.operation_a', v_operation_a::text, true);
    PERFORM set_config('rbac3b.operation_b', v_operation_b::text, true);
    PERFORM set_config('rbac3b.deal_a', v_deal_a::text, true);
    PERFORM set_config('rbac3b.deal_b', v_deal_b::text, true);
    PERFORM set_config('rbac3b.pedimento_a', v_pedimento_a::text, true);
    PERFORM set_config('rbac3b.pedimento_b', v_pedimento_b::text, true);
    PERFORM set_config('rbac3b.cfdi_a', v_cfdi_a::text, true);
END;
$fixtures$;

-- Run the reads as authenticated. This helper has no definer privileges.
CREATE FUNCTION pg_temp.rbac3b_reads(t uuid, d uuid, p uuid)
RETURNS TABLE (rpc text, payload jsonb, product_read boolean)
LANGUAGE sql SET search_path='' AS $$
    VALUES
        ('inventory_lots', public.rpc_list_inventory_lots(t, '{}'), true),
        ('pedimentos', public.rpc_list_pedimentos(t, '{}'), true),
        ('descargo_lines', public.rpc_list_descargo_lines(p), true),
        ('deals', public.rpc_list_deals(t, '{}'), true),
        ('deal', public.rpc_get_deal(d), true),
        ('deal_activities', public.rpc_list_deal_activities(d), true),
        ('deal_notes', public.rpc_list_deal_notes(d), true),
        ('deal_checklist', public.rpc_list_deal_checklist(d), true),
        ('tenant_settings', public.rpc_get_tenant_settings(t), true),
        ('members', public.rpc_list_members(t), false),
        ('audit_log', public.rpc_list_audit_log(t, 50, 0, NULL, NULL, NULL, NULL), false),
        ('tracking_tokens', public.rpc_list_tracking_tokens(t), false);
$$;

CREATE FUNCTION pg_temp.rbac3b_is_read(payload jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
    SELECT COALESCE(jsonb_typeof(payload) IN ('array', 'object') AND NOT (payload ? 'error'), false);
$$;

CREATE FUNCTION pg_temp.rbac3b_claims(actor uuid, selector jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', actor::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object(
        'sub', actor, 'role', 'authenticated', 'iss', 'https://synthetic-access.invalid/auth/v1'
    )::text, true);
    PERFORM set_config('request.headers', selector::text, true);
END $$;

CREATE FUNCTION pg_temp.rbac3b_expect_reads(
    t uuid, d uuid, p uuid, expected_error text, only_product boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE r record; checked int := 0;
BEGIN
    FOR r IN SELECT * FROM pg_temp.rbac3b_reads(t, d, p)
        WHERE NOT only_product OR product_read
    LOOP
        IF expected_error IS NULL THEN
            IF NOT pg_temp.rbac3b_is_read(r.payload) THEN
                RAISE EXCEPTION 'RBAC.3B expected read: %', r.rpc;
            END IF;
        ELSIF r.payload IS DISTINCT FROM jsonb_build_object('error', expected_error) THEN
            -- NULL, missing errors and extra data are all failures. Never print payloads.
            RAISE EXCEPTION 'RBAC.3B expected denial (%): %', expected_error, r.rpc;
        END IF;
        checked := checked + 1;
    END LOOP;
    IF checked <> (CASE WHEN only_product THEN 9 ELSE 12 END) THEN
        RAISE EXCEPTION 'RBAC.3B test coverage changed: %', checked;
    END IF;
    PERFORM set_config('rbac3b.checks',
        (COALESCE(NULLIF(current_setting('rbac3b.checks', true), '')::int, 0) + checked)::text, true);
END $$;

SET LOCAL ROLE authenticated;

DO $legacy$
DECLARE
    a uuid := current_setting('rbac3b.tenant_a')::uuid;
    b uuid := current_setting('rbac3b.tenant_b')::uuid;
    deal_a uuid := current_setting('rbac3b.deal_a')::uuid;
    deal_b uuid := current_setting('rbac3b.deal_b')::uuid;
    pedimento_a uuid := current_setting('rbac3b.pedimento_a')::uuid;
    pedimento_b uuid := current_setting('rbac3b.pedimento_b')::uuid;
    role_name text;
    rows jsonb;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['admin','operator','viewer'] LOOP
        PERFORM pg_temp.rbac3b_claims(current_setting('rbac3b.' || role_name)::uuid);
        PERFORM pg_temp.rbac3b_expect_reads(a, deal_a, pedimento_a, NULL, role_name <> 'admin');

        -- Demonstrate a genuine record in the result and no foreign record.
        rows := public.rpc_list_deals(a, '{}');
        IF position(deal_a::text IN rows::text) = 0 OR position(deal_b::text IN rows::text) > 0 THEN
            RAISE EXCEPTION 'RBAC.3B legacy deal contents not tenant-scoped';
        END IF;
        PERFORM pg_temp.rbac3b_expect_reads(b, deal_b, pedimento_b, 'unauthorized');
    END LOOP;

    PERFORM pg_temp.rbac3b_claims(current_setting('rbac3b.finance')::uuid);
    PERFORM pg_temp.rbac3b_expect_reads(a, deal_a, pedimento_a, 'unauthorized');

    PERFORM pg_temp.rbac3b_claims(gen_random_uuid());
    PERFORM pg_temp.rbac3b_expect_reads(a, deal_a, pedimento_a, 'unauthorized');
END $legacy$;

DO $finance_deny_and_allow$
DECLARE
    v_tenant uuid := current_setting('rbac3b.tenant_a')::uuid;
    v_operation uuid := current_setting('rbac3b.operation_a')::uuid;
    v_deal uuid := current_setting('rbac3b.deal_a')::uuid;
    v_pedimento uuid := current_setting('rbac3b.pedimento_a')::uuid;
    v_cfdi uuid := current_setting('rbac3b.cfdi_a')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', current_setting('rbac3b.finance'), true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', current_setting('rbac3b.finance'), 'role', 'authenticated')::text,
        true
    );

    IF NOT pg_temp.rbac3b_is_read(public.rpc_dashboard_overview(v_tenant, NULL, NULL))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_dashboard_recent_activity(v_tenant, NULL, NULL))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_dashboard_alerts(v_tenant, NULL, NULL))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_list_operations(v_tenant))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_get_operation(v_operation))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_get_operation_requirements(v_operation))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_list_route_points(v_operation, NULL, NULL, 500))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_list_cfdis(v_tenant, '{}'::jsonb))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_get_cfdi_detail(v_cfdi))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_finance_overview(v_tenant))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_list_finance_invoices(v_tenant, 50, NULL, NULL))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_reports_financial_summary(v_tenant, 'monthly'))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_reports_pipeline_summary(v_tenant))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_reports_inventory_summary(v_tenant))
       OR NOT pg_temp.rbac3b_is_read(public.rpc_reports_operations_summary(v_tenant)) THEN
        RAISE EXCEPTION 'RBAC.3B RUNTIME FAILED: finance denied an approved read';
    END IF;
END;
$finance_deny_and_allow$;

RESET ROLE;

-- On the company candidate, the same legacy RPCs are closed at cutover even
-- when a valid company is selected. Keep the original role contract above for
-- tenants outside cutover. These grants exist only in this rollback fixture.
SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT, INSERT ON public.companies, public.membership_company_access TO postgres;
RESET ROLE;

DO $cutover_fixture$
DECLARE
    a uuid := current_setting('rbac3b.tenant_a')::uuid;
    admin_id uuid := current_setting('rbac3b.admin')::uuid;
    company uuid;
    role_name text;
BEGIN
    INSERT INTO public.companies (tenant_id, display_name, legal_name, rfc_normalized, status)
    VALUES (a, 'Synthetic RBAC', 'Synthetic RBAC', 'AAA010101AA1', 'active') RETURNING id INTO company;
    INSERT INTO private.delivery_tenant_cutovers (tenant_id, enabled, approval_reference, approved_by)
    VALUES (a, true, 'synthetic-only', admin_id);
    FOREACH role_name IN ARRAY ARRAY['admin','operator','finance','viewer'] LOOP
        INSERT INTO public.membership_company_access (tenant_id, user_id, company_id, granted_by)
        VALUES (a, current_setting('rbac3b.' || role_name)::uuid, company, admin_id);
    END LOOP;
    PERFORM set_config('rbac3b.company', company::text, true);
END $cutover_fixture$;

SET LOCAL ROLE authenticated;

DO $cutover$
DECLARE
    a uuid := current_setting('rbac3b.tenant_a')::uuid;
    deal_a uuid := current_setting('rbac3b.deal_a')::uuid;
    pedimento_a uuid := current_setting('rbac3b.pedimento_a')::uuid;
    company uuid := current_setting('rbac3b.company')::uuid;
    selector jsonb := jsonb_build_object('x-rotero-scope', 'company', 'x-rotero-company-id', company);
    role_name text;
    actor uuid;
    context jsonb;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['admin','operator','finance','viewer'] LOOP
        actor := current_setting('rbac3b.' || role_name)::uuid;
        PERFORM pg_temp.rbac3b_claims(actor);
        PERFORM pg_temp.rbac3b_expect_reads(a, deal_a, pedimento_a, 'company_adoption_pending');

        PERFORM pg_temp.rbac3b_claims(actor, selector);
        context := public.rpc_delivery_context(a);
        IF context IS NULL OR NOT COALESCE((context->>'cutover_required')::boolean, false)
            OR NOT EXISTS (SELECT FROM jsonb_array_elements(context->'companies') c WHERE c->>'id'=company::text)
        THEN RAISE EXCEPTION 'RBAC.3B fixture has no valid company selector for %', role_name; END IF;
        PERFORM pg_temp.rbac3b_expect_reads(a, deal_a, pedimento_a, 'company_adoption_pending');
    END LOOP;
END $cutover$;

RESET ROLE;

SELECT 'RBAC3B_READ_CASES=' || current_setting('rbac3b.checks');
ROLLBACK;
