\set ON_ERROR_STOP on
-- Disposable local database, synthetic subjects only; all fixtures/ACL revert.
BEGIN;
CREATE FUNCTION pg_temp.m06_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MULTI06 failed: %',label; END IF; END;
$$;
CREATE FUNCTION pg_temp.m06_error(q text,code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE q;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE<>code THEN RAISE EXCEPTION 'MULTI06 expected %, got %',code,SQLSTATE; END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'MULTI06 expected %, succeeded',code;
END;
$$;
CREATE FUNCTION pg_temp.m06_actor(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated',
        'iss','https://synthetic-access.invalid/auth/v1','user_metadata',jsonb_build_object('company_id',current_setting('m06.b',true)))::text,true);
END;
$$;
CREATE FUNCTION pg_temp.m06_resolve(op uuid,company uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE result uuid;
BEGIN
    INSERT INTO private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,
        evidence_kind,evidence_reference,recorded_by)
    SELECT tenant_id,id,company,'resolved','verified_source_record','synthetic-source-record',current_setting('m06.u')::uuid
    FROM public.operations WHERE id=op RETURNING id INTO result;
    UPDATE public.operations SET company_id=company,company_classification_status='resolved',company_classification_event_id=result
    WHERE id=op;
    RETURN result;
END;
$$;

DO $closed$
DECLARE fn regprocedure; r text; c text;
BEGIN
    FOREACH fn IN ARRAY ARRAY[
        'public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer)'::regprocedure,
        'public.rpc_multi06_get_operation(uuid,uuid,uuid)'::regprocedure,
        'public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer)'::regprocedure,
        'private.multi06_operation_rows(uuid,uuid)'::regprocedure] LOOP
        FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            PERFORM pg_temp.m06_check(NOT has_function_privilege(r,fn,'EXECUTE'),'backend activation gate');
        END LOOP;
        PERFORM pg_temp.m06_check(EXISTS(SELECT FROM pg_proc WHERE oid=fn AND proowner='rotero_operations_read_owner'::regrole
            AND proconfig @> ARRAY['search_path=""']),'limited owner and safe path');
    END LOOP;
    PERFORM pg_temp.m06_check(NOT has_table_privilege('rotero_operations_read_owner','public.operations','SELECT'),
        'reader has column grants, not whole row');
    FOREACH c IN ARRAY ARRAY['provider_cost_amount','customer_price_amount','notes','service_catalog_snapshot','cargo_summary'] LOOP
        PERFORM pg_temp.m06_check(NOT has_column_privilege('rotero_operations_read_owner','public.operations',c,'SELECT'),
            'reader cannot read financial/unstructured column');
    END LOOP;
    FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        PERFORM pg_temp.m06_check(NOT has_any_column_privilege(r,'public.operations','SELECT,INSERT,UPDATE'), 'operations direct ACL');
        PERFORM pg_temp.m06_check(NOT has_table_privilege(r,'private.operation_company_classification_events','SELECT,INSERT,UPDATE,DELETE'), 'ledger ACL');
        PERFORM pg_temp.m06_check(NOT pg_has_role(r,'rotero_operations_read_owner','MEMBER'),'owner cannot be assumed');
    END LOOP;
    PERFORM pg_temp.m06_check(EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_operations_read_owner'
        AND NOT rolcanlogin AND NOT rolinherit AND NOT rolbypassrls AND NOT rolsuper AND NOT rolcreatedb
        AND NOT rolcreaterole AND NOT rolreplication),'limited role attributes');
    PERFORM pg_temp.m06_check(NOT has_schema_privilege('rotero_operations_read_owner','public','CREATE')
        AND NOT has_schema_privilege('rotero_operations_read_owner','private','CREATE'),'no persistent CREATE');
    PERFORM pg_temp.m06_check((SELECT count(*)=9 FROM pg_constraint WHERE conname LIKE '%_multi06_parent_fk' AND NOT convalidated),
        'historical validation explicitly deferred, all nine new-write parent guards');
