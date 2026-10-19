\set ON_ERROR_STOP on
BEGIN;

-- The suite is synthetic and transactional. It never needs Auth users, emails,
-- business fixtures or a persistent grant. Run only on a disposable local DB.
CREATE FUNCTION pg_temp.multi04_expect_error(p_sql text, p_state text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $test$
DECLARE v_state text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
        IF v_state <> p_state THEN
            RAISE EXCEPTION 'MULTI04 expected SQLSTATE %, received %', p_state, v_state;
        END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'MULTI04 expected SQLSTATE %, statement succeeded', p_state;
END;
$test$;

CREATE FUNCTION pg_temp.multi04_set_actor(p_actor text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $test$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', COALESCE(p_actor,''), true);
    PERFORM set_config('request.jwt.claims', CASE WHEN p_actor IS NULL THEN '{}'
        ELSE jsonb_build_object('sub',p_actor,'role','authenticated')::text END, true);
END;
$test$;

DO $contract$
DECLARE v_table text; v_role text; v_priv text; v_owner oid;
BEGIN
    SELECT oid INTO STRICT v_owner FROM pg_catalog.pg_roles
    WHERE rolname = 'rotero_company_access_owner'
      AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
      AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication;
    FOREACH v_table IN ARRAY ARRAY['companies', 'membership_company_access'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class
            WHERE oid = pg_catalog.to_regclass('public.' || v_table)
              AND relrowsecurity AND relowner = v_owner) THEN
            RAISE EXCEPTION 'MULTI04 RLS/owner missing on %', v_table;
        END IF;
        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
            FOREACH v_priv IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
                IF pg_catalog.has_table_privilege(v_role, 'public.' || v_table, v_priv) THEN
                    RAISE EXCEPTION 'MULTI04 unexpected effective table grant: % % %', v_role, v_table, v_priv;
                END IF;
            END LOOP;
            IF pg_catalog.pg_has_role(v_role, v_owner, 'MEMBER') THEN
                RAISE EXCEPTION 'MULTI04 client can assume owner: %', v_role;
            END IF;
            IF pg_catalog.has_any_column_privilege(v_role, 'public.' || v_table, 'SELECT,INSERT,UPDATE,REFERENCES') THEN
                RAISE EXCEPTION 'MULTI04 unexpected effective column grant: % %', v_role, v_table;
            END IF;
        END LOOP;
    END LOOP;
    IF EXISTS (SELECT FROM public.companies) OR EXISTS (SELECT FROM public.membership_company_access) THEN
        RAISE EXCEPTION 'MULTI04 requires fresh, unpopulated local roots';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc
        WHERE oid = 'private.multi04_has_company_access(uuid,uuid)'::regprocedure
          AND prosecdef AND provolatile = 's' AND proowner = v_owner
          AND proconfig @> ARRAY['search_path=""']::text[]) THEN
        RAISE EXCEPTION 'MULTI04 unsafe helper attributes';
    END IF;
    IF NOT pg_catalog.has_function_privilege('authenticated',
        'private.multi04_has_company_access(uuid,uuid)', 'EXECUTE')
       OR pg_catalog.has_function_privilege('anon',
        'private.multi04_has_company_access(uuid,uuid)', 'EXECUTE')
       OR pg_catalog.has_function_privilege('service_role',
        'private.multi04_has_company_access(uuid,uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'MULTI04 unexpected helper ACL';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS p,
        LATERAL pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS a
        WHERE p.oid = 'private.multi04_has_company_access(uuid,uuid)'::regprocedure
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
        RAISE EXCEPTION 'MULTI04 PUBLIC can execute helper';
    END IF;
    IF pg_catalog.has_table_privilege('rotero_company_access_owner','public.memberships','SELECT')
       OR pg_catalog.has_table_privilege('rotero_company_access_owner','public.finance_invoices','SELECT')
       OR pg_catalog.pg_has_role('rotero_company_access_owner','authenticated','MEMBER')
       OR pg_catalog.has_schema_privilege('rotero_company_access_owner','public','CREATE')
       OR pg_catalog.has_schema_privilege('rotero_company_access_owner','private','CREATE') THEN
        RAISE EXCEPTION 'MULTI04 owner has unrelated privileges';
    END IF;
END;
$contract$;
SELECT 'PASS: fresh roots, RLS, effective ACLs and limited helper owner' AS result;

-- The local migration administrator is not superuser and deliberately does
-- not inherit the new owner. Elevate explicitly for rollback-only fixtures.
SET LOCAL ROLE rotero_company_access_owner;
DO $temporary_fixture_acl$
BEGIN
    EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access TO %I', SESSION_USER);
END;
$temporary_fixture_acl$;
RESET ROLE;

DO $fixtures$
DECLARE t uuid; x uuid; a uuid; b uuid; c uuid; u uuid := gen_random_uuid();
    f uuid := gen_random_uuid(); stranger uuid := gen_random_uuid(); x_user uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.tenants(name,slug) VALUES ('MULTI04 synthetic A','multi04-' || gen_random_uuid()) RETURNING id INTO t;
    INSERT INTO public.tenants(name,slug) VALUES ('MULTI04 synthetic X','multi04-' || gen_random_uuid()) RETURNING id INTO x;
    INSERT INTO public.memberships(user_id,tenant_id,role) VALUES
        (u,t,'admin'), (f,t,'finance'), (stranger,t,'admin'), (x_user,x,'finance');
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES (t,'Synthetic A','Synthetic legal A','AAA010101AA1','active') RETURNING id INTO a;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES (t,'Synthetic B','Synthetic legal B','BBB010101BB1','active') RETURNING id INTO b;
    -- Same RFC in another tenant is allowed; identity remains tenant scoped.
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES (x,'Synthetic X','Synthetic legal X','AAA010101AA1','active') RETURNING id INTO c;
    PERFORM set_config('multi04.tenant',t::text,true);
    PERFORM set_config('multi04.other_tenant',x::text,true);
    PERFORM set_config('multi04.a',a::text,true);
    PERFORM set_config('multi04.b',b::text,true);
    PERFORM set_config('multi04.x',c::text,true);
    PERFORM set_config('multi04.admin',u::text,true);
    PERFORM set_config('multi04.finance',f::text,true);
    PERFORM set_config('multi04.stranger',stranger::text,true);
    PERFORM set_config('multi04.other_user',x_user::text,true);
END;
$fixtures$;

DO $integrity$
DECLARE t uuid := current_setting('multi04.tenant')::uuid;
    a uuid := current_setting('multi04.a')::uuid;
    u uuid := current_setting('multi04.admin')::uuid; original_id uuid;
BEGIN
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (%L,''dup'',''dup'',''AAA010101AA1'')',t),'23505');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (%L,''invalid'',''invalid'',''invalid-rfc'')',t),'23514');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (%L,'' '',''invalid'',''CCC010101CC1'')',t),'23514');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (%L,''bad tenant'',''bad tenant'',''CCC010101CC1'')',gen_random_uuid()),'23503');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',t,u,current_setting('multi04.x'),u),'23503');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',t,current_setting('multi04.other_user'),a,u),'23503');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',t,gen_random_uuid(),a,u),'23503');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',t,u,gen_random_uuid(),u),'23503');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by,status) VALUES (%L,%L,%L,%L,''revoked'')',t,u,a,u),'23514');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by,valid_from,valid_until) VALUES (%L,%L,%L,%L,now(),now()-interval ''1 day'')',t,u,a,u),'23514');
    SELECT id INTO original_id FROM public.companies WHERE id = a;
    UPDATE public.companies SET display_name = 'Renamed synthetic A' WHERE id = a;
    IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = original_id AND display_name = 'Renamed synthetic A') THEN
        RAISE EXCEPTION 'MULTI04 display rename changed identity';
    END IF;
