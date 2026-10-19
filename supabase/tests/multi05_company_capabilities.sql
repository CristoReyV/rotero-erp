\set ON_ERROR_STOP on
-- Disposable local database only. No Auth users or real principal assignments.
BEGIN;

CREATE FUNCTION pg_temp.m05_check(ok boolean,label text) RETURNS void
LANGUAGE plpgsql AS $test$
BEGIN
    IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MULTI05 failed: %',label; END IF;
END;
$test$;
CREATE FUNCTION pg_temp.m05_error(q text,expected text) RETURNS void
LANGUAGE plpgsql AS $test$
BEGIN
    BEGIN EXECUTE q;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE<>expected THEN RAISE EXCEPTION 'MULTI05 expected %, received %',expected,SQLSTATE; END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'MULTI05 expected %, statement succeeded',expected;
END;
$test$;
CREATE FUNCTION pg_temp.m05_actor(u uuid,issuer text DEFAULT 'https://synthetic-access.invalid/auth/v1') RETURNS void
LANGUAGE plpgsql AS $test$
BEGIN
    PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
    PERFORM set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object(
        'sub',u,'role','authenticated','iss',issuer,'user_metadata',jsonb_build_object(
            'financial_full',true,'principal_code','approved_financial_01','consolidated',true
        )))::text,true);
END;
$test$;
CREATE FUNCTION pg_temp.m05_cap(u uuid,c uuid,code text,b uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $test$
DECLARE result uuid;
BEGIN
    INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,
        financial_binding_id,approval_reference,granted_by)
    VALUES(current_setting('m05.t')::uuid,u,c,code,b,'synthetic-approval',current_setting('m05.admin')::uuid)
    RETURNING id INTO result;
    RETURN result;
END;
$test$;
CREATE FUNCTION pg_temp.m05_binding(u uuid,slot text) RETURNS uuid
LANGUAGE plpgsql AS $test$
DECLARE result uuid;
BEGIN
    INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,
        identity_issuer,approval_reference,verified_by,verified_at)
    VALUES(current_setting('m05.t')::uuid,u,slot,'verified_human','https://synthetic-access.invalid/auth/v1',
        'synthetic-identity-verification',current_setting('m05.admin')::uuid,now()-interval '1 minute')
    RETURNING id INTO result;
    RETURN result;
END;
$test$;
CREATE FUNCTION pg_temp.m05_consolidation(u uuid,b uuid) RETURNS uuid
LANGUAGE plpgsql AS $test$
DECLARE result uuid;
BEGIN
    INSERT INTO public.membership_consolidation_grants(tenant_id,user_id,financial_binding_id,approval_reference,granted_by)
    VALUES(current_setting('m05.t')::uuid,u,b,'synthetic-consolidation-approval',current_setting('m05.admin')::uuid)
    RETURNING id INTO result;
    RETURN result;
END;
$test$;
CREATE FUNCTION pg_temp.m05_scope(u uuid,g uuid,c uuid) RETURNS void
LANGUAGE plpgsql AS $test$
BEGIN
    INSERT INTO public.consolidation_grant_companies(tenant_id,user_id,consolidation_grant_id,company_id)
    VALUES(current_setting('m05.t')::uuid,u,g,c);
END;
$test$;