END;
$closed$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m06_error('SELECT public.rpc_multi06_list_operations(NULL,NULL)','42501');
SELECT pg_temp.m06_error('SELECT * FROM private.multi06_operation_rows(NULL,NULL)','42501');
SELECT pg_temp.m06_error('SELECT * FROM public.operations','42501');
SELECT pg_temp.m06_error('INSERT INTO private.operation_company_classification_events DEFAULT VALUES','42501');
RESET ROLE;
SELECT 'PASS: activation gate, effective ACL, minimal owner and deferred-history contract';

SET LOCAL ROLE rotero_company_access_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
    public.membership_company_capabilities TO %I',SESSION_USER); END; $$;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON private.operation_company_classification_events TO %I',SESSION_USER); END; $$;
-- Test-only activation inside this rollback: never shipped as a grant.
GRANT EXECUTE ON FUNCTION public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer),
    public.rpc_multi06_get_operation(uuid,uuid,uuid),public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer)
    TO authenticated;
RESET ROLE;

DO $fixtures$
DECLARE t uuid; x uuid; a uuid; b uuid; xc uuid; u uuid:=gen_random_uuid(); no_grant uuid:=gen_random_uuid();
    other_user uuid:=gen_random_uuid(); op uuid; i int;
BEGIN
    INSERT INTO public.tenants(name,slug) VALUES('MULTI06 synthetic','multi06-'||gen_random_uuid()) RETURNING id INTO t;
    INSERT INTO public.tenants(name,slug) VALUES('MULTI06 other','multi06-'||gen_random_uuid()) RETURNING id INTO x;
    INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(no_grant,t,'admin'),(other_user,x,'finance');
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
    INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
        VALUES(t,u,a,u),(t,no_grant,a,u),(x,other_user,xc,other_user);
    INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
        VALUES(t,u,a,'operations.read','synthetic-approval',u);
    PERFORM set_config('m06.t',t::text,true); PERFORM set_config('m06.x',x::text,true);
    PERFORM set_config('m06.a',a::text,true); PERFORM set_config('m06.b',b::text,true); PERFORM set_config('m06.xc',xc::text,true);
    PERFORM set_config('m06.u',u::text,true); PERFORM set_config('m06.no_grant',no_grant::text,true);
    PERFORM set_config('m06.other_user',other_user::text,true);
    FOR i IN 1..3 LOOP
        INSERT INTO public.operations(tenant_id,reference_code,client_display_name,provider_name,provider_cost_amount,
            customer_price_amount,notes,service_catalog_snapshot)
        VALUES(t,'A-'||i,CASE WHEN i=1 THEN 'Needle A' ELSE 'Visible' END,'QA provider',12345,54321,
            'FINANCIAL_CANARY','{"cost":"FINANCIAL_CANARY"}') RETURNING id INTO op;
        PERFORM pg_temp.m06_resolve(op,a);
        IF i=1 THEN PERFORM set_config('m06.op_a',op::text,true); END IF;
    END LOOP;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,provider_cost_amount,customer_price_amount)
        VALUES(t,'B-1','Needle B',12345,54321) RETURNING id INTO op;
    PERFORM pg_temp.m06_resolve(op,b); PERFORM set_config('m06.op_b',op::text,true);
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name) VALUES(x,'X-1','Needle X') RETURNING id INTO op;
    PERFORM pg_temp.m06_resolve(op,xc); PERFORM set_config('m06.op_x',op::text,true);
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name) VALUES(t,'P-1','Needle pending') RETURNING id INTO op;
    PERFORM set_config('m06.op_pending',op::text,true);
    INSERT INTO public.operations(tenant_id,reference_code,company_classification_status) VALUES(t,'C-1','conflict');
END;
$fixtures$;

