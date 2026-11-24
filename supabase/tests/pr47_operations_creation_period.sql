\set ON_ERROR_STOP on
-- Isolated local test only. All synthetic identities, evidence and grants roll back.
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.assert_result(ok boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'pr47: %', label; END IF;
    PERFORM set_config('pr47.count', (COALESCE(NULLIF(current_setting('pr47.count', true), ''), '0')::int + 1)::text, true);
END $$;

SET LOCAL ROLE rotero_company_access_owner;
GRANT INSERT ON public.companies, public.membership_company_access, public.membership_company_capabilities TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
GRANT INSERT ON private.operation_company_classification_events TO postgres;
RESET ROLE;

DO $setup$
DECLARE
    tenant uuid := gen_random_uuid();
    company_a uuid := gen_random_uuid();
    company_b uuid := gen_random_uuid();
    actor uuid := gen_random_uuid();
    fixture record;
    operation uuid;
    ledger uuid;
BEGIN
    INSERT INTO auth.users(id) VALUES (actor);
    INSERT INTO public.tenants(id, name, slug) VALUES (tenant, 'PR47 synthetic creation dates', 'pr47-' || tenant);
    INSERT INTO public.memberships(user_id, tenant_id, role) VALUES (actor, tenant, 'operator');
    INSERT INTO public.companies(id, tenant_id, display_name, legal_name, rfc_normalized, status)
    VALUES (company_a, tenant, 'PR47 Company A', 'Synthetic A', 'AAA010101AA1', 'active'),
           (company_b, tenant, 'PR47 Company B', 'Synthetic B', 'BBB010101BB1', 'active');
    INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
    VALUES (tenant,actor,company_a,actor),(tenant,actor,company_b,actor);
    INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
    VALUES (tenant,actor,company_a,'operations.read','pr47 isolated test only',actor),
           (tenant,actor,company_b,'operations.read','pr47 isolated test only',actor),
           (tenant,actor,company_a,'export.operational','pr47 isolated test only',actor);
    INSERT INTO private.delivery_tenant_cutovers(tenant_id,enabled,approval_reference,approved_by)
    VALUES (tenant,true,'pr47 isolated test only',actor);

    FOR fixture IN
        SELECT * FROM (VALUES
            ('PR47-A-BEFORE', company_a, TIMESTAMPTZ '2026-11-02 05:59:59.999999+00'),
            ('PR47-A-START',  company_a, TIMESTAMPTZ '2026-11-02 06:00:00+00'),
            ('PR47-A-END',    company_a, TIMESTAMPTZ '2026-11-09 05:59:59.999999+00'),
            ('PR47-A-AFTER',  company_a, TIMESTAMPTZ '2026-11-09 06:00:00+00'),
            ('PR47-B-OTHER',  company_b, TIMESTAMPTZ '2026-11-04 12:00:00+00'),
            ('UNMATCHED',     company_a, TIMESTAMPTZ '2026-11-04 12:00:00+00')
        ) AS value(reference, company, created)
        UNION ALL SELECT 'PR47-A-MIDDLE-' || n, company_a, TIMESTAMPTZ '2026-11-04 12:00:00+00'
        FROM generate_series(1,50) AS n
    LOOP
        INSERT INTO public.operations(tenant_id,reference_code,created_at,pricing_currency,provider_cost_amount,customer_price_amount)
        VALUES (tenant,fixture.reference,fixture.created,'MXN',313,701) RETURNING id INTO operation;
        INSERT INTO private.operation_company_classification_events(
            tenant_id, operation_id, company_id, decision, evidence_kind, evidence_reference, recorded_by
        ) VALUES (
            tenant,operation,fixture.company,'resolved','verified_source_record','pr47 creation date fixtures',actor
        ) RETURNING id INTO ledger;
        UPDATE public.operations SET company_id=fixture.company,company_classification_status='resolved',
            company_classification_event_id=ledger WHERE id=operation;
        IF fixture.company=company_b THEN PERFORM set_config('pr47.b_cursor',operation::text,true); END IF;
    END LOOP;

    PERFORM set_config('pr47.tenant',tenant::text,true);
    PERFORM set_config('pr47.company_a',company_a::text,true);
    PERFORM set_config('pr47.company_b',company_b::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object(
        'sub',actor,'role','authenticated','iss','https://pr47.test/auth/v1')::text,true);
    PERFORM set_config('request.headers',jsonb_build_object(
        'x-rotero-scope','company','x-rotero-company-id',company_a)::text,true);
END $setup$;

SELECT pg_temp.assert_result(
    NOT has_function_privilege('anon','public.rpc_delivery_operations_page_by_creation(uuid,text,uuid,integer,boolean,date,date)','EXECUTE')
    AND NOT has_function_privilege('service_role','public.rpc_delivery_operations_page_by_creation(uuid,text,uuid,integer,boolean,date,date)','EXECUTE')
    AND has_function_privilege('authenticated','public.rpc_delivery_operations_page_by_creation(uuid,text,uuid,integer,boolean,date,date)','EXECUTE')
    AND NOT has_function_privilege('authenticated','private.pr47_operations_page(uuid,text,uuid,integer,boolean,date,date)','EXECUTE'),
    'only authenticated can execute the protected entrypoint'
);

SET LOCAL ROLE authenticated;
DO $exercise$
DECLARE
    t uuid := current_setting('pr47.tenant')::uuid;
    a uuid := current_setting('pr47.company_a')::uuid;
    b uuid := current_setting('pr47.company_b')::uuid;
    start_day date := DATE '2026-11-02';
    end_day date := DATE '2026-11-08';
    first_page jsonb;
    second_page jsonb;
    csv_first jsonb;
    csv_second jsonb;
    result jsonb;
    combined jsonb;
    row_refs text[];
BEGIN
    first_page := public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,start_day,end_day);
    second_page := public.rpc_delivery_operations_page_by_creation(
        t,'PR47-',(first_page->>'next_cursor')::uuid,50,false,start_day,end_day);
    csv_first := public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,true,start_day,end_day);
    csv_second := public.rpc_delivery_operations_page_by_creation(
        t,'PR47-',(csv_first->>'next_cursor')::uuid,50,true,start_day,end_day);
    PERFORM pg_temp.assert_result(first_page->>'creation_date_timezone'='America/Mexico_City','ERP default zone');
    PERFORM pg_temp.assert_result(first_page->>'total'='52' AND second_page->>'total'='52','shared inclusive totals');
    PERFORM pg_temp.assert_result(jsonb_array_length(first_page->'items')=50
        AND jsonb_array_length(second_page->'items')=2 AND second_page->'next_cursor'='null'::jsonb,'pagination 50 + 2');
    PERFORM pg_temp.assert_result(first_page=csv_first AND second_page=csv_second,'CSV and listing pages identical');
    combined := (first_page->'items') || (second_page->'items');
    SELECT array_agg(r->>'reference_code') INTO row_refs FROM jsonb_array_elements(combined) AS r;
    PERFORM pg_temp.assert_result(row_refs @> ARRAY['PR47-A-START','PR47-A-END'],'both local midnight edges included');
    PERFORM pg_temp.assert_result(NOT row_refs && ARRAY['PR47-A-BEFORE','PR47-A-AFTER','PR47-B-OTHER','UNMATCHED'],
        'outside bounds, other company and search mismatches excluded');
    PERFORM pg_temp.assert_result((SELECT count(DISTINCT (r->>'id'))=52 FROM jsonb_array_elements(combined) AS r),'no duplicate IDs');
    PERFORM pg_temp.assert_result(NOT EXISTS (
        SELECT FROM jsonb_array_elements(combined) r
        WHERE r->>'company_id'<>a::text OR r ?| ARRAY['provider_cost_amount','customer_price_amount','profit','margin']
    ),'company scope and operational projection preserved');
    result := public.rpc_delivery_operations_page(t,'PR47-',NULL,50,false);
    PERFORM pg_temp.assert_result(result->>'total'='54' AND result->>'creation_date_timezone'='America/Mexico_City',
        'clearing date filters preserves legacy search and total');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,NULL,NULL)=result,
        'unbounded date contract matches original route');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,start_day,NULL)->>'total'='53',
        'inclusive lower bound without upper bound');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,NULL,end_day)->>'total'='53',
        'inclusive upper bound without lower bound');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,end_day,start_day)->>'error'='invalid_filters',
        'inverted dates rejected');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,NULL,'infinity')->>'error'='invalid_filters',
        'unbounded sentinel rejected');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',current_setting('pr47.b_cursor')::uuid,50,false,start_day,end_day)->>'error'='invalid_cursor',
        'other company cursor rejected');
    PERFORM set_config('request.headers',jsonb_build_object('x-rotero-scope','company','x-rotero-company-id',b)::text,true);
    result := public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,false,start_day,end_day);
    PERFORM pg_temp.assert_result(result->>'total'='1' AND result #>> '{items,0,reference_code}'='PR47-B-OTHER',
        'second company projects only its own row');
    PERFORM pg_temp.assert_result(public.rpc_delivery_operations_page_by_creation(t,'PR47-',NULL,50,true,start_day,end_day)->>'error'='unauthorized',
        'second company has read, CSV needs its own grant');