DO $contract$
DECLARE rel text; role_name text; privilege text; fn text; owner_id oid;
BEGIN
    SELECT oid INTO STRICT owner_id FROM pg_catalog.pg_roles WHERE rolname='rotero_company_access_owner'
        AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolbypassrls
        AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolreplication;
    FOREACH rel IN ARRAY ARRAY['private.financial_principal_bindings','public.membership_company_capabilities',
        'public.membership_consolidation_grants','public.consolidation_grant_companies'] LOOP
        PERFORM pg_temp.m05_check(EXISTS(SELECT FROM pg_class WHERE oid=rel::regclass
            AND relowner=owner_id AND relrowsecurity),'limited owner and RLS');
        PERFORM pg_temp.m05_check(NOT EXISTS(SELECT FROM pg_policy WHERE polrelid=rel::regclass),'no client policies');
        FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
                PERFORM pg_temp.m05_check(NOT has_table_privilege(role_name,rel,privilege),'no effective table privilege');
            END LOOP;
            PERFORM pg_temp.m05_check(NOT has_any_column_privilege(role_name,rel,'SELECT,INSERT,UPDATE,REFERENCES'),
                'no effective column privilege');
            PERFORM pg_temp.m05_check(NOT pg_has_role(role_name,owner_id,'MEMBER'),'cannot assume owner');
        END LOOP;
    END LOOP;
    FOREACH fn IN ARRAY ARRAY['private.multi05_request_actor()',
        'private.multi05_has_company_capability(uuid,uuid,text)','private.multi05_can_consolidate(uuid,uuid[])'] LOOP
        PERFORM pg_temp.m05_check(EXISTS(SELECT FROM pg_proc WHERE oid=fn::regprocedure
            AND proowner=owner_id AND provolatile='s' AND proconfig @> ARRAY['search_path=""']),
            'function owner, stability and empty path');
        PERFORM pg_temp.m05_check(NOT EXISTS(SELECT FROM pg_proc p,
            LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
            WHERE p.oid=fn::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE'),'no PUBLIC execute');
        FOREACH role_name IN ARRAY ARRAY['anon','service_role'] LOOP
            PERFORM pg_temp.m05_check(NOT has_function_privilege(role_name,fn,'EXECUTE'),'no technical/anonymous execute');
        END LOOP;
        PERFORM pg_temp.m05_check(has_function_privilege('authenticated',fn,'EXECUTE')=
            (fn<>'private.multi05_request_actor()'),'only two authenticated boolean helpers');
    END LOOP;
    PERFORM pg_temp.m05_check(NOT (SELECT prosecdef FROM pg_proc WHERE oid='private.multi05_request_actor()'::regprocedure)
        AND (SELECT prosecdef FROM pg_proc WHERE oid='private.multi05_has_company_capability(uuid,uuid,text)'::regprocedure)
        AND (SELECT prosecdef FROM pg_proc WHERE oid='private.multi05_can_consolidate(uuid,uuid[])'::regprocedure),
        'invoker parser and limited definer checks');
    PERFORM pg_temp.m05_check(NOT has_table_privilege('rotero_company_access_owner','public.memberships','SELECT')
        AND NOT has_table_privilege('rotero_company_access_owner','public.finance_invoices','SELECT')
        AND NOT has_schema_privilege('rotero_company_access_owner','public','CREATE')
        AND NOT has_schema_privilege('rotero_company_access_owner','private','CREATE'),'owner not expanded to business/schema writes');
    PERFORM pg_temp.m05_check(NOT EXISTS(SELECT FROM private.financial_principal_bindings)
        AND NOT EXISTS(SELECT FROM public.membership_company_capabilities)
        AND NOT EXISTS(SELECT FROM public.membership_consolidation_grants)
        AND NOT EXISTS(SELECT FROM public.consolidation_grant_companies),'fresh unpopulated model');
END;
$contract$;
SELECT 'PASS: effective table/column/function ACLs, RLS, owner and empty roots';

-- Explicit test-only DML: migration postgres does not inherit the owner.
SET LOCAL ROLE rotero_company_access_owner;
DO $fixture_acl$
BEGIN
    EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
        private.financial_principal_bindings,public.membership_company_capabilities,
        public.membership_consolidation_grants,public.consolidation_grant_companies TO %I',SESSION_USER);
END;
$fixture_acl$;
RESET ROLE;

DO $fixtures$
DECLARE t uuid; x uuid; a uuid; b uuid; xc uuid; u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid();
    adm uuid:=gen_random_uuid(); fin uuid:=gen_random_uuid(); qa uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
BEGIN
    INSERT INTO public.tenants(name,slug) VALUES('MULTI05 synthetic','multi05-'||gen_random_uuid()) RETURNING id INTO t;
    INSERT INTO public.tenants(name,slug) VALUES('MULTI05 other synthetic','multi05-'||gen_random_uuid()) RETURNING id INTO x;
    INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(v,t,'admin'),(adm,t,'admin'),
        (fin,t,'finance'),(qa,t,'finance'),(outsider,x,'finance');
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
    INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
        VALUES(t,u,a,adm),(t,u,b,adm),(t,v,a,adm),(t,adm,a,adm),(t,fin,a,adm),(t,qa,a,adm),(x,outsider,xc,outsider);
    PERFORM set_config('m05.t',t::text,true); PERFORM set_config('m05.x',x::text,true);
    PERFORM set_config('m05.a',a::text,true); PERFORM set_config('m05.b',b::text,true); PERFORM set_config('m05.xc',xc::text,true);
    PERFORM set_config('m05.u',u::text,true); PERFORM set_config('m05.v',v::text,true);
    PERFORM set_config('m05.admin',adm::text,true); PERFORM set_config('m05.finance',fin::text,true);
    PERFORM set_config('m05.qa',qa::text,true); PERFORM set_config('m05.outsider',outsider::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;
DO $defaults$
DECLARE u uuid; t uuid:=current_setting('m05.t')::uuid; a uuid:=current_setting('m05.a')::uuid;
BEGIN
    FOREACH u IN ARRAY ARRAY[current_setting('m05.u')::uuid,current_setting('m05.admin')::uuid,
        current_setting('m05.finance')::uuid,current_setting('m05.qa')::uuid] LOOP
        PERFORM pg_temp.m05_actor(u);
        PERFORM pg_temp.m05_check(private.multi04_has_company_access(t,a),'company access exists');
        PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'operations.read')
            AND NOT private.multi05_has_company_capability(t,a,'financial.full.read')
            AND NOT private.multi05_can_consolidate(t,ARRAY[a]),'access/role/metadata grants no capabilities');
    END LOOP;
    PERFORM pg_temp.m05_actor(NULL);
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a]),'no subject denied');
END;
$defaults$;
RESET ROLE;