DO $integrity$
DECLARE op uuid:=current_setting('m06.op_pending')::uuid; e uuid;
BEGIN
    PERFORM pg_temp.m06_check((SELECT company_id IS NULL AND company_classification_status='pending_classification'
        FROM public.operations WHERE id=op),'legacy and unknown inserts stay pending, no inference');
    PERFORM pg_temp.m06_error(format('UPDATE public.operations SET company_id=%L WHERE id=%L',current_setting('m06.a'),op),'23514');
    PERFORM pg_temp.m06_error(format('UPDATE public.operations SET company_classification_status=''resolved'' WHERE id=%L',op),'23514');
    PERFORM pg_temp.m06_error(format('SELECT pg_temp.m06_resolve(%L,%L)',op,current_setting('m06.xc')),'23503');
    PERFORM pg_temp.m06_error(format('UPDATE public.operations SET company_id=%L WHERE id=%L',current_setting('m06.b'),current_setting('m06.op_a')),'23503');
    PERFORM pg_temp.m06_error(format('UPDATE public.operations SET company_classification_event_id=gen_random_uuid() WHERE id=%L',current_setting('m06.op_a')),'23503');
    INSERT INTO public.operation_billing(tenant_id,operation_id) VALUES(current_setting('m06.t')::uuid,current_setting('m06.op_a')::uuid);
    PERFORM pg_temp.m06_error(format('INSERT INTO public.operation_billing(tenant_id,operation_id) VALUES(%L,%L)',
        current_setting('m06.x'),current_setting('m06.op_b')),'23503');
    PERFORM pg_temp.m06_error(format('INSERT INTO public.operation_crossings(tenant_id,operation_id,crossing_point) VALUES(%L,%L,''synthetic'')',
        current_setting('m06.x'),current_setting('m06.op_a')),'23503');
    PERFORM pg_temp.m06_error(format('UPDATE private.operation_company_classification_events SET evidence_kind=''insufficient_evidence'' WHERE operation_id=%L',
        current_setting('m06.op_a')),'23514');
END;
$integrity$;
SELECT 'PASS: tenant/company/evidence integrity, unresolved preservation and parent-derived ownership';

SET LOCAL ROLE authenticated;
DO $read_flow$
DECLARE t uuid:=current_setting('m06.t')::uuid; a uuid:=current_setting('m06.a')::uuid;
    result jsonb; item jsonb; cursor uuid; seen uuid[]:='{}'; expected text[]; actual text[];
BEGIN
    PERFORM pg_temp.m06_actor(current_setting('m06.u')::uuid);
    result:=public.rpc_multi06_list_operations(t,a,'',NULL,1);
    PERFORM pg_temp.m06_check((result->>'total')::int=3 AND jsonb_array_length(result->'items')=1
        AND result->>'classification_notice' LIKE 'resolved_only%','scoped count and explicit pending notice');
    LOOP
        result:=public.rpc_multi06_list_operations(t,a,'',cursor,1);
        seen:=array_append(seen,(result->'items'->0->>'id')::uuid);
        cursor:=(result->>'next_cursor')::uuid;
        EXIT WHEN cursor IS NULL;
        PERFORM pg_temp.m06_check(cardinality(seen)<=3,'bounded pagination');
    END LOOP;
    PERFORM pg_temp.m06_check(cardinality(seen)=3 AND (SELECT count(DISTINCT id)=3 FROM unnest(seen) q(id)),
        'keyset all three once, no cross-company/pending rows');
    result:=public.rpc_multi06_list_operations(t,a,'needle');
    PERFORM pg_temp.m06_check((result->>'total')::int=1 AND jsonb_array_length(result->'items')=1,'search only authorized resolved rows');
    result:=public.rpc_multi06_list_operations(t,a,'%');
    PERFORM pg_temp.m06_check((result->>'total')::int=0,'search metacharacters are literal');
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a,'',current_setting('m06.op_b')::uuid)->>'error'='invalid_cursor',
        'cursor cannot reference another company');
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a,'',NULL,0)->>'error'='invalid_filters'
        AND public.rpc_multi06_list_operations(t,a,NULL)->>'error'='invalid_filters','invalid filters fail');
    item:=public.rpc_multi06_get_operation(t,a,current_setting('m06.op_a')::uuid)->'item';
    SELECT array_agg(k ORDER BY k) INTO actual FROM jsonb_object_keys(item) k;
    SELECT array_agg(k ORDER BY k) INTO expected FROM unnest(ARRAY['id','company_id','reference_code','status','service_type',
        'route_summary','client_display_name','provider_name','operation_scope','execution_type','priority','planned_departure',
        'operational_window_start','operational_window_end','created_at']) k;
    PERFORM pg_temp.m06_check(actual=expected AND item::text NOT LIKE '%FINANCIAL_CANARY%','exact minimal DTO, no financial or nested free fields');
    PERFORM pg_temp.m06_check(public.rpc_multi06_get_operation(t,a,current_setting('m06.op_b')::uuid)->>'error'='not_found'
        AND public.rpc_multi06_get_operation(t,a,current_setting('m06.op_x')::uuid)->>'error'='not_found'
        AND public.rpc_multi06_get_operation(t,a,current_setting('m06.op_pending')::uuid)->>'error'='not_found',
        'direct IDs cannot bypass company/classification');
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,current_setting('m06.b')::uuid)->>'error'='unauthorized'
        AND public.rpc_multi06_list_operations(current_setting('m06.x')::uuid,a)->>'error'='unauthorized',
        'company and tenant manipulation denied');
    PERFORM pg_temp.m06_check(public.rpc_multi06_export_operations_page(t,a)->>'error'='unauthorized','export permission separate');
    PERFORM pg_temp.m06_actor(current_setting('m06.no_grant')::uuid);
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a)->>'error'='unauthorized','admin with access but no capability denied');
    PERFORM pg_temp.m06_actor(current_setting('m06.other_user')::uuid);
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a)->>'error'='unauthorized','other tenant actor denied');
    PERFORM pg_temp.m06_actor(NULL);
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a)->>'error'='unauthorized','missing subject denied');
END;
$read_flow$;
SELECT pg_temp.m06_error('UPDATE public.operations SET company_id=current_setting(''m06.b'')::uuid','42501');
SELECT pg_temp.m06_error('UPDATE private.operation_company_classification_events SET recorded_by=current_setting(''m06.u'')::uuid','42501');
RESET ROLE;
SELECT 'PASS: list/detail/search/count/keyset/DTO, company/tenant/direct-ID denials and no self-classification';