END $exercise$;
RESET ROLE;

-- Tenant-specific business timezone overrides the ERP default.
INSERT INTO public.tenant_settings(tenant_id,timezone)
VALUES(current_setting('pr47.tenant')::uuid,'America/Tijuana')
ON CONFLICT (tenant_id) DO UPDATE SET timezone=EXCLUDED.timezone;
SELECT set_config('request.headers',jsonb_build_object(
    'x-rotero-scope','company','x-rotero-company-id',current_setting('pr47.company_a'))::text,true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_result(
    public.rpc_delivery_operations_page_by_creation(
        current_setting('pr47.tenant')::uuid,'PR47-',NULL,50,false,DATE '2026-11-02',DATE '2026-11-08'
    )->>'creation_date_timezone'='America/Tijuana', 'valid configured timezone is used'
);
WITH chosen AS (
    SELECT public.rpc_delivery_operations_page_by_creation(
        current_setting('pr47.tenant')::uuid,'PR47-',NULL,100,false,DATE '2026-11-02',DATE '2026-11-08'
    )->'items' AS items
), ids AS (
    SELECT array_agg(item->>'reference_code') AS refs FROM chosen, jsonb_array_elements(items) AS item
)
SELECT pg_temp.assert_result(refs @> ARRAY['PR47-A-END','PR47-A-AFTER'] AND NOT refs @> ARRAY['PR47-A-START'],
    'configured timezone changes local midnight membership') FROM ids;
RESET ROLE;

SELECT current_setting('pr47.count') AS pr47_assertions;
ROLLBACK;