SELECT pg_temp.m05_cap(current_setting('m05.u')::uuid,current_setting('m05.a')::uuid,'operations.read') IS NOT NULL;
DO $integrity$
DECLARE u uuid:=current_setting('m05.u')::uuid; v uuid:=current_setting('m05.v')::uuid;
    a uuid:=current_setting('m05.a')::uuid; b uuid; b2 uuid;
BEGIN
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''financial.full.read'')',u,a),'23514');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''all'')',u,a),'23514');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''operations.read'')',u,a),'23505');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''operations.read'')',u,current_setting('m05.xc')),'23503');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''operations.read'')',current_setting('m05.outsider'),a),'23503');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_binding(%L,''approved_financial_01'')',gen_random_uuid()),'23503');
    b:=pg_temp.m05_binding(u,'approved_financial_01'); b2:=pg_temp.m05_binding(v,'approved_financial_02');
    PERFORM set_config('m05.binding',b::text,true); PERFORM set_config('m05.binding2',b2::text,true);
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_binding(%L,''approved_financial_01'')',current_setting('m05.admin')),'23505');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_binding(%L,''approved_financial_03'')',u),'23505');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_binding(%L,''fourth_principal'')',current_setting('m05.admin')),'23514');
    PERFORM pg_temp.m05_error(format('UPDATE private.financial_principal_bindings SET identity_kind=''qa'' WHERE id=%L',b),'23514');
    PERFORM pg_temp.m05_error(format('UPDATE private.financial_principal_bindings SET approval_reference='' '' WHERE id=%L',b),'23514');
    PERFORM pg_temp.m05_error(format('UPDATE private.financial_principal_bindings SET identity_issuer=''http://unverified.invalid'' WHERE id=%L',b),'23514');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''financial.full.read'',%L)',u,a,b2),'23503');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''operations.capture'',%L)',u,a,b),'23514');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_cap(%L,%L,''financial.full.read'',%L)',u,a,gen_random_uuid()),'23503');
END;
$integrity$;
SELECT 'PASS: access without capability; role/QA/metadata denials; binding, capability and tenant integrity';

SELECT pg_temp.m05_cap(current_setting('m05.u')::uuid,current_setting('m05.a')::uuid,
    'financial.full.read',current_setting('m05.binding')::uuid) IS NOT NULL;
SELECT pg_temp.m05_cap(current_setting('m05.u')::uuid,current_setting('m05.b')::uuid,
    'export.financial',current_setting('m05.binding')::uuid) IS NOT NULL;
SET LOCAL ROLE authenticated;
DO $individual$
DECLARE t uuid:=current_setting('m05.t')::uuid; a uuid:=current_setting('m05.a')::uuid; b uuid:=current_setting('m05.b')::uuid;
BEGIN
    PERFORM pg_temp.m05_actor(current_setting('m05.u')::uuid);
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(t,a,'operations.read')
        AND NOT private.multi05_has_company_capability(t,a,'operations.capture'),'only explicit work action');
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_has_company_capability(t,b,'financial.full.read')
        AND NOT private.multi05_has_company_capability(t,b,'export.financial')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a]),'individual financial read does not consolidate/export');
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM pg_temp.m05_check(auth.uid()=current_setting('m05.u')::uuid
        AND private.multi05_has_company_capability(t,a,'financial.full.read'),'JSON-only subject agrees with auth.uid');
    PERFORM set_config('request.jwt.claim.sub',current_setting('m05.u'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('m05.v'),
        'iss','https://synthetic-access.invalid/auth/v1')::text,true);
    PERFORM pg_temp.m05_check(auth.uid()=current_setting('m05.u')::uuid
        AND private.multi05_has_company_capability(t,a,'financial.full.read'),'legacy subject precedence agrees with auth.uid');
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('iss','https://synthetic-access.invalid/auth/v1',
        'user_metadata',jsonb_build_object('sub',current_setting('m05.u')))::text,true);
    PERFORM pg_temp.m05_check(auth.uid() IS NULL AND NOT private.multi05_has_company_capability(t,a,'financial.full.read'),
        'metadata never supplies the subject');
    PERFORM pg_temp.m05_actor(current_setting('m05.u')::uuid);
