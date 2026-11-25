from pathlib import Path
import json,hashlib,re
R=Path(__file__).resolve().parents[2]
CANONICAL_NAMES=json.loads((R/'supabase/contracts/cierre02/CANONICAL_PUBLIC_NAMES.json').read_text())
D=R/'supabase/contracts/cierre02';B=json.loads((D/'OBSERVED_FUNCTIONS.json').read_text());A=json.loads((D/'CANONICAL_ENTRIES.json').read_text());P=json.loads((R/'docs/delivery/reconciliation/DECISIONS.json').read_text());dec={x['signature']:x for x in P['decisions']}
def lit(v):return "'"+v.replace("'","''")+"'"
def archive(sig):return 'c02_observed_'+hashlib.sha256(sig.encode()).hexdigest()[:20]
def body(f):
 m=re.search(r'\bAS (\$\w*\$)(.*)\1',f['definition'],re.S);assert m,f['name'];return m[2].replace('\r\n','\n')
def argnames(f):return re.findall(r'\b(p_[a-z0-9_]+)\s',f['args'])
def acl(f,target,kind='legacy'):
 s=f'REVOKE ALL ON FUNCTION {target} FROM PUBLIC,anon,authenticated,service_role;\n'
 roles=[]
 if kind in ('server','trigger'):roles=['service_role'] if kind=='server' and f['service_role'] else []
 elif kind=='ordinary':roles=[r for r,k in [('authenticated','authenticated'),('service_role','service_role')] if f[k]]
 else:roles=[r for r,k in [('anon','anon'),('authenticated','authenticated'),('service_role','service_role')] if f[k]]
 if roles:s+=f'GRANT EXECUTE ON FUNCTION {target} TO '+','.join(roles)+';\n'
 return s
parts=[]
def add(s):parts.append('\n'.join(l.rstrip() for l in s.strip().splitlines())+'\n')
# Complete schema-state fence, not just a list of newly accepted function hashes.
fence=(D/'STATE_FENCE.sql').read_text(encoding='utf8');query=fence[fence.index('WITH snapshot'):].strip().removesuffix(';').replace('SELECT md5((payload', 'SELECT md5((payload')
query=query.replace(' FROM snapshot',' INTO v FROM snapshot')
storage_contract=json.loads((D/'STORAGE_PLATFORM_CONTRACT.json').read_text())
add("""-- CIERRE02_RECONCILIATION_BEGIN
-- A45 and the observed B catalog are the only reviewed entry states.
SET LOCAL search_path=pg_catalog;
DO $c02_fence$ DECLARE v text;BEGIN
"""+query+";\nIF v NOT IN('6767d279c285cfde732d84c5d1782947','16b137f19c54a6499924d0a8e663dc17','d86b1b5b73d52d77e1a864276d6e033a') THEN RAISE EXCEPTION 'cierre02_unreviewed_source_state'; END IF;\nPERFORM set_config('cierre02.source_variant',CASE WHEN v IN('16b137f19c54a6499924d0a8e663dc17','d86b1b5b73d52d77e1a864276d6e033a') THEN 'B' ELSE 'A' END,true);END $c02_fence$;")
add("""-- The concurrent Storage hook was reviewed separately, not accepted by name.
DO $c02_storage$ BEGIN
 IF EXISTS(SELECT FROM pg_trigger WHERE tgrelid='storage.buckets'::regclass
  AND tgname='enforce_versioning_status_transition' AND NOT tgisinternal) THEN
  IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=to_regprocedure('storage.enforce_versioning_status_transition()')
   AND NOT prosecdef AND proconfig IS NULL AND proacl IS NULL
   AND pg_get_userbyid(proowner)='supabase_storage_admin' AND prorettype='trigger'::regtype
   AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND provolatile='v' AND NOT proretset
   AND EXISTS(SELECT FROM pg_attribute WHERE attrelid='storage.buckets'::regclass
    AND attname='versioning_status' AND atttypid='text'::regtype AND attnotnull AND NOT attisdropped)
   AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))="""+lit(storage_contract['source_md5_lf'])+""" ) THEN
   RAISE EXCEPTION 'c02_storage_transition_drift';END IF;
 END IF;
END $c02_storage$;
""")
add("""DO $owner$ DECLARE r oid;api text;limited record;BEGIN
 IF EXISTS(SELECT FROM pg_auth_members WHERE member=ANY(ARRAY['anon'::regrole,'authenticated'::regrole,'service_role'::regrole])) THEN
  RAISE EXCEPTION 'c02_api_role_membership_drift';END IF;
 FOR limited IN SELECT * FROM pg_roles WHERE rolname LIKE 'rotero\\_%' ESCAPE '\\' LOOP
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
""")
# Archive only the actual observed B implementation. Fresh A receives no fake legacy implementation.
for sig,f in B.items():
 core=archive(sig);name=f['name'];types=f['input_types'];old='FUNCTION public.'+name+'(';new='FUNCTION private.'+core+'('
 add(f"""DO $capture$ DECLARE d text;BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 SELECT pg_get_functiondef({lit(sig)}::regprocedure) INTO d;
 IF position({lit(old)} IN d)=0 THEN RAISE EXCEPTION 'c02_definition_shape';END IF;
 EXECUTE replace(d,{lit(old)},{lit(new)});
 ALTER FUNCTION private.{core}({types}) SET search_path=pg_catalog,public,extensions,pg_temp;
 REVOKE ALL ON FUNCTION private.{core}({types}) FROM PUBLIC,anon,authenticated,service_role;
 GRANT EXECUTE ON FUNCTION private.{core}({types}) TO rotero_c02_gate_owner;
 END IF;END $capture$;""")
 add('INSERT INTO private.c02_contracts(signature,category,archive_signature,observed_body_md5,source_variant) VALUES('+','.join([lit(sig),lit(dec[sig]['category']),lit('private.'+core+'('+types+')'),lit(hashlib.md5(body(f).encode()).hexdigest()),"current_setting('cierre02.source_variant')"])+');')
