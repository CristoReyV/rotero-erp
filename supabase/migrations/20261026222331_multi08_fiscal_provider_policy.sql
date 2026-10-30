-- MULTI-08: explicit future selection, immutable origin and one local stamp lane.
-- No secrets, endpoint input, provider calls, real grants or production transport.
BEGIN;
DO $role$ DECLARE actor text:=current_user; BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_fiscal_policy_owner') THEN
  CREATE ROLE rotero_fiscal_policy_owner NOLOGIN NOINHERIT NOBYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
  COMMENT ON ROLE rotero_fiscal_policy_owner IS 'ROTERO MULTI-08 fiscal metadata owner v1';
 END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_fiscal_policy_owner' AND NOT rolcanlogin AND NOT rolinherit
  AND NOT rolbypassrls AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
  AND shobj_description(oid,'pg_authid')='ROTERO MULTI-08 fiscal metadata owner v1')
  OR EXISTS(SELECT FROM pg_auth_members WHERE member='rotero_fiscal_policy_owner'::regrole)
  OR EXISTS(SELECT FROM unnest(ARRAY['anon','authenticated','service_role','authenticator']) r WHERE pg_has_role(r,'rotero_fiscal_policy_owner','MEMBER')) THEN
  RAISE EXCEPTION 'multi08_owner_collision'; END IF;
 EXECUTE format('GRANT rotero_fiscal_policy_owner TO %I WITH SET TRUE',actor);
 EXECUTE format('GRANT rotero_fiscal_policy_owner TO %I WITH INHERIT FALSE',actor);
