-- MULTI-08 selective prerequisite from MULTI-06 commit 4a61ce2acbdd50d4fe6a481b62d0cdd38dbe5d95.
-- New version after the applied fiscal delta; original worktree/version preserved.
-- MULTI-06 preparation only: legacy APIs remain unchanged; new APIs stay closed.
BEGIN;
-- CIERRE02_RECONCILIATION_BEGIN
-- A45 and the observed B catalog are the only reviewed entry states.
SET LOCAL search_path=pg_catalog;
DO $c02_fence$ DECLARE v text;BEGIN
WITH snapshot(payload) AS (SELECT json_build_object(
 'functions',(SELECT json_agg(x ORDER BY x.schema,x.name,x.input_types) FROM (
  SELECT n.nspname schema,p.proname name,oidvectortypes(p.proargtypes) input_types,
  pg_get_function_identity_arguments(p.oid) args,pg_get_function_arguments(p.oid) default_args,
  pg_get_function_result(p.oid) result,pg_get_functiondef(p.oid) definition,p.prosrc,
  pg_get_userbyid(p.proowner) owner,p.prosecdef,p.proconfig,p.provolatile,p.proisstrict,p.proretset,l.lanname language,
  p.proparallel,p.proleakproof,
  has_function_privilege('anon',p.oid,'EXECUTE') anon,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated,
  has_function_privilege('service_role',p.oid,'EXECUTE') service_role,
  (SELECT json_agg(json_build_object('grantor',pg_get_userbyid(a.grantor),'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,'privilege',a.privilege_type,'grantable',a.is_grantable) ORDER BY CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,a.privilege_type)
   FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a) acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname IN('public','private') AND p.prokind='f') x),
 'tables',(SELECT json_agg(x ORDER BY x.schema,x.name) FROM (
  SELECT n.nspname schema,c.relname name,c.relkind kind,pg_get_userbyid(c.relowner) owner,c.relrowsecurity rls,c.relforcerowsecurity force_rls,c.reloptions,
  (SELECT json_agg(json_build_object('grantor',pg_get_userbyid(a.grantor),'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,'privilege',a.privilege_type,'grantable',a.is_grantable) ORDER BY CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,a.privilege_type)
   FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a) acl,
  (SELECT json_agg(json_build_object('column',a.attname,'position',a.attnum,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl) ORDER BY a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) columns
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('r','p','v','m','S')) x),
 'views',(SELECT json_agg(x ORDER BY x.schema,x.name) FROM (SELECT n.nspname schema,c.relname name,pg_get_viewdef(c.oid,true) definition
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private') AND c.relkind IN('v','m')) x),
 'constraints',(SELECT json_agg(x ORDER BY x.schema,x.table_name,x.name) FROM (SELECT n.nspname schema,c.relname table_name,a.conname name,a.contype kind,a.convalidated validated,a.condeferrable deferrable,a.condeferred deferred,pg_get_constraintdef(a.oid,true) definition
  FROM pg_constraint a JOIN pg_class c ON c.oid=a.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private')) x),
 'indexes',(SELECT json_agg(x ORDER BY x.schema,x.table_name,x.name) FROM (SELECT n.nspname schema,t.relname table_name,c.relname name,i.indisvalid valid,i.indisready ready,pg_get_indexdef(c.oid) definition
  FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname IN('public','private')) x),
 'triggers',(SELECT json_agg(x ORDER BY x.schema,x.table_name,x.name) FROM (SELECT n.nspname schema,c.relname table_name,t.tgname name,t.tgenabled enabled,pg_get_triggerdef(t.oid,true) definition,
  t.tgfoid::regprocedure::text function FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN('public','private','storage')) x),
 'policies',(SELECT json_agg(x ORDER BY x.schema,x.table_name,x.name) FROM (SELECT n.nspname schema,c.relname table_name,p.polname name,p.polpermissive permissive,p.polcmd command,
  (SELECT json_agg(CASE WHEN r=0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END ORDER BY CASE WHEN r=0 THEN 'PUBLIC' ELSE pg_get_userbyid(r) END) FROM unnest(p.polroles) r) roles,
  pg_get_expr(p.polqual,p.polrelid) using_expression,pg_get_expr(p.polwithcheck,p.polrelid) check_expression
  FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('public','private','storage')) x),
 'types',(SELECT json_agg(x ORDER BY x.schema,x.name) FROM (SELECT n.nspname schema,t.typname name,t.typtype kind,pg_get_userbyid(t.typowner) owner,format_type(t.typbasetype,t.typtypmod) base_type,t.typnotnull not_null,t.typdefault,
  (SELECT json_agg(e.enumlabel ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid=t.oid) enum_labels
  FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname IN('public','private') AND t.typtype IN('e','d')) x),
 'schemas',(SELECT json_agg(json_build_object('name',n.nspname,'owner',pg_get_userbyid(n.nspowner),'acl',n.nspacl) ORDER BY n.nspname) FROM pg_namespace n WHERE n.nspname IN('public','private')),
 'roles',(SELECT json_agg(json_build_object('name',r.rolname,'super',r.rolsuper,'inherit',r.rolinherit,'login',r.rolcanlogin,'bypassrls',r.rolbypassrls,'config',r.rolconfig) ORDER BY r.rolname) FROM pg_roles r WHERE r.rolname LIKE 'rotero_%' OR r.rolname IN('postgres','anon','authenticated','service_role','authenticator')),
 'role_memberships',(SELECT json_agg(json_build_object('role',pg_get_userbyid(m.roleid),'member',pg_get_userbyid(m.member),'admin',m.admin_option) ORDER BY m.roleid,m.member) FROM pg_auth_members m WHERE pg_get_userbyid(m.roleid) LIKE 'rotero_%' OR pg_get_userbyid(m.member) IN('anon','authenticated','service_role','authenticator')),
 'dependencies',(SELECT json_agg(x ORDER BY x.function_schema,x.function_name,x.function_types,x.direction,x.object_identity) FROM (
  SELECT n.nspname function_schema,p.proname function_name,oidvectortypes(p.proargtypes) function_types,'outbound' direction,d.deptype dependency_type,o.type object_type,o.schema object_schema,o.identity object_identity
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_depend d ON d.classid='pg_proc'::regclass AND d.objid=p.oid
  CROSS JOIN LATERAL pg_identify_object(d.refclassid,d.refobjid,d.refobjsubid) o WHERE n.nspname IN('public','private') AND p.prokind='f'
  UNION ALL
  SELECT n.nspname,p.proname,oidvectortypes(p.proargtypes),'inbound',d.deptype,o.type,o.schema,o.identity
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_depend d ON d.refclassid='pg_proc'::regclass AND d.refobjid=p.oid
  CROSS JOIN LATERAL pg_identify_object(d.classid,d.objid,d.objsubid) o WHERE n.nspname IN('public','private') AND p.prokind='f') x)
)) SELECT md5((payload::jsonb-'roles'-'role_memberships'-'dependencies')::text) INTO v FROM snapshot;
IF v NOT IN('6767d279c285cfde732d84c5d1782947','16b137f19c54a6499924d0a8e663dc17','d86b1b5b73d52d77e1a864276d6e033a') THEN RAISE EXCEPTION 'cierre02_unreviewed_source_state'; END IF;
PERFORM set_config('cierre02.source_variant',CASE WHEN v IN('16b137f19c54a6499924d0a8e663dc17','d86b1b5b73d52d77e1a864276d6e033a') THEN 'B' ELSE 'A' END,true);END $c02_fence$;

-- The concurrent Storage hook was reviewed separately, not accepted by name.
DO $c02_storage$ BEGIN
 IF EXISTS(SELECT FROM pg_trigger WHERE tgrelid='storage.buckets'::regclass
  AND tgname='enforce_versioning_status_transition' AND NOT tgisinternal) THEN
  IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=to_regprocedure('storage.enforce_versioning_status_transition()')
   AND NOT prosecdef AND proconfig IS NULL AND proacl IS NULL
   AND pg_get_userbyid(proowner)='supabase_storage_admin' AND prorettype='trigger'::regtype
   AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND provolatile='v' AND NOT proretset
   AND EXISTS(SELECT FROM pg_attribute WHERE attrelid='storage.buckets'::regclass
    AND attname='versioning_status' AND atttypid='text'::regtype AND attnotnull AND NOT attisdropped)
   AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))='4cc0836bc06678a1abf7c410df0872ff' ) THEN
   RAISE EXCEPTION 'c02_storage_transition_drift';END IF;
 END IF;
END $c02_storage$;

DO $owner$ DECLARE r oid;api text;limited record;BEGIN
 IF EXISTS(SELECT FROM pg_auth_members WHERE member=ANY(ARRAY['anon'::regrole,'authenticated'::regrole,'service_role'::regrole])) THEN
  RAISE EXCEPTION 'c02_api_role_membership_drift';END IF;
 FOR limited IN SELECT * FROM pg_roles WHERE rolname LIKE 'rotero\_%' ESCAPE '\' LOOP
  IF limited.rolcanlogin OR limited.rolinherit OR limited.rolsuper OR limited.rolbypassrls
   OR limited.rolcreatedb OR limited.rolcreaterole OR limited.rolreplication
   OR EXISTS(SELECT FROM pg_auth_members WHERE member=limited.oid) THEN RAISE EXCEPTION 'c02_limited_owner_role_drift';END IF;
  FOREACH api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
   IF pg_has_role(api,limited.oid,'MEMBER') THEN RAISE EXCEPTION 'c02_limited_owner_exposed';END IF;
  END LOOP;
 END LOOP;
 SELECT oid INTO r FROM pg_roles WHERE rolname='rotero_c02_gate_owner';
 IF r IS NULL THEN CREATE ROLE rotero_c02_gate_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 COMMENT ON ROLE rotero_c02_gate_owner IS 'ROTERO CIERRE-02 metadata gate v1';
 ELSIF NOT EXISTS(SELECT FROM pg_roles WHERE oid=r AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls AND shobj_description(oid,'pg_authid')='ROTERO CIERRE-02 metadata gate v1')
 OR EXISTS(SELECT FROM pg_auth_members WHERE member=r) THEN RAISE EXCEPTION 'c02_owner_collision';END IF;
 FOREACH api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
 IF pg_has_role(api,'rotero_c02_gate_owner','MEMBER') THEN RAISE EXCEPTION 'c02_owner_exposed';END IF;END LOOP;
END $owner$;
GRANT rotero_c02_gate_owner TO CURRENT_USER WITH SET TRUE;
GRANT rotero_c02_gate_owner TO CURRENT_USER WITH INHERIT FALSE;
GRANT USAGE ON SCHEMA public,private TO rotero_c02_gate_owner;
SET LOCAL ROLE rotero_company_access_owner;
GRANT EXECUTE ON FUNCTION private.multi05_request_actor() TO rotero_c02_gate_owner;
SET LOCAL ROLE postgres;
GRANT SELECT(tenant_id,user_id,role) ON public.memberships TO rotero_c02_gate_owner;
CREATE POLICY c02_membership_metadata ON public.memberships FOR SELECT TO rotero_c02_gate_owner USING(true);
GRANT EXECUTE ON FUNCTION public.tanda1_user_is_member(uuid),public.tanda1_user_has_role(uuid,text[]) TO rotero_c02_gate_owner;
CREATE TABLE private.c02_contracts(
 signature text PRIMARY KEY,category text NOT NULL,archive_signature text,observed_body_md5 text,
 source_variant text NOT NULL CHECK(source_variant IN('A','B')),public_body_md5 text,
 expected_owner name,expected_definer boolean,expected_result text,expected_config text[],
 expected_anon boolean,expected_auth boolean,expected_service boolean
);
ALTER TABLE private.c02_contracts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c02_contracts FROM PUBLIC,anon,authenticated,service_role,rotero_c02_gate_owner;
CREATE FUNCTION private.c02_required(p_tenant uuid) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE h jsonb;result boolean;
BEGIN
 BEGIN h:=COALESCE(NULLIF(pg_catalog.current_setting('request.headers',true),''),'{}')::jsonb;
 EXCEPTION WHEN invalid_text_representation THEN RETURN true;END;
 IF h ?| ARRAY['x-rotero-scope','x-rotero-company-id','x-rotero-company-ids'] THEN RETURN true;END IF;
 IF EXISTS(SELECT FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='delivery_required' AND pg_catalog.oidvectortypes(p.proargtypes)='uuid') THEN
  EXECUTE 'SELECT private.delivery_required($1) OR private.delivery_required(NULL)' INTO result USING p_tenant;
  RETURN COALESCE(result,true);
 END IF;RETURN false;
END $fn$;
GRANT CREATE ON SCHEMA private TO rotero_c02_gate_owner;
ALTER FUNCTION private.c02_required(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
REVOKE ALL ON FUNCTION private.c02_required(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.c02_required(uuid) TO postgres,anon,authenticated;
SET LOCAL ROLE postgres;

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.billing_build_api_payload(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.billing_build_api_payload(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.billing_build_api_payload(','FUNCTION private.c02_observed_fb4591d4a98003dfc506(');
 ALTER FUNCTION private.c02_observed_fb4591d4a98003dfc506(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_fb4591d4a98003dfc506(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_fb4591d4a98003dfc506(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.billing_build_api_payload(uuid)','server_only_helper','private.c02_observed_fb4591d4a98003dfc506(uuid)','30ba6e07bac86b114cbf9d5a8f842123',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.billing_fiscal_document_json(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.billing_fiscal_document_json(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.billing_fiscal_document_json(','FUNCTION private.c02_observed_583f5cb2a17ce6eb9387(');
 ALTER FUNCTION private.c02_observed_583f5cb2a17ce6eb9387(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_583f5cb2a17ce6eb9387(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_583f5cb2a17ce6eb9387(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.billing_fiscal_document_json(uuid)','server_only_helper','private.c02_observed_583f5cb2a17ce6eb9387(uuid)','ac5bd03fbd68b2bbb0f63f6c83c07d9d',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.billing_recalculate_document_totals(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.billing_recalculate_document_totals(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.billing_recalculate_document_totals(','FUNCTION private.c02_observed_9d0daf29575098e827e1(');
 ALTER FUNCTION private.c02_observed_9d0daf29575098e827e1(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9d0daf29575098e827e1(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9d0daf29575098e827e1(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.billing_recalculate_document_totals(uuid)','server_only_helper','private.c02_observed_9d0daf29575098e827e1(uuid)','9ec183954170174296d95998bfbef49d',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.billing_user_has_tenant(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.billing_user_has_tenant(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.billing_user_has_tenant(','FUNCTION private.c02_observed_ea3945e1253bb28551a6(');
 ALTER FUNCTION private.c02_observed_ea3945e1253bb28551a6(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_ea3945e1253bb28551a6(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_ea3945e1253bb28551a6(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.billing_user_has_tenant(uuid, text[])','own_membership_metadata','private.c02_observed_ea3945e1253bb28551a6(uuid, text[])','76945bf96b44dcf21af00228de6cb815',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.crm_generate_quote_reference(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.crm_generate_quote_reference(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.crm_generate_quote_reference(','FUNCTION private.c02_observed_1a6d584a5df65ad93b51(');
 ALTER FUNCTION private.c02_observed_1a6d584a5df65ad93b51(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_1a6d584a5df65ad93b51(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_1a6d584a5df65ad93b51(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.crm_generate_quote_reference(uuid)','server_only_helper','private.c02_observed_1a6d584a5df65ad93b51(uuid)','0c5fdc924fc8507309aa1797205a264e',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.crm_quote_payload_has_only_allowed_keys(jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.crm_quote_payload_has_only_allowed_keys(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.crm_quote_payload_has_only_allowed_keys(','FUNCTION private.c02_observed_37b8130e2694fef617c4(');
 ALTER FUNCTION private.c02_observed_37b8130e2694fef617c4(jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_37b8130e2694fef617c4(jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_37b8130e2694fef617c4(jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.crm_quote_payload_has_only_allowed_keys(jsonb)','pure_input_helper','private.c02_observed_37b8130e2694fef617c4(jsonb)','6c8eaf6da92da5b72a7b09324bd7c005',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.customer_display_name_is_valid(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.customer_display_name_is_valid(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.customer_display_name_is_valid(','FUNCTION private.c02_observed_53d917f0a9ce3b63a60f(');
 ALTER FUNCTION private.c02_observed_53d917f0a9ce3b63a60f(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_53d917f0a9ce3b63a60f(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_53d917f0a9ce3b63a60f(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.customer_display_name_is_valid(text)','pure_input_helper','private.c02_observed_53d917f0a9ce3b63a60f(text)','0a7fcd84390e089428a56fd4dd59f913',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.customer_normalize_display_name(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.customer_normalize_display_name(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.customer_normalize_display_name(','FUNCTION private.c02_observed_c0acb68f69788f827d44(');
 ALTER FUNCTION private.c02_observed_c0acb68f69788f827d44(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c0acb68f69788f827d44(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c0acb68f69788f827d44(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.customer_normalize_display_name(text)','pure_input_helper','private.c02_observed_c0acb68f69788f827d44(text)','c5dcc80475b8afe0d85f7a2d0e8aa44a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.customer_probable_duplicates_json(uuid, text, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.customer_probable_duplicates_json(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.customer_probable_duplicates_json(','FUNCTION private.c02_observed_eb10b0971f89e0b803ce(');
 ALTER FUNCTION private.c02_observed_eb10b0971f89e0b803ce(uuid, text, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_eb10b0971f89e0b803ce(uuid, text, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_eb10b0971f89e0b803ce(uuid, text, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.customer_probable_duplicates_json(uuid, text, uuid)','server_only_helper','private.c02_observed_eb10b0971f89e0b803ce(uuid, text, uuid)','bb0e9d2724d84d3502d2e602b543fbba',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.customer_summary_json(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.customer_summary_json(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.customer_summary_json(','FUNCTION private.c02_observed_07e60219498d98c831ed(');
 ALTER FUNCTION private.c02_observed_07e60219498d98c831ed(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_07e60219498d98c831ed(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_07e60219498d98c831ed(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.customer_summary_json(uuid)','server_only_helper','private.c02_observed_07e60219498d98c831ed(uuid)','f4002a2e185718b9e05cdcb2a02c26be',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.digest(text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.digest(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.digest(','FUNCTION private.c02_observed_08e660ed1c547e24455b(');
 ALTER FUNCTION private.c02_observed_08e660ed1c547e24455b(text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_08e660ed1c547e24455b(text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_08e660ed1c547e24455b(text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.digest(text, text)','pure_input_helper','private.c02_observed_08e660ed1c547e24455b(text, text)','5545ac1472453762b2e7ca3e97082ef7',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.fn_driver_active_operation(uuid, uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.fn_driver_active_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.fn_driver_active_operation(','FUNCTION private.c02_observed_790805283da324827843(');
 ALTER FUNCTION private.c02_observed_790805283da324827843(uuid, uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_790805283da324827843(uuid, uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_790805283da324827843(uuid, uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.fn_driver_active_operation(uuid, uuid, uuid)','server_only_helper','private.c02_observed_790805283da324827843(uuid, uuid, uuid)','f917a1d021bfdae4d222b918102afb0c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.fn_operations_infer_operation_scope()'::regprocedure) INTO d;
 IF position('FUNCTION public.fn_operations_infer_operation_scope(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.fn_operations_infer_operation_scope(','FUNCTION private.c02_observed_6b62086356a8093db3a8(');
 ALTER FUNCTION private.c02_observed_6b62086356a8093db3a8() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_6b62086356a8093db3a8() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_6b62086356a8093db3a8() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.fn_operations_infer_operation_scope()','internal_trigger','private.c02_observed_6b62086356a8093db3a8()','625039d8c43de1f964fef55821a1a52f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.fn_vehicle_active_operation(uuid, uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.fn_vehicle_active_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.fn_vehicle_active_operation(','FUNCTION private.c02_observed_1e5781e1a52da109f5b4(');
 ALTER FUNCTION private.c02_observed_1e5781e1a52da109f5b4(uuid, uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_1e5781e1a52da109f5b4(uuid, uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_1e5781e1a52da109f5b4(uuid, uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.fn_vehicle_active_operation(uuid, uuid, uuid)','server_only_helper','private.c02_observed_1e5781e1a52da109f5b4(uuid, uuid, uuid)','68c5e913223bed8a19b62e5a9b3f4012',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.haversine_m(double precision, double precision, double precision, double precision)'::regprocedure) INTO d;
 IF position('FUNCTION public.haversine_m(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.haversine_m(','FUNCTION private.c02_observed_7c4932fc454833abeaf1(');
 ALTER FUNCTION private.c02_observed_7c4932fc454833abeaf1(double precision, double precision, double precision, double precision) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7c4932fc454833abeaf1(double precision, double precision, double precision, double precision) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7c4932fc454833abeaf1(double precision, double precision, double precision, double precision) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.haversine_m(double precision, double precision, double precision, double precision)','pure_input_helper','private.c02_observed_7c4932fc454833abeaf1(double precision, double precision, double precision, double precision)','de4343d9013349f0ed5f7b8f42bb4452',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.logistics_provider_summary_json(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.logistics_provider_summary_json(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.logistics_provider_summary_json(','FUNCTION private.c02_observed_e0f45ef2bd74bc03ad04(');
 ALTER FUNCTION private.c02_observed_e0f45ef2bd74bc03ad04(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e0f45ef2bd74bc03ad04(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e0f45ef2bd74bc03ad04(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.logistics_provider_summary_json(uuid)','server_only_helper','private.c02_observed_e0f45ef2bd74bc03ad04(uuid)','ac1626c324cd894f4e6595ebac528b5d',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_accept_invitation(text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_accept_invitation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_accept_invitation(','FUNCTION private.c02_observed_c79f43999d2a6f941a43(');
 ALTER FUNCTION private.c02_observed_c79f43999d2a6f941a43(text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c79f43999d2a6f941a43(text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c79f43999d2a6f941a43(text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_accept_invitation(text, text, text)','closed_legacy_rpc','private.c02_observed_c79f43999d2a6f941a43(text, text, text)','38a54fa89fa293c0f6f39832f8d322d8',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_approve_payroll_period(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_approve_payroll_period(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_approve_payroll_period(','FUNCTION private.c02_observed_8b35b87dbc406e690fac(');
 ALTER FUNCTION private.c02_observed_8b35b87dbc406e690fac(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8b35b87dbc406e690fac(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8b35b87dbc406e690fac(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_approve_payroll_period(uuid, uuid)','closed_legacy_rpc','private.c02_observed_8b35b87dbc406e690fac(uuid, uuid)','3b898723fad36836283347171f0ec0a9',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_assign_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_assign_operation(','FUNCTION private.c02_observed_3b075d3a742666f5a5ce(');
 ALTER FUNCTION private.c02_observed_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text)','closed_legacy_rpc','private.c02_observed_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text)','0586dc7e1dca7f0f08c02bb58360a774',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_assign_operation_v2(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_assign_operation_v2(','FUNCTION private.c02_observed_1dbfc4783425e3705965(');
 ALTER FUNCTION private.c02_observed_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean)','closed_legacy_rpc','private.c02_observed_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean)','7cd733c3b0aa2f124629ab8eee99ea2a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_calculate_payroll_period(uuid, uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_calculate_payroll_period(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_calculate_payroll_period(','FUNCTION private.c02_observed_7668cb146ea65ae3b7e1(');
 ALTER FUNCTION private.c02_observed_7668cb146ea65ae3b7e1(uuid, uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7668cb146ea65ae3b7e1(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7668cb146ea65ae3b7e1(uuid, uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_calculate_payroll_period(uuid, uuid, jsonb)','closed_legacy_rpc','private.c02_observed_7668cb146ea65ae3b7e1(uuid, uuid, jsonb)','249bde33438602dc11ddeb93fe09ae5c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_complete_operation_planning(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_complete_operation_planning(','FUNCTION private.c02_observed_8fe30cd99a3ff09b2536(');
 ALTER FUNCTION private.c02_observed_8fe30cd99a3ff09b2536(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8fe30cd99a3ff09b2536(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8fe30cd99a3ff09b2536(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text)','closed_legacy_rpc','private.c02_observed_8fe30cd99a3ff09b2536(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text)','0be95832f95eca031a28a955d0daf3ae',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_complete_operation_planning(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_complete_operation_planning(','FUNCTION private.c02_observed_3e08aa274c9fd1d8ba20(');
 ALTER FUNCTION private.c02_observed_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text)','closed_legacy_rpc','private.c02_observed_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text)','68253fa015165cfeb8a51cf11e7f4560',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_configure_module(uuid, text, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_configure_module(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_configure_module(','FUNCTION private.c02_observed_8312b63bbb1a0b8b9f45(');
 ALTER FUNCTION private.c02_observed_8312b63bbb1a0b8b9f45(uuid, text, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8312b63bbb1a0b8b9f45(uuid, text, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8312b63bbb1a0b8b9f45(uuid, text, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_configure_module(uuid, text, jsonb)','closed_legacy_rpc','private.c02_observed_8312b63bbb1a0b8b9f45(uuid, text, jsonb)','244d0d750c337210f5067302fd45de22',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_billing_document_from_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_billing_document_from_operation(','FUNCTION private.c02_observed_5c8e0590ef4313ed0010(');
 ALTER FUNCTION private.c02_observed_5c8e0590ef4313ed0010(uuid, uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_5c8e0590ef4313ed0010(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_5c8e0590ef4313ed0010(uuid, uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb)','closed_legacy_rpc','private.c02_observed_5c8e0590ef4313ed0010(uuid, uuid, jsonb)','6854674791f0afab74248b1d0bd8483f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_credit_note(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_credit_note(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_credit_note(','FUNCTION private.c02_observed_197154c4c87a61893fe5(');
 ALTER FUNCTION private.c02_observed_197154c4c87a61893fe5(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_197154c4c87a61893fe5(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_197154c4c87a61893fe5(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_credit_note(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_197154c4c87a61893fe5(uuid, jsonb)','2514d251130516b79e93b6dbee66318c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_customer(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_customer(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_customer(','FUNCTION private.c02_observed_b5ed58565175016ab919(');
 ALTER FUNCTION private.c02_observed_b5ed58565175016ab919(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b5ed58565175016ab919(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b5ed58565175016ab919(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_customer(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_b5ed58565175016ab919(uuid, jsonb)','c7ebbc3516889ddb71fae17a693ab5c6',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_daily_work_item(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_daily_work_item(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_daily_work_item(','FUNCTION private.c02_observed_80362131891dde999d27(');
 ALTER FUNCTION private.c02_observed_80362131891dde999d27(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_80362131891dde999d27(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_80362131891dde999d27(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_daily_work_item(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_80362131891dde999d27(uuid, jsonb)','ad8d5636e89c6ad81b58b61073e0b547',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_driver(uuid, text, text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_driver(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_driver(','FUNCTION private.c02_observed_e283943c0fd6d9d24f83(');
 ALTER FUNCTION private.c02_observed_e283943c0fd6d9d24f83(uuid, text, text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e283943c0fd6d9d24f83(uuid, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e283943c0fd6d9d24f83(uuid, text, text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_driver(uuid, text, text, text, text)','closed_legacy_rpc','private.c02_observed_e283943c0fd6d9d24f83(uuid, text, text, text, text)','5ad3bb3fba934055b9ab063f66170336',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_inventory_lot(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_inventory_lot(','FUNCTION private.c02_observed_81156bbf35ff2925a3fe(');
 ALTER FUNCTION private.c02_observed_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text)','closed_legacy_rpc','private.c02_observed_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text)','e7a3fc957d5401a3c53722811e142283',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_inventory_lot(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_inventory_lot(','FUNCTION private.c02_observed_d8bdba3bfe3629ac0fde(');
 ALTER FUNCTION private.c02_observed_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text)','closed_legacy_rpc','private.c02_observed_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text)','b5423c46acf48c8923fdefb45b9af380',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_logistics_provider(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_logistics_provider(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_logistics_provider(','FUNCTION private.c02_observed_235250be5714c7a66548(');
 ALTER FUNCTION private.c02_observed_235250be5714c7a66548(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_235250be5714c7a66548(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_235250be5714c7a66548(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_logistics_provider(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_235250be5714c7a66548(uuid, jsonb)','5f3f0cd7d0b36f747c1b5e3b74df1c55',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_operation_billing(uuid, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_operation_billing(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_operation_billing(','FUNCTION private.c02_observed_334e6bbae2fe05d161ea(');
 ALTER FUNCTION private.c02_observed_334e6bbae2fe05d161ea(uuid, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_334e6bbae2fe05d161ea(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_334e6bbae2fe05d161ea(uuid, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_operation_billing(uuid, text, text)','closed_legacy_rpc','private.c02_observed_334e6bbae2fe05d161ea(uuid, text, text)','e81f4635bcdf414e4fcc1e3d87e57d2a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_operation_draft(uuid, text, text, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_operation_draft(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_operation_draft(','FUNCTION private.c02_observed_188db110a499f579131a(');
 ALTER FUNCTION private.c02_observed_188db110a499f579131a(uuid, text, text, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_188db110a499f579131a(uuid, text, text, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_188db110a499f579131a(uuid, text, text, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_operation_draft(uuid, text, text, uuid)','closed_legacy_rpc','private.c02_observed_188db110a499f579131a(uuid, text, text, uuid)','6eb0add23fc49b308d5ec2d80fa9cb97',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_operation_draft(uuid, text, text, uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_operation_draft(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_operation_draft(','FUNCTION private.c02_observed_4901b60f756d33394d22(');
 ALTER FUNCTION private.c02_observed_4901b60f756d33394d22(uuid, text, text, uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_4901b60f756d33394d22(uuid, text, text, uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_4901b60f756d33394d22(uuid, text, text, uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_operation_draft(uuid, text, text, uuid, text)','closed_legacy_rpc','private.c02_observed_4901b60f756d33394d22(uuid, text, text, uuid, text)','8ab4d0ef4e2bffdb202f7d106607268f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_payroll_period(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_payroll_period(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_payroll_period(','FUNCTION private.c02_observed_03750fcf36cfd3dc2626(');
 ALTER FUNCTION private.c02_observed_03750fcf36cfd3dc2626(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_03750fcf36cfd3dc2626(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_03750fcf36cfd3dc2626(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_payroll_period(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_03750fcf36cfd3dc2626(uuid, jsonb)','5be65890d0f25b06560859affecef9d0',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_vehicle(uuid, text, text, text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_vehicle(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_vehicle(','FUNCTION private.c02_observed_90255862aed9e1eb5bb9(');
 ALTER FUNCTION private.c02_observed_90255862aed9e1eb5bb9(uuid, text, text, text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_90255862aed9e1eb5bb9(uuid, text, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_90255862aed9e1eb5bb9(uuid, text, text, text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_vehicle(uuid, text, text, text, text, text)','closed_legacy_rpc','private.c02_observed_90255862aed9e1eb5bb9(uuid, text, text, text, text, text)','9b38413fc4fe1922cf834c83ca64b240',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_dashboard_alerts(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_dashboard_alerts(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_dashboard_alerts(','FUNCTION private.c02_observed_b45e1df65509538a8d39(');
 ALTER FUNCTION private.c02_observed_b45e1df65509538a8d39(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b45e1df65509538a8d39(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b45e1df65509538a8d39(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_dashboard_alerts(uuid)','canonical_default_redirect','private.c02_observed_b45e1df65509538a8d39(uuid)','26736856d232fbe9835b8bce8e6904a6',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_dashboard_overview(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_dashboard_overview(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_dashboard_overview(','FUNCTION private.c02_observed_6ec6c7a338466f5afc53(');
 ALTER FUNCTION private.c02_observed_6ec6c7a338466f5afc53(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_6ec6c7a338466f5afc53(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_6ec6c7a338466f5afc53(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_dashboard_overview(uuid)','canonical_default_redirect','private.c02_observed_6ec6c7a338466f5afc53(uuid)','53e5bdcc845b72a260c6b9ab5644006a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_dashboard_recent_activity(uuid, integer)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_dashboard_recent_activity(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_dashboard_recent_activity(','FUNCTION private.c02_observed_34e1d88722077f141b5d(');
 ALTER FUNCTION private.c02_observed_34e1d88722077f141b5d(uuid, integer) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_34e1d88722077f141b5d(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_34e1d88722077f141b5d(uuid, integer) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_dashboard_recent_activity(uuid, integer)','closed_legacy_rpc','private.c02_observed_34e1d88722077f141b5d(uuid, integer)','ec32e2f4acfe5def077eb3f50e37bde7',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_dashboard_recent_activity(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_dashboard_recent_activity(','FUNCTION private.c02_observed_64317cc295fa4a1529ba(');
 ALTER FUNCTION private.c02_observed_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone)','closed_legacy_rpc','private.c02_observed_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone)','e75ad3e5a49f36c555aa4ce27c4878d6',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_delete_billing_document_line(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_delete_billing_document_line(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_delete_billing_document_line(','FUNCTION private.c02_observed_7f44ab6fe37fb673acb2(');
 ALTER FUNCTION private.c02_observed_7f44ab6fe37fb673acb2(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7f44ab6fe37fb673acb2(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7f44ab6fe37fb673acb2(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_delete_billing_document_line(uuid)','closed_legacy_rpc','private.c02_observed_7f44ab6fe37fb673acb2(uuid)','127c963da73421ecacaee265dd170d93',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_delete_billing_document_tax(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_delete_billing_document_tax(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_delete_billing_document_tax(','FUNCTION private.c02_observed_90946e6322367775712a(');
 ALTER FUNCTION private.c02_observed_90946e6322367775712a(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_90946e6322367775712a(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_90946e6322367775712a(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_delete_billing_document_tax(uuid)','closed_legacy_rpc','private.c02_observed_90946e6322367775712a(uuid)','f05ba8bec8498a649a7fb8455763e39f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_export_daily_control_items(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_export_daily_control_items(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_export_daily_control_items(','FUNCTION private.c02_observed_dc0764973da406be3a24(');
 ALTER FUNCTION private.c02_observed_dc0764973da406be3a24(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_dc0764973da406be3a24(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_dc0764973da406be3a24(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_export_daily_control_items(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_dc0764973da406be3a24(uuid, jsonb)','3bbc645a60d38dbf4fb27f1253e73784',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_export_issued_cfdis(uuid, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_export_issued_cfdis(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_export_issued_cfdis(','FUNCTION private.c02_observed_b3214be28e6db0b98331(');
 ALTER FUNCTION private.c02_observed_b3214be28e6db0b98331(uuid, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b3214be28e6db0b98331(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b3214be28e6db0b98331(uuid, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_export_issued_cfdis(uuid, text, text)','closed_legacy_rpc','private.c02_observed_b3214be28e6db0b98331(uuid, text, text)','c08db015a2cf31a1eeaadac74cfc4ecc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_export_operations(uuid, text[], text, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_export_operations(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_export_operations(','FUNCTION private.c02_observed_dd0439f88824140b2e31(');
 ALTER FUNCTION private.c02_observed_dd0439f88824140b2e31(uuid, text[], text, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_dd0439f88824140b2e31(uuid, text[], text, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_dd0439f88824140b2e31(uuid, text[], text, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_export_operations(uuid, text[], text, text, text)','closed_legacy_rpc','private.c02_observed_dd0439f88824140b2e31(uuid, text[], text, text, text)','537cdc0a99ff46fafa90001830a8efff',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_export_payroll_period(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_export_payroll_period(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_export_payroll_period(','FUNCTION private.c02_observed_69d058b07561deca423e(');
 ALTER FUNCTION private.c02_observed_69d058b07561deca423e(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_69d058b07561deca423e(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_69d058b07561deca423e(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_export_payroll_period(uuid, uuid)','closed_legacy_rpc','private.c02_observed_69d058b07561deca423e(uuid, uuid)','1e3de244b1c54ded210ae1a7bb7f43fe',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_export_quotes(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_export_quotes(','FUNCTION private.c02_observed_d47fcba82bff1a8a11ac(');
 ALTER FUNCTION private.c02_observed_d47fcba82bff1a8a11ac(uuid, text[], text[], text, text, boolean, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d47fcba82bff1a8a11ac(uuid, text[], text[], text, text, boolean, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d47fcba82bff1a8a11ac(uuid, text[], text[], text, text, boolean, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text)','closed_legacy_rpc','private.c02_observed_d47fcba82bff1a8a11ac(uuid, text[], text[], text, text, boolean, text, text)','3c4dfee2d3f2ad49bb7f399470128706',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_billing_document(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_billing_document(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_billing_document(','FUNCTION private.c02_observed_2d326485f986bcce664a(');
 ALTER FUNCTION private.c02_observed_2d326485f986bcce664a(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_2d326485f986bcce664a(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_2d326485f986bcce664a(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_billing_document(uuid)','closed_legacy_rpc','private.c02_observed_2d326485f986bcce664a(uuid)','f04f854f749b1ab804b490817dd90087',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_customer(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_customer(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_customer(','FUNCTION private.c02_observed_7729731cf09d818191f7(');
 ALTER FUNCTION private.c02_observed_7729731cf09d818191f7(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7729731cf09d818191f7(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7729731cf09d818191f7(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_customer(uuid)','closed_legacy_rpc','private.c02_observed_7729731cf09d818191f7(uuid)','fcadf9cc32b12c604a02195b37fb8981',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_daily_control_summary(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_daily_control_summary(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_daily_control_summary(','FUNCTION private.c02_observed_40eff1c3a69067feb921(');
 ALTER FUNCTION private.c02_observed_40eff1c3a69067feb921(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_40eff1c3a69067feb921(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_40eff1c3a69067feb921(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_daily_control_summary(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_40eff1c3a69067feb921(uuid, jsonb)','7c967e944fc8f66ad1f19aaf7b245c9e',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_dispatch_dashboard(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_dispatch_dashboard(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_dispatch_dashboard(','FUNCTION private.c02_observed_ab43eb882b2848329c8e(');
 ALTER FUNCTION private.c02_observed_ab43eb882b2848329c8e(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_ab43eb882b2848329c8e(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_ab43eb882b2848329c8e(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_dispatch_dashboard(uuid)','closed_legacy_rpc','private.c02_observed_ab43eb882b2848329c8e(uuid)','edbf8209f65969f0803ad80eb6ab1370',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_executive_dashboard(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_executive_dashboard(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_executive_dashboard(','FUNCTION private.c02_observed_67a1da4c2cceb1d215de(');
 ALTER FUNCTION private.c02_observed_67a1da4c2cceb1d215de(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_67a1da4c2cceb1d215de(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_67a1da4c2cceb1d215de(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_executive_dashboard(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_67a1da4c2cceb1d215de(uuid, jsonb)','bbfb49582e6a3c444438d8f0fe084300',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_issue_payroll_receipts(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_issue_payroll_receipts(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_issue_payroll_receipts(','FUNCTION private.c02_observed_8307161ef346d2082c6b(');
 ALTER FUNCTION private.c02_observed_8307161ef346d2082c6b(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8307161ef346d2082c6b(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8307161ef346d2082c6b(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_issue_payroll_receipts(uuid, uuid)','closed_legacy_rpc','private.c02_observed_8307161ef346d2082c6b(uuid, uuid)','11218397afe53d679193c15c6b0407ed',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_audit_log(uuid, integer)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_audit_log(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_audit_log(','FUNCTION private.c02_observed_1243db36b949cbbe34f4(');
 ALTER FUNCTION private.c02_observed_1243db36b949cbbe34f4(uuid, integer) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_1243db36b949cbbe34f4(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_1243db36b949cbbe34f4(uuid, integer) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_audit_log(uuid, integer)','canonical_default_redirect','private.c02_observed_1243db36b949cbbe34f4(uuid, integer)','631cce7db5235c684919959e931655d0',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_billing_documents(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_billing_documents(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_billing_documents(','FUNCTION private.c02_observed_ea94d671c51f4343069d(');
 ALTER FUNCTION private.c02_observed_ea94d671c51f4343069d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_ea94d671c51f4343069d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_ea94d671c51f4343069d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_billing_documents(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_ea94d671c51f4343069d(uuid, jsonb)','7c944f00a0feff35474d52a129d99d33',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_billing_sat_catalog_entries(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_billing_sat_catalog_entries(','FUNCTION private.c02_observed_2ca100f5c9d17437cce8(');
 ALTER FUNCTION private.c02_observed_2ca100f5c9d17437cce8(uuid, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_2ca100f5c9d17437cce8(uuid, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_2ca100f5c9d17437cce8(uuid, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean)','closed_legacy_rpc','private.c02_observed_2ca100f5c9d17437cce8(uuid, text, boolean)','1c791a2202678fa41fd9b76c78e2effc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_credit_notes(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_credit_notes(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_credit_notes(','FUNCTION private.c02_observed_9a3b4e8d6920c69debcd(');
 ALTER FUNCTION private.c02_observed_9a3b4e8d6920c69debcd(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9a3b4e8d6920c69debcd(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9a3b4e8d6920c69debcd(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_credit_notes(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_9a3b4e8d6920c69debcd(uuid, jsonb)','4dddc27c15ab5cb29056f6c8111f4ea5',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_currency_exchange_rates(uuid, integer)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_currency_exchange_rates(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_currency_exchange_rates(','FUNCTION private.c02_observed_41989552448775a317cd(');
 ALTER FUNCTION private.c02_observed_41989552448775a317cd(uuid, integer) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_41989552448775a317cd(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_41989552448775a317cd(uuid, integer) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_currency_exchange_rates(uuid, integer)','closed_legacy_rpc','private.c02_observed_41989552448775a317cd(uuid, integer)','d6b98f2e5333e0ed88cdfc607b041805',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_daily_control_items(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_daily_control_items(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_daily_control_items(','FUNCTION private.c02_observed_6faa4e861750958f91cb(');
 ALTER FUNCTION private.c02_observed_6faa4e861750958f91cb(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_6faa4e861750958f91cb(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_6faa4e861750958f91cb(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_daily_control_items(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_6faa4e861750958f91cb(uuid, jsonb)','294a6a4d8d778774a6cec76fbf3ee58d',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_document_finance_pending(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_document_finance_pending(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_document_finance_pending(','FUNCTION private.c02_observed_0a5b991de8a1aff91cf0(');
 ALTER FUNCTION private.c02_observed_0a5b991de8a1aff91cf0(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_0a5b991de8a1aff91cf0(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_0a5b991de8a1aff91cf0(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_document_finance_pending(uuid)','closed_legacy_rpc','private.c02_observed_0a5b991de8a1aff91cf0(uuid)','2eadd99b3dad116709ec6855d576af58',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_document_tax_summary(uuid, date, date)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_document_tax_summary(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_document_tax_summary(','FUNCTION private.c02_observed_7a1e9c6abedae4763710(');
 ALTER FUNCTION private.c02_observed_7a1e9c6abedae4763710(uuid, date, date) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7a1e9c6abedae4763710(uuid, date, date) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7a1e9c6abedae4763710(uuid, date, date) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_document_tax_summary(uuid, date, date)','closed_legacy_rpc','private.c02_observed_7a1e9c6abedae4763710(uuid, date, date)','79beb280d9f787efe95da18e2926d9d3',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_document_template_versions(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_document_template_versions(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_document_template_versions(','FUNCTION private.c02_observed_09ede2633c120d9fb46e(');
 ALTER FUNCTION private.c02_observed_09ede2633c120d9fb46e(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_09ede2633c120d9fb46e(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_09ede2633c120d9fb46e(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_document_template_versions(uuid, uuid)','closed_legacy_rpc','private.c02_observed_09ede2633c120d9fb46e(uuid, uuid)','846a88c3938481891bd268016c57f782',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_document_templates(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_document_templates(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_document_templates(','FUNCTION private.c02_observed_d08a62f57071d19b3556(');
 ALTER FUNCTION private.c02_observed_d08a62f57071d19b3556(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d08a62f57071d19b3556(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d08a62f57071d19b3556(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_document_templates(uuid, text)','closed_legacy_rpc','private.c02_observed_d08a62f57071d19b3556(uuid, text)','a2ee5e8c98a9860f5a137a4503f01483',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_drivers(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_drivers(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_drivers(','FUNCTION private.c02_observed_87bea051c00f765b9395(');
 ALTER FUNCTION private.c02_observed_87bea051c00f765b9395(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_87bea051c00f765b9395(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_87bea051c00f765b9395(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_drivers(uuid)','closed_legacy_rpc','private.c02_observed_87bea051c00f765b9395(uuid)','61e90ea41f4373b749b6d166abeaf472',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_fiscal_document_workbench(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_fiscal_document_workbench(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_fiscal_document_workbench(','FUNCTION private.c02_observed_cea4bfa633144f9b81b5(');
 ALTER FUNCTION private.c02_observed_cea4bfa633144f9b81b5(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_cea4bfa633144f9b81b5(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_cea4bfa633144f9b81b5(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_fiscal_document_workbench(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_cea4bfa633144f9b81b5(uuid, jsonb)','d4ebfe7b3193b278a5896b5a63b628f0',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_internal_notifications(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_internal_notifications(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_internal_notifications(','FUNCTION private.c02_observed_14be0422d75af232ca8a(');
 ALTER FUNCTION private.c02_observed_14be0422d75af232ca8a(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_14be0422d75af232ca8a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_14be0422d75af232ca8a(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_internal_notifications(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_14be0422d75af232ca8a(uuid, jsonb)','85e6f592801020bf5aeaeb2c99635d5f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_logistics_providers(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_logistics_providers(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_logistics_providers(','FUNCTION private.c02_observed_fb4b56ad8e1753721427(');
 ALTER FUNCTION private.c02_observed_fb4b56ad8e1753721427(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_fb4b56ad8e1753721427(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_fb4b56ad8e1753721427(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_logistics_providers(uuid)','closed_legacy_rpc','private.c02_observed_fb4b56ad8e1753721427(uuid)','fdd0b010e663fe573e8001efb73c1318',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_operation_billing(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_operation_billing(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_operation_billing(','FUNCTION private.c02_observed_e3d35e9783cb6119b066(');
 ALTER FUNCTION private.c02_observed_e3d35e9783cb6119b066(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e3d35e9783cb6119b066(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e3d35e9783cb6119b066(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_operation_billing(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_e3d35e9783cb6119b066(uuid, jsonb)','758f6d08a9f64258b51f06c30c810764',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_payroll_employees(uuid, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_payroll_employees(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_payroll_employees(','FUNCTION private.c02_observed_f3f45084bd3a5db0d600(');
 ALTER FUNCTION private.c02_observed_f3f45084bd3a5db0d600(uuid, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_f3f45084bd3a5db0d600(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_f3f45084bd3a5db0d600(uuid, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_payroll_employees(uuid, boolean)','closed_legacy_rpc','private.c02_observed_f3f45084bd3a5db0d600(uuid, boolean)','cdd8246c00f490eda3b29f96512f6819',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_payroll_entries(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_payroll_entries(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_payroll_entries(','FUNCTION private.c02_observed_9bd933001d0f0cf72865(');
 ALTER FUNCTION private.c02_observed_9bd933001d0f0cf72865(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9bd933001d0f0cf72865(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9bd933001d0f0cf72865(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_payroll_entries(uuid, uuid)','closed_legacy_rpc','private.c02_observed_9bd933001d0f0cf72865(uuid, uuid)','7b7a82a5484b6794b605e139491c4667',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_payroll_loans(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_payroll_loans(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_payroll_loans(','FUNCTION private.c02_observed_dcb44c0a835753a72701(');
 ALTER FUNCTION private.c02_observed_dcb44c0a835753a72701(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_dcb44c0a835753a72701(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_dcb44c0a835753a72701(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_payroll_loans(uuid, text)','closed_legacy_rpc','private.c02_observed_dcb44c0a835753a72701(uuid, text)','036621005772debfc88d5e06f1a3e0af',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_payroll_periods(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_payroll_periods(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_payroll_periods(','FUNCTION private.c02_observed_d2936b62fcb784343c6f(');
 ALTER FUNCTION private.c02_observed_d2936b62fcb784343c6f(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d2936b62fcb784343c6f(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d2936b62fcb784343c6f(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_payroll_periods(uuid, text)','closed_legacy_rpc','private.c02_observed_d2936b62fcb784343c6f(uuid, text)','294bd3eb06328b74ebde525e0ea7ec09',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_payroll_receipts(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_payroll_receipts(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_payroll_receipts(','FUNCTION private.c02_observed_edec4f660ff15c148c32(');
 ALTER FUNCTION private.c02_observed_edec4f660ff15c148c32(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_edec4f660ff15c148c32(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_edec4f660ff15c148c32(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_payroll_receipts(uuid, uuid)','closed_legacy_rpc','private.c02_observed_edec4f660ff15c148c32(uuid, uuid)','e790a408868ce60521910b02391896ef',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_route_points(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_route_points(','FUNCTION private.c02_observed_f38939d840edf43c9707(');
 ALTER FUNCTION private.c02_observed_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer)','closed_legacy_rpc','private.c02_observed_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer)','f87f97122f15ee2ca192bd020b62694e',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_service_catalog_items(uuid, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_service_catalog_items(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_service_catalog_items(','FUNCTION private.c02_observed_7bf3086826152f15500c(');
 ALTER FUNCTION private.c02_observed_7bf3086826152f15500c(uuid, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7bf3086826152f15500c(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7bf3086826152f15500c(uuid, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_service_catalog_items(uuid, boolean)','closed_legacy_rpc','private.c02_observed_7bf3086826152f15500c(uuid, boolean)','d972578655513244a3d873065f9396c1',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_vehicles(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_vehicles(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_vehicles(','FUNCTION private.c02_observed_3b9f7a5ddd586b2f5976(');
 ALTER FUNCTION private.c02_observed_3b9f7a5ddd586b2f5976(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3b9f7a5ddd586b2f5976(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3b9f7a5ddd586b2f5976(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_vehicles(uuid)','closed_legacy_rpc','private.c02_observed_3b9f7a5ddd586b2f5976(uuid)','53aa1b51e843f6ae262bf52a537439a1',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_mark_operation_billing_issued(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_mark_operation_billing_issued(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_mark_operation_billing_issued(','FUNCTION private.c02_observed_654947ef338daca14a7c(');
 ALTER FUNCTION private.c02_observed_654947ef338daca14a7c(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_654947ef338daca14a7c(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_654947ef338daca14a7c(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_mark_operation_billing_issued(uuid, text)','closed_legacy_rpc','private.c02_observed_654947ef338daca14a7c(uuid, text)','7b194ecd6cca42f4fdefa07892f5aa67',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_move_deal(uuid, text, timestamp with time zone)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_move_deal(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_move_deal(','FUNCTION private.c02_observed_2e8af3a893dbe1bde803(');
 ALTER FUNCTION private.c02_observed_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_move_deal(uuid, text, timestamp with time zone)','closed_legacy_rpc','private.c02_observed_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone)','d6c1d92959a7549adef9157b96359c33',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_queue_billing_document_for_api(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_queue_billing_document_for_api(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_queue_billing_document_for_api(','FUNCTION private.c02_observed_cad3c443fe153d2a38d5(');
 ALTER FUNCTION private.c02_observed_cad3c443fe153d2a38d5(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_cad3c443fe153d2a38d5(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_cad3c443fe153d2a38d5(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_queue_billing_document_for_api(uuid)','closed_legacy_rpc','private.c02_observed_cad3c443fe153d2a38d5(uuid)','619ac8f996f9c400d2e77e80951235cb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_recalculate_billing_document_totals(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_recalculate_billing_document_totals(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_recalculate_billing_document_totals(','FUNCTION private.c02_observed_debba76c73b7f6e027c2(');
 ALTER FUNCTION private.c02_observed_debba76c73b7f6e027c2(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_debba76c73b7f6e027c2(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_debba76c73b7f6e027c2(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_recalculate_billing_document_totals(uuid)','closed_legacy_rpc','private.c02_observed_debba76c73b7f6e027c2(uuid)','50d6473924808838005a3776ca8a97af',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_register_billing_api_result(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_register_billing_api_result(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_register_billing_api_result(','FUNCTION private.c02_observed_d7ba1b7ca1954648adcd(');
 ALTER FUNCTION private.c02_observed_d7ba1b7ca1954648adcd(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d7ba1b7ca1954648adcd(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d7ba1b7ca1954648adcd(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_register_billing_api_result(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_d7ba1b7ca1954648adcd(uuid, jsonb)','79bf0e332ec16d7feb310b144d00bcd5',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_resolve_daily_work_item(uuid, text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_resolve_daily_work_item(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_resolve_daily_work_item(','FUNCTION private.c02_observed_6b19d3a1104f11ff08c5(');
 ALTER FUNCTION private.c02_observed_6b19d3a1104f11ff08c5(uuid, text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_6b19d3a1104f11ff08c5(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_6b19d3a1104f11ff08c5(uuid, text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_resolve_daily_work_item(uuid, text, text)','closed_legacy_rpc','private.c02_observed_6b19d3a1104f11ff08c5(uuid, text, text)','fb32acd680cb8577a412cec202b7a7f8',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_revoke_invitation(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_revoke_invitation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_revoke_invitation(','FUNCTION private.c02_observed_b1d32b3d12054a5cf664(');
 ALTER FUNCTION private.c02_observed_b1d32b3d12054a5cf664(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b1d32b3d12054a5cf664(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b1d32b3d12054a5cf664(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_revoke_invitation(uuid, uuid)','closed_legacy_rpc','private.c02_observed_b1d32b3d12054a5cf664(uuid, uuid)','38a54fa89fa293c0f6f39832f8d322d8',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_revoke_operation_tokens(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_revoke_operation_tokens(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_revoke_operation_tokens(','FUNCTION private.c02_observed_1a02ac7224bcaef815da(');
 ALTER FUNCTION private.c02_observed_1a02ac7224bcaef815da(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_1a02ac7224bcaef815da(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_1a02ac7224bcaef815da(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_revoke_operation_tokens(uuid)','closed_legacy_rpc','private.c02_observed_1a02ac7224bcaef815da(uuid)','aa87eae7fe0e42efab3a57ff45fae41c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_set_customer_active_status(uuid, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_set_customer_active_status(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_set_customer_active_status(','FUNCTION private.c02_observed_db7ed6a03cd1ba4ae080(');
 ALTER FUNCTION private.c02_observed_db7ed6a03cd1ba4ae080(uuid, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_db7ed6a03cd1ba4ae080(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_db7ed6a03cd1ba4ae080(uuid, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_set_customer_active_status(uuid, boolean)','closed_legacy_rpc','private.c02_observed_db7ed6a03cd1ba4ae080(uuid, boolean)','7ff4855d87ab6e56b98094c0dc05fa25',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_set_driver_status(uuid, text, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_set_driver_status(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_set_driver_status(','FUNCTION private.c02_observed_339cdbe7ae06ba48584a(');
 ALTER FUNCTION private.c02_observed_339cdbe7ae06ba48584a(uuid, text, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_339cdbe7ae06ba48584a(uuid, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_339cdbe7ae06ba48584a(uuid, text, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_set_driver_status(uuid, text, text, boolean)','closed_legacy_rpc','private.c02_observed_339cdbe7ae06ba48584a(uuid, text, text, boolean)','195c8cce02613b89539a3af782e037f6',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_set_vehicle_status(uuid, text, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_set_vehicle_status(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_set_vehicle_status(','FUNCTION private.c02_observed_7d9c898db1a55864fb62(');
 ALTER FUNCTION private.c02_observed_7d9c898db1a55864fb62(uuid, text, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7d9c898db1a55864fb62(uuid, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7d9c898db1a55864fb62(uuid, text, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_set_vehicle_status(uuid, text, text, boolean)','closed_legacy_rpc','private.c02_observed_7d9c898db1a55864fb62(uuid, text, text, boolean)','c810ce72b3bd5d14c635bfbbcb65c696',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_tracking_healthcheck(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_tracking_healthcheck(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_tracking_healthcheck(','FUNCTION private.c02_observed_f5a08231aab94b1e124d(');
 ALTER FUNCTION private.c02_observed_f5a08231aab94b1e124d(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_f5a08231aab94b1e124d(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_f5a08231aab94b1e124d(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_tracking_healthcheck(uuid)','closed_legacy_rpc','private.c02_observed_f5a08231aab94b1e124d(uuid)','0f6a98bfd9e5995664078abfc6004b79',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_billing_document(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_billing_document(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_billing_document(','FUNCTION private.c02_observed_83ce1492c6a459dbc943(');
 ALTER FUNCTION private.c02_observed_83ce1492c6a459dbc943(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_83ce1492c6a459dbc943(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_83ce1492c6a459dbc943(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_billing_document(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_83ce1492c6a459dbc943(uuid, jsonb)','81cc0d11e1543c3185048b4e0e804ab6',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_customer(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_customer(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_customer(','FUNCTION private.c02_observed_c8d35d8022ed6399e3bb(');
 ALTER FUNCTION private.c02_observed_c8d35d8022ed6399e3bb(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c8d35d8022ed6399e3bb(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c8d35d8022ed6399e3bb(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_customer(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_c8d35d8022ed6399e3bb(uuid, jsonb)','4689d1dd429edadb82d341a9e51fbebc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_customer_preferred_currency(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_customer_preferred_currency(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_customer_preferred_currency(','FUNCTION private.c02_observed_05fcdb92c209ba40b312(');
 ALTER FUNCTION private.c02_observed_05fcdb92c209ba40b312(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_05fcdb92c209ba40b312(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_05fcdb92c209ba40b312(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_customer_preferred_currency(uuid, text)','closed_legacy_rpc','private.c02_observed_05fcdb92c209ba40b312(uuid, text)','223a00e5373c2031945ec4b49136ea55',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_daily_work_item(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_daily_work_item(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_daily_work_item(','FUNCTION private.c02_observed_22c88b95458843e03b85(');
 ALTER FUNCTION private.c02_observed_22c88b95458843e03b85(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_22c88b95458843e03b85(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_22c88b95458843e03b85(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_daily_work_item(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_22c88b95458843e03b85(uuid, jsonb)','a9798f0d36c3008f2f54677c97821176',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_driver(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_driver(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_driver(','FUNCTION private.c02_observed_cd16ca464e54a70ceccf(');
 ALTER FUNCTION private.c02_observed_cd16ca464e54a70ceccf(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_cd16ca464e54a70ceccf(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_cd16ca464e54a70ceccf(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_driver(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_cd16ca464e54a70ceccf(uuid, jsonb)','57302273a8a50bfcb2d4933842326464',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_logistics_provider(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_logistics_provider(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_logistics_provider(','FUNCTION private.c02_observed_139ecbe3c17e10ba7f50(');
 ALTER FUNCTION private.c02_observed_139ecbe3c17e10ba7f50(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_139ecbe3c17e10ba7f50(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_139ecbe3c17e10ba7f50(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_logistics_provider(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_139ecbe3c17e10ba7f50(uuid, jsonb)','75aee636ef97d3ac3019f42abe670cc8',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_vehicle(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_vehicle(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_vehicle(','FUNCTION private.c02_observed_23cb2ecf315c06bce720(');
 ALTER FUNCTION private.c02_observed_23cb2ecf315c06bce720(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_23cb2ecf315c06bce720(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_23cb2ecf315c06bce720(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_vehicle(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_23cb2ecf315c06bce720(uuid, jsonb)','01aef815fce94d4f770df59fb683c97f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_billing_document_line(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_billing_document_line(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_billing_document_line(','FUNCTION private.c02_observed_0652a7d5e8fb53fa5c5d(');
 ALTER FUNCTION private.c02_observed_0652a7d5e8fb53fa5c5d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_0652a7d5e8fb53fa5c5d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_0652a7d5e8fb53fa5c5d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_billing_document_line(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_0652a7d5e8fb53fa5c5d(uuid, jsonb)','3824fb6b1ba3cfad97056c5d75cd9f57',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_billing_document_party(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_billing_document_party(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_billing_document_party(','FUNCTION private.c02_observed_76a078d697c0a8f67713(');
 ALTER FUNCTION private.c02_observed_76a078d697c0a8f67713(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_76a078d697c0a8f67713(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_76a078d697c0a8f67713(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_billing_document_party(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_76a078d697c0a8f67713(uuid, jsonb)','13ea3005bdc597fe3604a83bff70d189',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_billing_document_tax(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_billing_document_tax(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_billing_document_tax(','FUNCTION private.c02_observed_a3b675d5dd677dc31abf(');
 ALTER FUNCTION private.c02_observed_a3b675d5dd677dc31abf(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_a3b675d5dd677dc31abf(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_a3b675d5dd677dc31abf(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_billing_document_tax(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_a3b675d5dd677dc31abf(uuid, jsonb)','e6755a2aa23b7da86095059eece65202',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_billing_fiscal_profile(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_billing_fiscal_profile(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_billing_fiscal_profile(','FUNCTION private.c02_observed_3c57ec49898fe6d1dd00(');
 ALTER FUNCTION private.c02_observed_3c57ec49898fe6d1dd00(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3c57ec49898fe6d1dd00(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3c57ec49898fe6d1dd00(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_billing_fiscal_profile(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_3c57ec49898fe6d1dd00(uuid, jsonb)','2e802d9a3f96a1b9030a177a20f928e2',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_currency_exchange_rate(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_currency_exchange_rate(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_currency_exchange_rate(','FUNCTION private.c02_observed_f1d5e24d74d0ac59b47d(');
 ALTER FUNCTION private.c02_observed_f1d5e24d74d0ac59b47d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_f1d5e24d74d0ac59b47d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_f1d5e24d74d0ac59b47d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_currency_exchange_rate(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_f1d5e24d74d0ac59b47d(uuid, jsonb)','062c91ed8648f516575101b741638a87',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_document_template(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_document_template(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_document_template(','FUNCTION private.c02_observed_3f9e8a4a26108e20228d(');
 ALTER FUNCTION private.c02_observed_3f9e8a4a26108e20228d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3f9e8a4a26108e20228d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3f9e8a4a26108e20228d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_document_template(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_3f9e8a4a26108e20228d(uuid, jsonb)','b8d810cb0a87b495693f11ab076bd924',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_document_template_v2(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_document_template_v2(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_document_template_v2(','FUNCTION private.c02_observed_7732f0dfb9a65ed75d11(');
 ALTER FUNCTION private.c02_observed_7732f0dfb9a65ed75d11(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7732f0dfb9a65ed75d11(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7732f0dfb9a65ed75d11(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_document_template_v2(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_7732f0dfb9a65ed75d11(uuid, jsonb)','750e5fb5b7ccd2f745bd1b64c4bb2173',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_payroll_employee(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_payroll_employee(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_payroll_employee(','FUNCTION private.c02_observed_41629924c61832a547bd(');
 ALTER FUNCTION private.c02_observed_41629924c61832a547bd(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_41629924c61832a547bd(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_41629924c61832a547bd(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_payroll_employee(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_41629924c61832a547bd(uuid, jsonb)','6d8ed1e36fc20f96aae2b7880b6d2da5',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_payroll_loan(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_payroll_loan(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_payroll_loan(','FUNCTION private.c02_observed_c3384698b30c88f2a8a6(');
 ALTER FUNCTION private.c02_observed_c3384698b30c88f2a8a6(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c3384698b30c88f2a8a6(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c3384698b30c88f2a8a6(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_payroll_loan(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_c3384698b30c88f2a8a6(uuid, jsonb)','e2aa7f69b8c603c7c9affab77e4c2fbf',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_service_catalog_item(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_service_catalog_item(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_service_catalog_item(','FUNCTION private.c02_observed_e6ba73d80def3d922776(');
 ALTER FUNCTION private.c02_observed_e6ba73d80def3d922776(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e6ba73d80def3d922776(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e6ba73d80def3d922776(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_service_catalog_item(uuid, jsonb)','closed_legacy_rpc','private.c02_observed_e6ba73d80def3d922776(uuid, jsonb)','4a002a8d8b1b969add14a35b085a859e',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_validate_billing_document_for_api(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_validate_billing_document_for_api(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_validate_billing_document_for_api(','FUNCTION private.c02_observed_5b19bf7557a5a770f689(');
 ALTER FUNCTION private.c02_observed_5b19bf7557a5a770f689(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_5b19bf7557a5a770f689(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_5b19bf7557a5a770f689(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_validate_billing_document_for_api(uuid)','closed_legacy_rpc','private.c02_observed_5b19bf7557a5a770f689(uuid)','b31bc28552ee676e6dee5afa897dd189',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_void_operation_billing(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_void_operation_billing(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_void_operation_billing(','FUNCTION private.c02_observed_b5840236291f23655a48(');
 ALTER FUNCTION private.c02_observed_b5840236291f23655a48(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b5840236291f23655a48(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b5840236291f23655a48(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_void_operation_billing(uuid, text)','closed_legacy_rpc','private.c02_observed_b5840236291f23655a48(uuid, text)','889ab7d3ad42de1f98669ec01fa20038',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda2_amount_mxn(numeric, text, numeric)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda2_amount_mxn(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda2_amount_mxn(','FUNCTION private.c02_observed_e76b4c050b4404a4b354(');
 ALTER FUNCTION private.c02_observed_e76b4c050b4404a4b354(numeric, text, numeric) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e76b4c050b4404a4b354(numeric, text, numeric) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e76b4c050b4404a4b354(numeric, text, numeric) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda2_amount_mxn(numeric, text, numeric)','pure_input_helper','private.c02_observed_e76b4c050b4404a4b354(numeric, text, numeric)','e2714b90800837c04ab1c191dd361721',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda2_user_has_role(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda2_user_has_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda2_user_has_role(','FUNCTION private.c02_observed_21393ca430221b952f77(');
 ALTER FUNCTION private.c02_observed_21393ca430221b952f77(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_21393ca430221b952f77(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_21393ca430221b952f77(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda2_user_has_role(uuid, text[])','own_membership_metadata','private.c02_observed_21393ca430221b952f77(uuid, text[])','474ac0db33c1731136e056699004dd4c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda3_sync_payroll_period_from_finance()'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda3_sync_payroll_period_from_finance(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda3_sync_payroll_period_from_finance(','FUNCTION private.c02_observed_6ee7c7d0a1e93cea062f(');
 ALTER FUNCTION private.c02_observed_6ee7c7d0a1e93cea062f() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_6ee7c7d0a1e93cea062f() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_6ee7c7d0a1e93cea062f() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda3_sync_payroll_period_from_finance()','internal_trigger','private.c02_observed_6ee7c7d0a1e93cea062f()','3a5452c72bcf81166023b2109cdcfef9',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda3_user_has_role(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda3_user_has_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda3_user_has_role(','FUNCTION private.c02_observed_82b1070f8ac97c5ff60b(');
 ALTER FUNCTION private.c02_observed_82b1070f8ac97c5ff60b(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_82b1070f8ac97c5ff60b(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_82b1070f8ac97c5ff60b(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda3_user_has_role(uuid, text[])','own_membership_metadata','private.c02_observed_82b1070f8ac97c5ff60b(uuid, text[])','8eaefcf36bcef1f38920b6d841ca54e7',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_document_prefix(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_document_prefix(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_document_prefix(','FUNCTION private.c02_observed_e79e6e860ccc693926dc(');
 ALTER FUNCTION private.c02_observed_e79e6e860ccc693926dc(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e79e6e860ccc693926dc(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e79e6e860ccc693926dc(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_document_prefix(text)','pure_input_helper','private.c02_observed_e79e6e860ccc693926dc(text)','63a6bb578dfe70e325d9ee558172a778',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_document_type_label(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_document_type_label(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_document_type_label(','FUNCTION private.c02_observed_ae29d04bd6a2884a6012(');
 ALTER FUNCTION private.c02_observed_ae29d04bd6a2884a6012(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_ae29d04bd6a2884a6012(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_ae29d04bd6a2884a6012(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_document_type_label(text)','pure_input_helper','private.c02_observed_ae29d04bd6a2884a6012(text)','277d5955eb0a4990044861d3f1189158',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_ensure_document_template(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_ensure_document_template(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_ensure_document_template(','FUNCTION private.c02_observed_fd3310a7bc9d037fc502(');
 ALTER FUNCTION private.c02_observed_fd3310a7bc9d037fc502(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_fd3310a7bc9d037fc502(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_fd3310a7bc9d037fc502(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_ensure_document_template(uuid, text)','server_only_helper','private.c02_observed_fd3310a7bc9d037fc502(uuid, text)','507e48582b01525e1967bb7b58fcb169',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_escape_html(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_escape_html(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_escape_html(','FUNCTION private.c02_observed_37adfd691f00c4168f95(');
 ALTER FUNCTION private.c02_observed_37adfd691f00c4168f95(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_37adfd691f00c4168f95(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_37adfd691f00c4168f95(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_escape_html(text)','pure_input_helper','private.c02_observed_37adfd691f00c4168f95(text)','c86a994707fc2484969553695f5931d7',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_field_visible(jsonb, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_field_visible(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_field_visible(','FUNCTION private.c02_observed_9eba11a8d067d7e4117d(');
 ALTER FUNCTION private.c02_observed_9eba11a8d067d7e4117d(jsonb, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9eba11a8d067d7e4117d(jsonb, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9eba11a8d067d7e4117d(jsonb, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_field_visible(jsonb, jsonb)','pure_input_helper','private.c02_observed_9eba11a8d067d7e4117d(jsonb, jsonb)','7414e95974da4f89c5cda089f8f6605b',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_generated_documents_defaults()'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_generated_documents_defaults(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_generated_documents_defaults(','FUNCTION private.c02_observed_23541a53da1b855c8631(');
 ALTER FUNCTION private.c02_observed_23541a53da1b855c8631() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_23541a53da1b855c8631() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_23541a53da1b855c8631() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_generated_documents_defaults()','internal_trigger','private.c02_observed_23541a53da1b855c8631()','ad92bba86eb01068533b4e65b1ae9223',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_money(numeric, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_money(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_money(','FUNCTION private.c02_observed_11a2adf633505590b58e(');
 ALTER FUNCTION private.c02_observed_11a2adf633505590b58e(numeric, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_11a2adf633505590b58e(numeric, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_11a2adf633505590b58e(numeric, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_money(numeric, text)','pure_input_helper','private.c02_observed_11a2adf633505590b58e(numeric, text)','b543cee4f8df06987ebc6c05221ac03e',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_render_document_html(uuid, jsonb, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_render_document_html(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_render_document_html(','FUNCTION private.c02_observed_d1ac57d0a1319266d54d(');
 ALTER FUNCTION private.c02_observed_d1ac57d0a1319266d54d(uuid, jsonb, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d1ac57d0a1319266d54d(uuid, jsonb, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d1ac57d0a1319266d54d(uuid, jsonb, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_render_document_html(uuid, jsonb, text)','server_only_helper','private.c02_observed_d1ac57d0a1319266d54d(uuid, jsonb, text)','6f1d6da37f249c7a9970be4c22d7bb12',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda4_user_has_role(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda4_user_has_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda4_user_has_role(','FUNCTION private.c02_observed_37b67d37b8c91a975901(');
 ALTER FUNCTION private.c02_observed_37b67d37b8c91a975901(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_37b67d37b8c91a975901(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_37b67d37b8c91a975901(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda4_user_has_role(uuid, text[])','own_membership_metadata','private.c02_observed_37b67d37b8c91a975901(uuid, text[])','7f8bd8a75cfeec7669a295c935f3890a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda5_storage_tenant_from_path(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda5_storage_tenant_from_path(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda5_storage_tenant_from_path(','FUNCTION private.c02_observed_263cf1e5f5d4990174c2(');
 ALTER FUNCTION private.c02_observed_263cf1e5f5d4990174c2(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_263cf1e5f5d4990174c2(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_263cf1e5f5d4990174c2(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda5_storage_tenant_from_path(text)','pure_input_helper','private.c02_observed_263cf1e5f5d4990174c2(text)','b9499fda114d462c885e39a440890857',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda5_user_has_role(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda5_user_has_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda5_user_has_role(','FUNCTION private.c02_observed_87cd66a16b783390a028(');
 ALTER FUNCTION private.c02_observed_87cd66a16b783390a028(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_87cd66a16b783390a028(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_87cd66a16b783390a028(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda5_user_has_role(uuid, text[])','own_membership_metadata','private.c02_observed_87cd66a16b783390a028(uuid, text[])','7f8bd8a75cfeec7669a295c935f3890a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda6_can_mutate_area(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda6_can_mutate_area(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda6_can_mutate_area(','FUNCTION private.c02_observed_bcfcbf7418200fedfc39(');
 ALTER FUNCTION private.c02_observed_bcfcbf7418200fedfc39(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_bcfcbf7418200fedfc39(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_bcfcbf7418200fedfc39(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda6_can_mutate_area(uuid, text)','own_membership_metadata','private.c02_observed_bcfcbf7418200fedfc39(uuid, text)','fb68e4a17129663695be4731253285b4',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda6_can_view_area(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda6_can_view_area(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda6_can_view_area(','FUNCTION private.c02_observed_48028a25d24058127b76(');
 ALTER FUNCTION private.c02_observed_48028a25d24058127b76(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_48028a25d24058127b76(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_48028a25d24058127b76(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda6_can_view_area(uuid, text)','own_membership_metadata','private.c02_observed_48028a25d24058127b76(uuid, text)','f573200a9f7d7875104641ecfd8d9618',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda6_touch_daily_work_item_updated_at()'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda6_touch_daily_work_item_updated_at(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda6_touch_daily_work_item_updated_at(','FUNCTION private.c02_observed_4f79d0120dccff087558(');
 ALTER FUNCTION private.c02_observed_4f79d0120dccff087558() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_4f79d0120dccff087558() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_4f79d0120dccff087558() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda6_touch_daily_work_item_updated_at()','internal_trigger','private.c02_observed_4f79d0120dccff087558()','f8778fa84b849f96f2f2197b9a7b56fb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda6_user_role(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda6_user_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda6_user_role(','FUNCTION private.c02_observed_c07f100b50d8967d559f(');
 ALTER FUNCTION private.c02_observed_c07f100b50d8967d559f(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c07f100b50d8967d559f(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c07f100b50d8967d559f(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda6_user_role(uuid)','own_membership_metadata','private.c02_observed_c07f100b50d8967d559f(uuid)','908abfe021fe32306b1c967c51b32061',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda7_bool_setting(jsonb, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda7_bool_setting(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda7_bool_setting(','FUNCTION private.c02_observed_419df7bb5a2ee5da847a(');
 ALTER FUNCTION private.c02_observed_419df7bb5a2ee5da847a(jsonb, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_419df7bb5a2ee5da847a(jsonb, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_419df7bb5a2ee5da847a(jsonb, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda7_bool_setting(jsonb, text, boolean)','pure_input_helper','private.c02_observed_419df7bb5a2ee5da847a(jsonb, text, boolean)','0a16dedf2548399703e3099032a189e1',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda7_section_order(jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda7_section_order(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda7_section_order(','FUNCTION private.c02_observed_646df27c542579f13e85(');
 ALTER FUNCTION private.c02_observed_646df27c542579f13e85(jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_646df27c542579f13e85(jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_646df27c542579f13e85(jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda7_section_order(jsonb)','pure_input_helper','private.c02_observed_646df27c542579f13e85(jsonb)','6ab3fbbf19ce1650d5dd86fa92d94eee',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda8_notification_icon(text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda8_notification_icon(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda8_notification_icon(','FUNCTION private.c02_observed_04212e9bfc615f463506(');
 ALTER FUNCTION private.c02_observed_04212e9bfc615f463506(text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_04212e9bfc615f463506(text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_04212e9bfc615f463506(text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda8_notification_icon(text, text)','pure_input_helper','private.c02_observed_04212e9bfc615f463506(text, text)','7e7dcbac656eb43505c8e8e3f541debc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda8_notification_trigger_type(text, text, text, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda8_notification_trigger_type(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda8_notification_trigger_type(','FUNCTION private.c02_observed_73463fd0fb8b143b4e23(');
 ALTER FUNCTION private.c02_observed_73463fd0fb8b143b4e23(text, text, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_73463fd0fb8b143b4e23(text, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_73463fd0fb8b143b4e23(text, text, text, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda8_notification_trigger_type(text, text, text, boolean)','pure_input_helper','private.c02_observed_73463fd0fb8b143b4e23(text, text, text, boolean)','2e0ad695ea27fe448d0041290b68f384',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda8_seed_default_notification_rules(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda8_seed_default_notification_rules(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda8_seed_default_notification_rules(','FUNCTION private.c02_observed_8fa285f7c40fbe0489e7(');
 ALTER FUNCTION private.c02_observed_8fa285f7c40fbe0489e7(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8fa285f7c40fbe0489e7(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8fa285f7c40fbe0489e7(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda8_seed_default_notification_rules(uuid)','server_only_helper','private.c02_observed_8fa285f7c40fbe0489e7(uuid)','81f6de2702963d83af00ff57547bef24',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda8_touch_notification_rule_updated_at()'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda8_touch_notification_rule_updated_at(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda8_touch_notification_rule_updated_at(','FUNCTION private.c02_observed_9f1bb433fc7afd47d115(');
 ALTER FUNCTION private.c02_observed_9f1bb433fc7afd47d115() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9f1bb433fc7afd47d115() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9f1bb433fc7afd47d115() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda8_touch_notification_rule_updated_at()','internal_trigger','private.c02_observed_9f1bb433fc7afd47d115()','f8778fa84b849f96f2f2197b9a7b56fb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tracking_expire_tokens()'::regprocedure) INTO d;
 IF position('FUNCTION public.tracking_expire_tokens(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tracking_expire_tokens(','FUNCTION private.c02_observed_7dbbe9e663f193bbe57c(');
 ALTER FUNCTION private.c02_observed_7dbbe9e663f193bbe57c() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7dbbe9e663f193bbe57c() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7dbbe9e663f193bbe57c() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tracking_expire_tokens()','server_only_helper','private.c02_observed_7dbbe9e663f193bbe57c()','14f463f7797eaf28dd54831efa3925f0',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone)'::regprocedure) INTO d;
 IF position('FUNCTION public.tracking_try_append_route_point(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tracking_try_append_route_point(','FUNCTION private.c02_observed_b2b42cf02231e345a512(');
 ALTER FUNCTION private.c02_observed_b2b42cf02231e345a512(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b2b42cf02231e345a512(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b2b42cf02231e345a512(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone)','server_only_helper','private.c02_observed_b2b42cf02231e345a512(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone)','9466be818fe309f66628f0352bfc0b48',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_add_deal_activity(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_add_deal_activity(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_add_deal_activity(','FUNCTION private.c02_observed_570c58a704ef3622978b(');
 ALTER FUNCTION private.c02_observed_570c58a704ef3622978b(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_570c58a704ef3622978b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_570c58a704ef3622978b(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_add_deal_activity(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_570c58a704ef3622978b(uuid, jsonb)','1736874591f9dc8c9951dfe65247435b',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_add_deal_note(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_add_deal_note(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_add_deal_note(','FUNCTION private.c02_observed_ff3b8885b4d257d48d2d(');
 ALTER FUNCTION private.c02_observed_ff3b8885b4d257d48d2d(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_ff3b8885b4d257d48d2d(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_ff3b8885b4d257d48d2d(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_add_deal_note(uuid, text)','canonical_contract_and_security','private.c02_observed_ff3b8885b4d257d48d2d(uuid, text)','2cb9d286e23de4b04df96eb6550e35eb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_assign_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_assign_operation(','FUNCTION private.c02_observed_60887222820f37e469d0(');
 ALTER FUNCTION private.c02_observed_60887222820f37e469d0(uuid, uuid, uuid, uuid, timestamp with time zone, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_60887222820f37e469d0(uuid, uuid, uuid, uuid, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_60887222820f37e469d0(uuid, uuid, uuid, uuid, timestamp with time zone, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text)','canonical_contract_and_security','private.c02_observed_60887222820f37e469d0(uuid, uuid, uuid, uuid, timestamp with time zone, text)','77f9f3e92455aa0c8d53013f6d748920',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_cfdi(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_cfdi(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_cfdi(','FUNCTION private.c02_observed_dc1f92c600e4cb34b42d(');
 ALTER FUNCTION private.c02_observed_dc1f92c600e4cb34b42d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_dc1f92c600e4cb34b42d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_dc1f92c600e4cb34b42d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_cfdi(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_dc1f92c600e4cb34b42d(uuid, jsonb)','e90c358a7d090179e659e76ffda16f0b',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_deal(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_deal(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_deal(','FUNCTION private.c02_observed_c65c3571003421848d24(');
 ALTER FUNCTION private.c02_observed_c65c3571003421848d24(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c65c3571003421848d24(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c65c3571003421848d24(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_deal(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_c65c3571003421848d24(uuid, jsonb)','d546b820d5fcbf7d34987ef6d24ad6cc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_operation(','FUNCTION private.c02_observed_363b1f46bca0efdae12f(');
 ALTER FUNCTION private.c02_observed_363b1f46bca0efdae12f(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_363b1f46bca0efdae12f(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_363b1f46bca0efdae12f(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone)','canonical_contract_and_security','private.c02_observed_363b1f46bca0efdae12f(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone)','c175bf985e6058bbf33f7d0e441938cb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_create_pedimento(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_create_pedimento(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_create_pedimento(','FUNCTION private.c02_observed_31e1fc3950db18a6050a(');
 ALTER FUNCTION private.c02_observed_31e1fc3950db18a6050a(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_31e1fc3950db18a6050a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_31e1fc3950db18a6050a(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_create_pedimento(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_31e1fc3950db18a6050a(uuid, jsonb)','d0806f581d66d520a2b618b5fa30efaf',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_deactivate_member(uuid, uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_deactivate_member(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_deactivate_member(','FUNCTION private.c02_observed_0d2c129a22d2798cbaa3(');
 ALTER FUNCTION private.c02_observed_0d2c129a22d2798cbaa3(uuid, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_0d2c129a22d2798cbaa3(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_0d2c129a22d2798cbaa3(uuid, uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_deactivate_member(uuid, uuid)','canonical_contract_and_security','private.c02_observed_0d2c129a22d2798cbaa3(uuid, uuid)','139dde21e7e7e43587342f78b8c8d1eb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_generate_document(uuid, text, text, uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_generate_document(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_generate_document(','FUNCTION private.c02_observed_b7c112a53f3f3d5f0046(');
 ALTER FUNCTION private.c02_observed_b7c112a53f3f3d5f0046(uuid, text, text, uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b7c112a53f3f3d5f0046(uuid, text, text, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b7c112a53f3f3d5f0046(uuid, text, text, uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_generate_document(uuid, text, text, uuid, jsonb)','canonical_contract_and_security','private.c02_observed_b7c112a53f3f3d5f0046(uuid, text, text, uuid, jsonb)','f8b9c49e695543dca9bca25b2ee21709',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_cfdi_detail(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_cfdi_detail(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_cfdi_detail(','FUNCTION private.c02_observed_e13d31ab0fb3c7597615(');
 ALTER FUNCTION private.c02_observed_e13d31ab0fb3c7597615(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_e13d31ab0fb3c7597615(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_e13d31ab0fb3c7597615(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_cfdi_detail(uuid)','canonical_contract_and_security','private.c02_observed_e13d31ab0fb3c7597615(uuid)','157262dfbed74fb65a851e57a5627292',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_driver_view(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_driver_view(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_driver_view(','FUNCTION private.c02_observed_9f5b52c94f1abd0f3ec1(');
 ALTER FUNCTION private.c02_observed_9f5b52c94f1abd0f3ec1(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9f5b52c94f1abd0f3ec1(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9f5b52c94f1abd0f3ec1(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_driver_view(text)','keep_token_service_variant','private.c02_observed_9f5b52c94f1abd0f3ec1(text)','08a04f481ca61667710c3953e1fd7298',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_my_context()'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_my_context(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_my_context(','FUNCTION private.c02_observed_7d08488617fa86f9f9aa(');
 ALTER FUNCTION private.c02_observed_7d08488617fa86f9f9aa() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7d08488617fa86f9f9aa() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7d08488617fa86f9f9aa() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_my_context()','canonical_contract_and_security','private.c02_observed_7d08488617fa86f9f9aa()','d47b42001de3ce4cc19d2d55f8a9c97f',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_operation(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_operation(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_operation(','FUNCTION private.c02_observed_b571e0e8bae75d2b9fb1(');
 ALTER FUNCTION private.c02_observed_b571e0e8bae75d2b9fb1(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b571e0e8bae75d2b9fb1(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b571e0e8bae75d2b9fb1(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_operation(uuid)','retain_enriched_legacy_and_canonical_scoped','private.c02_observed_b571e0e8bae75d2b9fb1(uuid)','3bb60865f2b71b8babc3930f73c75572',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_get_public_tracking(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_get_public_tracking(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_get_public_tracking(','FUNCTION private.c02_observed_08b1305fe80b2062f7dc(');
 ALTER FUNCTION private.c02_observed_08b1305fe80b2062f7dc(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_08b1305fe80b2062f7dc(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_08b1305fe80b2062f7dc(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_get_public_tracking(text)','keep_token_service_variant','private.c02_observed_08b1305fe80b2062f7dc(text)','02f079e276b1c44e3d3f7e0756dd2d23',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_cfdis(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_cfdis(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_cfdis(','FUNCTION private.c02_observed_eb597b550f2b0f3b5238(');
 ALTER FUNCTION private.c02_observed_eb597b550f2b0f3b5238(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_eb597b550f2b0f3b5238(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_eb597b550f2b0f3b5238(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_cfdis(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_eb597b550f2b0f3b5238(uuid, jsonb)','f41d7a081b710ae17c42e2e48657ea87',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_operations(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_operations(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_operations(','FUNCTION private.c02_observed_06c91f3c6cd8070eb6d8(');
 ALTER FUNCTION private.c02_observed_06c91f3c6cd8070eb6d8(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_06c91f3c6cd8070eb6d8(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_06c91f3c6cd8070eb6d8(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_operations(uuid)','retain_enriched_legacy_and_canonical_scoped','private.c02_observed_06c91f3c6cd8070eb6d8(uuid)','09ee77c4835e6f6d05778e9774ef7200',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_list_route_points(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_list_route_points(','FUNCTION private.c02_observed_0f04048c46d8734fa190(');
 ALTER FUNCTION private.c02_observed_0f04048c46d8734fa190(uuid, timestamp with time zone, timestamp with time zone, integer) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_0f04048c46d8734fa190(uuid, timestamp with time zone, timestamp with time zone, integer) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_0f04048c46d8734fa190(uuid, timestamp with time zone, timestamp with time zone, integer) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer)','keep_token_service_variant','private.c02_observed_0f04048c46d8734fa190(uuid, timestamp with time zone, timestamp with time zone, integer)','7b13425bb1ad61427e12003d464dcb2b',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_post_driver_event(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_post_driver_event(','FUNCTION private.c02_observed_7c1aa61f915938559b6e(');
 ALTER FUNCTION private.c02_observed_7c1aa61f915938559b6e(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7c1aa61f915938559b6e(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7c1aa61f915938559b6e(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean)','keep_token_service_variant','private.c02_observed_7c1aa61f915938559b6e(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean)','e580c2a786480e51b6a6048a2fd39f2c',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_reports_financial_summary(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_reports_financial_summary(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_reports_financial_summary(','FUNCTION private.c02_observed_d3b2ab28d0a1f450579b(');
 ALTER FUNCTION private.c02_observed_d3b2ab28d0a1f450579b(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d3b2ab28d0a1f450579b(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d3b2ab28d0a1f450579b(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_reports_financial_summary(uuid, text)','canonical_contract_and_security','private.c02_observed_d3b2ab28d0a1f450579b(uuid, text)','d9d8989744754ddce0e3388eb847a856',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_toggle_deal_checklist_item(uuid, boolean)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_toggle_deal_checklist_item(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_toggle_deal_checklist_item(','FUNCTION private.c02_observed_8aaf235c23e475815271(');
 ALTER FUNCTION private.c02_observed_8aaf235c23e475815271(uuid, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8aaf235c23e475815271(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8aaf235c23e475815271(uuid, boolean) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_toggle_deal_checklist_item(uuid, boolean)','canonical_contract_and_security','private.c02_observed_8aaf235c23e475815271(uuid, boolean)','de32f5f0ac9edc5c03d6dbc7a2b4a958',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_cfdi(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_cfdi(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_cfdi(','FUNCTION private.c02_observed_7129cfaea0fe59110b27(');
 ALTER FUNCTION private.c02_observed_7129cfaea0fe59110b27(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7129cfaea0fe59110b27(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7129cfaea0fe59110b27(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_cfdi(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_7129cfaea0fe59110b27(uuid, jsonb)','d1532c9792ad34882146370699c6f761',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_deal(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_deal(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_deal(','FUNCTION private.c02_observed_c80608e88ea275fbf8b3(');
 ALTER FUNCTION private.c02_observed_c80608e88ea275fbf8b3(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c80608e88ea275fbf8b3(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c80608e88ea275fbf8b3(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_deal(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_c80608e88ea275fbf8b3(uuid, jsonb)','d2f6cbcf9b0cc5e07f0dd798aa8283fc',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_inventory_lot(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_inventory_lot(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_inventory_lot(','FUNCTION private.c02_observed_7572522803cae03c4b59(');
 ALTER FUNCTION private.c02_observed_7572522803cae03c4b59(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_7572522803cae03c4b59(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_7572522803cae03c4b59(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_inventory_lot(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_7572522803cae03c4b59(uuid, jsonb)','445cf4c93edc41710bd7093848a276ee',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_member_role(uuid, uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_member_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_member_role(','FUNCTION private.c02_observed_b199a198e3619ac6bf42(');
 ALTER FUNCTION private.c02_observed_b199a198e3619ac6bf42(uuid, uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_b199a198e3619ac6bf42(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_b199a198e3619ac6bf42(uuid, uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_member_role(uuid, uuid, text)','canonical_contract_and_security','private.c02_observed_b199a198e3619ac6bf42(uuid, uuid, text)','2ebd6781fd2ab6e76f45746bca11dd3a',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_operation_details(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_operation_details(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_operation_details(','FUNCTION private.c02_observed_c682d19a2c44e9abe83c(');
 ALTER FUNCTION private.c02_observed_c682d19a2c44e9abe83c(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_c682d19a2c44e9abe83c(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_c682d19a2c44e9abe83c(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_operation_details(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_c682d19a2c44e9abe83c(uuid, jsonb)','5685e19f08b117f71cd1bd36075285e8',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_pedimento(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_pedimento(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_pedimento(','FUNCTION private.c02_observed_d09122252506178d5fa9(');
 ALTER FUNCTION private.c02_observed_d09122252506178d5fa9(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_d09122252506178d5fa9(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_d09122252506178d5fa9(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_pedimento(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_d09122252506178d5fa9(uuid, jsonb)','df90c88ae81e66230c2e4459eb3cd7d9',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_update_tenant_settings(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_update_tenant_settings(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_update_tenant_settings(','FUNCTION private.c02_observed_5c724372b9b714d0ea3d(');
 ALTER FUNCTION private.c02_observed_5c724372b9b714d0ea3d(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_5c724372b9b714d0ea3d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_5c724372b9b714d0ea3d(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_update_tenant_settings(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_5c724372b9b714d0ea3d(uuid, jsonb)','11a72591b873e2c24b0556aa58431bd1',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_upsert_carta_porte(uuid, jsonb)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_upsert_carta_porte(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_upsert_carta_porte(','FUNCTION private.c02_observed_77db399ca9c8b5faeb25(');
 ALTER FUNCTION private.c02_observed_77db399ca9c8b5faeb25(uuid, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_77db399ca9c8b5faeb25(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_77db399ca9c8b5faeb25(uuid, jsonb) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_upsert_carta_porte(uuid, jsonb)','canonical_contract_and_security','private.c02_observed_77db399ca9c8b5faeb25(uuid, jsonb)','a4b0d675206049c9abad5500eaa7f894',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.rpc_validate_module_access(uuid, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.rpc_validate_module_access(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.rpc_validate_module_access(','FUNCTION private.c02_observed_0cd040c1b6b7af27ac72(');
 ALTER FUNCTION private.c02_observed_0cd040c1b6b7af27ac72(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_0cd040c1b6b7af27ac72(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_0cd040c1b6b7af27ac72(uuid, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.rpc_validate_module_access(uuid, text)','canonical_contract_and_security','private.c02_observed_0cd040c1b6b7af27ac72(uuid, text)','fa60d4b36c8e9ff3d97d9e2fd06eebbe',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda1_touch_updated_at()'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda1_touch_updated_at(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda1_touch_updated_at(','FUNCTION private.c02_observed_05def937004eda2b69d0(');
 ALTER FUNCTION private.c02_observed_05def937004eda2b69d0() SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_05def937004eda2b69d0() FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_05def937004eda2b69d0() TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda1_touch_updated_at()','canonical_contract_and_security','private.c02_observed_05def937004eda2b69d0()','f8778fa84b849f96f2f2197b9a7b56fb',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda1_user_has_role(uuid, text[])'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda1_user_has_role(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda1_user_has_role(','FUNCTION private.c02_observed_9a4a4a1ea415794ae1d9(');
 ALTER FUNCTION private.c02_observed_9a4a4a1ea415794ae1d9(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_9a4a4a1ea415794ae1d9(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_9a4a4a1ea415794ae1d9(uuid, text[]) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda1_user_has_role(uuid, text[])','canonical_contract_and_security','private.c02_observed_9a4a4a1ea415794ae1d9(uuid, text[])','6c9832d101e3f39329a72e95aaaa9a08',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tanda1_user_is_member(uuid)'::regprocedure) INTO d;
 IF position('FUNCTION public.tanda1_user_is_member(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tanda1_user_is_member(','FUNCTION private.c02_observed_8a1d2fba06dac26f7d59(');
 ALTER FUNCTION private.c02_observed_8a1d2fba06dac26f7d59(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_8a1d2fba06dac26f7d59(uuid) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_8a1d2fba06dac26f7d59(uuid) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tanda1_user_is_member(uuid)','canonical_contract_and_security','private.c02_observed_8a1d2fba06dac26f7d59(uuid)','01e6a198988d9057bef6c287534dfd45',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tracking_hash_token(text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tracking_hash_token(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tracking_hash_token(','FUNCTION private.c02_observed_f3f51c9935849650bfd1(');
 ALTER FUNCTION private.c02_observed_f3f51c9935849650bfd1(text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_f3f51c9935849650bfd1(text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_f3f51c9935849650bfd1(text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tracking_hash_token(text)','canonical_contract_and_security','private.c02_observed_f3f51c9935849650bfd1(text)','5e95bf5111999be9353490bc8f439ae2',current_setting('cierre02.source_variant'));

DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef('public.tracking_validate_token(text, text)'::regprocedure) INTO d;
 IF position('FUNCTION public.tracking_validate_token(' IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,'FUNCTION public.tracking_validate_token(','FUNCTION private.c02_observed_3d608aebfd21b99265be(');
 ALTER FUNCTION private.c02_observed_3d608aebfd21b99265be(text, text) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.c02_observed_3d608aebfd21b99265be(text, text) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.c02_observed_3d608aebfd21b99265be(text, text) TO rotero_c02_gate_owner;
 END IF;END $capture$;

INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('public.tracking_validate_token(text, text)','keep_token_service_variant','private.c02_observed_3d608aebfd21b99265be(text, text)','299eeb69d699936077f671ddaee0255a',current_setting('cierre02.source_variant'));

ALTER TABLE public.billing_carta_porte ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

DO $compat$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER TABLE public.billing_carta_porte ALTER COLUMN updated_at SET DEFAULT now();END IF;END $compat$;

ALTER TABLE public.billing_cfdis ADD COLUMN IF NOT EXISTS operation_id uuid;

ALTER TABLE public.crm_deal_checklist_items ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone;

ALTER TABLE public.crm_deal_checklist_items ADD COLUMN IF NOT EXISTS completed_by uuid;

ALTER TABLE public.crm_deal_checklist_items ADD COLUMN IF NOT EXISTS created_at timestamp with time zone;

DO $compat$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER TABLE public.crm_deal_checklist_items ALTER COLUMN created_at SET DEFAULT now();END IF;END $compat$;

ALTER TABLE public.crm_deal_notes ADD COLUMN IF NOT EXISTS author_id uuid;

ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS license_ref text;

ALTER TABLE public.inventory_lots ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone;

DO $compat$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER TABLE public.inventory_lots ALTER COLUMN updated_at SET DEFAULT now();END IF;END $compat$;

ALTER TABLE public.tenant_settings ADD COLUMN IF NOT EXISTS notifications_enabled boolean;

DO $compat$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER TABLE public.tenant_settings ALTER COLUMN notifications_enabled SET DEFAULT true;END IF;END $compat$;

ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS plate_ref text;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can view audit_log" ON public.audit_log TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_api_attempts_insert_tenant_operators" ON public.billing_api_attempts TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_api_attempts_select_tenant_members" ON public.billing_api_attempts TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_api_outbox_insert_tenant_operators" ON public.billing_api_outbox TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_api_outbox_select_tenant_members" ON public.billing_api_outbox TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_api_outbox_update_tenant_operators" ON public.billing_api_outbox TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read billing_carta_porte in their tenants" ON public.billing_carta_porte TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read billing_cfdis in their tenants" ON public.billing_cfdis TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_credit_notes_manage_finance" ON public.billing_credit_notes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_credit_notes_select_tenant_members" ON public.billing_credit_notes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_lines_delete_tenant_operators" ON public.billing_document_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_lines_insert_tenant_operators" ON public.billing_document_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_lines_select_tenant_members" ON public.billing_document_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_lines_update_tenant_operators" ON public.billing_document_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_parties_insert_tenant_operators" ON public.billing_document_parties TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_parties_select_tenant_members" ON public.billing_document_parties TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_parties_update_tenant_operators" ON public.billing_document_parties TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_taxes_delete_tenant_operators" ON public.billing_document_taxes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_taxes_insert_tenant_operators" ON public.billing_document_taxes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_taxes_select_tenant_members" ON public.billing_document_taxes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_document_taxes_update_tenant_operators" ON public.billing_document_taxes TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_documents_insert_tenant_operators" ON public.billing_documents TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_documents_select_tenant_members" ON public.billing_documents TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_documents_update_tenant_operators" ON public.billing_documents TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_fiscal_profiles_insert_tenant_operators" ON public.billing_fiscal_profiles TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_fiscal_profiles_select_tenant_members" ON public.billing_fiscal_profiles TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_fiscal_profiles_update_tenant_operators" ON public.billing_fiscal_profiles TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_payment_complements_manage_finance" ON public.billing_payment_complements TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_payment_complements_select_tenant_members" ON public.billing_payment_complements TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_sat_catalog_entries_insert_tenant_operators" ON public.billing_sat_catalog_entries TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_sat_catalog_entries_select" ON public.billing_sat_catalog_entries TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "billing_sat_catalog_entries_update_tenant_operators" ON public.billing_sat_catalog_entries TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can insert crm_deal_activity in their tenants" ON public.crm_deal_activity TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read crm_deal_activity in their tenants" ON public.crm_deal_activity TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update crm_deal_activity in their tenants" ON public.crm_deal_activity TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can delete crm_deals in their tenants" ON public.crm_deals TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can insert crm_deals in their tenants" ON public.crm_deals TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read crm_deals in their tenants" ON public.crm_deals TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update crm_deals in their tenants" ON public.crm_deals TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "currency_exchange_rates_manage_finance" ON public.currency_exchange_rates TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "currency_exchange_rates_select_tenant_members" ON public.currency_exchange_rates TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "customers_select_tenant_members" ON public.customers TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can create descargo lines in their tenants" ON public.customs_descargo_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can delete descargo lines in their tenants" ON public.customs_descargo_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read descargo lines in their tenants" ON public.customs_descargo_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update descargo lines in their tenants" ON public.customs_descargo_lines TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can create pedimentos in their tenants" ON public.customs_pedimentos TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read pedimentos in their tenants" ON public.customs_pedimentos TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update pedimentos in their tenants" ON public.customs_pedimentos TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "daily_work_items_insert_by_role_area" ON public.daily_work_items TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "daily_work_items_select_by_role_area" ON public.daily_work_items TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "daily_work_items_update_by_role_area" ON public.daily_work_items TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "drivers_admin_manage" ON public.drivers TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "drivers_select_tenant_members" ON public.drivers TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read finance_invoices in their tenants" ON public.finance_invoices TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read finance_payments in their tenants" ON public.finance_payments TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "internal_notification_rules_manage_admin" ON public.internal_notification_rules TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "internal_notification_rules_select_by_tenant" ON public.internal_notification_rules TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "internal_notifications_select_own" ON public.internal_notifications TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "internal_notifications_update_own" ON public.internal_notifications TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can create inventory in their tenants" ON public.inventory_lots TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can read inventory in their tenants" ON public.inventory_lots TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update inventory in their tenants" ON public.inventory_lots TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "logistics_providers_manage_tenant_ops" ON public.logistics_providers TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "logistics_providers_select_tenant_members" ON public.logistics_providers TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "operation_assignment_history_select_tenant_members" ON public.operation_assignment_history TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "operation_billing_select_tenant_members" ON public.operation_billing TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "operation_documents_select_tenant_members" ON public.operation_documents TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "operation_evidence_select_tenant_members" ON public.operation_evidence TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "operation_incidents_select_tenant_members" ON public.operation_incidents TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can create operations in their tenants" ON public.operations TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can delete operations in their tenants" ON public.operations TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can update operations in their tenants" ON public.operations TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_employees_manage_finance" ON public.payroll_employees TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_entries_manage_finance" ON public.payroll_entries TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_entry_items_manage_finance" ON public.payroll_entry_items TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_loans_manage_finance" ON public.payroll_loans TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_periods_manage_finance" ON public.payroll_periods TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "payroll_receipts_manage_finance" ON public.payroll_receipts TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Admins and Operators can update tenant settings" ON public.tenant_settings TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Admins can insert tenant settings" ON public.tenant_settings TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "Users can view their tenant settings" ON public.tenant_settings TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "route_points_select_members" ON public.tracking_route_points TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "vehicles_admin_manage" ON public.vehicles TO anon,authenticated,service_role;END IF;END $policy_roles$;

DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY "vehicles_select_tenant_members" ON public.vehicles TO anon,authenticated,service_role;END IF;END $policy_roles$;

-- Cover observed document FKs without changing rows or relaxing integrity.
-- Restore the canonical server-only access-log insert exception, missing on B.
GRANT INSERT(token_hash,ip_hash,user_agent,country_code) ON public.tracking_access_log TO service_role;
DO $document_indexes$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 CREATE INDEX c02_document_files_billing_fk ON public.document_files(billing_document_id);
 CREATE INDEX c02_document_files_generated_fk ON public.document_files(generated_document_id);
 CREATE INDEX c02_document_files_uploader_fk ON public.document_files(uploaded_by);
 CREATE INDEX c02_document_relations_creator_fk ON public.document_relations(created_by);
 CREATE INDEX c02_document_versions_creator_fk ON public.document_template_versions(created_by);
 CREATE INDEX c02_document_templates_creator_fk ON public.document_templates(created_by);
 CREATE INDEX c02_generated_documents_creator_fk ON public.generated_documents(generated_by);
END IF;END $document_indexes$;

CREATE OR REPLACE FUNCTION public.rpc_accept_invitation(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_email text;
    v_invitation public.invitations%ROWTYPE;
    v_membership_inserted integer := 0;
    v_state text;
BEGIN
    IF v_actor IS NULL THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'authentication_required');
    END IF;

    SELECT lower(btrim(u.email))
    INTO v_email
    FROM auth.users AS u
    WHERE u.id = v_actor
      AND u.email IS NOT NULL
      AND u.email_confirmed_at IS NOT NULL;

    IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{48}$' THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;

    SELECT i.* INTO v_invitation FROM public.invitations AS i
    WHERE i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;
    IF v_invitation.accepted_at IS NOT NULL THEN
        IF v_invitation.accepted_by = v_actor THEN
            RETURN jsonb_build_object('accepted', true, 'state', 'already_accepted');
        END IF;
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;
    IF v_invitation.revoked_at IS NOT NULL
       OR v_invitation.expires_at <= now()
       OR v_invitation.email <> v_email
       OR v_invitation.role NOT IN ('admin', 'operator', 'finance', 'viewer')
       OR NOT EXISTS (SELECT 1 FROM public.tenants AS t WHERE t.id = v_invitation.tenant_id) THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;

    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES (v_invitation.tenant_id, v_actor, v_invitation.role)
    ON CONFLICT (user_id, tenant_id) DO NOTHING;
    GET DIAGNOSTICS v_membership_inserted = ROW_COUNT;

    v_state := CASE WHEN v_membership_inserted = 1 THEN 'accepted' ELSE 'already_member' END;

    UPDATE public.invitations
    SET accepted_at = now(), accepted_by = v_actor
    WHERE id = v_invitation.id;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (
        v_invitation.tenant_id,
        v_actor,
        CASE WHEN v_membership_inserted = 1 THEN 'invitation_accepted' ELSE 'invitation_already_member' END,
        'invitation',
        v_invitation.id,
        jsonb_build_object('role', v_invitation.role)
    );

    RETURN jsonb_build_object('accepted', true, 'state', v_state);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_accept_invitation(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_accept_invitation(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v2(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text DEFAULT 'normal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o
    SET driver_id = p_driver_id, driver_name = NULLIF(p_driver_name, ''),
        vehicle_id = p_vehicle_id, vehicle_ref = NULLIF(p_vehicle_ref, ''),
        planned_departure = p_planned_departure, priority = p_priority,
        assigned_at = now(), status = CASE WHEN o.status IN ('planned', 'draft') THEN 'assigned' ELSE o.status END
    WHERE o.id = p_operation_id AND o.tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_create_inventory_lot(p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_currency text, p_pedimento_ref text, p_description text, p_unit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.inventory_lots (tenant_id,sku,lot_code,qty_on_hand,warehouse,received_at,currency,pedimento_ref,description,unit)
    VALUES (p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_currency,p_pedimento_ref,p_description,p_unit) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, text, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.reference_code,'client',COALESCE(o.client_display_name,'N/A'),
        'status',o.status,'route',COALESCE(o.route_summary,o.destination_city,'N/A'),'eta',COALESCE(o.eta_display,'')) ORDER BY o.updated_at DESC)
        FROM (SELECT * FROM public.operations AS x WHERE x.tenant_id=p_tenant_id AND (p_start_date IS NULL OR x.created_at>=p_start_date)
            AND (p_end_date IS NULL OR x.created_at<=p_end_date) ORDER BY x.updated_at DESC LIMIT 10) AS o),'[]'::jsonb);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_dashboard_recent_activity(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid, timestamp with time zone, timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_list_invitations(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_tenant_id IS NULL
       OR NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', i.id,
            'email', i.email,
            'role', i.role,
            'state', CASE
                WHEN i.accepted_at IS NOT NULL THEN 'accepted'
                WHEN i.revoked_at IS NOT NULL THEN 'revoked'
                WHEN i.expires_at <= now() THEN 'expired'
                ELSE 'pending'
            END,
            'created_at', i.created_at,
            'expires_at', i.expires_at,
            'accepted_at', i.accepted_at,
            'revoked_at', i.revoked_at
        ) ORDER BY i.created_at DESC)
        FROM public.invitations AS i
        WHERE i.tenant_id = p_tenant_id
    ), '[]'::jsonb);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_list_invitations(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_invitations(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_move_deal(p_deal_id uuid, p_new_stage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid; v_old_stage text;
BEGIN
    SELECT d.tenant_id,d.stage INTO v_tenant_id,v_old_stage FROM public.crm_deals AS d WHERE d.id=p_deal_id FOR UPDATE;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_new_stage NOT IN ('lead','qualified','proposal','won','lost') THEN RETURN jsonb_build_object('error','invalid_stage'); END IF;
    UPDATE public.crm_deals SET stage=p_new_stage,last_touch_at=now() WHERE id=p_deal_id;
    INSERT INTO public.crm_deal_activity (tenant_id,deal_id,type,body,created_by)
    VALUES (v_tenant_id,p_deal_id,'status_change',v_old_stage||' -> '||p_new_stage,auth.uid());
    RETURN jsonb_build_object('success',true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_move_deal(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_move_deal(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_revoke_invitation(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_invitation public.invitations%ROWTYPE;
BEGIN
    IF v_actor IS NULL OR p_invitation_id IS NULL THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;

    SELECT i.* INTO v_invitation
    FROM public.invitations AS i
    WHERE i.id = p_invitation_id
      AND public.tanda1_user_has_role(i.tenant_id, ARRAY['admin'])
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'invalid_invitation');
    END IF;
    IF v_invitation.accepted_at IS NOT NULL THEN
        RETURN jsonb_build_object('accepted', false, 'state', 'already_accepted');
    END IF;
    IF v_invitation.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('accepted', true, 'state', 'already_revoked');
    END IF;

    UPDATE public.invitations
    SET revoked_at = now(), revoked_by = v_actor
    WHERE id = v_invitation.id;

    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id)
    VALUES (v_invitation.tenant_id, v_actor, 'invitation_revoked', 'invitation', v_invitation.id);

    RETURN jsonb_build_object('accepted', true, 'state', 'revoked');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_revoke_invitation(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_invitation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$
;

REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_deal_activity(p_deal_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.crm_deal_activity (tenant_id,deal_id,type,body,created_by)
    VALUES (v_tenant_id,p_deal_id,p_payload->>'type',p_payload->>'body',auth.uid()) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_add_deal_activity(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_add_deal_activity(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_add_deal_note(p_deal_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF NULLIF(btrim(p_note),'') IS NULL THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    INSERT INTO public.crm_deal_notes (tenant_id,deal_id,author_id,note) VALUES (v_tenant_id,p_deal_id,auth.uid(),p_note) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_add_deal_note(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_add_deal_note(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text DEFAULT 'normal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o
    SET driver_id = p_driver_id, vehicle_id = p_vehicle_id,
        planned_departure = p_planned_departure, priority = p_priority,
        assigned_at = now(), status = CASE WHEN o.status IN ('planned', 'draft') THEN 'assigned' ELSE o.status END
    WHERE o.id = p_operation_id AND o.tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_create_cfdi(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.billing_cfdis (tenant_id, operation_id, uuid, serie, folio, rfc_emisor, rfc_receptor,
        receptor_name, subtotal, total, currency, status, has_carta_porte, has_complemento_pago, issued_at, pac_provider, notes)
    VALUES (p_tenant_id, (p_payload->>'operation_id')::uuid, p_payload->>'uuid', p_payload->>'serie', p_payload->>'folio',
        p_payload->>'rfc_emisor', p_payload->>'rfc_receptor', p_payload->>'receptor_name', COALESCE((p_payload->>'subtotal')::numeric, 0),
        (p_payload->>'total')::numeric, COALESCE(p_payload->>'currency', 'MXN'), COALESCE(p_payload->>'status', 'draft'),
        COALESCE((p_payload->>'has_carta_porte')::boolean, false), COALESCE((p_payload->>'has_complemento_pago')::boolean, false),
        (p_payload->>'issued_at')::timestamptz, p_payload->>'pac_provider', p_payload->>'notes') RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN
    RETURN jsonb_build_object('error', 'invalid_payload');
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'uuid_conflict');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_create_cfdi(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_cfdi(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_create_deal(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.crm_deals (tenant_id,title,company,contact_name,contact_email,contact_phone,value,currency,stage,priority,notes,owner_user_id)
    VALUES (p_tenant_id,p_payload->>'title',p_payload->>'company',p_payload->>'contact_name',p_payload->>'contact_email',p_payload->>'contact_phone',
        (p_payload->>'value')::numeric,COALESCE(p_payload->>'currency','MXN'),COALESCE(p_payload->>'stage','lead'),
        COALESCE(p_payload->>'priority','medium'),p_payload->>'notes',(p_payload->>'owner_user_id')::uuid) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_create_deal(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_deal(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_create_operation(p_tenant_id uuid, p_reference_code text, p_route_summary text DEFAULT NULL::text, p_client_display_name text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_eta_display text DEFAULT NULL::text, p_status text DEFAULT 'planned'::text, p_origin_place jsonb DEFAULT NULL::jsonb, p_destination_place jsonb DEFAULT NULL::jsonb, p_eta timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO public.operations (
        tenant_id, reference_code, route_summary, client_display_name,
        destination_city, eta_display, status, origin_place,
        destination_place, eta
    ) VALUES (
        p_tenant_id, p_reference_code, p_route_summary, p_client_display_name,
        p_destination_city, p_eta_display, p_status, p_origin_place,
        p_destination_place, p_eta
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('id', v_id);
EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('error', 'reference_conflict');
    WHEN check_violation THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_create_pedimento(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.customs_pedimentos (tenant_id,pedimento_number,operation_id,aduana,regimen,tipo_operacion,status,fecha_pago,total_value,currency)
    VALUES (p_tenant_id,p_payload->>'pedimento_number',(p_payload->>'operation_id')::uuid,p_payload->>'aduana',p_payload->>'regimen',
        p_payload->>'tipo_operacion',COALESCE(p_payload->>'status','draft'),(p_payload->>'fecha_pago')::date,
        (p_payload->>'total_value')::numeric,COALESCE(p_payload->>'currency','MXN')) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN unique_violation THEN RETURN jsonb_build_object('error','pedimento_conflict');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_create_pedimento(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_pedimento(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_deactivate_member(p_tenant_id uuid, p_member_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_member_user_id = auth.uid() THEN RETURN jsonb_build_object('error', 'cannot_deactivate_self'); END IF;
    DELETE FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_deactivate_member(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_deactivate_member(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_generate_document(p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT public.rpc_generate_document_f3($1, $2, $3, $4, $5); $function$
;

REVOKE ALL ON FUNCTION public.rpc_generate_document(uuid, text, text, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_generate_document(uuid, text, text, uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_get_cfdi_detail(p_cfdi_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE;
BEGIN
    SELECT c.* INTO v_cfdi FROM private.fiscal02_readable_cfdis AS c WHERE c.id = p_cfdi_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN to_jsonb(v_cfdi) || jsonb_build_object('carta_porte',
        (SELECT to_jsonb(cp) FROM public.billing_carta_porte AS cp WHERE cp.cfdi_id = p_cfdi_id));
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_get_cfdi_detail(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_cfdi_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_get_my_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT jsonb_build_object(
        'user_id', auth.uid(),
        'email', (SELECT u.email FROM auth.users AS u WHERE u.id = auth.uid()),
        'memberships', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tenant_id', m.tenant_id,
                'tenant_name', t.name,
                'role', m.role
            ) ORDER BY t.name)
            FROM public.memberships AS m
            JOIN public.tenants AS t ON t.id = m.tenant_id
            WHERE m.user_id = auth.uid()
        ), '[]'::jsonb)
    );
$function$
;

REVOKE ALL ON FUNCTION public.rpc_get_my_context() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_context() TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_get_operation(p_operation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
BEGIN
    SELECT o.* INTO v_operation
    FROM public.operations AS o
    WHERE o.id = p_operation_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_is_member(v_operation.tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN to_jsonb(v_operation);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_get_operation(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_list_cfdis(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC) FROM private.fiscal02_readable_cfdis AS c
        WHERE c.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'status') OR c.status = p_filters->>'status')
          AND (NOT (p_filters ? 'rfc') OR c.rfc_emisor ILIKE '%' || (p_filters->>'rfc') || '%' OR c.rfc_receptor ILIKE '%' || (p_filters->>'rfc') || '%')
          AND (NOT (p_filters ? 'searchText') OR c.folio ILIKE '%' || (p_filters->>'searchText') || '%'
               OR c.receptor_name ILIKE '%' || (p_filters->>'searchText') || '%')), '[]'::jsonb);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_list_cfdis(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_cfdis(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_list_operations(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC)
        FROM public.operations AS o
        WHERE o.tenant_id = p_tenant_id
    ), '[]'::jsonb);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_list_operations(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_operations(uuid) TO authenticated;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_reports_financial_summary(uuid, text) SET SCHEMA private;ALTER FUNCTION private.rpc_reports_financial_summary(uuid, text) RENAME TO c02_bound_d3b2ab28d0a1f450579b;REVOKE ALL ON FUNCTION private.c02_bound_d3b2ab28d0a1f450579b(uuid, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_reports_financial_summary(p_tenant_id uuid, p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_revenue numeric; v_expenses numeric;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(sum(i.amount) FILTER (WHERE i.direction='ar'),0),
           COALESCE(sum(i.amount) FILTER (WHERE i.direction='ap'),0)
    INTO v_revenue,v_expenses FROM private.fiscal02_legacy_finance_invoices AS i WHERE i.tenant_id=p_tenant_id;
    RETURN jsonb_build_object('revenue_by_month','[]'::jsonb,'ar_open_by_month','[]'::jsonb,'ap_open_by_month','[]'::jsonb,
        'cashflow_by_month','[]'::jsonb,'total_revenue_ytd',COALESCE(v_revenue,0),'total_expenses_ytd',COALESCE(v_expenses,0),
        'net_position',COALESCE(v_revenue,0)-COALESCE(v_expenses,0));
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_reports_financial_summary(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_reports_financial_summary(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_toggle_deal_checklist_item(p_item_id uuid, p_is_done boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM public.crm_deal_checklist_items AS c WHERE c.id=p_item_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.crm_deal_checklist_items SET is_done=p_is_done,completed_by=CASE WHEN p_is_done THEN auth.uid() ELSE NULL END,
        completed_at=CASE WHEN p_is_done THEN now() ELSE NULL END WHERE id=p_item_id;
    RETURN jsonb_build_object('success',true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_toggle_deal_checklist_item(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_toggle_deal_checklist_item(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_cfdi(p_cfdi_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM private.fiscal02_readable_cfdis AS c WHERE c.id = p_cfdi_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    UPDATE public.billing_cfdis AS c SET
        status = COALESCE(p_patch->>'status', c.status),
        cancelled_at = CASE WHEN p_patch ? 'cancelled_at' THEN (p_patch->>'cancelled_at')::timestamptz ELSE c.cancelled_at END,
        notes = CASE WHEN p_patch ? 'notes' THEN p_patch->>'notes' ELSE c.notes END,
        has_carta_porte = COALESCE((p_patch->>'has_carta_porte')::boolean, c.has_carta_porte),
        has_complemento_pago = COALESCE((p_patch->>'has_complemento_pago')::boolean, c.has_complemento_pago)
    WHERE c.id = p_cfdi_id;
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_cfdi(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_cfdi(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_deal(p_deal_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.crm_deals AS d SET title=COALESCE(p_patch->>'title',d.title),company=COALESCE(p_patch->>'company',d.company),
        contact_name=COALESCE(p_patch->>'contact_name',d.contact_name),contact_email=COALESCE(p_patch->>'contact_email',d.contact_email),
        contact_phone=COALESCE(p_patch->>'contact_phone',d.contact_phone),value=COALESCE((p_patch->>'value')::numeric,d.value),
        currency=COALESCE(p_patch->>'currency',d.currency),stage=COALESCE(p_patch->>'stage',d.stage),
        priority=COALESCE(p_patch->>'priority',d.priority),notes=COALESCE(p_patch->>'notes',d.notes),
        owner_user_id=COALESCE((p_patch->>'owner_user_id')::uuid,d.owner_user_id),last_touch_at=now() WHERE d.id=p_deal_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_deal(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_deal(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_inventory_lot(p_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT i.tenant_id INTO v_tenant_id FROM public.inventory_lots AS i WHERE i.id=p_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.inventory_lots AS i SET qty_reserved=COALESCE((p_patch->>'qty_reserved')::numeric,i.qty_reserved),
        status=COALESCE(p_patch->>'status',i.status),warehouse=COALESCE(p_patch->>'warehouse',i.warehouse),
        description=COALESCE(p_patch->>'description',i.description) WHERE i.id=p_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_inventory_lot(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_inventory_lot(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_member_role(p_tenant_id uuid, p_member_user_id uuid, p_new_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_new_role NOT IN ('admin', 'operator', 'finance', 'viewer') THEN RETURN jsonb_build_object('error', 'invalid_role'); END IF;
    UPDATE public.memberships SET role = p_new_role WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_member_role(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_member_role(uuid, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_operation_details(p_operation_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT o.tenant_id INTO v_tenant_id FROM public.operations AS o WHERE o.id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o SET
        route_summary = COALESCE(p_patch->>'route_summary', o.route_summary),
        client_display_name = COALESCE(p_patch->>'client_display_name', o.client_display_name),
        destination_city = COALESCE(p_patch->>'destination_city', o.destination_city),
        eta_display = COALESCE(p_patch->>'eta_display', o.eta_display),
        priority = COALESCE(p_patch->>'priority', o.priority),
        execution_type = COALESCE(p_patch->>'execution_type', o.execution_type),
        provider_name = COALESCE(p_patch->>'provider_name', o.provider_name),
        notes = COALESCE(p_patch->>'notes', o.notes),
        documentation_received_note = COALESCE(p_patch->>'documentation_received_note', o.documentation_received_note),
        external_driver = COALESCE(p_patch->'external_driver', o.external_driver),
        external_vehicle = COALESCE(p_patch->'external_vehicle', o.external_vehicle),
        required_documents = COALESCE(p_patch->'required_documents', o.required_documents),
        cargo_summary = COALESCE(p_patch->'cargo_summary', o.cargo_summary),
        provider_cost_amount = COALESCE((p_patch->>'provider_cost_amount')::numeric, o.provider_cost_amount),
        customer_price_amount = COALESCE((p_patch->>'customer_price_amount')::numeric, o.customer_price_amount)
    WHERE o.id = p_operation_id;
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation THEN
    RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_operation_details(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_operation_details(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_pedimento(p_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT p.tenant_id INTO v_tenant_id FROM public.customs_pedimentos AS p WHERE p.id=p_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.customs_pedimentos AS p SET status=COALESCE(p_patch->>'status',p.status),aduana=COALESCE(p_patch->>'aduana',p.aduana),
        regimen=COALESCE(p_patch->>'regimen',p.regimen),fecha_pago=COALESCE((p_patch->>'fecha_pago')::date,p.fecha_pago),
        fecha_entrada=COALESCE((p_patch->>'fecha_entrada')::date,p.fecha_entrada),fecha_salida=COALESCE((p_patch->>'fecha_salida')::date,p.fecha_salida),
        total_value=COALESCE((p_patch->>'total_value')::numeric,p.total_value),currency=COALESCE(p_patch->>'currency',p.currency) WHERE p.id=p_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_pedimento(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_pedimento(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_update_tenant_settings(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.tenant_settings (tenant_id, brand_name, primary_color, logo_url, timezone, notifications_enabled, allow_demo_mode)
    VALUES (p_tenant_id, COALESCE(p_payload->>'brand_name', 'ROTERO'), COALESCE(p_payload->>'primary_color', '#0F2B5B'),
        p_payload->>'logo_url', COALESCE(p_payload->>'timezone', 'America/Mexico_City'),
        COALESCE((p_payload->>'notifications_enabled')::boolean, true), COALESCE((p_payload->>'allow_demo_mode')::boolean, false))
    ON CONFLICT (tenant_id) DO UPDATE SET
        brand_name = COALESCE(p_payload->>'brand_name', public.tenant_settings.brand_name),
        primary_color = COALESCE(p_payload->>'primary_color', public.tenant_settings.primary_color),
        logo_url = CASE WHEN p_payload ? 'logo_url' THEN p_payload->>'logo_url' ELSE public.tenant_settings.logo_url END,
        timezone = COALESCE(p_payload->>'timezone', public.tenant_settings.timezone),
        notifications_enabled = COALESCE((p_payload->>'notifications_enabled')::boolean, public.tenant_settings.notifications_enabled),
        allow_demo_mode = COALESCE((p_payload->>'allow_demo_mode')::boolean, public.tenant_settings.allow_demo_mode);
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_update_tenant_settings(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_tenant_settings(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_upsert_carta_porte(p_cfdi_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM private.fiscal02_readable_cfdis AS c WHERE c.id = p_cfdi_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.billing_carta_porte (tenant_id, cfdi_id, trans_type, vehicle_plate, carrier_name, origin, destination, goods_desc)
    VALUES (v_tenant_id, p_cfdi_id, p_payload->>'trans_type', p_payload->>'vehicle_plate', p_payload->>'carrier_name',
        p_payload->>'origin', p_payload->>'destination', p_payload->>'goods_desc')
    ON CONFLICT (cfdi_id) DO UPDATE SET trans_type = EXCLUDED.trans_type, vehicle_plate = EXCLUDED.vehicle_plate,
        carrier_name = EXCLUDED.carrier_name, origin = EXCLUDED.origin, destination = EXCLUDED.destination,
        goods_desc = EXCLUDED.goods_desc RETURNING id INTO v_id;
    UPDATE public.billing_cfdis SET has_carta_porte = true WHERE id = p_cfdi_id;
    RETURN jsonb_build_object('id', v_id);
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_upsert_carta_porte(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_carta_porte(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_validate_module_access(p_tenant_id uuid, p_module_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_row public.tenant_setup_status%ROWTYPE;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error', 'unauthorized', 'is_configured', false); END IF;
    SELECT s.* INTO v_row FROM public.tenant_setup_status AS s WHERE s.tenant_id = p_tenant_id AND s.module_name = p_module_name;
    RETURN jsonb_build_object('is_configured', COALESCE(v_row.is_configured, false), 'config_data', COALESCE(v_row.config_data, '{}'::jsonb));
END;
$function$
;

REVOKE ALL ON FUNCTION public.rpc_validate_module_access(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_validate_module_access(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.tanda1_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
        BEGIN
            NEW.updated_at := now();
            RETURN NEW;
        END;
        $function$
;

REVOKE ALL ON FUNCTION public.tanda1_touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda1_user_has_role(p_tenant_id uuid, p_roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role = ANY(p_roles)
    );
$function$
;

REVOKE ALL ON FUNCTION public.tanda1_user_has_role(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_has_role(uuid, text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.tanda1_user_is_member(p_tenant_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
    );
$function$
;

REVOKE ALL ON FUNCTION public.tanda1_user_is_member(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_is_member(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.tracking_hash_token(p_token text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
    SELECT encode(extensions.digest(p_token, 'sha256'), 'hex');
$function$
;

REVOKE ALL ON FUNCTION public.tracking_hash_token(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tracking_hash_token(text) TO service_role;

DO $metadata$ BEGIN IF to_regclass('public.billing_document_lines') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.billing_document_lines TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.billing_document_lines FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.billing_document_taxes') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.billing_document_taxes TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.billing_document_taxes FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.billing_documents') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.billing_documents TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.billing_documents FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.crm_deals') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.crm_deals TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.crm_deals FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.customers') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.customers TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.customers FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.daily_work_items') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.daily_work_items TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.daily_work_items FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.document_templates') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.document_templates TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.document_templates FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.drivers') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.drivers TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.drivers FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.logistics_providers') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.logistics_providers TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.logistics_providers FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.operations') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.operations TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.operations FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

DO $metadata$ BEGIN IF to_regclass('public.vehicles') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.vehicles TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.vehicles FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;

CREATE OR REPLACE FUNCTION public.billing_fiscal_document_json(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_583f5cb2a17ce6eb9387(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_583f5cb2a17ce6eb9387(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.billing_fiscal_document_json(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.billing_fiscal_document_json(uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.billing_fiscal_document_json(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.billing_fiscal_document_json(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.billing_recalculate_document_totals(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_9d0daf29575098e827e1(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_9d0daf29575098e827e1(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.billing_recalculate_document_totals(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.billing_recalculate_document_totals(uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.billing_recalculate_document_totals(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.billing_recalculate_document_totals(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.billing_user_has_tenant(p_tenant_id uuid, p_roles text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = (SELECT user_id FROM private.multi05_request_actor())
          AND m.tenant_id = p_tenant_id
          AND (
              p_roles IS NULL
              OR (
                  CASE
                      WHEN 'operator' = ANY(p_roles)
                      THEN m.role = ANY(array_append(array_remove(p_roles, 'operator'), 'finance'))
                      ELSE m.role = ANY(p_roles)
                  END
              )
          )
    );
$function$
;

ALTER FUNCTION public.billing_user_has_tenant(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.billing_user_has_tenant(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.billing_user_has_tenant(uuid, text[]) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.billing_user_has_tenant(uuid, text[]) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.billing_user_has_tenant(uuid, text[]) TO postgres;
SET LOCAL ROLE postgres;

DO $helper$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 ALTER FUNCTION public.crm_generate_quote_reference(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 ELSE
 EXECUTE 'CREATE FUNCTION public.crm_generate_quote_reference(p_tenant_id uuid) RETURNS text LANGUAGE plpgsql SET search_path='''' AS $stub$ BEGIN RAISE EXCEPTION USING ERRCODE=''42501'',MESSAGE=''company_adoption_pending''; END $stub$';
 END IF;END $helper$;

REVOKE ALL ON FUNCTION public.crm_generate_quote_reference(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.crm_quote_payload_has_only_allowed_keys(p_payload jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT NOT EXISTS (
        SELECT 1
        FROM jsonb_object_keys(COALESCE(
            CASE WHEN jsonb_typeof(p_payload) = 'object' THEN p_payload ELSE '{}'::jsonb END,
            '{}'::jsonb
        )) AS key
        WHERE key NOT IN (
            'operation_scope',
            'execution_type',
            'provider_id',
            'provider_name',
            'external_driver',
            'external_vehicle',
            'provider_cost_amount',
            'customer_price_amount',
            'pricing_currency',
            'service_catalog_item_id',
            'service_catalog_snapshot',
            'service_type',
            'service_class',
            'presentation',
            'packaging',
            'modality',
            'origin_place',
            'destination_place',
            'operational_window_start',
            'operational_window_end',
            'cargo_summary',
            'route_summary',
            'destination_city',
            'notes',
            'eta',
            'eta_display'
        )
    );
$function$
;

ALTER FUNCTION public.crm_quote_payload_has_only_allowed_keys(jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.crm_quote_payload_has_only_allowed_keys(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.customer_normalize_display_name(p_value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT regexp_replace(lower(trim(COALESCE(p_value, ''))), '\s+', ' ', 'g');
$function$
;

ALTER FUNCTION public.customer_normalize_display_name(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.customer_normalize_display_name(text) FROM PUBLIC,anon,authenticated,service_role;

DO $helper$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 ALTER FUNCTION public.customer_summary_json(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 ELSE
 EXECUTE 'CREATE FUNCTION public.customer_summary_json(p_customer_id uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='''' AS $stub$ BEGIN RAISE EXCEPTION USING ERRCODE=''42501'',MESSAGE=''company_adoption_pending''; END $stub$';
 END IF;END $helper$;

REVOKE ALL ON FUNCTION public.customer_summary_json(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.digest(data text, type text)
 RETURNS bytea
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE STRICT
AS $function$
    SELECT extensions.digest(data, type);
$function$
;

ALTER FUNCTION public.digest(text, text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.digest(text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.digest(text, text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_driver_active_operation(p_tenant_id uuid, p_driver_id uuid, p_exclude_operation_id uuid DEFAULT NULL::uuid) RETURNS TABLE(operation_id uuid, reference_code text, operation_status text) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF to_regprocedure('private.c02_observed_790805283da324827843(uuid, uuid, uuid)') IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='unauthorized'; END IF;
RETURN QUERY SELECT * FROM private.c02_observed_790805283da324827843(p_tenant_id,p_driver_id,p_exclude_operation_id);RETURN;
END $c02$;

REVOKE ALL ON FUNCTION public.fn_driver_active_operation(uuid, uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_driver_active_operation(uuid, uuid, uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.fn_driver_active_operation(uuid, uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.fn_driver_active_operation(uuid, uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.fn_operations_infer_operation_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(NEW.origin_place->>'countryCode', 'MX') = 'US'
       OR COALESCE(NEW.destination_place->>'countryCode', 'MX') = 'US' THEN
        NEW.operation_scope := 'international';
    ELSIF NEW.operation_scope IS NULL OR NEW.operation_scope NOT IN ('national', 'international') THEN
        NEW.operation_scope := 'national';
    END IF;

    RETURN NEW;
END;
$function$
;

ALTER FUNCTION public.fn_operations_infer_operation_scope() SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.fn_operations_infer_operation_scope() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_vehicle_active_operation(p_tenant_id uuid, p_vehicle_id uuid, p_exclude_operation_id uuid DEFAULT NULL::uuid) RETURNS TABLE(operation_id uuid, reference_code text, operation_status text) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF to_regprocedure('private.c02_observed_1e5781e1a52da109f5b4(uuid, uuid, uuid)') IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='unauthorized'; END IF;
RETURN QUERY SELECT * FROM private.c02_observed_1e5781e1a52da109f5b4(p_tenant_id,p_vehicle_id,p_exclude_operation_id);RETURN;
END $c02$;

REVOKE ALL ON FUNCTION public.fn_vehicle_active_operation(uuid, uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_vehicle_active_operation(uuid, uuid, uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.fn_vehicle_active_operation(uuid, uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.fn_vehicle_active_operation(uuid, uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.haversine_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT 6371000.0 * 2 * asin(sqrt(
        sin(radians(lat2 - lat1) / 2) ^ 2 +
        cos(radians(lat1)) * cos(radians(lat2)) *
        sin(radians(lng2 - lng1) / 2) ^ 2
    ));
$function$
;

ALTER FUNCTION public.haversine_m(double precision, double precision, double precision, double precision) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.haversine_m(double precision, double precision, double precision, double precision) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.haversine_m(double precision, double precision, double precision, double precision) TO anon,authenticated,service_role;

DO $helper$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 ALTER FUNCTION public.logistics_provider_summary_json(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 ELSE
 EXECUTE 'CREATE FUNCTION public.logistics_provider_summary_json(p_provider_id uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='''' AS $stub$ BEGIN RAISE EXCEPTION USING ERRCODE=''42501'',MESSAGE=''company_adoption_pending''; END $stub$';
 END IF;END $helper$;

REVOKE ALL ON FUNCTION public.logistics_provider_summary_json(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.logistics_provider_summary_json(uuid) TO service_role;

DO $inert$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN EXECUTE 'CREATE OR REPLACE FUNCTION public.rpc_accept_invitation(p_token text, p_password text, p_full_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''pg_catalog'', ''public''
AS $function$
            BEGIN
                RETURN jsonb_build_object(''accepted'', false, ''state'', ''disabled'');
            END
            $function$
';END IF;END $inert$;

DO $inert$ BEGIN IF to_regprocedure('public.rpc_accept_invitation(text, text, text)') IS NOT NULL THEN EXECUTE 'REVOKE ALL ON FUNCTION public.rpc_accept_invitation(text, text, text) FROM PUBLIC,anon,authenticated,service_role;
';END IF;END $inert$;

CREATE OR REPLACE FUNCTION public.rpc_complete_operation_planning(p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text DEFAULT NULL::text, p_cargo_summary jsonb DEFAULT NULL::jsonb, p_route_summary text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_eta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_eta_display text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_8fe30cd99a3ff09b2536(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_8fe30cd99a3ff09b2536(p_operation_id,p_service_type,p_origin_place,p_destination_place,p_operational_window_start,p_operational_window_end,p_notes,p_cargo_summary,p_route_summary,p_destination_city,p_eta,p_eta_display);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) SET SCHEMA private;ALTER FUNCTION private.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) RENAME TO c02_bound_3e08aa274c9fd1d8ba20;REVOKE ALL ON FUNCTION private.c02_bound_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_complete_operation_planning(p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text, p_cargo_summary jsonb, p_route_summary text, p_destination_city text, p_eta timestamp with time zone, p_eta_display text, p_operation_scope text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_3e08aa274c9fd1d8ba20(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_3e08aa274c9fd1d8ba20(p_operation_id,p_service_type,p_origin_place,p_destination_place,p_operational_window_start,p_operational_window_end,p_notes,p_cargo_summary,p_route_summary,p_destination_city,p_eta,p_eta_display,p_operation_scope);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_complete_operation_planning(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_configure_module(p_tenant_id uuid, p_module_name text, p_config_data jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_8312b63bbb1a0b8b9f45(uuid, text, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_8312b63bbb1a0b8b9f45(p_tenant_id,p_module_name,p_config_data);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_configure_module(uuid, text, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_configure_module(uuid, text, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_configure_module(uuid, text, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_configure_module(uuid, text, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_driver(p_tenant_id uuid, p_display_name text, p_phone text DEFAULT NULL::text, p_license_number text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_e283943c0fd6d9d24f83(uuid, text, text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_e283943c0fd6d9d24f83(p_tenant_id,p_display_name,p_phone,p_license_number,p_notes);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_driver(uuid, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_driver(uuid, text, text, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_driver(uuid, text, text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_driver(uuid, text, text, text, text) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) SET SCHEMA private;ALTER FUNCTION private.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) RENAME TO c02_bound_81156bbf35ff2925a3fe;REVOKE ALL ON FUNCTION private.c02_bound_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_create_inventory_lot(p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_unit_cost numeric, p_currency text, p_pedimento_ref text, p_description text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_81156bbf35ff2925a3fe(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_81156bbf35ff2925a3fe(p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_unit_cost,p_currency,p_pedimento_ref,p_description);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) SET SCHEMA private;ALTER FUNCTION private.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) RENAME TO c02_bound_d8bdba3bfe3629ac0fde;REVOKE ALL ON FUNCTION private.c02_bound_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_create_inventory_lot(p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_unit_cost numeric, p_currency text, p_pedimento_ref text, p_description text, p_unit text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_d8bdba3bfe3629ac0fde(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_d8bdba3bfe3629ac0fde(p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_unit_cost,p_currency,p_pedimento_ref,p_description,p_unit);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamp with time zone, numeric, text, text, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_logistics_provider(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_235250be5714c7a66548(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_235250be5714c7a66548(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_logistics_provider(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_logistics_provider(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_logistics_provider(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_logistics_provider(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_operation_billing(p_operation_id uuid, p_billing_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_334e6bbae2fe05d161ea(uuid, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_334e6bbae2fe05d161ea(p_operation_id,p_billing_reference,p_notes);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_operation_billing(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_billing(uuid, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_operation_billing(uuid, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_billing(uuid, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_operation_draft(p_tenant_id uuid, p_reference_code text, p_client_display_name text, p_customer_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_188db110a499f579131a(uuid, text, text, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_188db110a499f579131a(p_tenant_id,p_reference_code,p_client_display_name,p_customer_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid, text) SET SCHEMA private;ALTER FUNCTION private.rpc_create_operation_draft(uuid, text, text, uuid, text) RENAME TO c02_bound_4901b60f756d33394d22;REVOKE ALL ON FUNCTION private.c02_bound_4901b60f756d33394d22(uuid, text, text, uuid, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_create_operation_draft(p_tenant_id uuid, p_reference_code text, p_client_display_name text, p_customer_id uuid, p_operation_scope text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_4901b60f756d33394d22(uuid, text, text, uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_4901b60f756d33394d22(p_tenant_id,p_reference_code,p_client_display_name,p_customer_id,p_operation_scope);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_draft(uuid, text, text, uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_vehicle(p_tenant_id uuid, p_unit_code text, p_display_name text, p_plate text DEFAULT NULL::text, p_vehicle_type text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_90255862aed9e1eb5bb9(uuid, text, text, text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_90255862aed9e1eb5bb9(p_tenant_id,p_unit_code,p_display_name,p_plate,p_vehicle_type,p_notes);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_vehicle(uuid, text, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_vehicle(uuid, text, text, text, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_vehicle(uuid, text, text, text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_vehicle(uuid, text, text, text, text, text) TO postgres;
SET LOCAL ROLE postgres;

DO $redirect$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_dashboard_alerts(uuid) SET SCHEMA private;ALTER FUNCTION private.rpc_dashboard_alerts(uuid) RENAME TO c02_bound_b45e1df65509538a8d39;ALTER FUNCTION private.c02_bound_b45e1df65509538a8d39(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;REVOKE ALL ON FUNCTION private.c02_bound_b45e1df65509538a8d39(uuid) FROM PUBLIC,anon,authenticated,service_role;END IF;END $redirect$;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) SET SCHEMA private;ALTER FUNCTION private.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) RENAME TO c02_bound_64317cc295fa4a1529ba;REVOKE ALL ON FUNCTION private.c02_bound_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid, p_limit integer, p_start_date timestamp with time zone, p_end_date timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_64317cc295fa4a1529ba(uuid, integer, timestamp with time zone, timestamp with time zone)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_64317cc295fa4a1529ba(p_tenant_id,p_limit,p_start_date,p_end_date);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid, integer, timestamp with time zone, timestamp with time zone) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_export_operations(p_tenant_id uuid, p_status_filter text[] DEFAULT NULL::text[], p_search_text text DEFAULT NULL::text, p_date_from text DEFAULT NULL::text, p_date_to text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_dd0439f88824140b2e31(uuid, text[], text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_dd0439f88824140b2e31(p_tenant_id,p_status_filter,p_search_text,p_date_from,p_date_to);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_export_operations(uuid, text[], text, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_export_operations(uuid, text[], text, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_export_operations(uuid, text[], text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_export_operations(uuid, text[], text, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_export_quotes(p_tenant_id uuid, p_quote_status_filter text[] DEFAULT NULL::text[], p_priority_filter text[] DEFAULT NULL::text[], p_search_text text DEFAULT NULL::text, p_converted_filter text DEFAULT NULL::text, p_ready_to_convert boolean DEFAULT NULL::boolean, p_date_from text DEFAULT NULL::text, p_date_to text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_d47fcba82bff1a8a11ac(uuid, text[], text[], text, text, boolean, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_d47fcba82bff1a8a11ac(p_tenant_id,p_quote_status_filter,p_priority_filter,p_search_text,p_converted_filter,p_ready_to_convert,p_date_from,p_date_to);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_export_quotes(uuid, text[], text[], text, text, boolean, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_get_dispatch_dashboard(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_ab43eb882b2848329c8e(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_ab43eb882b2848329c8e(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_get_dispatch_dashboard(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_dispatch_dashboard(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_get_dispatch_dashboard(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_get_dispatch_dashboard(uuid) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_get_executive_dashboard(uuid, jsonb) SET SCHEMA private;ALTER FUNCTION private.rpc_get_executive_dashboard(uuid, jsonb) RENAME TO c02_bound_67a1da4c2cceb1d215de;REVOKE ALL ON FUNCTION private.c02_bound_67a1da4c2cceb1d215de(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_get_executive_dashboard(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_67a1da4c2cceb1d215de(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_67a1da4c2cceb1d215de(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_get_executive_dashboard(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_get_executive_dashboard(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

DO $redirect$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_list_audit_log(uuid, integer) SET SCHEMA private;ALTER FUNCTION private.rpc_list_audit_log(uuid, integer) RENAME TO c02_bound_1243db36b949cbbe34f4;ALTER FUNCTION private.c02_bound_1243db36b949cbbe34f4(uuid, integer) SET search_path=pg_catalog,public,extensions,pg_temp;REVOKE ALL ON FUNCTION private.c02_bound_1243db36b949cbbe34f4(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;END IF;END $redirect$;

CREATE OR REPLACE FUNCTION public.rpc_list_logistics_providers(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_fb4b56ad8e1753721427(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_fb4b56ad8e1753721427(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_logistics_providers(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_logistics_providers(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_logistics_providers(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_logistics_providers(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_billing(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_e3d35e9783cb6119b066(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_e3d35e9783cb6119b066(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_operation_billing(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_billing(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_operation_billing(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_billing(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) SET SCHEMA private;ALTER FUNCTION private.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) RENAME TO c02_bound_f38939d840edf43c9707;REVOKE ALL ON FUNCTION private.c02_bound_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_list_route_points(p_operation_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_limit integer, p_max_display integer) RETURNS TABLE(lat double precision, lng double precision, recorded_at timestamp with time zone, accuracy_m double precision, source text) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF to_regprocedure('private.c02_observed_f38939d840edf43c9707(uuid, timestamp with time zone, timestamp with time zone, integer, integer)') IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='unauthorized'; END IF;
RETURN QUERY SELECT * FROM private.c02_observed_f38939d840edf43c9707(p_operation_id,p_start,p_end,p_limit,p_max_display);RETURN;
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) TO authenticated;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer, integer) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_mark_operation_billing_issued(p_operation_id uuid, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_654947ef338daca14a7c(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_654947ef338daca14a7c(p_operation_id,p_notes);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_mark_operation_billing_issued(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_mark_operation_billing_issued(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_mark_operation_billing_issued(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_mark_operation_billing_issued(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_move_deal(uuid, text, timestamp with time zone) SET SCHEMA private;ALTER FUNCTION private.rpc_move_deal(uuid, text, timestamp with time zone) RENAME TO c02_bound_2e8af3a893dbe1bde803;REVOKE ALL ON FUNCTION private.c02_bound_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_move_deal(p_deal_id uuid, p_new_stage text, p_client_timestamp timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_2e8af3a893dbe1bde803(uuid, text, timestamp with time zone)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.crm_deals WHERE id=p_deal_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_2e8af3a893dbe1bde803(p_deal_id,p_new_stage,p_client_timestamp);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_move_deal(uuid, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_move_deal(uuid, text, timestamp with time zone) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_move_deal(uuid, text, timestamp with time zone) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_move_deal(uuid, text, timestamp with time zone) TO postgres;
SET LOCAL ROLE postgres;

DO $inert$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN EXECUTE 'CREATE OR REPLACE FUNCTION public.rpc_revoke_invitation(p_tenant_id uuid, p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''pg_catalog'', ''public''
AS $function$
            BEGIN
                RETURN jsonb_build_object(''accepted'', false, ''state'', ''disabled'');
            END
            $function$
';END IF;END $inert$;

DO $inert$ BEGIN IF to_regprocedure('public.rpc_revoke_invitation(uuid, uuid)') IS NOT NULL THEN EXECUTE 'REVOKE ALL ON FUNCTION public.rpc_revoke_invitation(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
';END IF;END $inert$;

CREATE OR REPLACE FUNCTION public.rpc_revoke_operation_tokens(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_1a02ac7224bcaef815da(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_1a02ac7224bcaef815da(p_operation_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_revoke_operation_tokens(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_operation_tokens(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_revoke_operation_tokens(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_operation_tokens(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_set_customer_active_status(p_customer_id uuid, p_is_active boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_db7ed6a03cd1ba4ae080(uuid, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.customers WHERE id=p_customer_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_db7ed6a03cd1ba4ae080(p_customer_id,p_is_active);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_set_customer_active_status(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_set_customer_active_status(uuid, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_set_customer_active_status(uuid, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_set_customer_active_status(uuid, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_tracking_healthcheck(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_f5a08231aab94b1e124d(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_f5a08231aab94b1e124d(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_tracking_healthcheck(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_tracking_healthcheck(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_tracking_healthcheck(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_tracking_healthcheck(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_driver(p_driver_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_cd16ca464e54a70ceccf(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.drivers WHERE id=p_driver_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_cd16ca464e54a70ceccf(p_driver_id,p_patch);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_driver(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_driver(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_driver(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_driver(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_logistics_provider(p_provider_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_139ecbe3c17e10ba7f50(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.logistics_providers WHERE id=p_provider_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_139ecbe3c17e10ba7f50(p_provider_id,p_patch);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_logistics_provider(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_logistics_provider(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_logistics_provider(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_logistics_provider(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_vehicle(p_vehicle_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_23cb2ecf315c06bce720(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.vehicles WHERE id=p_vehicle_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_23cb2ecf315c06bce720(p_vehicle_id,p_patch);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_vehicle(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_vehicle(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_vehicle(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_vehicle(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_void_operation_billing(p_operation_id uuid, p_void_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_b5840236291f23655a48(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_b5840236291f23655a48(p_operation_id,p_void_reason);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_void_operation_billing(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_void_operation_billing(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_void_operation_billing(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_void_operation_billing(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda2_amount_mxn(p_amount numeric, p_currency text, p_exchange_rate numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_amount IS NULL THEN NULL
        WHEN upper(COALESCE(p_currency, 'MXN')) = 'MXN' THEN round(p_amount, 2)
        WHEN p_exchange_rate IS NULL THEN NULL
        ELSE round(p_amount * p_exchange_rate, 2)
    END;
$function$
;

ALTER FUNCTION public.tanda2_amount_mxn(numeric, text, numeric) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda2_amount_mxn(numeric, text, numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda2_amount_mxn(numeric, text, numeric) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda2_user_has_role(p_tenant_id uuid, p_roles text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = (SELECT user_id FROM private.multi05_request_actor())
          AND m.tenant_id = p_tenant_id
          AND (p_roles IS NULL OR m.role = ANY(p_roles))
    );
$function$
;

ALTER FUNCTION public.tanda2_user_has_role(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda2_user_has_role(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda2_user_has_role(uuid, text[]) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda2_user_has_role(uuid, text[]) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda2_user_has_role(uuid, text[]) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda3_sync_payroll_period_from_finance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
 IF private.c02_required(NEW.tenant_id) THEN RETURN NEW;END IF;
    IF NEW.payroll_period_id IS NOT NULL AND NEW.status = 'paid' THEN
        UPDATE public.payroll_periods
        SET
            status = 'paid',
            paid_at = COALESCE(NEW.paid_at, now()),
            paid_by = COALESCE(auth.uid(), paid_by),
            updated_at = now()
        WHERE id = NEW.payroll_period_id
          AND tenant_id = NEW.tenant_id
          AND status <> 'paid';
    END IF;

    RETURN NEW;
END;
$function$
;

ALTER FUNCTION public.tanda3_sync_payroll_period_from_finance() SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda3_sync_payroll_period_from_finance() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda3_user_has_role(p_tenant_id uuid, p_roles text[] DEFAULT ARRAY['admin'::text, 'finance'::text])
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.tenant_id = p_tenant_id
          AND m.user_id = (SELECT user_id FROM private.multi05_request_actor())
          AND m.role = ANY(p_roles)
    );
$function$
;

ALTER FUNCTION public.tanda3_user_has_role(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda3_user_has_role(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda3_user_has_role(uuid, text[]) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda3_user_has_role(uuid, text[]) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda3_user_has_role(uuid, text[]) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda4_document_prefix(p_template_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_template_type
        WHEN 'commercial_quote' THEN 'COT'
        WHEN 'payroll_receipt' THEN 'NOM'
        WHEN 'operation_summary' THEN 'OPE'
        WHEN 'operation_document' THEN 'DOC'
        WHEN 'payment_complement' THEN 'CPG'
        WHEN 'credit_note' THEN 'NCR'
        WHEN 'provider_document' THEN 'PROV'
        WHEN 'finance_internal_receipt' THEN 'FIN'
        WHEN 'finance_note' THEN 'FIN'
        ELSE 'DOC'
    END;
$function$
;

ALTER FUNCTION public.tanda4_document_prefix(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_document_prefix(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_document_prefix(text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_document_type_label(p_template_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_template_type
        WHEN 'commercial_quote' THEN 'Cotizacion'
        WHEN 'payroll_receipt' THEN 'Recibo de nomina'
        WHEN 'operation_summary' THEN 'Resumen operativo'
        WHEN 'operation_document' THEN 'Documento operativo'
        WHEN 'payment_complement' THEN 'Complemento de pago'
        WHEN 'credit_note' THEN 'Nota de credito'
        WHEN 'provider_document' THEN 'Documento proveedor'
        WHEN 'finance_internal_receipt' THEN 'Comprobante interno'
        WHEN 'finance_note' THEN 'Nota financiera'
        ELSE 'Documento'
    END;
$function$
;

ALTER FUNCTION public.tanda4_document_type_label(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_document_type_label(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_document_type_label(text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_escape_html(p_value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT replace(
        replace(
            replace(
                replace(
                    replace(COALESCE(p_value, ''), '&', '&amp;'),
                    '<', '&lt;'
                ),
                '>', '&gt;'
            ),
            '"', '&quot;'
        ),
        '''', '&#39;'
    );
$function$
;

ALTER FUNCTION public.tanda4_escape_html(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_escape_html(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_escape_html(text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_field_visible(p_visible_fields jsonb, p_field jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_visible_fields IS NULL
          OR jsonb_typeof(p_visible_fields) <> 'array'
          OR jsonb_array_length(p_visible_fields) = 0 THEN true
        ELSE EXISTS (
            SELECT 1
            FROM jsonb_array_elements_text(p_visible_fields) AS visible(token)
            WHERE trim(visible.token) <> ''
              AND (
                  lower(trim(COALESCE(p_field->>'key', ''))) = lower(trim(visible.token))
                  OR lower(trim(COALESCE(p_field->>'label', ''))) = lower(trim(visible.token))
                  OR lower(trim(COALESCE(p_field->>'label', ''))) LIKE '%' || lower(trim(visible.token)) || '%'
              )
        )
    END;
$function$
;

ALTER FUNCTION public.tanda4_field_visible(jsonb, jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_field_visible(jsonb, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_field_visible(jsonb, jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_money(p_amount numeric, p_currency text DEFAULT 'MXN'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_amount IS NULL THEN ''
        ELSE '$' || to_char(round(p_amount, 2), 'FM999,999,999,990.00') || ' ' || COALESCE(NULLIF(p_currency, ''), 'MXN')
    END;
$function$
;

ALTER FUNCTION public.tanda4_money(numeric, text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_money(numeric, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_money(numeric, text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_user_has_role(p_tenant_id uuid, p_roles text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.tenant_id = p_tenant_id
          AND m.user_id = (SELECT user_id FROM private.multi05_request_actor())
          AND (p_roles IS NULL OR m.role = ANY(p_roles))
    );
$function$
;

ALTER FUNCTION public.tanda4_user_has_role(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_user_has_role(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_user_has_role(uuid, text[]) TO anon,authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda4_user_has_role(uuid, text[]) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda4_user_has_role(uuid, text[]) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda5_storage_tenant_from_path(p_name text)
 RETURNS uuid
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN split_part(COALESCE(p_name, ''), '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN split_part(p_name, '/', 1)::uuid
        ELSE NULL
    END;
$function$
;

ALTER FUNCTION public.tanda5_storage_tenant_from_path(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda5_storage_tenant_from_path(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda5_storage_tenant_from_path(text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda5_user_has_role(p_tenant_id uuid, p_roles text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.tenant_id = p_tenant_id
          AND m.user_id = (SELECT user_id FROM private.multi05_request_actor())
          AND (p_roles IS NULL OR m.role = ANY(p_roles))
    );
$function$
;

ALTER FUNCTION public.tanda5_user_has_role(uuid, text[]) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda5_user_has_role(uuid, text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda5_user_has_role(uuid, text[]) TO anon,authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda5_user_has_role(uuid, text[]) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda5_user_has_role(uuid, text[]) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda6_touch_daily_work_item_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$
;

ALTER FUNCTION public.tanda6_touch_daily_work_item_updated_at() SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda6_touch_daily_work_item_updated_at() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda6_user_role(p_tenant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT m.role::text
    FROM public.memberships m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = (SELECT user_id FROM private.multi05_request_actor())
    LIMIT 1
$function$
;

ALTER FUNCTION public.tanda6_user_role(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda6_user_role(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda6_user_role(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda6_user_role(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda6_user_role(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda7_bool_setting(p_settings jsonb, p_key text, p_default boolean)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN lower(COALESCE(p_settings->>p_key, '')) IN ('true', '1', 'yes', 'si') THEN true
        WHEN lower(COALESCE(p_settings->>p_key, '')) IN ('false', '0', 'no') THEN false
        ELSE p_default
    END;
$function$
;

ALTER FUNCTION public.tanda7_bool_setting(jsonb, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda7_bool_setting(jsonb, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda7_bool_setting(jsonb, text, boolean) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda7_section_order(p_settings jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT COALESCE(
        ARRAY(
            SELECT lower(trim(value))
            FROM jsonb_array_elements_text(CASE
                WHEN jsonb_typeof(p_settings->'section_order') = 'array' THEN p_settings->'section_order'
                ELSE '[]'::jsonb
            END)
            WHERE lower(trim(value)) IN ('fields', 'amounts', 'notes', 'payment', 'signature')
        ),
        ARRAY[]::text[]
    );
$function$
;

ALTER FUNCTION public.tanda7_section_order(jsonb) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda7_section_order(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda7_section_order(jsonb) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda8_notification_icon(p_area text, p_priority text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN COALESCE(p_priority, '') IN ('critical', 'high') THEN 'warning'
        WHEN COALESCE(p_area, '') = 'operations' THEN 'truck'
        ELSE 'info'
    END;
$function$
;

ALTER FUNCTION public.tanda8_notification_icon(text, text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda8_notification_icon(text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda8_notification_icon(text, text) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda8_notification_trigger_type(p_area text, p_kind text, p_priority text, p_is_overdue boolean)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN COALESCE(p_is_overdue, false) THEN 'daily_control_overdue'
        WHEN COALESCE(p_kind, '') ILIKE '%invoice%' OR COALESCE(p_kind, '') ILIKE '%factura%' THEN 'invoice_due'
        WHEN COALESCE(p_area, '') = 'documents' AND (COALESCE(p_kind, '') ILIKE '%fiscal%' OR COALESCE(p_kind, '') ILIKE '%workbench%') THEN 'fiscal_workbench'
        WHEN COALESCE(p_area, '') = 'payroll' THEN 'payroll_pending'
        WHEN COALESCE(p_priority, '') = 'critical' THEN 'daily_control_critical'
        WHEN COALESCE(p_priority, '') = 'high' THEN 'daily_control_high'
        ELSE 'daily_control_high'
    END;
$function$
;

ALTER FUNCTION public.tanda8_notification_trigger_type(text, text, text, boolean) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda8_notification_trigger_type(text, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda8_notification_trigger_type(text, text, text, boolean) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda8_seed_default_notification_rules(p_tenant_id uuid) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN; END IF;IF to_regprocedure('private.c02_observed_8fa285f7c40fbe0489e7(uuid)') IS NULL THEN RETURN; END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN; END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RETURN; END IF;
PERFORM private.c02_observed_8fa285f7c40fbe0489e7(p_tenant_id);RETURN;
END $c02$;

REVOKE ALL ON FUNCTION public.tanda8_seed_default_notification_rules(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda8_seed_default_notification_rules(uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda8_seed_default_notification_rules(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda8_seed_default_notification_rules(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda8_touch_notification_rule_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$
;

ALTER FUNCTION public.tanda8_touch_notification_rule_updated_at() SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda8_touch_notification_rule_updated_at() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tracking_expire_tokens() RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF to_regprocedure('private.c02_observed_7dbbe9e663f193bbe57c()') IS NULL THEN RETURN NULL; END IF;
RETURN private.c02_observed_7dbbe9e663f193bbe57c();
END $c02$;

REVOKE ALL ON FUNCTION public.tracking_expire_tokens() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tracking_expire_tokens() TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tracking_expire_tokens() OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tracking_expire_tokens() TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tracking_try_append_route_point(p_tenant_id uuid, p_operation_id uuid, p_token_id uuid, p_lat double precision, p_lng double precision, p_accuracy double precision DEFAULT NULL::double precision, p_source text DEFAULT 'gps'::text, p_recorded_at timestamp with time zone DEFAULT now()) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF to_regprocedure('private.c02_observed_b2b42cf02231e345a512(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone)') IS NULL THEN RETURN NULL; END IF;
RETURN private.c02_observed_b2b42cf02231e345a512(p_tenant_id,p_operation_id,p_token_id,p_lat,p_lng,p_accuracy,p_source,p_recorded_at);
END $c02$;

REVOKE ALL ON FUNCTION public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tracking_try_append_route_point(uuid, uuid, uuid, double precision, double precision, double precision, text, timestamp with time zone) TO postgres;
SET LOCAL ROLE postgres;

DO $route$ BEGIN IF current_setting('cierre02.source_variant')='A' THEN EXECUTE 'CREATE OR REPLACE FUNCTION private.c02_observed_0f04048c46d8734fa190_a(p_operation_id uuid, p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 2000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''pg_catalog'', ''public''
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT o.tenant_id INTO v_tenant_id FROM public.operations AS o WHERE o.id=p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object(''error'',''not_found''); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object(''error'',''unauthorized''); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(''lat'',x.lat,''lng'',x.lng,''recorded_at'',x.recorded_at,''accuracy_m'',x.accuracy_m,''source'',x.source) ORDER BY x.recorded_at)
        FROM (SELECT r.lat,r.lng,r.recorded_at,r.accuracy_m,r.source FROM public.tracking_route_points AS r WHERE r.operation_id=p_operation_id
            AND (p_start IS NULL OR r.recorded_at>=p_start) AND (p_end IS NULL OR r.recorded_at<=p_end)
            ORDER BY r.recorded_at DESC LIMIT LEAST(GREATEST(p_limit,1),5000)) AS x),''[]''::jsonb);
END;
$function$
';REVOKE ALL ON FUNCTION private.c02_observed_0f04048c46d8734fa190_a(uuid, timestamp with time zone, timestamp with time zone, integer) FROM PUBLIC,anon,authenticated,service_role;GRANT EXECUTE ON FUNCTION private.c02_observed_0f04048c46d8734fa190_a(uuid, timestamp with time zone, timestamp with time zone, integer) TO rotero_c02_gate_owner;END IF;END $route$;

DO $route$ BEGIN IF current_setting('cierre02.source_variant')='A' THEN EXECUTE 'CREATE OR REPLACE FUNCTION public.rpc_list_route_points(p_operation_id uuid, p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 2000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route_impl$ DECLARE tenant uuid;BEGIN SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object(''error'',''company_adoption_pending''); END IF;RETURN private.c02_observed_0f04048c46d8734fa190_a(p_operation_id,p_start,p_end,p_limit); END $route_impl$';END IF;END $route$;

DO $route$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN EXECUTE 'CREATE OR REPLACE FUNCTION public.rpc_list_route_points(p_operation_id uuid, p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 2000) RETURNS TABLE(lat double precision, lng double precision, recorded_at timestamp with time zone, accuracy_m double precision, source text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route_impl$ DECLARE tenant uuid;BEGIN SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN RAISE EXCEPTION USING ERRCODE=''42501'',MESSAGE=''company_adoption_pending''; END IF;RETURN QUERY SELECT * FROM private.c02_observed_0f04048c46d8734fa190(p_operation_id,p_start,p_end,p_limit);RETURN; END $route_impl$';END IF;END $route$;

REVOKE ALL ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer) TO authenticated;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamp with time zone, timestamp with time zone, integer) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.billing_build_api_payload(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_fb4591d4a98003dfc506(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_fb4591d4a98003dfc506(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.billing_build_api_payload(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.billing_build_api_payload(uuid) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.billing_build_api_payload(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.billing_build_api_payload(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.customer_display_name_is_valid(p_value text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT
        NULLIF(trim(COALESCE(p_value, '')), '') IS NOT NULL
        AND char_length(trim(COALESCE(p_value, ''))) >= 3
        AND trim(COALESCE(p_value, '')) !~ '^[[:punct:][:space:]]+$'
        AND public.customer_normalize_display_name(p_value) <> 'cliente nuevo';
$function$
;

ALTER FUNCTION public.customer_display_name_is_valid(text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.customer_display_name_is_valid(text) FROM PUBLIC,anon,authenticated,service_role;

DO $helper$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 ALTER FUNCTION public.customer_probable_duplicates_json(uuid, text, uuid) SET search_path=pg_catalog,public,extensions,pg_temp;
 ELSE
 EXECUTE 'CREATE FUNCTION public.customer_probable_duplicates_json(p_tenant_id uuid, p_display_name text, p_exclude_customer_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='''' AS $stub$ BEGIN RAISE EXCEPTION USING ERRCODE=''42501'',MESSAGE=''company_adoption_pending''; END $stub$';
 END IF;END $helper$;

REVOKE ALL ON FUNCTION public.customer_probable_duplicates_json(uuid, text, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_approve_payroll_period(p_tenant_id uuid, p_period_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_8b35b87dbc406e690fac(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_8b35b87dbc406e690fac(p_tenant_id,p_period_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_approve_payroll_period(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_approve_payroll_period(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_approve_payroll_period(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_approve_payroll_period(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) SET SCHEMA private;ALTER FUNCTION private.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) RENAME TO c02_bound_3b075d3a742666f5a5ce;REVOKE ALL ON FUNCTION private.c02_bound_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text, p_driver_name text, p_vehicle_ref text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_3b075d3a742666f5a5ce(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_3b075d3a742666f5a5ce(p_tenant_id,p_operation_id,p_driver_id,p_vehicle_id,p_planned_departure,p_priority,p_driver_name,p_vehicle_ref);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamp with time zone, text, text, text) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) SET SCHEMA private;ALTER FUNCTION private.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) RENAME TO c02_bound_1dbfc4783425e3705965;REVOKE ALL ON FUNCTION private.c02_bound_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v2(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text, p_reason text, p_force_override boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_1dbfc4783425e3705965(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_1dbfc4783425e3705965(p_tenant_id,p_operation_id,p_driver_id,p_driver_name,p_vehicle_id,p_vehicle_ref,p_planned_departure,p_priority,p_reason,p_force_override);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_calculate_payroll_period(p_tenant_id uuid, p_period_id uuid, p_entries jsonb DEFAULT '[]'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7668cb146ea65ae3b7e1(uuid, uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7668cb146ea65ae3b7e1(p_tenant_id,p_period_id,p_entries);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_calculate_payroll_period(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_payroll_period(uuid, uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_calculate_payroll_period(uuid, uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_calculate_payroll_period(uuid, uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_credit_note(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_197154c4c87a61893fe5(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_197154c4c87a61893fe5(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_credit_note(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_credit_note(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_credit_note(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_credit_note(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_payroll_period(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_03750fcf36cfd3dc2626(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_03750fcf36cfd3dc2626(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_payroll_period(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_payroll_period(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_payroll_period(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_payroll_period(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

DO $redirect$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_dashboard_overview(uuid) SET SCHEMA private;ALTER FUNCTION private.rpc_dashboard_overview(uuid) RENAME TO c02_bound_6ec6c7a338466f5afc53;ALTER FUNCTION private.c02_bound_6ec6c7a338466f5afc53(uuid) SET search_path=pg_catalog,public,extensions,pg_temp;REVOKE ALL ON FUNCTION private.c02_bound_6ec6c7a338466f5afc53(uuid) FROM PUBLIC,anon,authenticated,service_role;END IF;END $redirect$;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_dashboard_recent_activity(uuid, integer) SET SCHEMA private;ALTER FUNCTION private.rpc_dashboard_recent_activity(uuid, integer) RENAME TO c02_bound_34e1d88722077f141b5d;REVOKE ALL ON FUNCTION private.c02_bound_34e1d88722077f141b5d(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid, p_limit integer) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_34e1d88722077f141b5d(uuid, integer)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_34e1d88722077f141b5d(p_tenant_id,p_limit);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_dashboard_recent_activity(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_dashboard_recent_activity(uuid, integer) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid, integer) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_delete_billing_document_line(p_line_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7f44ab6fe37fb673acb2(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_document_lines WHERE id=p_line_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7f44ab6fe37fb673acb2(p_line_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_delete_billing_document_line(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delete_billing_document_line(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_delete_billing_document_line(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_delete_billing_document_line(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_delete_billing_document_tax(p_tax_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_90946e6322367775712a(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_document_taxes WHERE id=p_tax_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_90946e6322367775712a(p_tax_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_delete_billing_document_tax(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delete_billing_document_tax(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_delete_billing_document_tax(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_delete_billing_document_tax(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_export_issued_cfdis(p_tenant_id uuid, p_date_from text DEFAULT NULL::text, p_date_to text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_b3214be28e6db0b98331(uuid, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_b3214be28e6db0b98331(p_tenant_id,p_date_from,p_date_to);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_export_issued_cfdis(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_export_issued_cfdis(uuid, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_export_issued_cfdis(uuid, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_export_issued_cfdis(uuid, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_export_payroll_period(p_tenant_id uuid, p_period_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_69d058b07561deca423e(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_69d058b07561deca423e(p_tenant_id,p_period_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_export_payroll_period(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_export_payroll_period(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_export_payroll_period(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_export_payroll_period(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_get_billing_document(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_2d326485f986bcce664a(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_2d326485f986bcce664a(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_get_billing_document(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_billing_document(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_get_billing_document(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_get_billing_document(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_get_customer(p_customer_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7729731cf09d818191f7(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.customers WHERE id=p_customer_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7729731cf09d818191f7(p_customer_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_get_customer(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_customer(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_get_customer(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_get_customer(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_issue_payroll_receipts(p_tenant_id uuid, p_period_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_8307161ef346d2082c6b(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_8307161ef346d2082c6b(p_tenant_id,p_period_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_issue_payroll_receipts(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_issue_payroll_receipts(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_issue_payroll_receipts(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_issue_payroll_receipts(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_billing_documents(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_ea94d671c51f4343069d(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_ea94d671c51f4343069d(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_billing_documents(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_billing_documents(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_billing_documents(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_billing_documents(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_billing_sat_catalog_entries(p_tenant_id uuid, p_catalog text DEFAULT NULL::text, p_include_inactive boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_2ca100f5c9d17437cce8(uuid, text, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_2ca100f5c9d17437cce8(p_tenant_id,p_catalog,p_include_inactive);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_billing_sat_catalog_entries(uuid, text, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_credit_notes(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_9a3b4e8d6920c69debcd(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_9a3b4e8d6920c69debcd(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_credit_notes(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_credit_notes(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_credit_notes(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_credit_notes(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_currency_exchange_rates(p_tenant_id uuid, p_limit integer DEFAULT 30) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_41989552448775a317cd(uuid, integer)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_41989552448775a317cd(p_tenant_id,p_limit);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_currency_exchange_rates(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_currency_exchange_rates(uuid, integer) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_currency_exchange_rates(uuid, integer) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_currency_exchange_rates(uuid, integer) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_document_finance_pending(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_0a5b991de8a1aff91cf0(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_0a5b991de8a1aff91cf0(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_document_finance_pending(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_finance_pending(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_document_finance_pending(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_finance_pending(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_document_tax_summary(p_tenant_id uuid, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7a1e9c6abedae4763710(uuid, date, date)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7a1e9c6abedae4763710(p_tenant_id,p_date_from,p_date_to);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_document_tax_summary(uuid, date, date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_tax_summary(uuid, date, date) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_document_tax_summary(uuid, date, date) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_tax_summary(uuid, date, date) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_document_template_versions(p_tenant_id uuid, p_template_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_09ede2633c120d9fb46e(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_09ede2633c120d9fb46e(p_tenant_id,p_template_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_document_template_versions(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_template_versions(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_document_template_versions(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_template_versions(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_document_templates(p_tenant_id uuid, p_template_type text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_d08a62f57071d19b3556(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_d08a62f57071d19b3556(p_tenant_id,p_template_type);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_document_templates(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_templates(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_document_templates(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_templates(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_drivers(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_87bea051c00f765b9395(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_87bea051c00f765b9395(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_drivers(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_drivers(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_drivers(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_drivers(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_fiscal_document_workbench(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_cea4bfa633144f9b81b5(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_cea4bfa633144f9b81b5(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_fiscal_document_workbench(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_fiscal_document_workbench(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_fiscal_document_workbench(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_fiscal_document_workbench(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_payroll_employees(p_tenant_id uuid, p_include_inactive boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_f3f45084bd3a5db0d600(uuid, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_f3f45084bd3a5db0d600(p_tenant_id,p_include_inactive);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_payroll_employees(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_employees(uuid, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_payroll_employees(uuid, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_employees(uuid, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_payroll_entries(p_tenant_id uuid, p_period_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_9bd933001d0f0cf72865(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_9bd933001d0f0cf72865(p_tenant_id,p_period_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_payroll_entries(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_entries(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_payroll_entries(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_entries(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_payroll_loans(p_tenant_id uuid, p_status text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_dcb44c0a835753a72701(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_dcb44c0a835753a72701(p_tenant_id,p_status);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_payroll_loans(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_loans(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_payroll_loans(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_loans(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_payroll_periods(p_tenant_id uuid, p_status text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_d2936b62fcb784343c6f(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_d2936b62fcb784343c6f(p_tenant_id,p_status);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_payroll_periods(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_periods(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_payroll_periods(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_periods(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_payroll_receipts(p_tenant_id uuid, p_period_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_edec4f660ff15c148c32(uuid, uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_edec4f660ff15c148c32(p_tenant_id,p_period_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_payroll_receipts(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_receipts(uuid, uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_payroll_receipts(uuid, uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_payroll_receipts(uuid, uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_service_catalog_items(p_tenant_id uuid, p_include_inactive boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7bf3086826152f15500c(uuid, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7bf3086826152f15500c(p_tenant_id,p_include_inactive);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_service_catalog_items(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_service_catalog_items(uuid, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_service_catalog_items(uuid, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_service_catalog_items(uuid, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_vehicles(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_3b9f7a5ddd586b2f5976(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_3b9f7a5ddd586b2f5976(p_tenant_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_vehicles(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_vehicles(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_vehicles(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_vehicles(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_recalculate_billing_document_totals(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_debba76c73b7f6e027c2(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_debba76c73b7f6e027c2(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_recalculate_billing_document_totals(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_recalculate_billing_document_totals(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_recalculate_billing_document_totals(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_recalculate_billing_document_totals(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_register_billing_api_result(p_outbox_id uuid, p_result jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_d7ba1b7ca1954648adcd(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_d7ba1b7ca1954648adcd(p_outbox_id,p_result);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_register_billing_api_result(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_register_billing_api_result(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_register_billing_api_result(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_register_billing_api_result(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_set_driver_status(p_driver_id uuid, p_status text, p_reason text DEFAULT NULL::text, p_force_override boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_339cdbe7ae06ba48584a(uuid, text, text, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.drivers WHERE id=p_driver_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_339cdbe7ae06ba48584a(p_driver_id,p_status,p_reason,p_force_override);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_set_driver_status(uuid, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_set_driver_status(uuid, text, text, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_set_driver_status(uuid, text, text, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_set_driver_status(uuid, text, text, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_set_vehicle_status(p_vehicle_id uuid, p_status text, p_reason text DEFAULT NULL::text, p_force_override boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7d9c898db1a55864fb62(uuid, text, text, boolean)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.vehicles WHERE id=p_vehicle_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7d9c898db1a55864fb62(p_vehicle_id,p_status,p_reason,p_force_override);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_set_vehicle_status(uuid, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_set_vehicle_status(uuid, text, text, boolean) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_set_vehicle_status(uuid, text, text, boolean) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_set_vehicle_status(uuid, text, text, boolean) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_billing_document(p_document_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_83ce1492c6a459dbc943(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_83ce1492c6a459dbc943(p_document_id,p_patch);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_billing_document(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_billing_document(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_billing_document(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_billing_document(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_customer_preferred_currency(p_customer_id uuid, p_currency text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_05fcdb92c209ba40b312(uuid, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.customers WHERE id=p_customer_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_05fcdb92c209ba40b312(p_customer_id,p_currency);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_customer_preferred_currency(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_customer_preferred_currency(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_customer_preferred_currency(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_customer_preferred_currency(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_billing_document_line(p_document_id uuid, p_line jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_0652a7d5e8fb53fa5c5d(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_0652a7d5e8fb53fa5c5d(p_document_id,p_line);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_billing_document_line(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_line(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_billing_document_line(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_line(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_billing_document_party(p_document_id uuid, p_party jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_76a078d697c0a8f67713(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_76a078d697c0a8f67713(p_document_id,p_party);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_billing_document_party(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_party(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_billing_document_party(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_party(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_billing_document_tax(p_document_id uuid, p_tax jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_a3b675d5dd677dc31abf(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_a3b675d5dd677dc31abf(p_document_id,p_tax);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_billing_document_tax(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_tax(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_billing_document_tax(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_document_tax(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_billing_fiscal_profile(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_3c57ec49898fe6d1dd00(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_3c57ec49898fe6d1dd00(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_billing_fiscal_profile(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_fiscal_profile(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_billing_fiscal_profile(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_billing_fiscal_profile(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_currency_exchange_rate(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_f1d5e24d74d0ac59b47d(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_f1d5e24d74d0ac59b47d(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_currency_exchange_rate(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_currency_exchange_rate(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_currency_exchange_rate(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_currency_exchange_rate(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_document_template_v2(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_7732f0dfb9a65ed75d11(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_7732f0dfb9a65ed75d11(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_document_template_v2(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_document_template_v2(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_document_template_v2(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_document_template_v2(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_payroll_employee(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_41629924c61832a547bd(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_41629924c61832a547bd(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_payroll_employee(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_payroll_employee(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_payroll_employee(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_payroll_employee(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_payroll_loan(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_c3384698b30c88f2a8a6(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_c3384698b30c88f2a8a6(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_payroll_loan(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_payroll_loan(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_payroll_loan(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_payroll_loan(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_service_catalog_item(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_e6ba73d80def3d922776(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_e6ba73d80def3d922776(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_service_catalog_item(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_service_catalog_item(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_service_catalog_item(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_service_catalog_item(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda4_ensure_document_template(p_tenant_id uuid, p_template_type text) RETURNS TABLE(template_id uuid, version_id uuid) LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF to_regprocedure('private.c02_observed_fd3310a7bc9d037fc502(uuid, text)') IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='unauthorized'; END IF;
RETURN QUERY SELECT * FROM private.c02_observed_fd3310a7bc9d037fc502(p_tenant_id,p_template_type);RETURN;
END $c02$;

REVOKE ALL ON FUNCTION public.tanda4_ensure_document_template(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_ensure_document_template(uuid, text) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda4_ensure_document_template(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda4_ensure_document_template(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda4_generated_documents_defaults()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_prefix text;
    v_count integer;
BEGIN
    IF NEW.template_version_id IS NULL AND NEW.template_id IS NOT NULL THEN
        SELECT active_version_id INTO NEW.template_version_id
        FROM public.document_templates
        WHERE id = NEW.template_id;
    END IF;

    IF NEW.document_number IS NULL OR trim(NEW.document_number) = '' THEN
        v_prefix := public.tanda4_document_prefix(NEW.entity_type);
        SELECT count(*) + 1 INTO v_count
        FROM public.generated_documents
        WHERE tenant_id = NEW.tenant_id
          AND entity_type = NEW.entity_type
          AND date_trunc('month', generated_at) = date_trunc('month', now());
        NEW.document_number := v_prefix || '-' || to_char(now(), 'YYMM') || '-' || lpad(v_count::text, 4, '0');
    END IF;

    IF NEW.status = 'final' AND NEW.finalized_at IS NULL THEN
        NEW.finalized_at := COALESCE(NEW.generated_at, now());
    END IF;

    RETURN NEW;
END;
$function$
;

ALTER FUNCTION public.tanda4_generated_documents_defaults() SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda4_generated_documents_defaults() FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.tanda4_render_document_html(p_version_id uuid, p_data jsonb, p_document_number text) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN NULL; END IF;IF to_regprocedure('private.c02_observed_d1ac57d0a1319266d54d(uuid, jsonb, text)') IS NULL THEN RETURN NULL; END IF;tenant:=NULL::uuid;IF private.c02_required(tenant) THEN RETURN NULL; END IF;IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN RETURN NULL; END IF;
RETURN private.c02_observed_d1ac57d0a1319266d54d(p_version_id,p_data,p_document_number);
END $c02$;

REVOKE ALL ON FUNCTION public.tanda4_render_document_html(uuid, jsonb, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda4_render_document_html(uuid, jsonb, text) TO service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda4_render_document_html(uuid, jsonb, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda4_render_document_html(uuid, jsonb, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda6_can_mutate_area(p_tenant_id uuid, p_area text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role text := public.tanda6_user_role(p_tenant_id);
    v_area text := lower(COALESCE(p_area, ''));
BEGIN
    IF v_role IS NULL THEN
        RETURN false;
    END IF;

    IF v_role = 'admin' THEN
        RETURN true;
    END IF;

    IF v_role = 'finance' THEN
        RETURN v_area IN ('finance', 'billing', 'documents', 'payroll', 'provider');
    END IF;

    IF v_role = 'operator' THEN
        RETURN v_area IN ('operations', 'commercial', 'documents');
    END IF;

    RETURN false;
END;
$function$
;

ALTER FUNCTION public.tanda6_can_mutate_area(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda6_can_mutate_area(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda6_can_mutate_area(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda6_can_mutate_area(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda6_can_mutate_area(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.tanda6_can_view_area(p_tenant_id uuid, p_area text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role text := public.tanda6_user_role(p_tenant_id);
    v_area text := lower(COALESCE(p_area, ''));
BEGIN
    IF v_role IS NULL THEN
        RETURN false;
    END IF;

    IF v_role = 'admin' THEN
        RETURN true;
    END IF;

    IF v_role = 'finance' THEN
        RETURN v_area IN ('finance', 'billing', 'documents', 'payroll', 'provider');
    END IF;

    IF v_role IN ('operator', 'viewer') THEN
        RETURN v_area IN ('operations', 'commercial', 'documents');
    END IF;

    RETURN false;
END;
$function$
;

ALTER FUNCTION public.tanda6_can_view_area(uuid, text) SET search_path=pg_catalog,public,extensions,pg_temp;

REVOKE ALL ON FUNCTION public.tanda6_can_view_area(uuid, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tanda6_can_view_area(uuid, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.tanda6_can_view_area(uuid, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.tanda6_can_view_area(uuid, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_customer(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_b5ed58565175016ab919(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_b5ed58565175016ab919(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_customer(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_customer(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_customer(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_customer(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_daily_work_item(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_80362131891dde999d27(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_80362131891dde999d27(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_daily_work_item(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_daily_work_item(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_daily_work_item(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_daily_work_item(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_list_daily_control_items(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_6faa4e861750958f91cb(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_6faa4e861750958f91cb(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_daily_control_items(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_daily_control_items(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_daily_control_items(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_daily_control_items(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_resolve_daily_work_item(p_item_id uuid, p_status text, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_6b19d3a1104f11ff08c5(uuid, text, text)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.daily_work_items WHERE id=p_item_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_6b19d3a1104f11ff08c5(p_item_id,p_status,p_note);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_resolve_daily_work_item(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_resolve_daily_work_item(uuid, text, text) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_resolve_daily_work_item(uuid, text, text) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_resolve_daily_work_item(uuid, text, text) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_customer(p_customer_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_c8d35d8022ed6399e3bb(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.customers WHERE id=p_customer_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_c8d35d8022ed6399e3bb(p_customer_id,p_patch);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_customer(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_customer(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_customer(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_customer(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_update_daily_work_item(p_item_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_22c88b95458843e03b85(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.daily_work_items WHERE id=p_item_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_22c88b95458843e03b85(p_item_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_update_daily_work_item(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_update_daily_work_item(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_update_daily_work_item(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_update_daily_work_item(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_upsert_document_template(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_3f9e8a4a26108e20228d(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_3f9e8a4a26108e20228d(p_tenant_id,p_payload);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_upsert_document_template(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_document_template(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_upsert_document_template(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_document_template(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_validate_billing_document_for_api(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_5b19bf7557a5a770f689(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_5b19bf7557a5a770f689(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_validate_billing_document_for_api(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_validate_billing_document_for_api(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_validate_billing_document_for_api(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_validate_billing_document_for_api(uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_create_billing_document_from_operation(p_tenant_id uuid, p_operation_id uuid, p_options jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_5c8e0590ef4313ed0010(uuid, uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_5c8e0590ef4313ed0010(p_tenant_id,p_operation_id,p_options);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_create_billing_document_from_operation(uuid, uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_export_daily_control_items(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_dc0764973da406be3a24(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_dc0764973da406be3a24(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_export_daily_control_items(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_export_daily_control_items(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_export_daily_control_items(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_export_daily_control_items(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_get_daily_control_summary(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_40eff1c3a69067feb921(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_40eff1c3a69067feb921(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_get_daily_control_summary(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_daily_control_summary(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_get_daily_control_summary(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_get_daily_control_summary(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION public.rpc_list_internal_notifications(uuid, jsonb) SET SCHEMA private;ALTER FUNCTION private.rpc_list_internal_notifications(uuid, jsonb) RENAME TO c02_bound_14be0422d75af232ca8a;REVOKE ALL ON FUNCTION private.c02_bound_14be0422d75af232ca8a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(p_tenant_id) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_14be0422d75af232ca8a(uuid, jsonb)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=p_tenant_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_14be0422d75af232ca8a(p_tenant_id,p_filters);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_list_internal_notifications(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid, jsonb) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_list_internal_notifications(uuid, jsonb) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid, jsonb) TO postgres;
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION public.rpc_queue_billing_document_for_api(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $c02$
DECLARE tenant uuid;BEGIN IF private.c02_required(NULL::uuid) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF to_regprocedure('private.c02_observed_cad3c443fe153d2a38d5(uuid)') IS NULL THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;tenant:=NULL::uuid;SELECT tenant_id INTO tenant FROM public.billing_documents WHERE id=p_document_id;IF private.c02_required(tenant) THEN RETURN jsonb_build_object('error','company_adoption_pending'); END IF;IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
RETURN private.c02_observed_cad3c443fe153d2a38d5(p_document_id);
END $c02$;

REVOKE ALL ON FUNCTION public.rpc_queue_billing_document_for_api(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_queue_billing_document_for_api(uuid) TO authenticated,service_role;

GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;
ALTER FUNCTION public.rpc_queue_billing_document_for_api(uuid) OWNER TO rotero_c02_gate_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;
SET LOCAL ROLE rotero_c02_gate_owner;
GRANT EXECUTE ON FUNCTION public.rpc_queue_billing_document_for_api(uuid) TO postgres;
SET LOCAL ROLE postgres;

DO $rls$ BEGIN IF to_regclass('public.billing_api_attempts') IS NOT NULL THEN
 ALTER TABLE public.billing_api_attempts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_api_attempts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_api_outbox') IS NOT NULL THEN
 ALTER TABLE public.billing_api_outbox ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_api_outbox AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_document_lines') IS NOT NULL THEN
 ALTER TABLE public.billing_document_lines ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_document_lines AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_document_parties') IS NOT NULL THEN
 ALTER TABLE public.billing_document_parties ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_document_parties AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_document_taxes') IS NOT NULL THEN
 ALTER TABLE public.billing_document_taxes ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_document_taxes AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_fiscal_profiles') IS NOT NULL THEN
 ALTER TABLE public.billing_fiscal_profiles ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_fiscal_profiles AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.billing_sat_catalog_entries') IS NOT NULL THEN
 ALTER TABLE public.billing_sat_catalog_entries ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.billing_sat_catalog_entries AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.currency_exchange_rates') IS NOT NULL THEN
 ALTER TABLE public.currency_exchange_rates ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.currency_exchange_rates AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.daily_work_items') IS NOT NULL THEN
 ALTER TABLE public.daily_work_items ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.daily_work_items AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_employees') IS NOT NULL THEN
 ALTER TABLE public.payroll_employees ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_employees AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_entries') IS NOT NULL THEN
 ALTER TABLE public.payroll_entries ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_entries AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_entry_items') IS NOT NULL THEN
 ALTER TABLE public.payroll_entry_items ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_entry_items AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_loans') IS NOT NULL THEN
 ALTER TABLE public.payroll_loans ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_loans AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_periods') IS NOT NULL THEN
 ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_periods AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

DO $rls$ BEGIN IF to_regclass('public.payroll_receipts') IS NOT NULL THEN
 ALTER TABLE public.payroll_receipts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.payroll_receipts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;

CREATE FUNCTION private.c02_legacy_definition(p_signature text) RETURNS text LANGUAGE plpgsql STABLE SET search_path='' AS $fn$
DECLARE c record;p record;
BEGIN
 SELECT * INTO c FROM private.c02_contracts WHERE signature=p_signature AND category='retain_enriched_legacy_and_canonical_scoped' AND source_variant='B';
 IF NOT FOUND THEN RETURN NULL;END IF;
 SELECT x.* INTO p FROM pg_catalog.pg_proc x WHERE x.oid=pg_catalog.to_regprocedure(c.archive_signature);
 IF NOT FOUND OR md5(replace(p.prosrc,chr(13)||chr(10),chr(10)))<>c.observed_body_md5 THEN RAISE EXCEPTION 'c02_archived_source_drift';END IF;
 RETURN pg_catalog.pg_get_functiondef(p.oid);
END $fn$;
REVOKE ALL ON FUNCTION private.c02_legacy_definition(text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.c02_is_reviewed_api(p_oid oid) RETURNS boolean LANGUAGE sql STABLE SET search_path='' AS $fn$
 SELECT EXISTS(SELECT FROM private.c02_contracts c JOIN pg_catalog.pg_proc p ON p.oid=p_oid
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE c.signature=n.nspname||'.'||p.proname||'('||pg_catalog.oidvectortypes(p.proargtypes)||')'
 AND c.public_body_md5=md5(replace(p.prosrc,chr(13)||chr(10),chr(10)))
 AND c.expected_owner=pg_catalog.pg_get_userbyid(p.proowner) AND c.expected_definer=p.prosecdef
 AND c.expected_result=pg_catalog.pg_get_function_result(p.oid) AND c.expected_config IS NOT DISTINCT FROM p.proconfig
 AND c.expected_anon=pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
 AND c.expected_auth=pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND c.expected_service=pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE'))
$fn$;
REVOKE ALL ON FUNCTION private.c02_is_reviewed_api(oid) FROM PUBLIC,anon,authenticated,service_role;
-- Close the metadata registry before handing control to the unchanged MULTI-08 block.
DO $register$ DECLARE c record;p record;BEGIN
 FOR c IN SELECT * FROM private.c02_contracts LOOP
  SELECT x.* INTO p FROM pg_proc x WHERE x.oid=to_regprocedure(c.signature);
  IF FOUND THEN UPDATE private.c02_contracts SET public_body_md5=md5(replace(p.prosrc,chr(13)||chr(10),chr(10))),
   expected_owner=pg_get_userbyid(p.proowner),expected_definer=p.prosecdef,expected_result=pg_get_function_result(p.oid),expected_config=p.proconfig,
   expected_anon=has_function_privilege('anon',p.oid,'EXECUTE'),expected_auth=has_function_privilege('authenticated',p.oid,'EXECUTE'),expected_service=has_function_privilege('service_role',p.oid,'EXECUTE') WHERE signature=c.signature;
  END IF;
 END LOOP;
END $register$;
-- CIERRE02_RECONCILIATION_END


DO $owner$
DECLARE r oid; api text;
BEGIN
    SELECT oid INTO r FROM pg_catalog.pg_roles WHERE rolname='rotero_operations_read_owner';
    IF r IS NULL THEN
        CREATE ROLE rotero_operations_read_owner NOLOGIN NOINHERIT NOSUPERUSER
            NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
        COMMENT ON ROLE rotero_operations_read_owner IS 'ROTERO MULTI-06 minimal operations reader v1';
        SELECT oid INTO r FROM pg_catalog.pg_roles WHERE rolname='rotero_operations_read_owner';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE oid=r AND NOT rolcanlogin AND NOT rolinherit
        AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication
        AND pg_catalog.shobj_description(oid,'pg_authid')='ROTERO MULTI-06 minimal operations reader v1')
        OR EXISTS (SELECT FROM pg_catalog.pg_auth_members WHERE member=r) THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi06_owner_collision';
    END IF;
    FOREACH api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
        IF pg_catalog.pg_has_role(api,r,'MEMBER') THEN
            RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi06_owner_exposed';
        END IF;
    END LOOP;
END;
$owner$;
GRANT rotero_operations_read_owner TO CURRENT_USER WITH SET TRUE;
GRANT rotero_operations_read_owner TO CURRENT_USER WITH INHERIT FALSE;
GRANT USAGE ON SCHEMA public,private TO rotero_operations_read_owner;

-- Preserve pre-existing column REFERENCES; remove only temporary additions.
DO $company_reference$
DECLARE actor text:=current_user; missing text;
BEGIN
    SELECT string_agg(pg_catalog.quote_ident(c),',') INTO missing
    FROM unnest(ARRAY['tenant_id','id']) cols(c)
    WHERE NOT pg_catalog.has_column_privilege(actor,'public.companies',c,'REFERENCES');
    PERFORM pg_catalog.set_config('multi06.migration_actor',actor,true);
    PERFORM pg_catalog.set_config('multi06.reference_columns',COALESCE(missing,''),true);
    SET LOCAL ROLE rotero_company_access_owner;
    IF missing IS NOT NULL THEN
        EXECUTE format('GRANT REFERENCES (%s) ON public.companies TO %I',missing,actor);
    END IF;
    GRANT EXECUTE ON FUNCTION private.multi05_has_company_capability(uuid,uuid,text)
        TO rotero_operations_read_owner;
    EXECUTE format('SET LOCAL ROLE %I',actor);
END;
$company_reference$;

ALTER TABLE public.operations
    ADD COLUMN company_id uuid,
    ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
    ADD COLUMN company_classification_event_id uuid,
    ADD CONSTRAINT operations_tenant_id_key UNIQUE (tenant_id,id),
    ADD CONSTRAINT operations_company_id_key UNIQUE (tenant_id,company_id,id),
    ADD CONSTRAINT operations_company_fk FOREIGN KEY (tenant_id,company_id)
        REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_company_classification_check CHECK (
        (company_classification_status='resolved' AND company_id IS NOT NULL AND company_classification_event_id IS NOT NULL)
        OR (company_classification_status IN ('pending_classification','conflict') AND company_id IS NULL)
    );
CREATE INDEX operations_company_page_idx ON public.operations(tenant_id,company_id,id)
    WHERE company_classification_status='resolved';

-- No automatic inference or historical-row DML. A trusted evidence event must
-- precede an explicit resolution; ordinary users get no classification API.
CREATE TABLE private.operation_company_classification_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    operation_id uuid NOT NULL,
    company_id uuid,
    decision text NOT NULL,
    evidence_kind text NOT NULL CHECK (evidence_kind IN (
        'verified_source_record','verified_parent','approved_resolution','insufficient_evidence','conflicting_evidence'
    )),
    evidence_reference text NOT NULL CHECK (
        evidence_reference=btrim(evidence_reference) AND char_length(evidence_reference) BETWEEN 1 AND 400
    ),
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_classification_decision_check CHECK (
        (decision='resolved' AND company_id IS NOT NULL
            AND evidence_kind IN ('verified_source_record','verified_parent','approved_resolution'))
        OR (decision='pending_classification' AND company_id IS NULL AND evidence_kind='insufficient_evidence')
        OR (decision='conflict' AND company_id IS NULL AND evidence_kind='conflicting_evidence')
    ),
    CONSTRAINT operation_classification_operation_fk FOREIGN KEY (tenant_id,operation_id)
        REFERENCES public.operations(tenant_id,id) ON DELETE RESTRICT,
    CONSTRAINT operation_classification_company_fk FOREIGN KEY (tenant_id,company_id)
        REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
    CONSTRAINT operation_classification_identity_key UNIQUE (tenant_id,operation_id,id),
    CONSTRAINT operation_classification_decision_key UNIQUE (tenant_id,operation_id,decision,id),
    CONSTRAINT operation_classification_resolution_key UNIQUE (tenant_id,operation_id,company_id,decision,id)
);
CREATE INDEX operation_classification_history_idx
    ON private.operation_company_classification_events(tenant_id,operation_id,recorded_at,id);
ALTER TABLE private.operation_company_classification_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.operation_company_classification_events FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE public.operations
    ADD CONSTRAINT operations_classification_event_fk FOREIGN KEY (tenant_id,id,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_classification_decision_fk
        FOREIGN KEY (tenant_id,id,company_classification_status,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,decision,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_classification_company_event_fk
        FOREIGN KEY (tenant_id,id,company_id,company_classification_status,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,id) ON DELETE RESTRICT;

-- Parent-derived ownership: no independent company field on these children.
-- NOT VALID preserves uninspected history; new writes must already be coherent.
DO $children$
DECLARE child text;
BEGIN
    FOREACH child IN ARRAY ARRAY['operation_assignment_history','operation_incidents','operation_evidence',
        'operation_documents','operation_crossings','operation_billing','tracking_tokens','tracking_events','tracking_route_points'] LOOP
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id,operation_id)
            REFERENCES public.operations(tenant_id,id) ON DELETE CASCADE NOT VALID',child,child||'_multi06_parent_fk');
    END LOOP;
END;
$children$;

-- This owner cannot read costs, pricing, snapshots, notes, tokens or documents.
GRANT SELECT (id,tenant_id,company_id,company_classification_status,reference_code,status,service_type,
    route_summary,client_display_name,provider_name,operation_scope,execution_type,priority,
    planned_departure,operational_window_start,operational_window_end,created_at)
    ON public.operations TO rotero_operations_read_owner;
CREATE POLICY operations_multi06_minimal_reader ON public.operations
    FOR SELECT TO rotero_operations_read_owner
    USING (company_classification_status='resolved'
        AND private.multi05_has_company_capability(tenant_id,company_id,'operations.read'));

CREATE FUNCTION private.multi06_operation_rows(p_tenant_id uuid,p_company_id uuid)
RETURNS TABLE (id uuid,company_id uuid,reference_code text,status text,service_type text,
    route_summary text,client_display_name text,provider_name text,operation_scope text,
    execution_type text,priority text,planned_departure timestamptz,
    operational_window_start timestamptz,operational_window_end timestamptz,created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
    SELECT o.id,o.company_id,o.reference_code,o.status,o.service_type,o.route_summary,
        o.client_display_name,o.provider_name,o.operation_scope,o.execution_type,o.priority,
        o.planned_departure,o.operational_window_start,o.operational_window_end,o.created_at
    FROM public.operations o WHERE o.tenant_id=p_tenant_id AND o.company_id=p_company_id
        AND o.company_classification_status='resolved';
$fn$;

CREATE FUNCTION public.rpc_multi06_list_operations(p_tenant_id uuid,p_company_id uuid,
    p_search text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE search_text text:=lower(btrim(p_search)); result jsonb; total bigint; next_id uuid;
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'operations.read') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR search_text IS NULL OR char_length(search_text)>160 THEN
        RETURN jsonb_build_object('error','invalid_filters');
    END IF;
    IF p_after_id IS NOT NULL AND NOT EXISTS (
        SELECT FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o WHERE o.id=p_after_id
    ) THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
    WITH scoped AS MATERIALIZED (
        SELECT o.* FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o
        WHERE search_text='' OR position(search_text IN lower(concat_ws(' ',o.reference_code,o.route_summary,
            o.client_display_name,o.provider_name)))>0
    ), page AS (
        SELECT s.* FROM scoped s WHERE p_after_id IS NULL OR s.id>p_after_id ORDER BY s.id LIMIT p_limit
    )
    SELECT (SELECT count(*) FROM scoped),
        COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM page p),'[]'::jsonb),
        CASE WHEN EXISTS (SELECT FROM scoped s WHERE s.id>(SELECT p.id FROM page p ORDER BY p.id DESC LIMIT 1))
            THEN (SELECT p.id FROM page p ORDER BY p.id DESC LIMIT 1) END
        INTO total,result,next_id;
    RETURN jsonb_build_object('items',result,'total',total,'next_cursor',next_id,
        'scope',jsonb_build_object('tenant_id',p_tenant_id,'company_id',p_company_id),
        'classification_notice','resolved_only; pending/conflict remain in the unchanged legacy workflow');
END;
$fn$;

CREATE FUNCTION public.rpc_multi06_get_operation(p_tenant_id uuid,p_company_id uuid,p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE item jsonb;
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'operations.read') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    SELECT to_jsonb(o) INTO item FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o WHERE o.id=p_operation_id;
    IF item IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('item',item);
END;
$fn$;

CREATE FUNCTION public.rpc_multi06_export_operations_page(p_tenant_id uuid,p_company_id uuid,
    p_search text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'export.operational') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN public.rpc_multi06_list_operations(p_tenant_id,p_company_id,p_search,p_after_id,p_limit);
END;
$fn$;

-- Backend activation gate, not a UI flag. Even authorized clients cannot call
-- these prepared endpoints until a later reviewed migration closes bypasses.
REVOKE ALL ON FUNCTION private.multi06_operation_rows(uuid,uuid),
    public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer),
    public.rpc_multi06_get_operation(uuid,uuid,uuid),
    public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer)
    FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE private.operation_company_classification_events IS
    'Closed trusted evidence ledger; no inference, public administration, seeds or backfill. Retain history.';
GRANT CREATE ON SCHEMA public,private TO rotero_operations_read_owner;
ALTER TABLE private.operation_company_classification_events OWNER TO rotero_operations_read_owner;
ALTER FUNCTION private.multi06_operation_rows(uuid,uuid) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_get_operation(uuid,uuid,uuid) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer) OWNER TO rotero_operations_read_owner;
REVOKE CREATE ON SCHEMA public,private FROM rotero_operations_read_owner;
DO $reference_cleanup$
DECLARE actor text:=pg_catalog.current_setting('multi06.migration_actor');
    missing text:=pg_catalog.current_setting('multi06.reference_columns');
BEGIN
    IF missing<>'' THEN
        SET LOCAL ROLE rotero_company_access_owner;
        EXECUTE format('REVOKE REFERENCES (%s) ON public.companies FROM %I',missing,actor);
        EXECUTE format('SET LOCAL ROLE %I',actor);
    END IF;
END;
$reference_cleanup$;
COMMENT ON COLUMN public.operations.company_id IS 'No inferred/default company. MULTI-06 remains prepared, not activated.';
COMMIT;