END;
$individual$;
RESET ROLE;
SELECT set_config('m05.grant',pg_temp.m05_consolidation(current_setting('m05.u')::uuid,
    current_setting('m05.binding')::uuid)::text,true) IS NOT NULL;
SELECT pg_temp.m05_scope(current_setting('m05.u')::uuid,current_setting('m05.grant')::uuid,current_setting('m05.a')::uuid);
SELECT pg_temp.m05_error(format('SELECT pg_temp.m05_scope(%L,%L,%L)',current_setting('m05.u'),
    current_setting('m05.grant'),current_setting('m05.b')),'23503');
SELECT pg_temp.m05_cap(current_setting('m05.u')::uuid,current_setting('m05.b')::uuid,
    'financial.full.read',current_setting('m05.binding')::uuid) IS NOT NULL;
SET LOCAL ROLE authenticated;
DO $explicit_scope$
DECLARE t uuid:=current_setting('m05.t')::uuid; a uuid:=current_setting('m05.a')::uuid; b uuid:=current_setting('m05.b')::uuid;
BEGIN
    PERFORM pg_temp.m05_check(private.multi05_can_consolidate(t,ARRAY[a])
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'scope does not expand with full read');
END;
$explicit_scope$;
RESET ROLE;
SELECT pg_temp.m05_scope(current_setting('m05.u')::uuid,current_setting('m05.grant')::uuid,current_setting('m05.b')::uuid);

SET LOCAL ROLE authenticated;
DO $consolidated$
DECLARE t uuid:=current_setting('m05.t')::uuid; x uuid:=current_setting('m05.x')::uuid;
    a uuid:=current_setting('m05.a')::uuid; b uuid:=current_setting('m05.b')::uuid; xc uuid:=current_setting('m05.xc')::uuid;
BEGIN
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(t,b,'export.financial')
        AND private.multi05_can_consolidate(t,ARRAY[a,b]) AND private.multi05_can_consolidate(t,ARRAY[b,a])
        AND private.multi05_can_consolidate(t,ARRAY[b]),'explicit financial, export and consolidated sets positive');
    PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,NULL)
        AND NOT private.multi05_can_consolidate(t,ARRAY[]::uuid[])
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,a])
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,NULL])
        AND NOT private.multi05_can_consolidate(t,ARRAY[ARRAY[a,b]])
        AND NOT private.multi05_can_consolidate(t,array_fill(a,ARRAY[1],ARRAY[0]))
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,xc])
        AND NOT private.multi05_can_consolidate(x,ARRAY[a,b])
        AND NOT private.multi05_can_consolidate(t,ARRAY[gen_random_uuid()]),'invalid/cross-tenant scope rejected atomically');
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,xc,'financial.full.read')
        AND NOT private.multi05_has_company_capability(x,a,'financial.full.read')
        AND NOT private.multi05_has_company_capability(t,NULL,'financial.full.read')
        AND NOT private.multi05_has_company_capability(NULL,a,'financial.full.read')
        AND NOT private.multi05_has_company_capability(t,a,NULL)
        AND NOT private.multi05_has_company_capability(t,a,'consolidated.read'),'identifier/code manipulation denied');
    PERFORM pg_temp.m05_actor(current_setting('m05.v')::uuid);
    PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'another actor cannot reuse the set');
    PERFORM pg_temp.m05_actor(current_setting('m05.u')::uuid);
    PERFORM pg_temp.m05_error('SELECT * FROM private.multi05_request_actor()','42501');
END;
$consolidated$;
RESET ROLE;

DO $scope_integrity$
DECLARE u uuid:=current_setting('m05.u')::uuid; g uuid:=current_setting('m05.grant')::uuid;
    a uuid:=current_setting('m05.a')::uuid;
