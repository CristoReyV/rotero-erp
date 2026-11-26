\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.check_case(passed boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF passed IS DISTINCT FROM true THEN RAISE EXCEPTION 'archive assertion: %', label; END IF;
END;
$$;

SET LOCAL ROLE rotero_company_access_owner;
GRANT INSERT ON public.companies, public.membership_company_access, public.membership_company_capabilities TO postgres;
SET LOCAL ROLE postgres;

DO $seed$
DECLARE
    t constant uuid := '64000000-0000-4000-8000-000000000001';
    a constant uuid := '64000000-0000-4000-8000-000000000002';
    b constant uuid := '64000000-0000-4000-8000-000000000003';
    exporter constant uuid := '64000000-0000-4000-8000-000000000004';
    reader constant uuid := '64000000-0000-4000-8000-000000000005';
BEGIN
    INSERT INTO public.tenants (id,name,slug) VALUES (t,'Archive synthetic tests','archive-synthetic-test');
    INSERT INTO auth.users (id) VALUES (exporter),(reader);
    INSERT INTO public.memberships (tenant_id,user_id,role)
    VALUES (t,exporter,'operator'),(t,reader,'operator');
    INSERT INTO public.companies (id,tenant_id,display_name,legal_name,rfc_normalized,status)
    VALUES (a,t,'Synthetic A','Synthetic A','AAA010101AA1','active'),(b,t,'Synthetic B','Synthetic B','BBB010101BB1','active');
    INSERT INTO private.delivery_tenant_cutovers (tenant_id,enabled,approval_reference,approved_by)
    VALUES (t,true,'archive-tests',exporter);
    INSERT INTO public.membership_company_access (tenant_id,user_id,company_id,granted_by)
    VALUES (t,exporter,a,exporter),(t,reader,a,exporter);
    INSERT INTO public.membership_company_capabilities (tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
    VALUES (t,exporter,a,'operations.read','archive-tests',exporter),(t,exporter,a,'export.operational','archive-tests',exporter),
           (t,reader,a,'operations.read','archive-tests',exporter);
    INSERT INTO private.operation_history_archive
        (id,tenant_id,company_id,reference_code,source_customer_name,source_dispatch_crossing_date,source_sha256,source_sheet,source_row)
    VALUES ('64000000-0000-4000-8000-000000000011',t,a,'A-01','Fictitious A','02/01/2025 - 04/01/2025',repeat('a',64),'A',2),
           ('64000000-0000-4000-8000-000000000012',t,a,'A-02',NULL,NULL,repeat('a',64),'A',3),
           ('64000000-0000-4000-8000-000000000013',t,b,'B-01','Fictitious B','2025-01-03',repeat('a',64),'B',2);
    BEGIN
        INSERT INTO private.operation_history_archive(tenant_id,company_id,reference_code,source_sha256,source_sheet,source_row)
        VALUES(t,a,'a-01',repeat('b',64),'A',8);
        RAISE EXCEPTION 'duplicate archive folio was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO private.operation_history_archive(tenant_id,company_id,reference_code,source_sha256,source_sheet,source_row)
        VALUES(t,b,'A-01',repeat('a',64),'A',2);
        RAISE EXCEPTION 'duplicate source identity was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO private.operation_history_archive(tenant_id,company_id,reference_code,source_sha256,source_sheet,source_row)
        VALUES(a,b,'foreign-tenant',repeat('b',64),'X',2);
        RAISE EXCEPTION 'company and tenant mismatch was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
END;
$seed$;

SELECT pg_temp.check_case(
    NOT has_table_privilege('authenticated','private.operation_history_archive','SELECT')
    AND NOT has_table_privilege('authenticated','private.operation_history_archive','INSERT')
    AND NOT has_table_privilege('service_role','private.operation_history_archive','INSERT')
    AND NOT has_table_privilege('rotero_delivery_scope_owner','private.operation_history_archive','INSERT')
    AND NOT has_function_privilege('anon','public.rpc_delivery_operations_history_page(uuid,text,uuid,integer,boolean)','EXECUTE')
    AND NOT has_function_privilege('service_role','public.rpc_delivery_operations_history_page(uuid,text,uuid,integer,boolean)','EXECUTE'),
    'table and RPC restricted to the approved surfaces');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"64000000-0000-4000-8000-000000000004","iss":"https://synthetic-access.invalid/auth/v1","role":"authenticated"}';
SET LOCAL "request.headers" = '{"x-rotero-scope":"company","x-rotero-company-id":"64000000-0000-4000-8000-000000000002"}';
DO $queries$
DECLARE t constant uuid := '64000000-0000-4000-8000-000000000001'; r jsonb; next_page uuid;
BEGIN
    r := public.rpc_delivery_operations_history_page(t,'',NULL,1,false);
    next_page := (r->>'next_cursor')::uuid;
    PERFORM pg_temp.check_case((r->>'total')::int=2 AND next_page IS NOT NULL AND r->'items'->0->>'reference_code'='A-01','company page and total');
    PERFORM pg_temp.check_case(r->'items'->0->>'source_dispatch_crossing_date'='02/01/2025 - 04/01/2025'
        AND r->'items'->0->>'source_row'='2'
        AND NOT (r->'items'->0 ?| ARRAY['source_sha256','status','customer_id','provider_id']), 'literal, scoped provenance');
    r := public.rpc_delivery_operations_history_page(t,'',next_page,1,false);
    PERFORM pg_temp.check_case(r->'items'->0->>'reference_code'='A-02' AND r->'next_cursor'='null','stable cursor');
    r := public.rpc_delivery_operations_history_page(t,'fictitious a',NULL,50,true);
    PERFORM pg_temp.check_case((r->>'total')::int=1 AND r->'items'->0->>'reference_code'='A-01','export shares scope and search');
    PERFORM pg_temp.check_case(public.rpc_delivery_operations_history_page(t,'B-01',NULL,50,true)->'items'='[]','outside company is excluded');
    PERFORM pg_temp.check_case(public.rpc_delivery_operations_history_page(t,'','64000000-0000-4000-8000-000000000013')->>'error'='invalid_cursor','foreign cursor denied');
    PERFORM pg_temp.check_case(public.rpc_delivery_operations_history_page(t,'',NULL,101,false)->>'error'='invalid_filters','bounded page');
END;
$queries$;
SET LOCAL "request.jwt.claims" = '{"sub":"64000000-0000-4000-8000-000000000005","iss":"https://synthetic-access.invalid/auth/v1","role":"authenticated"}';
SELECT pg_temp.check_case(
    (public.rpc_delivery_operations_history_page('64000000-0000-4000-8000-000000000001')->>'total')::int=2
    AND public.rpc_delivery_operations_history_page('64000000-0000-4000-8000-000000000001','',NULL,50,true)->>'error'='unauthorized',
    'operator with read but no export grant');
SET LOCAL "request.headers" = '{"x-rotero-scope":"company","x-rotero-company-id":"64000000-0000-4000-8000-000000000003"}';
SELECT pg_temp.check_case(
    public.rpc_delivery_operations_history_page('64000000-0000-4000-8000-000000000001')->>'error'='unauthorized',
    'company selection is not an access grant');

SELECT 'PASS: archive constraints, access, pagination, source fields and export scope';
ROLLBACK;