-- Independent RLS check, even if an accidental ledger table grant is added.
SET LOCAL ROLE rotero_operations_read_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.operation_company_classification_events TO authenticated;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m06_actor(current_setting('m06.u')::uuid);
SELECT pg_temp.m06_check((SELECT count(*)=0 FROM private.operation_company_classification_events),'ledger RLS hides evidence');
DO $$ DECLARE n int;
BEGIN
    UPDATE private.operation_company_classification_events SET recorded_by=current_setting('m06.u')::uuid;
    GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM pg_temp.m06_check(n=0,'ledger RLS prevents self-edit');
    PERFORM pg_temp.m06_error('INSERT INTO private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,
        evidence_kind,evidence_reference,recorded_by) VALUES(current_setting(''m06.t'')::uuid,current_setting(''m06.op_a'')::uuid,
        current_setting(''m06.a'')::uuid,''resolved'',''approved_resolution'',''self-claim'',current_setting(''m06.u'')::uuid)','42501');
END; $$;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
REVOKE ALL ON private.operation_company_classification_events FROM authenticated;
RESET ROLE;

-- Two companies can be explicitly authorized without mixing their results.
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
VALUES(current_setting('m06.t')::uuid,current_setting('m06.u')::uuid,current_setting('m06.b')::uuid,current_setting('m06.u')::uuid);
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
VALUES(current_setting('m06.t')::uuid,current_setting('m06.u')::uuid,current_setting('m06.b')::uuid,'operations.read','synthetic-B',current_setting('m06.u')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.m06_check((public.rpc_multi06_list_operations(current_setting('m06.t')::uuid,current_setting('m06.b')::uuid)->>'total')::int=1
    AND (public.rpc_multi06_list_operations(current_setting('m06.t')::uuid,current_setting('m06.a')::uuid)->>'total')::int=3,
    'explicit A and B still require separate mandatory scopes');
RESET ROLE;
DELETE FROM public.membership_company_capabilities WHERE company_id=current_setting('m06.b')::uuid;
DELETE FROM public.membership_company_access WHERE company_id=current_setting('m06.b')::uuid;
SELECT 'PASS: independent ledger RLS and separate positive scopes for two companies';

INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
VALUES(current_setting('m06.t')::uuid,current_setting('m06.u')::uuid,current_setting('m06.a')::uuid,
    'export.operational','synthetic-export-approval',current_setting('m06.u')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.m06_actor(current_setting('m06.u')::uuid);
DO $export$ DECLARE l jsonb; e jsonb;
BEGIN
    l:=public.rpc_multi06_list_operations(current_setting('m06.t')::uuid,current_setting('m06.a')::uuid,'',NULL,2);
    e:=public.rpc_multi06_export_operations_page(current_setting('m06.t')::uuid,current_setting('m06.a')::uuid,'',NULL,2);
    PERFORM pg_temp.m06_check(l=e AND e::text NOT LIKE '%FINANCIAL_CANARY%','export uses exactly screen scope/projection/pagination');
    PERFORM pg_temp.m06_check(public.rpc_multi06_export_operations_page(current_setting('m06.t')::uuid,
        current_setting('m06.b')::uuid)->>'error'='unauthorized','export cannot change company');
END;
$export$;
RESET ROLE;
DO $revocation$
DECLARE t uuid:=current_setting('m06.t')::uuid; a uuid:=current_setting('m06.a')::uuid; u uuid:=current_setting('m06.u')::uuid;
BEGIN
    UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=u
        WHERE user_id=u AND company_id=a AND capability_code='export.operational';
    PERFORM pg_temp.m06_check(public.rpc_multi06_export_operations_page(t,a)->>'error'='unauthorized','export revoked before next page');
    UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by=u WHERE user_id=u AND company_id=a;
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a)->>'error'='unauthorized'
        AND public.rpc_multi06_get_operation(t,a,current_setting('m06.op_a')::uuid)->>'error'='unauthorized','access revocation dominates reads');
    UPDATE public.membership_company_access SET status='active',revoked_at=NULL,revoked_by=NULL WHERE user_id=u AND company_id=a;
    UPDATE public.companies SET status='inactive' WHERE id=a;
    PERFORM pg_temp.m06_check(public.rpc_multi06_list_operations(t,a)->>'error'='unauthorized','inactive company');
    UPDATE public.companies SET status='active' WHERE id=a;