END;
$integrity$;
SELECT 'PASS: ten integrity/invalid-reference cases and editable display name' AS result;

SET LOCAL ROLE authenticated;
DO $default_denials$
DECLARE t uuid := current_setting('multi04.tenant')::uuid; a uuid := current_setting('multi04.a')::uuid; actor text;
BEGIN
    FOREACH actor IN ARRAY ARRAY[current_setting('multi04.admin'),current_setting('multi04.finance')] LOOP
        PERFORM pg_temp.multi04_set_actor(actor);
        PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated',
            'user_metadata',jsonb_build_object('financial_full',true,'company_id',a))::text,true);
        IF private.multi04_has_company_access(t,a) THEN
            RAISE EXCEPTION 'MULTI04 role/metadata granted access without assignment';
        END IF;
    END LOOP;
    PERFORM pg_temp.multi04_set_actor(NULL);
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 null identity allowed'; END IF;
END;
$default_denials$;
RESET ROLE;

INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
SELECT current_setting('multi04.tenant')::uuid,current_setting('multi04.admin')::uuid,
    current_setting('multi04.a')::uuid,current_setting('multi04.admin')::uuid;
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
SELECT current_setting('multi04.tenant')::uuid,current_setting('multi04.finance')::uuid,
    current_setting('multi04.b')::uuid,current_setting('multi04.admin')::uuid;

