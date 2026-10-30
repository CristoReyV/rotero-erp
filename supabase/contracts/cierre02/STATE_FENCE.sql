SET search_path=pg_catalog;
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
)) SELECT md5((payload::jsonb-'roles'-'role_memberships'-'dependencies')::text) FROM snapshot;