END;
$revocation$;
SET LOCAL ROLE rotero_operations_read_owner;
SELECT pg_temp.m06_error('SELECT provider_cost_amount FROM public.operations','42501');
SELECT pg_temp.m06_check((SELECT count(*)=3 FROM public.operations),'reader RLS allows only explicit resolved company');
RESET ROLE;
SELECT 'PASS: export equality and revocation, inactive company, reader column ACL and RLS';

-- Demonstrate the known bypass using synthetic data, not merely static review.
-- These existing contracts are deliberately unchanged: therefore no activation.
SET LOCAL ROLE authenticated;
DO $bypass$
DECLARE t uuid:=current_setting('m06.t')::uuid; b uuid:=current_setting('m06.op_b')::uuid; legacy jsonb;
BEGIN
    legacy:=public.rpc_get_operation(b);
    PERFORM pg_temp.m06_check(legacy ? 'provider_cost_amount' AND legacy->>'id'=b::text,
        'confirmed legacy direct-ID financial bypass, activation blocked');
    PERFORM pg_temp.m06_check(jsonb_array_length(public.rpc_list_operations(t))=6,
        'legacy keeps all six tenant operations, including unresolved/conflict');
    legacy:=public.rpc_export_data_page(t,'operations');
    PERFORM pg_temp.m06_check(EXISTS(SELECT FROM jsonb_array_elements(legacy->'items') q WHERE q ? 'provider_cost_amount'),
        'confirmed legacy export financial bypass, activation blocked');
END;
$bypass$;
RESET ROLE;
SELECT 'PASS: legacy regression preserved; financial bypasses demonstrated, new experience must remain closed';
ROLLBACK;

DO $clean$
BEGIN
    IF EXISTS(SELECT FROM private.operation_company_classification_events) OR EXISTS(SELECT FROM public.operations)
        OR EXISTS(SELECT FROM public.tenants WHERE slug LIKE 'multi06-%')
        OR has_function_privilege('authenticated','public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer)','EXECUTE')
        OR has_table_privilege('authenticated','private.operation_company_classification_events','SELECT,INSERT') THEN
        RAISE EXCEPTION 'MULTI06 residue or activation grant remains';
    END IF;
END;
$clean$;
SELECT 'PASS: synthetic rows and activation/fixture grants rolled back';