SELECT pg_temp.multi04_expect_error(format(
    'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',
    current_setting('multi04.tenant'),current_setting('multi04.admin'),current_setting('multi04.a'),current_setting('multi04.admin')),'23505');
SELECT pg_temp.multi04_expect_error(format(
    'UPDATE public.membership_company_access SET company_id=%L WHERE user_id=%L',
    current_setting('multi04.x'),current_setting('multi04.admin')),'23503');
SELECT pg_temp.multi04_expect_error(format(
    'UPDATE public.membership_company_access SET user_id=%L WHERE user_id=%L',
    current_setting('multi04.other_user'),current_setting('multi04.admin')),'23503');

SET LOCAL ROLE authenticated;
DO $explicit_access$
DECLARE t uuid := current_setting('multi04.tenant')::uuid;
    a uuid := current_setting('multi04.a')::uuid; b uuid := current_setting('multi04.b')::uuid;
BEGIN
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.admin'));
    IF NOT private.multi04_has_company_access(t,a) OR private.multi04_has_company_access(t,b)
       OR private.multi04_has_company_access(t,current_setting('multi04.x')::uuid)
       OR private.multi04_has_company_access(current_setting('multi04.other_tenant')::uuid,a)
       OR private.multi04_has_company_access(t,gen_random_uuid())
       OR private.multi04_has_company_access(NULL,a) OR private.multi04_has_company_access(t,NULL) THEN
        RAISE EXCEPTION 'MULTI04 explicit access or cross-scope denial failed';
    END IF;
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.finance'));
    IF NOT private.multi04_has_company_access(t,b) OR private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 finance explicit access failed';
    END IF;
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.stranger'));
    IF private.multi04_has_company_access(t,a) OR private.multi04_has_company_access(t,b) THEN
        RAISE EXCEPTION 'MULTI04 unassigned user allowed';
    END IF;
END;
$explicit_access$;

DO $subject_contract$
DECLARE u text := current_setting('multi04.admin');
    t uuid := current_setting('multi04.tenant')::uuid; a uuid := current_setting('multi04.a')::uuid;
BEGIN
    -- Modern JSON claims, legacy sub, precedence and missing identity must
    -- agree with the installed auth.uid(), without Auth schema privileges for
    -- the closed helper's owner. Never treat user_metadata as the subject.
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u)::text,true);
    IF auth.uid()::text <> u OR NOT private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 JSON subject contract failed';
    END IF;
    PERFORM set_config('request.jwt.claim.sub',u,true);
    PERFORM set_config('request.jwt.claims','{}',true);
    IF auth.uid()::text <> u OR NOT private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 legacy subject contract failed';
    END IF;
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('multi04.stranger'))::text,true);
    IF auth.uid()::text <> u OR NOT private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 subject precedence failed';
    END IF;
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('user_metadata',jsonb_build_object('sub',u))::text,true);
    IF auth.uid() IS NOT NULL OR private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 metadata impersonated subject';
    END IF;
    PERFORM set_config('request.jwt.claims','',true);
    IF auth.uid() IS NOT NULL OR private.multi04_has_company_access(t,a) THEN
        RAISE EXCEPTION 'MULTI04 empty claims allowed';
    END IF;
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.stranger'));
END;
$subject_contract$;