# Nullable compatibility, never a historical company, author, license or date backfill.
objects=json.loads((R/'docs/delivery/reconciliation/OBJECT_DELTAS.json').read_text())
for table in objects['columns']:
 if not table['table'].startswith('public.'):continue
 for c in table['missing_columns']:
  t=table['table'];col=c['column'];typ=c['type']
  add(f'ALTER TABLE {t} ADD COLUMN IF NOT EXISTS {col} {typ};')
  if c['default'] is not None:
   add(f"DO $compat$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER TABLE {t} ALTER COLUMN {col} SET DEFAULT {c['default']};END IF;END $compat$;")
# Restore the main entry contracts. Token/service return-shape variants stay unchanged.
for policy in json.loads((R/'docs/delivery/reconciliation/POLICY_ROLE_ADAPTATIONS.json').read_text()):
 assert policy['roles']==['PUBLIC'] and policy['schema']=='public'
 assert 'public.memberships' in str(policy) or re.search(r'public\.(billing_user_has_tenant|tanda[23456]_[a-z_]+)\(',str(policy))
 identifier='"'+policy['name'].replace('"','""')+'"'
 add(f"DO $policy_roles$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER POLICY {identifier} ON public.{policy['table_name']} TO anon,authenticated,service_role;END IF;END $policy_roles$;")
add("""-- Cover observed document FKs without changing rows or relaxing integrity.
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
END IF;END $document_indexes$;""")
for sig,f in A.items():
 row=dec[sig]
 if row['category']=='keep_token_service_variant':continue
 if sig in B and f['default_args']!=B[sig]['default_args']:
  bound='c02_bound_'+hashlib.sha256(sig.encode()).hexdigest()[:20]
  add(f"DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION {sig} SET SCHEMA private;ALTER FUNCTION private.{f['name']}({f['input_types']}) RENAME TO {bound};REVOKE ALL ON FUNCTION private.{bound}({f['input_types']}) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;")
 add(f['definition'].replace('\r\n','\n')+';');add(acl(f,sig))