BEGIN
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_scope(%L,%L,%L)',u,g,a),'23505');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_scope(%L,%L,%L)',u,g,current_setting('m05.xc')),'23503');
    PERFORM pg_temp.m05_error(format('UPDATE public.consolidation_grant_companies SET user_id=%L WHERE consolidation_grant_id=%L',current_setting('m05.v'),g),'23503');
    PERFORM pg_temp.m05_error(format('UPDATE public.membership_consolidation_grants SET financial_binding_id=%L WHERE id=%L',current_setting('m05.binding2'),g),'23503');
    PERFORM pg_temp.m05_error(format('UPDATE public.membership_consolidation_grants SET tenant_id=%L WHERE id=%L',current_setting('m05.x'),g),'23503');
    PERFORM pg_temp.m05_error(format('UPDATE public.consolidation_grant_companies SET required_capability=''operations.read'' WHERE consolidation_grant_id=%L',g),'23514');
    PERFORM pg_temp.m05_error(format('UPDATE public.membership_company_capabilities SET company_id=%L WHERE user_id=%L AND capability_code=''operations.read''',current_setting('m05.xc'),u),'23503');
    PERFORM pg_temp.m05_error(format('UPDATE public.membership_company_capabilities SET valid_until=valid_from WHERE user_id=%L',u),'23514');
    PERFORM pg_temp.m05_error(format('UPDATE public.membership_consolidation_grants SET status=''revoked'' WHERE id=%L',g),'23514');
END;
$scope_integrity$;
SELECT 'PASS: individual vs consolidated grants, full set authorization, invalid arrays and cross-actor/tenant references';

-- A company created later does not inherit a consolidated grant, even after
-- separately approved company access and full financial permission.
DO $new_company$
DECLARE t uuid:=current_setting('m05.t')::uuid; u uuid:=current_setting('m05.u')::uuid; c uuid;
BEGIN
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
        VALUES(t,'C','Synthetic later C','CCC010101CC1','active') RETURNING id INTO c;
    INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
        VALUES(t,u,c,current_setting('m05.admin')::uuid);
    PERFORM pg_temp.m05_cap(u,c,'financial.full.read',current_setting('m05.binding')::uuid);
    PERFORM set_config('m05.c',c::text,true);
END;
$new_company$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m05_check(private.multi05_has_company_capability(current_setting('m05.t')::uuid,
    current_setting('m05.c')::uuid,'financial.full.read') AND NOT private.multi05_can_consolidate(
    current_setting('m05.t')::uuid,ARRAY[current_setting('m05.a')::uuid,current_setting('m05.c')::uuid]),'new company never expands set');

DO $direct_paths$
DECLARE rel text; q text;
BEGIN
    FOREACH rel IN ARRAY ARRAY['private.financial_principal_bindings','public.membership_company_capabilities',
        'public.membership_consolidation_grants','public.consolidation_grant_companies'] LOOP
        PERFORM pg_temp.m05_error('SELECT * FROM '||rel,'42501');
        PERFORM pg_temp.m05_error('SELECT to_jsonb(r) FROM '||rel||' r','42501');
        PERFORM pg_temp.m05_error('DELETE FROM '||rel,'42501');
        PERFORM pg_temp.m05_error('TRUNCATE '||rel,'42501');
        PERFORM pg_temp.m05_error('ALTER TABLE '||rel||' ADD COLUMN self_approved boolean DEFAULT true','42501');
    END LOOP;
    FOREACH q IN ARRAY ARRAY[
        'SELECT pg_temp.m05_binding(current_setting(''m05.qa'')::uuid,''approved_financial_03'')',
        'SELECT pg_temp.m05_cap(current_setting(''m05.qa'')::uuid,current_setting(''m05.a'')::uuid,''operations.read'')',
        'SELECT pg_temp.m05_consolidation(current_setting(''m05.u'')::uuid,current_setting(''m05.binding'')::uuid)',
        'SELECT pg_temp.m05_scope(current_setting(''m05.u'')::uuid,current_setting(''m05.grant'')::uuid,current_setting(''m05.c'')::uuid)',
        'UPDATE private.financial_principal_bindings SET user_id=current_setting(''m05.qa'')::uuid',
        'UPDATE public.membership_company_capabilities SET capability_code=''financial.full.read'',financial_binding_id=current_setting(''m05.binding'')::uuid',
        'UPDATE public.membership_company_capabilities SET tenant_id=current_setting(''m05.x'')::uuid',
        'UPDATE public.membership_consolidation_grants SET financial_binding_id=current_setting(''m05.binding2'')::uuid',
        'UPDATE public.consolidation_grant_companies SET company_id=current_setting(''m05.xc'')::uuid'
    ] LOOP
        PERFORM pg_temp.m05_error(q,'42501');
    END LOOP;