DO $closed_direct_paths$
DECLARE q text;
BEGIN
    FOREACH q IN ARRAY ARRAY[
        'SELECT * FROM public.companies',
        'SELECT id FROM public.companies',
        'SELECT * FROM public.membership_company_access',
        'SELECT to_jsonb(c) FROM public.companies AS c',
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (current_setting(''multi04.tenant'')::uuid,current_setting(''multi04.stranger'')::uuid,current_setting(''multi04.b'')::uuid,current_setting(''multi04.stranger'')::uuid)',
        'UPDATE public.membership_company_access SET tenant_id=current_setting(''multi04.other_tenant'')::uuid',
        'UPDATE public.membership_company_access SET status=''active'',revoked_at=NULL,revoked_by=NULL',
        'DELETE FROM public.membership_company_access',
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (current_setting(''multi04.tenant'')::uuid,''self'',''self'',''CCC010101CC1'')',
        'UPDATE public.companies SET tenant_id=current_setting(''multi04.other_tenant'')::uuid',
        'DELETE FROM public.companies',
        'TRUNCATE public.membership_company_access',
        'ALTER TABLE public.membership_company_access ADD COLUMN financial_full boolean DEFAULT true'
    ] LOOP
        PERFORM pg_temp.multi04_expect_error(q,'42501');
    END LOOP;
END;
$closed_direct_paths$;
RESET ROLE;
SELECT 'PASS: role defaults denied, explicit grants positive, cross-scope and 13 direct paths denied' AS result;

INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
SELECT current_setting('multi04.tenant')::uuid,current_setting('multi04.finance')::uuid,
    current_setting('multi04.a')::uuid,current_setting('multi04.admin')::uuid;
SET LOCAL ROLE authenticated;
DO $multiple_explicit_companies$
DECLARE t uuid := current_setting('multi04.tenant')::uuid;
BEGIN
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.finance'));
    IF NOT private.multi04_has_company_access(t,current_setting('multi04.a')::uuid)
       OR NOT private.multi04_has_company_access(t,current_setting('multi04.b')::uuid) THEN
        RAISE EXCEPTION 'MULTI04 multiple explicitly granted companies failed';
    END IF;
END;
$multiple_explicit_companies$;
RESET ROLE;

SET LOCAL ROLE anon;
SELECT pg_temp.multi04_expect_error('SELECT * FROM public.companies','42501');
SELECT pg_temp.multi04_expect_error('SELECT * FROM public.membership_company_access','42501');
SELECT pg_temp.multi04_expect_error('SELECT private.multi04_has_company_access(NULL,NULL)','42501');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.multi04_expect_error('SELECT * FROM public.companies','42501');
SELECT pg_temp.multi04_expect_error('SELECT * FROM public.membership_company_access','42501');
SELECT pg_temp.multi04_expect_error('SELECT private.multi04_has_company_access(NULL,NULL)','42501');
RESET ROLE;