# Explicit minimal identifier grants for the gate, where the observed schema exists.
lookup={'p_document_id':'billing_documents','p_line_id':'billing_document_lines','p_tax_id':'billing_document_taxes','p_customer_id':'customers','p_provider_id':'logistics_providers','p_driver_id':'drivers','p_vehicle_id':'vehicles','p_operation_id':'operations','p_item_id':'daily_work_items','p_template_id':'document_templates','p_deal_id':'crm_deals'}
for t in sorted(set(lookup.values())):
 add(f"""DO $metadata$ BEGIN IF to_regclass('public.{t}') IS NOT NULL THEN
 GRANT SELECT(id,tenant_id) ON public.{t} TO rotero_c02_gate_owner;
 CREATE POLICY c02_identifier_metadata ON public.{t} FOR SELECT TO rotero_c02_gate_owner USING(true);
 END IF;END $metadata$;""")
# SQL-language helpers must be created after their public helper dependencies.
ordered=[];remaining=dict(B)
while remaining:
 ready=[k for k,f in remaining.items() if not any(other!=k and re.search(r'\bpublic\.'+re.escape(g['name'])+r'\s*\(',body(f)) for other,g in remaining.items())]
 if not ready:ready=[next(iter(remaining))]  # PL/pgSQL bodies are planned lazily; cycles are recorded in the review graph.
 for k in ready:ordered.append((k,remaining.pop(k)))