END $role$;
GRANT USAGE ON SCHEMA public,private TO rotero_fiscal_policy_owner;
SELECT set_config('multi08.actor',current_user,true);
SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO rotero_fiscal_policy_owner;
GRANT EXECUTE ON FUNCTION private.multi04_has_company_access(uuid,uuid),private.multi05_has_company_capability(uuid,uuid,text),private.multi05_request_actor() TO rotero_fiscal_policy_owner;
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;
GRANT REFERENCES(id) ON public.billing_cfdis TO rotero_fiscal_policy_owner;
ALTER TABLE public.fiscal_requests ADD CONSTRAINT fiscal_requests_m08_origin_identity UNIQUE(id,billing_cfdi_id);
GRANT REFERENCES(id,billing_cfdi_id) ON public.fiscal_requests TO rotero_fiscal_policy_owner;
GRANT EXECUTE ON FUNCTION public.rpc_write_audit(uuid,text,text,uuid,jsonb) TO rotero_fiscal_policy_owner;
GRANT CREATE ON SCHEMA private,public TO rotero_fiscal_policy_owner;
SET LOCAL ROLE rotero_fiscal_policy_owner;
CREATE TABLE private.company_fiscal_provider_configs (
 tenant_id uuid NOT NULL, company_id uuid NOT NULL, provider_code text NOT NULL,
 environment text NOT NULL, configured_by uuid NOT NULL, configured_at timestamptz NOT NULL DEFAULT now(),
 approval_reference text NOT NULL CHECK(length(trim(approval_reference)) BETWEEN 1 AND 240),
 PRIMARY KEY(tenant_id,company_id), FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 CHECK(provider_code IN ('facturama','soft_management')),
 CHECK(environment IN ('sandbox','production') AND (provider_code<>'facturama' OR environment='sandbox'))
);
-- A configured row deliberately has no enabled flag. Activation of new transport
-- needs a later reviewed contract; browser configuration cannot grant it.
CREATE TABLE private.fiscal_document_origins (
 cfdi_id uuid PRIMARY KEY REFERENCES public.billing_cfdis(id), tenant_id uuid NOT NULL,company_id uuid NOT NULL,
 provider_code text NOT NULL,environment text NOT NULL,credential_profile text NOT NULL, external_id text,
 bound_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 UNIQUE(cfdi_id,provider_code,environment,credential_profile),
 UNIQUE(provider_code,environment,credential_profile,external_id),
 CHECK((provider_code='facturama' AND environment='sandbox' AND credential_profile='facturama_sandbox_lab_v1')
  OR (provider_code='soft_management' AND environment='sandbox' AND credential_profile='soft_management_sandbox_v1')
  OR (provider_code='soft_management' AND environment='production' AND credential_profile='soft_management_production_v1')),
 CHECK(external_id IS NULL OR length(external_id) BETWEEN 1 AND 240)
);
CREATE TABLE private.fiscal_stamp_lanes (
 cfdi_id uuid PRIMARY KEY, provider_code text NOT NULL,environment text NOT NULL,credential_profile text NOT NULL,
 lease_id uuid NOT NULL DEFAULT gen_random_uuid(), state text NOT NULL CHECK(state IN ('uncertain','identified','completed','rejected')),
 claimed_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(cfdi_id,provider_code,environment,credential_profile)
  REFERENCES private.fiscal_document_origins(cfdi_id,provider_code,environment,credential_profile)
);
CREATE TABLE private.fiscal_request_origins (
 request_id uuid PRIMARY KEY, cfdi_id uuid NOT NULL,
 provider_code text NOT NULL,environment text NOT NULL,credential_profile text NOT NULL,
 FOREIGN KEY(request_id,cfdi_id) REFERENCES public.fiscal_requests(id,billing_cfdi_id),
 FOREIGN KEY(cfdi_id,provider_code,environment,credential_profile)
  REFERENCES private.fiscal_document_origins(cfdi_id,provider_code,environment,credential_profile)
);
DO $close$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['company_fiscal_provider_configs','fiscal_document_origins','fiscal_stamp_lanes','fiscal_request_origins'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $close$;
CREATE FUNCTION public.rpc_configure_company_fiscal_provider(p_tenant_id uuid,p_company_id uuid,p_provider_code text,p_environment text,p_approval_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'companies.manage') THEN
  RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_provider_code IS NULL OR p_environment IS NULL OR p_provider_code NOT IN ('facturama','soft_management')
  OR p_environment NOT IN ('sandbox','production') OR (p_provider_code='facturama' AND p_environment<>'sandbox')
  OR p_approval_reference IS NULL OR length(trim(p_approval_reference)) NOT BETWEEN 1 AND 240 THEN
  RETURN jsonb_build_object('error','invalid_provider_selection'); END IF;
 INSERT INTO private.company_fiscal_provider_configs(tenant_id,company_id,provider_code,environment,configured_by,approval_reference)
 VALUES(p_tenant_id,p_company_id,p_provider_code,p_environment,(SELECT user_id FROM private.multi05_request_actor()),p_approval_reference)
 ON CONFLICT(tenant_id,company_id) DO UPDATE SET provider_code=EXCLUDED.provider_code,environment=EXCLUDED.environment,
  configured_by=EXCLUDED.configured_by,configured_at=now(),approval_reference=EXCLUDED.approval_reference;
 PERFORM public.rpc_write_audit(p_tenant_id,'company_fiscal_provider_configured','company',p_company_id,
  jsonb_build_object('provider_code',p_provider_code,'environment',p_environment,'enabled',false));
 RETURN jsonb_build_object('configured',true,'enabled',false,'provider_code',p_provider_code,'environment',p_environment,
  'validation',CASE WHEN p_provider_code='soft_management' THEN 'pending_validation' ELSE 'sandbox_only' END);
END $fn$;
CREATE FUNCTION public.rpc_get_company_fiscal_provider(p_tenant_id uuid,p_company_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c private.company_fiscal_provider_configs;
BEGIN
 IF NOT private.multi04_has_company_access(p_tenant_id,p_company_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT * INTO c FROM private.company_fiscal_provider_configs WHERE tenant_id=p_tenant_id AND company_id=p_company_id;
 RETURN jsonb_build_object('configured',c.company_id IS NOT NULL,'enabled',false,'provider_code',c.provider_code,'environment',c.environment,
  'available_providers',jsonb_build_array(
   jsonb_build_object('code','facturama','available',true,'validation','sandbox_only','environments',jsonb_build_array('sandbox')),
   jsonb_build_object('code','soft_management','available',true,'validation','pending_validation','environments',jsonb_build_array('sandbox','production'))));
END $fn$;
-- Not an API/worker entry point. The canonical aggregate is the local fiscal
-- operation key, across providers. There is no timeout-based stamp retry: an
-- uncertain lane requires explicit reconciliation, never a provider fallback.
CREATE FUNCTION private.multi08_begin_stamp(p_cfdi uuid,p_provider text,p_environment text,p_profile text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE o private.fiscal_document_origins; token uuid;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('multi08:stamp:'||p_cfdi::text,0));
 SELECT * INTO o FROM private.fiscal_document_origins WHERE cfdi_id=p_cfdi;
 IF o.cfdi_id IS NULL OR ROW(o.provider_code,o.environment,o.credential_profile) IS DISTINCT FROM ROW(p_provider,p_environment,p_profile)
  OR o.external_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_conflict'; END IF;
 INSERT INTO private.fiscal_stamp_lanes(cfdi_id,provider_code,environment,credential_profile,state)
 VALUES(p_cfdi,p_provider,p_environment,p_profile,'uncertain') ON CONFLICT(cfdi_id) DO NOTHING RETURNING lease_id INTO token;
 IF token IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_reconciliation_required'; END IF;
 RETURN token;
END $fn$;
CREATE FUNCTION private.multi08_immutable_origin() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF TG_OP='DELETE' OR ROW(NEW.cfdi_id,NEW.tenant_id,NEW.company_id,NEW.provider_code,NEW.environment,NEW.credential_profile,NEW.bound_at)
  IS DISTINCT FROM ROW(OLD.cfdi_id,OLD.tenant_id,OLD.company_id,OLD.provider_code,OLD.environment,OLD.credential_profile,OLD.bound_at)
  OR (OLD.external_id IS NOT NULL AND NEW.external_id IS DISTINCT FROM OLD.external_id) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_fiscal_origin'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER fiscal_origin_immutable BEFORE UPDATE OR DELETE ON private.fiscal_document_origins FOR EACH ROW EXECUTE FUNCTION private.multi08_immutable_origin();
CREATE FUNCTION private.multi08_immutable_request_binding() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF TG_OP='DELETE' OR NEW IS DISTINCT FROM OLD THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_fiscal_request_binding'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER fiscal_request_binding_immutable BEFORE UPDATE OR DELETE ON private.fiscal_request_origins FOR EACH ROW EXECUTE FUNCTION private.multi08_immutable_request_binding();
CREATE FUNCTION private.multi08_stamp_lane_guard() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF TG_OP='DELETE' OR ROW(NEW.cfdi_id,NEW.provider_code,NEW.environment,NEW.credential_profile,NEW.lease_id,NEW.claimed_at)
  IS DISTINCT FROM ROW(OLD.cfdi_id,OLD.provider_code,OLD.environment,OLD.credential_profile,OLD.lease_id,OLD.claimed_at)
  OR (OLD.state IN ('identified','completed','rejected') AND NEW.state='uncertain') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_fiscal_stamp_lane'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER fiscal_stamp_lane_immutable BEFORE UPDATE OR DELETE ON private.fiscal_stamp_lanes FOR EACH ROW EXECUTE FUNCTION private.multi08_stamp_lane_guard();
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;
REVOKE CREATE ON SCHEMA private,public FROM rotero_fiscal_policy_owner;
ALTER TABLE public.billing_cfdis ADD COLUMN fiscal_environment text CHECK(fiscal_environment IN ('sandbox','production')),
 ADD COLUMN fiscal_credential_profile text,
 ADD CONSTRAINT fiscal_origin_namespace_pair CHECK((fiscal_environment IS NULL)=(fiscal_credential_profile IS NULL));
-- Keep legacy unknown-origin uniqueness, but never treat an external ID as
-- global across providers, environments or credential namespaces.
DROP INDEX public.billing_cfdis_tenant_provider_document_uidx;
CREATE UNIQUE INDEX billing_cfdis_legacy_external_uidx ON public.billing_cfdis(tenant_id,fiscal_provider,provider_document_id)
 WHERE provider_document_id IS NOT NULL AND fiscal_provider IS NOT NULL AND fiscal_environment IS NULL;
CREATE UNIQUE INDEX billing_cfdis_origin_external_uidx ON public.billing_cfdis(fiscal_provider,fiscal_environment,fiscal_credential_profile,provider_document_id)
 WHERE provider_document_id IS NOT NULL AND fiscal_environment IS NOT NULL;
-- Only metadata is visible to the integration guards, never payloads/secrets.
GRANT SELECT(id,tenant_id,fiscal_provider,provider_document_id) ON public.billing_cfdis TO rotero_fiscal_policy_owner;
CREATE POLICY billing_cfdis_m08_metadata ON public.billing_cfdis FOR SELECT TO rotero_fiscal_policy_owner USING(true);
GRANT SELECT(tenant_id,company_id,enabled,environment) ON private.fiscal01_company_bindings TO rotero_fiscal_policy_owner;
GRANT SELECT(cfdi_id,tenant_id,company_id,provider_document_id,uncertain,busy_token,busy_action,xml_path) ON private.fiscal01_documents TO rotero_fiscal_policy_owner;
CREATE POLICY fiscal01_binding_m08_metadata ON private.fiscal01_company_bindings FOR SELECT TO rotero_fiscal_policy_owner USING(true);
CREATE POLICY fiscal01_document_m08_metadata ON private.fiscal01_documents FOR SELECT TO rotero_fiscal_policy_owner USING(true);
CREATE FUNCTION private.multi08_bind_origin() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c record;
BEGIN
 SELECT id,tenant_id,fiscal_provider,provider_document_id INTO c FROM public.billing_cfdis WHERE id=NEW.cfdi_id;
 IF NOT FOUND OR c.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_tenant_conflict'; END IF;
 IF (c.fiscal_provider IS NOT NULL AND c.fiscal_provider IS DISTINCT FROM NEW.provider_code)
  OR (c.provider_document_id IS NOT NULL AND (c.fiscal_provider IS NULL OR c.provider_document_id IS DISTINCT FROM NEW.external_id)) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_conflict'; END IF;
 RETURN NEW;
END $fn$;
SET LOCAL ROLE rotero_fiscal_policy_owner;
CREATE TRIGGER fiscal_origin_tenant BEFORE INSERT ON private.fiscal_document_origins FOR EACH ROW EXECUTE FUNCTION private.multi08_bind_origin();
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;

CREATE FUNCTION private.multi08_fiscal01_origin() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c private.company_fiscal_provider_configs; o private.fiscal_document_origins;
BEGIN
 IF TG_OP='INSERT' THEN
  SELECT * INTO c FROM private.company_fiscal_provider_configs WHERE tenant_id=NEW.tenant_id AND company_id=NEW.company_id;
  -- Existing explicit laboratory bindings remain a compatibility route. A new
  -- configured selection is disabled and cannot silently enable new emissions.
  IF c.company_id IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='company_fiscal_transport_disabled'; END IF;
  IF NOT EXISTS(SELECT FROM private.fiscal01_company_bindings b WHERE b.tenant_id=NEW.tenant_id AND b.company_id=NEW.company_id AND b.enabled AND b.environment='sandbox') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='company_fiscal_transport_disabled'; END IF;
  INSERT INTO private.fiscal_document_origins(cfdi_id,tenant_id,company_id,provider_code,environment,credential_profile,external_id)
   VALUES(NEW.cfdi_id,NEW.tenant_id,NEW.company_id,'facturama','sandbox','facturama_sandbox_lab_v1',NEW.provider_document_id);
 ELSE
  SELECT * INTO o FROM private.fiscal_document_origins WHERE cfdi_id=NEW.cfdi_id;
  IF o.cfdi_id IS NULL OR ROW(o.tenant_id,o.company_id,o.provider_code,o.environment,o.credential_profile)
   IS DISTINCT FROM ROW(NEW.tenant_id,NEW.company_id,'facturama'::text,'sandbox'::text,'facturama_sandbox_lab_v1'::text) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_conflict'; END IF;
  IF NEW.busy_action='claim' AND NEW.busy_token IS NOT NULL AND NEW.busy_token IS DISTINCT FROM OLD.busy_token THEN
   IF EXISTS(SELECT FROM private.company_fiscal_provider_configs WHERE tenant_id=NEW.tenant_id AND company_id=NEW.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='company_fiscal_transport_disabled'; END IF;
   PERFORM private.multi08_begin_stamp(NEW.cfdi_id,'facturama','sandbox','facturama_sandbox_lab_v1');
  END IF;
  IF NEW.provider_document_id IS DISTINCT FROM OLD.provider_document_id THEN
   UPDATE private.fiscal_document_origins SET external_id=NEW.provider_document_id WHERE cfdi_id=NEW.cfdi_id;
  END IF;
  UPDATE private.fiscal_stamp_lanes SET state=CASE WHEN NEW.xml_path IS NOT NULL THEN 'completed'
    WHEN NEW.provider_document_id IS NOT NULL THEN 'identified' ELSE state END,updated_at=now() WHERE cfdi_id=NEW.cfdi_id;
 END IF;
 RETURN NEW;
END $fn$;
CREATE FUNCTION private.multi08_canonical_origin() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE o private.fiscal_document_origins;
BEGIN
 SELECT * INTO o FROM private.fiscal_document_origins WHERE cfdi_id=NEW.id;
 IF o.cfdi_id IS NOT NULL AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.tenant_id IS DISTINCT FROM o.tenant_id
  OR NEW.fiscal_provider IS DISTINCT FROM o.provider_code
  OR (o.external_id IS NOT NULL AND NEW.provider_document_id IS DISTINCT FROM o.external_id)) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_conflict'; END IF;
 IF o.cfdi_id IS NOT NULL THEN
  IF o.external_id IS NULL AND NEW.provider_document_id IS NOT NULL THEN
   UPDATE private.fiscal_document_origins SET external_id=NEW.provider_document_id WHERE cfdi_id=NEW.id;
   UPDATE private.fiscal_stamp_lanes SET state='identified',updated_at=now() WHERE cfdi_id=NEW.id;
  END IF;
  NEW.fiscal_environment:=o.environment; NEW.fiscal_credential_profile:=o.credential_profile;
 ELSIF NEW.fiscal_environment IS NOT NULL OR NEW.fiscal_credential_profile IS NOT NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_origin_required';
 END IF;
 RETURN NEW;
END $fn$;
-- Bind only proven historical Facturama laboratory rows. No company inference
-- or rewriting of their canonical documents, requests, attempts or artifacts.
SET LOCAL ROLE rotero_fiscal_policy_owner;
INSERT INTO private.fiscal_document_origins(cfdi_id,tenant_id,company_id,provider_code,environment,credential_profile,external_id)
 SELECT cfdi_id,tenant_id,company_id,'facturama','sandbox','facturama_sandbox_lab_v1',provider_document_id FROM private.fiscal01_documents;
INSERT INTO private.fiscal_stamp_lanes(cfdi_id,provider_code,environment,credential_profile,state)
 SELECT cfdi_id,'facturama','sandbox','facturama_sandbox_lab_v1',CASE WHEN xml_path IS NOT NULL THEN 'completed' WHEN provider_document_id IS NOT NULL THEN 'identified' ELSE 'uncertain' END
 FROM private.fiscal01_documents WHERE uncertain OR provider_document_id IS NOT NULL OR busy_action='claim';
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;
CREATE TRIGGER zz_multi08_fiscal01_origin BEFORE INSERT OR UPDATE ON private.fiscal01_documents FOR EACH ROW EXECUTE FUNCTION private.multi08_fiscal01_origin();
CREATE TRIGGER zz_multi08_canonical_origin BEFORE INSERT OR UPDATE ON public.billing_cfdis FOR EACH ROW EXECUTE FUNCTION private.multi08_canonical_origin();
-- Requests and artifacts retain their original aggregate link. Attempts already
-- have the fiscal0 immutable trigger; also disallow origin/link reassignment.
CREATE FUNCTION private.multi08_request_origin() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
 IF ROW(NEW.id,NEW.tenant_id,NEW.billing_cfdi_id,NEW.request_type,NEW.payload_snapshot,NEW.idempotency_key)
  IS DISTINCT FROM ROW(OLD.id,OLD.tenant_id,OLD.billing_cfdi_id,OLD.request_type,OLD.payload_snapshot,OLD.idempotency_key) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='immutable_fiscal_request_origin'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER multi08_request_origin BEFORE UPDATE ON public.fiscal_requests FOR EACH ROW EXECUTE FUNCTION private.multi08_request_origin();
CREATE FUNCTION private.multi08_bind_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
 IF EXISTS(SELECT FROM private.fiscal_document_origins WHERE cfdi_id=NEW.billing_cfdi_id AND tenant_id IS DISTINCT FROM NEW.tenant_id) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_request_tenant_conflict'; END IF;
 INSERT INTO private.fiscal_request_origins(request_id,cfdi_id,provider_code,environment,credential_profile)
  SELECT NEW.id,o.cfdi_id,o.provider_code,o.environment,o.credential_profile FROM private.fiscal_document_origins o
  WHERE o.cfdi_id=NEW.billing_cfdi_id AND o.tenant_id=NEW.tenant_id;
 RETURN NEW;
END $fn$;
CREATE TRIGGER multi08_bind_request AFTER INSERT ON public.fiscal_requests FOR EACH ROW EXECUTE FUNCTION private.multi08_bind_request();
-- Historical bindings are admitted only for the explicit laboratory snapshots.
-- Unknown earlier attempts remain unknown; binding a document later does not
-- relabel a request that used another/unknown provider or environment.
SET LOCAL ROLE rotero_fiscal_policy_owner;
DO $$ BEGIN EXECUTE format('GRANT INSERT ON private.fiscal_request_origins TO %I',current_setting('multi08.actor')); END $$;
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;
INSERT INTO private.fiscal_request_origins(request_id,cfdi_id,provider_code,environment,credential_profile)
 SELECT r.id,d.cfdi_id,'facturama','sandbox','facturama_sandbox_lab_v1' FROM public.fiscal_requests r
 JOIN private.fiscal01_documents d ON d.cfdi_id=r.billing_cfdi_id AND d.tenant_id=r.tenant_id
 WHERE r.payload_snapshot->>'company_id'=d.company_id::text
  AND NOT EXISTS(SELECT FROM public.fiscal_provider_attempts a WHERE a.request_id=r.id AND a.provider_code IS DISTINCT FROM 'facturama');
SET LOCAL ROLE rotero_fiscal_policy_owner;
DO $$ BEGIN EXECUTE format('REVOKE INSERT ON private.fiscal_request_origins FROM %I',current_setting('multi08.actor')); END $$;
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('multi08.actor')); END $$;
CREATE FUNCTION private.multi08_attempt_origin() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE o private.fiscal_document_origins;
BEGIN
 SELECT x.* INTO o FROM private.fiscal_document_origins x JOIN private.fiscal_request_origins r ON r.cfdi_id=x.cfdi_id WHERE r.request_id=NEW.request_id;
 IF o.cfdi_id IS NOT NULL AND (o.provider_code IS DISTINCT FROM NEW.provider_code OR o.tenant_id IS DISTINCT FROM NEW.tenant_id) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_attempt_origin_conflict'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER multi08_attempt_origin BEFORE INSERT ON public.fiscal_provider_attempts FOR EACH ROW EXECUTE FUNCTION private.multi08_attempt_origin();
CREATE FUNCTION private.multi08_readiness_provider(p_cfdi uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE o private.fiscal_document_origins;
BEGIN
 SELECT * INTO o FROM private.fiscal_document_origins WHERE cfdi_id=p_cfdi;
 IF o.cfdi_id IS NULL OR NOT private.multi04_has_company_access(o.tenant_id,o.company_id) THEN
  RETURN jsonb_build_object('configured',false,'enabled',false,'code',NULL,'environment','sandbox','validation','not_configured'); END IF;
 -- The existing guarded Facturama laboratory panel is the only active path.
 -- General neutral orchestration stays disabled, even for configured providers.
 RETURN jsonb_build_object('configured',true,'enabled',false,'code',o.provider_code,'environment',o.environment,
  'validation',CASE WHEN o.provider_code='facturama' THEN 'sandbox_only' ELSE 'pending_validation' END,
  'capabilities',jsonb_build_object('stamp',false,'status',false,'cancel',false));
END $fn$;
CREATE FUNCTION private.multi08_lab_selection(p_tenant uuid,p_company uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE c private.company_fiscal_provider_configs;
BEGIN
 SELECT * INTO c FROM private.company_fiscal_provider_configs WHERE tenant_id=p_tenant AND company_id=p_company;
 RETURN jsonb_build_object('configured',c.company_id IS NOT NULL,'enabled',false,'code',c.provider_code,'environment',c.environment,
  'validation',CASE WHEN c.provider_code='soft_management' THEN 'pending_validation' WHEN c.provider_code='facturama' THEN 'sandbox_only' ELSE 'not_configured' END);
END $fn$;
DO $lab_context$ DECLARE d text; needle text:='jsonb_object_agg(a,private.fiscal01_authorized(d.tenant_id,d.company_id,a))'; BEGIN
 SELECT pg_get_functiondef('public.rpc_fiscal01_context(uuid)'::regprocedure) INTO d;
 IF position(needle IN d)=0 OR d NOT LIKE '%cancellation_pdf_available%' OR d NOT LIKE '%''actions'',actions,%' THEN RAISE EXCEPTION 'unsupported_fiscal05_context'; END IF;
 d:=replace(d,needle,'jsonb_object_agg(a,private.fiscal01_authorized(d.tenant_id,d.company_id,a) AND (a NOT IN (''prepare'',''issue'') OR NOT (private.multi08_lab_selection(d.tenant_id,d.company_id)->>''configured'')::boolean))');
 d:=replace(d,'''actions'',actions,','''actions'',actions,''future_provider'',private.multi08_lab_selection(d.tenant_id,d.company_id),');
 EXECUTE d;
END $lab_context$;
DO $readiness$ DECLARE d text; needle text:=E'''provider'',jsonb_build_object(''configured'',COALESCE(v_config.enabled,false) AND v_config.provider_code IS NOT NULL,\n            ''code'',v_config.provider_code,''environment'',COALESCE(v_config.environment,''sandbox''))'; BEGIN
 SELECT pg_get_functiondef('public.rpc_get_fiscal_readiness(uuid)'::regprocedure) INTO d;
 -- Same reviewed source fragment, accepting the Windows transport newline.
 -- Preserve the stored body; do not broaden the source match or replace logic.
 IF position(needle IN d)=0 AND position(replace(needle,chr(10),chr(13)||chr(10)) IN d)>0
 THEN needle:=replace(needle,chr(10),chr(13)||chr(10)); END IF;
 IF position(needle IN d)=0 OR d NOT LIKE '%private.fiscal02_readable_cfdis%' THEN RAISE EXCEPTION 'unsupported_fiscal_readiness_source'; END IF;
 EXECUTE replace(d,needle,'''provider'',private.multi08_readiness_provider(v_cfdi.id)');
END $readiness$;
-- The neutral worker remains owner-only. It must not dispatch legacy queued
-- requests lacking a verified company/origin or bypass the shared stamp lane.
DO $claim_guard$ DECLARE p oid:='private.fiscal0_claim_requests(integer)'::regprocedure; d text; BEGIN
 SELECT pg_get_functiondef(p) INTO d;
 IF d NOT LIKE '%FOR UPDATE SKIP LOCKED%' OR d NOT LIKE '%RETURN NEXT v_request;%' OR d LIKE '%multi08_begin_stamp%' THEN RAISE EXCEPTION 'unsupported_fiscal0_claim'; END IF;
 d:=replace(d,'RETURN NEXT v_request;',E'RAISE EXCEPTION USING ERRCODE=\'23514\',MESSAGE=\'neutral_transport_not_activated\';\n    RETURN NEXT v_request;');
 EXECUTE d;
END $claim_guard$;
-- Finite company selections replace the old tenant-wide writable toggle. Keep
-- its signature for callers but return an explicit transition error, not success.
CREATE OR REPLACE FUNCTION public.rpc_update_fiscal_provider_config(p_tenant_id uuid,p_provider_code text,p_enabled boolean,p_environment text,p_capabilities jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
BEGIN RETURN jsonb_build_object('error','company_provider_configuration_required'); END $fn$;
CREATE OR REPLACE FUNCTION public.rpc_queue_fiscal_stamp(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE tenant uuid;
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT tenant_id INTO tenant FROM private.fiscal02_readable_cfdis WHERE id=p_cfdi_id;
 IF tenant IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
 IF NOT public.tanda1_user_has_role(tenant,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 -- The owner-only neutral worker and general UI have no activated transport.
 -- The reviewed Facturama lab uses its separate guarded worker and stamp lane.
 RETURN jsonb_build_object('error','company_fiscal_transport_disabled');
END $fn$;
DO $owners$ DECLARE f record; actor text:=current_user; BEGIN
 GRANT CREATE ON SCHEMA private TO rotero_fiscal_policy_owner;
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname LIKE 'multi08_%' AND p.proname<>'multi08_legacy_write_target' LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO rotero_fiscal_policy_owner',f.signature);
 END LOOP;
 REVOKE CREATE ON SCHEMA private FROM rotero_fiscal_policy_owner;
 SET LOCAL ROLE rotero_fiscal_policy_owner;
 GRANT SELECT(cfdi_id) ON private.fiscal_document_origins TO rotero_finance_scope_owner;
 CREATE POLICY fiscal_origins_finance_metadata ON private.fiscal_document_origins FOR SELECT TO rotero_finance_scope_owner USING(true);
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname LIKE 'multi08_%' AND p.proname<>'multi08_legacy_write_target' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
 EXECUTE format('GRANT EXECUTE ON FUNCTION private.multi08_begin_stamp(uuid,text,text,text) TO %I',actor);
 EXECUTE format('GRANT EXECUTE ON FUNCTION private.multi08_readiness_provider(uuid) TO %I',actor);
 EXECUTE format('GRANT EXECUTE ON FUNCTION private.multi08_lab_selection(uuid,uuid) TO %I',actor);
 REVOKE ALL ON FUNCTION public.rpc_configure_company_fiscal_provider(uuid,uuid,text,text,text),public.rpc_get_company_fiscal_provider(uuid,uuid) FROM PUBLIC,anon,service_role;
 GRANT EXECUTE ON FUNCTION public.rpc_configure_company_fiscal_provider(uuid,uuid,text,text,text),public.rpc_get_company_fiscal_provider(uuid,uuid) TO authenticated;
 EXECUTE format('SET LOCAL ROLE %I',actor);
END $owners$;
DO $financial_origin$ DECLARE d text; actor text:=current_user; BEGIN
 SELECT pg_get_functiondef('private.multi08_legacy_write_target(uuid,text,uuid)'::regprocedure) INTO d;
 IF d NOT LIKE '%IF p_kind=''cfdi'' THEN%' THEN RAISE EXCEPTION 'unsupported_multi08_finance_cfdi_guard'; END IF;
 d:=replace(d,'IF p_kind=''cfdi'' THEN',E'IF p_kind=\'cfdi\' THEN\n  IF EXISTS(SELECT FROM private.fiscal_document_origins WHERE cfdi_id=p_id) THEN RETURN false; END IF;');
 GRANT CREATE ON SCHEMA private TO rotero_finance_scope_owner;
 SET LOCAL ROLE rotero_finance_scope_owner;
 EXECUTE d;
 EXECUTE format('SET LOCAL ROLE %I',actor);
 REVOKE CREATE ON SCHEMA private FROM rotero_finance_scope_owner;
END $financial_origin$;
COMMIT;