END;
$direct_paths$;
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.m05_error('SELECT private.multi05_has_company_capability(NULL,NULL,NULL)','42501');
SELECT pg_temp.m05_error('SELECT private.multi05_can_consolidate(NULL,NULL)','42501');
SELECT pg_temp.m05_error('SELECT * FROM private.multi05_request_actor()','42501');
SELECT pg_temp.m05_error('SELECT * FROM public.membership_company_capabilities','42501');
SELECT pg_temp.m05_error('SELECT * FROM private.financial_principal_bindings','42501');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.m05_error('SELECT private.multi05_has_company_capability(NULL,NULL,NULL)','42501');
SELECT pg_temp.m05_error('SELECT private.multi05_can_consolidate(NULL,NULL)','42501');
SELECT pg_temp.m05_error('SELECT * FROM private.multi05_request_actor()','42501');
SELECT pg_temp.m05_error('SELECT * FROM public.membership_company_capabilities','42501');
SELECT pg_temp.m05_error('SELECT * FROM private.financial_principal_bindings','42501');
RESET ROLE;

SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.financial_principal_bindings,public.membership_company_capabilities,
    public.membership_consolidation_grants,public.consolidation_grant_companies TO authenticated;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $rls$
DECLARE rel text; n integer;
BEGIN
    FOREACH rel IN ARRAY ARRAY['private.financial_principal_bindings','public.membership_company_capabilities',
        'public.membership_consolidation_grants','public.consolidation_grant_companies'] LOOP
        EXECUTE 'SELECT count(*) FROM '||rel INTO n;
        PERFORM pg_temp.m05_check(n=0,'RLS hides even own grant/binding rows');
        EXECUTE 'UPDATE '||rel||' SET tenant_id=tenant_id'; GET DIAGNOSTICS n=ROW_COUNT;
        PERFORM pg_temp.m05_check(n=0,'no RLS update');
        EXECUTE 'DELETE FROM '||rel; GET DIAGNOSTICS n=ROW_COUNT;
        PERFORM pg_temp.m05_check(n=0,'no RLS delete');
    END LOOP;
    PERFORM pg_temp.m05_error('SELECT pg_temp.m05_binding(current_setting(''m05.qa'')::uuid,''approved_financial_03'')','42501');
    PERFORM pg_temp.m05_error('SELECT pg_temp.m05_cap(current_setting(''m05.qa'')::uuid,current_setting(''m05.a'')::uuid,''operations.read'')','42501');
    PERFORM pg_temp.m05_error('SELECT pg_temp.m05_consolidation(current_setting(''m05.u'')::uuid,current_setting(''m05.binding'')::uuid)','42501');
    PERFORM pg_temp.m05_error('SELECT pg_temp.m05_scope(current_setting(''m05.u'')::uuid,current_setting(''m05.grant'')::uuid,current_setting(''m05.c'')::uuid)','42501');
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(current_setting('m05.t')::uuid,
        current_setting('m05.a')::uuid,'financial.full.read'),'closed RLS does not recurse/block boolean check');
END;
$rls$;
RESET ROLE;
SET LOCAL ROLE rotero_company_access_owner;
REVOKE ALL ON TABLE private.financial_principal_bindings,public.membership_company_capabilities,
    public.membership_consolidation_grants,public.consolidation_grant_companies FROM authenticated;
RESET ROLE;
SELECT 'PASS: direct reads/writes/escalation denied; anon/service denied; independent RLS under temporary grants';

DO $revocation$
DECLARE t uuid:=current_setting('m05.t')::uuid; u uuid:=current_setting('m05.u')::uuid;
    a uuid:=current_setting('m05.a')::uuid; b uuid:=current_setting('m05.b')::uuid;
    binding uuid:=current_setting('m05.binding')::uuid; g uuid:=current_setting('m05.grant')::uuid;
    pred text;