# Preserve disabled overloads and input-only helpers; close data helpers individually.
for sig,f in ordered:
 row=dec[sig];category=row['category'];name=f['name'];types=f['input_types'];core=archive(sig);names=argnames(f);params=','.join(names)
 if category=='canonical_default_redirect':
  # These exact shorter signatures make approved canonical DEFAULT arguments
  # ambiguous. Preserve their original OIDs privately; the public name resolves
  # the reviewed canonical contract. No function is dropped.
  bound='c02_bound_'+hashlib.sha256(sig.encode()).hexdigest()[:20]
  add(f"DO $redirect$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION {sig} SET SCHEMA private;ALTER FUNCTION private.{name}({types}) RENAME TO {bound};ALTER FUNCTION private.{bound}({types}) SET search_path=pg_catalog,public,extensions,pg_temp;REVOKE ALL ON FUNCTION private.{bound}({types}) FROM PUBLIC,anon,authenticated,service_role;END IF;END $redirect$;")
  continue
 if row['kind']=='changed' and name=='rpc_list_route_points':
  canonical=A[sig];a_core=core+'_a'
  a_def=canonical['definition'].replace('FUNCTION public.'+name+'(','FUNCTION private.'+a_core+'(',1)
  add(f"DO $route$ BEGIN IF current_setting('cierre02.source_variant')='A' THEN EXECUTE {lit(a_def)};REVOKE ALL ON FUNCTION private.{a_core}({types}) FROM PUBLIC,anon,authenticated,service_role;GRANT EXECUTE ON FUNCTION private.{a_core}({types}) TO rotero_c02_gate_owner;END IF;END $route$;")
  for variant,src,target in [('A',canonical,a_core),('B',f,core)]:
   denied="RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending';" if src['proretset'] else "RETURN jsonb_build_object('error','company_adoption_pending');"
   invoke=f'RETURN QUERY SELECT * FROM private.{target}({params});RETURN;' if src['proretset'] else f'RETURN private.{target}({params});'
   definition=f"CREATE OR REPLACE FUNCTION public.{name}({src['default_args']}) RETURNS {src['result']} LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route_impl$ DECLARE tenant uuid;BEGIN SELECT tenant_id INTO tenant FROM public.operations WHERE id=p_operation_id;IF private.c02_required(tenant) THEN {denied} END IF;{invoke} END $route_impl$"
   add(f"DO $route$ BEGIN IF current_setting('cierre02.source_variant')={lit(variant)} THEN EXECUTE {lit(definition)};END IF;END $route$;")
  add(acl(f,sig,'ordinary'))
  add(f'GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;\nALTER FUNCTION {sig} OWNER TO rotero_c02_gate_owner;\nREVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;\nSET LOCAL ROLE rotero_c02_gate_owner;\nGRANT EXECUTE ON FUNCTION {sig} TO postgres;\nSET LOCAL ROLE postgres;')
  continue
 if row['kind']=='changed':continue
 if category in ('pure_input_helper','own_membership_metadata','internal_trigger'):
  definition=f['definition'].replace('\r\n','\n')
  if category=='own_membership_metadata':definition=definition.replace('auth.uid()', '(SELECT user_id FROM private.multi05_request_actor())')
  if name=='tanda3_sync_payroll_period_from_finance':definition=re.sub(r'\bBEGIN\b','BEGIN\n IF private.c02_required(NEW.tenant_id) THEN RETURN NEW;END IF;',definition,count=1)
  add(definition+';');add(f'ALTER FUNCTION {sig} SET search_path=pg_catalog,public,extensions,pg_temp;')
  if category=='internal_trigger':add(acl(f,sig,'trigger'))
  else:
   add(acl(f,sig))
   if f['prosecdef']:
    add(f'GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;\nALTER FUNCTION {sig} OWNER TO rotero_c02_gate_owner;\nREVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;\nSET LOCAL ROLE rotero_c02_gate_owner;\nGRANT EXECUTE ON FUNCTION {sig} TO postgres;\nSET LOCAL ROLE postgres;')
  continue
 # Invoker helpers retain caller security. They are never silently elevated to definer.
 if category=='server_only_helper' and not f['prosecdef']:
  add(f"""DO $helper$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN
 ALTER FUNCTION {sig} SET search_path=pg_catalog,public,extensions,pg_temp;
 ELSE
 EXECUTE {lit('CREATE FUNCTION public.'+name+'('+f['default_args']+') RETURNS '+f['result']+" LANGUAGE plpgsql SET search_path='' AS $stub$ BEGIN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending'; END $stub$")};
 END IF;END $helper$;""");add(acl(f,sig,'server'));continue
 if name in ('rpc_accept_invitation','rpc_revoke_invitation'):
  add(f"DO $inert$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN EXECUTE {lit(f['definition'].replace(chr(13)+chr(10),chr(10)))};END IF;END $inert$;")
  add(f"DO $inert$ BEGIN IF to_regprocedure({lit(sig)}) IS NOT NULL THEN EXECUTE {lit(acl(f,sig))};END IF;END $inert$;");continue
 assert len(names)==(len(types.split(', ')) if types else 0),('unreviewed wrapper arguments',sig)
 # No ambiguous defaults on legacy overloads of a canonical entry. Full explicit
 # old signatures remain callable; canonical payloads have one deterministic entry.
 args=f['default_args']
 canonical_name=name in CANONICAL_NAMES
 siblings=[(k,x) for k,x in B.items() if x['name']==name and dec[k]['kind']=='extra']
 shortest=min(siblings,key=lambda pair:(len(argnames(pair[1])),pair[0]))[0] if siblings else sig
 if canonical_name or (len(siblings)>1 and sig!=shortest):args=f['args']
 if args!=f['default_args']:
  bound='c02_bound_'+hashlib.sha256(sig.encode()).hexdigest()[:20]
  add(f"DO $abi$ BEGIN IF current_setting('cierre02.source_variant')='B' THEN ALTER FUNCTION {sig} SET SCHEMA private;ALTER FUNCTION private.{name}({types}) RENAME TO {bound};REVOKE ALL ON FUNCTION private.{bound}({types}) FROM PUBLIC,anon,authenticated,service_role;END IF;END $abi$;")
 result=f['result'];is_set=f['proretset'];deny="RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='company_adoption_pending';" if is_set else "RETURN jsonb_build_object('error','company_adoption_pending');" if result=='jsonb' else 'RETURN;' if result=='void' else 'RETURN NULL;'
 unauth="RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='unauthorized';" if is_set else "RETURN jsonb_build_object('error','unauthorized');" if result=='jsonb' else 'RETURN;' if result=='void' else 'RETURN NULL;'
 call=f'RETURN QUERY SELECT * FROM private.{core}({params});RETURN;' if is_set else f'PERFORM private.{core}({params});RETURN;' if result=='void' else f'RETURN private.{core}({params});'
 tenant='p_tenant_id' if 'p_tenant_id' in names else 'NULL::uuid';resolve=''
 if tenant.startswith('NULL'):
  for p,t in lookup.items():
   if p in names:resolve=f'SELECT tenant_id INTO tenant FROM public.{t} WHERE id={p};';break
 trusted=category=='server_only_helper';token_helper=name in ('tracking_expire_tokens','tracking_try_append_route_point')
 guards='' if token_helper else f'IF private.c02_required({tenant}) THEN {deny} END IF;'
 guards+=f"IF to_regprocedure({lit('private.'+core+'('+types+')')}) IS NULL THEN {deny} END IF;"
 if not token_helper:
  guards+=f'tenant:={tenant};'+resolve+f'IF private.c02_required(tenant) THEN {deny} END IF;'
  if trusted:guards+=f"IF COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role' AND ((SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant)) THEN {unauth} END IF;"
  else:guards+=f'IF (SELECT user_id FROM private.multi05_request_actor()) IS NULL OR tenant IS NULL OR NOT public.tanda1_user_is_member(tenant) THEN {unauth} END IF;'
 vol='VOLATILE' if f['provolatile']=='v' else 'STABLE'
 add(f"CREATE OR REPLACE FUNCTION public.{name}({args}) RETURNS {result} LANGUAGE plpgsql {vol} SECURITY DEFINER SET search_path='' AS $c02$\nDECLARE tenant uuid;BEGIN {guards}\n{call}\nEND $c02$;")
 add(acl(f,sig,'server' if trusted else 'ordinary'))
 add(f'GRANT CREATE ON SCHEMA public TO rotero_c02_gate_owner;\nALTER FUNCTION {sig} OWNER TO rotero_c02_gate_owner;\nREVOKE CREATE ON SCHEMA public FROM rotero_c02_gate_owner;\nSET LOCAL ROLE rotero_c02_gate_owner;\nGRANT EXECUTE ON FUNCTION {sig} TO postgres;\nSET LOCAL ROLE postgres;')