-- Grant SELECT/DML only inside this rollback-only test to exercise policies,
-- independently of the production ACL (which was proved closed above).
SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access TO authenticated;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $rls$
DECLARE n integer; t uuid := current_setting('multi04.tenant')::uuid;
BEGIN
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.admin'));
    SELECT count(*) INTO n FROM public.companies;
    IF n <> 1 OR NOT EXISTS (SELECT 1 FROM public.companies WHERE id=current_setting('multi04.a')::uuid) THEN
        RAISE EXCEPTION 'MULTI04 company RLS did not scope explicit access';
    END IF;
    SELECT count(*) INTO n FROM public.membership_company_access;
    IF n <> 1 OR EXISTS (SELECT 1 FROM public.membership_company_access WHERE user_id<>auth.uid()) THEN
        RAISE EXCEPTION 'MULTI04 access-row RLS leaked another identity';
    END IF;
    UPDATE public.companies SET display_name='forbidden';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 0 THEN RAISE EXCEPTION 'MULTI04 write policy unexpectedly allows update'; END IF;
    DELETE FROM public.membership_company_access;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 0 THEN RAISE EXCEPTION 'MULTI04 write policy unexpectedly allows delete'; END IF;
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized) VALUES (%L,''self'',''self'',''CCC010101CC1'')',t),'42501');
    PERFORM pg_temp.multi04_expect_error(format(
        'INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES (%L,%L,%L,%L)',
        t,current_setting('multi04.admin'),current_setting('multi04.b'),current_setting('multi04.admin')),'42501');
    PERFORM pg_temp.multi04_set_actor(current_setting('multi04.stranger'));
    IF EXISTS (SELECT FROM public.companies) OR EXISTS (SELECT FROM public.membership_company_access) THEN
        RAISE EXCEPTION 'MULTI04 RLS allowed unassigned actor';
    END IF;
END;
$rls$;
RESET ROLE;
SET LOCAL ROLE rotero_company_access_owner;
REVOKE ALL ON TABLE public.companies,public.membership_company_access FROM authenticated;
RESET ROLE;
SELECT 'PASS: anonymous/service paths denied and RLS remains effective under temporary ACL grants' AS result;

DO $lifecycle$
DECLARE t uuid := current_setting('multi04.tenant')::uuid;
    a uuid := current_setting('multi04.a')::uuid; u uuid := current_setting('multi04.admin')::uuid;
BEGIN
    PERFORM pg_temp.multi04_set_actor(u::text);
    UPDATE public.companies SET status='inactive' WHERE id=a;
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 inactive company allowed'; END IF;
    UPDATE public.companies SET status='draft' WHERE id=a;
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 draft company allowed'; END IF;
    UPDATE public.companies SET status='active' WHERE id=a;
    UPDATE public.membership_company_access SET valid_from=now()+interval '1 day' WHERE company_id=a AND user_id=u;
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 future assignment allowed'; END IF;
    UPDATE public.membership_company_access SET valid_from=now()-interval '2 days',valid_until=now()-interval '1 day' WHERE company_id=a AND user_id=u;
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 expired assignment allowed'; END IF;
    UPDATE public.membership_company_access SET valid_until=NULL,status='revoked',revoked_at=now(),revoked_by=u WHERE company_id=a AND user_id=u;
    IF private.multi04_has_company_access(t,a) THEN RAISE EXCEPTION 'MULTI04 revoked assignment allowed'; END IF;
    PERFORM pg_temp.multi04_expect_error(format('DELETE FROM public.companies WHERE id=%L',a),'23503');
    PERFORM pg_temp.multi04_expect_error(format('DELETE FROM public.memberships WHERE user_id=%L AND tenant_id=%L',u,t),'23503');
END;
$lifecycle$;
SELECT 'PASS: company state, future/expired/revoked assignment and reference retention' AS result;
ROLLBACK;

-- Same connection after rollback: no fixture or temporary table grant survives.
DO $clean$
BEGIN
    IF EXISTS (SELECT FROM public.companies) OR EXISTS (SELECT FROM public.membership_company_access)
       OR EXISTS (SELECT FROM public.tenants WHERE slug LIKE 'multi04-%')
       OR pg_catalog.has_table_privilege('authenticated','public.companies','SELECT')
       OR pg_catalog.has_table_privilege('authenticated','public.membership_company_access','INSERT') THEN
        RAISE EXCEPTION 'MULTI04 test residue or temporary grants remain';
    END IF;
END;
$clean$;
SELECT 'PASS: rollback removed all synthetic roots, assignments and temporary grants' AS result;