BEGIN
    -- Same request identity throughout: server rows, not refreshed JWT metadata.
    PERFORM pg_temp.m05_actor(u);
    UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=u
        WHERE user_id=u AND company_id=a AND capability_code='financial.full.read';
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,b]) AND private.multi05_can_consolidate(t,ARRAY[b])
        AND private.multi05_has_company_capability(t,a,'operations.read'),'financial revocation is separate and effective');
    UPDATE public.membership_company_capabilities SET status='active',revoked_at=NULL,revoked_by=NULL,
        valid_from=now()+interval '1 day' WHERE user_id=u AND company_id=a AND capability_code='financial.full.read';
    PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'future capability denied');
    UPDATE public.membership_company_capabilities SET valid_from=now()-interval '2 days',valid_until=now()-interval '1 day'
        WHERE user_id=u AND company_id=a AND capability_code='financial.full.read';
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read'),'expired capability denied');
    UPDATE public.membership_company_capabilities SET valid_from=now()-interval '1 day',valid_until=NULL
        WHERE user_id=u AND company_id=a AND capability_code='financial.full.read';
    UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=u
        WHERE user_id=u AND company_id=b AND capability_code='financial.full.read';
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,b,'export.financial'),'export needs current full read');
    UPDATE public.membership_company_capabilities SET status='active',revoked_at=NULL,revoked_by=NULL
        WHERE user_id=u AND company_id=b AND capability_code='financial.full.read';

    FOREACH pred IN ARRAY ARRAY[
        'status=''revoked'',revoked_at=now(),revoked_by=user_id',
        'valid_from=now()+interval ''1 day''',
        'valid_from=now()-interval ''2 days'',valid_until=now()-interval ''1 day'''
    ] LOOP
        EXECUTE format('UPDATE public.membership_consolidation_grants SET %s WHERE id=%L',pred,g);
        PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,ARRAY[a,b])
            AND private.multi05_has_company_capability(t,a,'financial.full.read'),'grant revocation/validity does not revoke individual');
        UPDATE public.membership_consolidation_grants SET status='active',revoked_at=NULL,revoked_by=NULL,
            valid_from=now()-interval '1 day',valid_until=NULL WHERE id=g;
    END LOOP;
    FOREACH pred IN ARRAY ARRAY[
        'status=''revoked'',revoked_at=now(),revoked_by=user_id',
        'verified_at=now()+interval ''1 day''',
        'valid_from=now()+interval ''1 day''',
        'valid_from=now()-interval ''2 days'',valid_until=now()-interval ''1 day'''
    ] LOOP
        EXECUTE format('UPDATE private.financial_principal_bindings SET %s WHERE id=%L',pred,binding);
        PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read')
            AND NOT private.multi05_can_consolidate(t,ARRAY[a,b])
            AND private.multi05_has_company_capability(t,a,'operations.read'),'binding revocation/validity; work separate');
        UPDATE private.financial_principal_bindings SET status='active',revoked_at=NULL,revoked_by=NULL,
            verified_at=now()-interval '1 day',valid_from=now()-interval '1 day',valid_until=NULL WHERE id=binding;
    END LOOP;
    PERFORM pg_temp.m05_actor(u,'https://wrong-issuer.invalid/auth/v1');
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,b])
        AND private.multi05_has_company_capability(t,a,'operations.read'),'issuer pinning, metadata cannot bypass');
    PERFORM pg_temp.m05_actor(u,NULL);
    PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'missing issuer denied');
    PERFORM pg_temp.m05_actor(u);

    FOREACH pred IN ARRAY ARRAY['inactive','draft'] LOOP
        UPDATE public.companies SET status=pred WHERE id=a;
        PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'operations.read')
            AND NOT private.multi05_has_company_capability(t,a,'financial.full.read')
            AND NOT private.multi05_can_consolidate(t,ARRAY[a,b]) AND private.multi05_can_consolidate(t,ARRAY[b]),
            'company state immediately restricts affected set');
    END LOOP;
    UPDATE public.companies SET status='active' WHERE id=a;
    FOREACH pred IN ARRAY ARRAY[
        'status=''revoked'',revoked_at=now(),revoked_by=user_id',
        'valid_from=now()+interval ''1 day''',
        'valid_from=now()-interval ''2 days'',valid_until=now()-interval ''1 day'''
    ] LOOP
        EXECUTE format('UPDATE public.membership_company_access SET %s WHERE tenant_id=%L AND user_id=%L AND company_id=%L',pred,t,u,a);
        PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'operations.read')
            AND NOT private.multi05_has_company_capability(t,a,'financial.full.read')
            AND NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'access removal/expiry dominates every capability');
        UPDATE public.membership_company_access SET status='active',revoked_at=NULL,revoked_by=NULL,
            valid_from=now()-interval '1 day',valid_until=NULL WHERE tenant_id=t AND user_id=u AND company_id=a;
    END LOOP;
    PERFORM pg_temp.m05_check(private.multi05_can_consolidate(t,ARRAY[a,b]),'explicit active graph restored');
END;
$revocation$;
SELECT 'PASS: capability, binding, issuer, company, access and consolidation revocation/validity';