# Known extra tenant tables: conditional, additive RLS; no tables or rows fabricated.
for t in objects['additional_tables']:
 if t['kind'] not in ('r','p'):continue
 cols=[c['column'] for c in t['columns'] or []]
 if 'tenant_id' not in cols:raise RuntimeError('Non-tenant business table requires a separate decision: '+t['name'])
 name=t['name'];add(f"""DO $rls$ BEGIN IF to_regclass('public.{name}') IS NOT NULL THEN
 ALTER TABLE public.{name} ENABLE ROW LEVEL SECURITY;
 CREATE POLICY c02_company_boundary ON public.{name} AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.c02_required(tenant_id)) WITH CHECK(NOT private.c02_required(tenant_id));
 END IF;END $rls$;""")
add("""CREATE FUNCTION private.c02_legacy_definition(p_signature text) RETURNS text LANGUAGE plpgsql STABLE SET search_path='' AS $fn$
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
""")
prelude='\n'.join(parts)
f=R/'supabase/migrations/20261026222327_multi08_operations_prerequisite.sql';original=f.read_bytes().replace(b'\r\n',b'\n').decode()
if '-- CIERRE02_RECONCILIATION_BEGIN' in original:original=original[:original.index('-- CIERRE02_RECONCILIATION_BEGIN')-1]+original[original.index('-- CIERRE02_RECONCILIATION_END')+len('-- CIERRE02_RECONCILIATION_END\n'):]
expected='dc9d34ea57e4f942b10598068da67bad56f1047046df1410e72e7a5c419aaea9';assert hashlib.sha256(original.encode()).hexdigest()==expected,'Unapplied prerequisite changed outside generator'
assert original.count('BEGIN;')>=1;pos=original.index('BEGIN;')+len('BEGIN;');new=original[:pos]+'\n'+prelude+original[pos:]
f.write_bytes(new.encode());print('Generated reviewed reconciliation prelude:',len(prelude),'bytes; 45 applied migrations untouched')