DO $binding_rotation$
DECLARE t uuid:=current_setting('m05.t')::uuid; u uuid:=current_setting('m05.u')::uuid;
    a uuid:=current_setting('m05.a')::uuid; b uuid:=current_setting('m05.b')::uuid;
    old_binding uuid:=current_setting('m05.binding')::uuid; replacement uuid;
BEGIN
    UPDATE private.financial_principal_bindings SET status='revoked',revoked_at=now(),revoked_by=u WHERE id=old_binding;
    replacement:=pg_temp.m05_binding(u,'approved_financial_01');
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'financial.full.read'),
        'new verified binding never revives old financial grants');
    UPDATE public.membership_company_capabilities SET financial_binding_id=replacement
        WHERE tenant_id=t AND user_id=u AND capability_code='financial.full.read';
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a,b]),'individual reapproval does not revive consolidation');
    UPDATE public.membership_consolidation_grants SET financial_binding_id=replacement WHERE tenant_id=t AND user_id=u;
    PERFORM pg_temp.m05_check(private.multi05_can_consolidate(t,ARRAY[a,b])
        AND NOT private.multi05_has_company_capability(t,b,'export.financial'),'consolidation reapproval separate from export');
    UPDATE public.membership_company_capabilities SET financial_binding_id=replacement
        WHERE tenant_id=t AND user_id=u AND capability_code='export.financial';
    PERFORM pg_temp.m05_check(private.multi05_has_company_capability(t,b,'export.financial'),'explicit export reapproval positive');
    DELETE FROM public.consolidation_grant_companies WHERE user_id=u AND company_id=a;
    PERFORM pg_temp.m05_check(NOT private.multi05_can_consolidate(t,ARRAY[a,b])
        AND private.multi05_can_consolidate(t,ARRAY[b]) AND private.multi05_has_company_capability(t,a,'financial.full.read'),
        'removing a company from grant does not broaden/erase other permissions');
END;
$binding_rotation$;
SELECT 'PASS: replacement binding, reapproval boundaries and explicit scope removal';

DO $membership_loss$
DECLARE t uuid:=current_setting('m05.t')::uuid; u uuid:=current_setting('m05.u')::uuid; a uuid:=current_setting('m05.a')::uuid;
BEGIN
    PERFORM pg_temp.m05_error(format('DELETE FROM public.memberships WHERE tenant_id=%L AND user_id=%L',t,u),'23503');
    -- The established RESTRICT contract forbids orphans. Simulate authorized
    -- dependency-aware retirement only on these rollback-only synthetic rows.
    DELETE FROM public.consolidation_grant_companies WHERE tenant_id=t AND user_id=u;
    DELETE FROM public.membership_consolidation_grants WHERE tenant_id=t AND user_id=u;
    DELETE FROM public.membership_company_capabilities WHERE tenant_id=t AND user_id=u;
    DELETE FROM private.financial_principal_bindings WHERE tenant_id=t AND user_id=u;
    DELETE FROM public.membership_company_access WHERE tenant_id=t AND user_id=u;
    DELETE FROM public.memberships WHERE tenant_id=t AND user_id=u;
    PERFORM pg_temp.m05_check(NOT private.multi05_has_company_capability(t,a,'operations.read')
        AND NOT private.multi05_has_company_capability(t,a,'financial.full.read')
        AND NOT private.multi05_can_consolidate(t,ARRAY[a]),'same claims after loss of membership denied');
    PERFORM pg_temp.m05_error(format('SELECT pg_temp.m05_binding(%L,''approved_financial_01'')',u),'23503');
END;
$membership_loss$;
SELECT 'PASS: membership removal cannot orphan grants; actual synthetic retirement leaves no authorization';
ROLLBACK;

DO $clean$
BEGIN
    IF EXISTS(SELECT FROM private.financial_principal_bindings)
        OR EXISTS(SELECT FROM public.membership_company_capabilities)
        OR EXISTS(SELECT FROM public.membership_consolidation_grants)
        OR EXISTS(SELECT FROM public.consolidation_grant_companies)
        OR EXISTS(SELECT FROM public.companies) OR EXISTS(SELECT FROM public.membership_company_access)
        OR EXISTS(SELECT FROM public.tenants WHERE slug LIKE 'multi05-%')
        OR has_table_privilege('authenticated','public.membership_company_capabilities','SELECT,INSERT')
        OR has_table_privilege('authenticated','private.financial_principal_bindings','SELECT,INSERT') THEN
        RAISE EXCEPTION 'MULTI05 fixtures or temporary application grants remain after rollback';
    END IF;
END;
$clean$;
SELECT 'PASS: rollback cleanup';
