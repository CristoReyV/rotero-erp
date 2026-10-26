-- FACTURAMA-02: retain strict XML acknowledgement identity and reconcile known
-- MULTI ownership without adopting or granting the unfinished MULTI-06/07 UI.
BEGIN;
ALTER TABLE private.fiscal01_documents
 ADD COLUMN cancellation_ack_state text NOT NULL DEFAULT 'unavailable'
  CHECK(cancellation_ack_state IN ('unavailable','unverified','mismatch','validated')),
 ADD COLUMN cancellation_ack_sha256 text CHECK(cancellation_ack_sha256 IS NULL OR cancellation_ack_sha256~'^[0-9a-f]{64}$');

CREATE FUNCTION private.fiscal02_assert_parent(p_parent jsonb,p_tenant uuid,p_company uuid)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $fn$
BEGIN
 IF (p_parent->>'tenant_id')::uuid IS DISTINCT FROM p_tenant
  OR p_parent->>'operation_id' IS NOT NULL
  OR (p_parent->>'company_id' IS NOT NULL AND (p_parent->>'company_id')::uuid IS DISTINCT FROM p_company) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='incompatible_sandbox_financial_parent';
 END IF;
END $fn$;
REVOKE ALL ON FUNCTION private.fiscal02_assert_parent(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fiscal02_guard_relation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s private.fiscal01_draft_scope; parent jsonb; cfdi uuid; tenant uuid; company uuid;
BEGIN
 -- Same transaction lock and ordering namespace as MULTI-07, also when that
 -- candidate is installed later. Never infer a company for pending history.
 tenant:=NEW.tenant_id;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(tenant::text,7007));
 IF TG_TABLE_SCHEMA='public' THEN
  cfdi:=(to_jsonb(NEW)->>'linked_cfdi_id')::uuid;
  FOR s IN SELECT q.* FROM private.fiscal01_draft_scope q WHERE q.cfdi_id=cfdi
   UNION SELECT q.* FROM private.fiscal01_draft_scope q WHERE TG_OP='UPDATE' AND q.cfdi_id=(to_jsonb(OLD)->>'linked_cfdi_id')::uuid
   UNION SELECT q.* FROM private.fiscal01_draft_scope q JOIN public.finance_invoices i ON i.linked_cfdi_id=q.cfdi_id
    WHERE TG_TABLE_NAME='billing_documents' AND i.billing_document_id=NEW.id LOOP
   PERFORM private.fiscal02_assert_parent(to_jsonb(NEW),s.tenant_id,s.company_id);
   IF auth.uid() IS NOT NULL AND NOT private.fiscal02_worker_company(s.tenant_id,s.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='sandbox_requires_guarded_worker'; END IF;
   IF TG_TABLE_NAME='finance_invoices' AND to_jsonb(NEW)->>'billing_document_id' IS NOT NULL THEN
    SELECT to_jsonb(b) INTO parent FROM public.billing_documents b WHERE b.id=(to_jsonb(NEW)->>'billing_document_id')::uuid;
    IF parent IS NOT NULL THEN PERFORM private.fiscal02_assert_parent(parent,s.tenant_id,s.company_id); END IF;
   END IF;
  END LOOP;
 ELSE
  cfdi:=NEW.cfdi_id;company:=NEW.company_id;
  FOR parent IN SELECT to_jsonb(i) FROM public.finance_invoices i WHERE i.linked_cfdi_id=cfdi
   UNION ALL SELECT to_jsonb(b) FROM public.billing_documents b WHERE b.linked_cfdi_id=cfdi
    OR b.id IN (SELECT i.billing_document_id FROM public.finance_invoices i WHERE i.linked_cfdi_id=cfdi) LOOP
   PERFORM private.fiscal02_assert_parent(parent,tenant,company);
  END LOOP;
 END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION private.fiscal02_guard_relation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fiscal02_scope_relation BEFORE INSERT OR UPDATE ON private.fiscal01_draft_scope FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_relation();
CREATE TRIGGER fiscal02_invoice_relation BEFORE INSERT OR UPDATE ON private.fiscal01_invoice_links FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_relation();
CREATE TRIGGER fiscal02_parent_relation BEFORE INSERT OR UPDATE ON public.finance_invoices FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_relation();
CREATE TRIGGER fiscal02_parent_relation BEFORE INSERT OR UPDATE ON public.billing_documents FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_relation();
DO $existing$
DECLARE r record; parent jsonb;
BEGIN
 FOR r IN SELECT * FROM private.fiscal01_draft_scope LOOP
  FOR parent IN SELECT to_jsonb(i) FROM public.finance_invoices i WHERE linked_cfdi_id=r.cfdi_id
   UNION ALL SELECT to_jsonb(b) FROM public.billing_documents b WHERE linked_cfdi_id=r.cfdi_id
    OR b.id IN (SELECT i.billing_document_id FROM public.finance_invoices i WHERE i.linked_cfdi_id=r.cfdi_id) LOOP
   PERFORM private.fiscal02_assert_parent(parent,r.tenant_id,r.company_id);
  END LOOP;
 END LOOP;
END $existing$;

-- Closed sandbox rows cannot be read or mutated through a legacy tenant-only
-- contract. Non-lab rows retain exactly their previous authorization contract.
CREATE FUNCTION private.fiscal02_is_lab_entity(p_kind text,p_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $guard$
BEGIN
 IF p_id IS NULL THEN RETURN false; END IF;
 CASE p_kind
 WHEN 'cfdi' THEN RETURN EXISTS(SELECT FROM private.fiscal01_draft_scope WHERE cfdi_id=p_id);
 WHEN 'invoice' THEN RETURN EXISTS(SELECT FROM public.finance_invoices i JOIN private.fiscal01_draft_scope s ON s.cfdi_id=i.linked_cfdi_id WHERE i.id=p_id);
 WHEN 'payment' THEN RETURN EXISTS(SELECT FROM public.finance_payments p WHERE p.id=p_id AND private.fiscal02_is_lab_entity('invoice',p.invoice_id));
 WHEN 'document' THEN RETURN EXISTS(SELECT FROM public.billing_documents b WHERE b.id=p_id AND
  (private.fiscal02_is_lab_entity('cfdi',b.linked_cfdi_id) OR EXISTS(SELECT FROM public.finance_invoices i WHERE i.billing_document_id=b.id AND private.fiscal02_is_lab_entity('invoice',i.id))));
 WHEN 'credit' THEN RETURN EXISTS(SELECT FROM public.billing_credit_notes c WHERE c.id=p_id AND
  (private.fiscal02_is_lab_entity('invoice',c.finance_invoice_id)
   OR private.fiscal02_is_lab_entity('document',(to_jsonb(c)->>'source_billing_document_id')::uuid)
   OR private.fiscal02_is_lab_entity('document',(to_jsonb(c)->>'credit_billing_document_id')::uuid)));
 WHEN 'complement' THEN RETURN EXISTS(SELECT FROM public.billing_payment_complements c WHERE c.id=p_id AND
  (private.fiscal02_is_lab_entity('invoice',c.finance_invoice_id)
   OR private.fiscal02_is_lab_entity('document',(to_jsonb(c)->>'invoice_billing_document_id')::uuid)
   OR private.fiscal02_is_lab_entity('document',(to_jsonb(c)->>'complement_billing_document_id')::uuid)));
 ELSE RETURN false;
 END CASE;
END $guard$;
REVOKE ALL ON FUNCTION private.fiscal02_is_lab_entity(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fiscal02_set_worker(p_cfdi uuid,p_actor uuid,p_cap text) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $guard$
DECLARE s private.fiscal01_draft_scope;
BEGIN
 SELECT * INTO s FROM private.fiscal01_draft_scope WHERE cfdi_id=p_cfdi;
 IF p_actor IS NULL OR p_actor IS DISTINCT FROM auth.uid() OR s.cfdi_id IS NULL
  OR NOT private.fiscal01_authorized(s.tenant_id,s.company_id,p_cap) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 PERFORM pg_catalog.set_config('fiscal02.cfdi',p_cfdi::text,true);
 PERFORM pg_catalog.set_config('fiscal02.actor',p_actor::text,true);
 PERFORM pg_catalog.set_config('fiscal02.company',s.company_id::text,true);
 PERFORM pg_catalog.set_config('fiscal02.tenant',s.tenant_id::text,true);
 PERFORM pg_catalog.set_config('fiscal02.cap',p_cap,true);
END $guard$;
REVOKE ALL ON FUNCTION private.fiscal02_set_worker(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fiscal02_worker_company(p_tenant uuid,p_company uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $guard$
 SELECT COALESCE(pg_catalog.current_setting('fiscal02.actor',true)=auth.uid()::text
  AND pg_catalog.current_setting('fiscal02.tenant',true)=p_tenant::text
  AND pg_catalog.current_setting('fiscal02.company',true)=p_company::text
  AND EXISTS(SELECT FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=NULLIF(pg_catalog.current_setting('fiscal02.cfdi',true),'')::uuid AND s.tenant_id=p_tenant AND s.company_id=p_company)
  AND private.fiscal01_authorized(p_tenant,p_company,pg_catalog.current_setting('fiscal02.cap',true)),false)
$guard$;
REVOKE ALL ON FUNCTION private.fiscal02_worker_company(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fiscal02_guard_cfdi_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
DECLARE s private.fiscal01_draft_scope;
BEGIN
 SELECT * INTO s FROM private.fiscal01_draft_scope WHERE cfdi_id=OLD.id;
 IF s.cfdi_id IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_OP='DELETE' OR pg_catalog.current_setting('fiscal02.cfdi',true) IS DISTINCT FROM OLD.id::text
  OR NOT private.fiscal02_worker_company(s.tenant_id,s.company_id) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='sandbox_requires_guarded_worker'; END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION private.fiscal02_guard_cfdi_write() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER a_fiscal02_guard_cfdi_write BEFORE UPDATE OR DELETE ON public.billing_cfdis FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_cfdi_write();

CREATE FUNCTION private.fiscal02_guard_financial_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
DECLARE row_data jsonb; old_data jsonb; s private.fiscal01_draft_scope; invoice_id uuid; old_invoice_id uuid;
BEGIN
 row_data:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 invoice_id:=COALESCE(row_data->>'invoice_id',row_data->>'finance_invoice_id')::uuid;
 IF TG_OP='UPDATE' THEN old_data:=to_jsonb(OLD);old_invoice_id:=COALESCE(old_data->>'invoice_id',old_data->>'finance_invoice_id')::uuid; END IF;
 FOR s IN SELECT q.* FROM private.fiscal01_draft_scope q JOIN public.finance_invoices i ON i.linked_cfdi_id=q.cfdi_id WHERE i.id=ANY(ARRAY[invoice_id,old_invoice_id]) LOOP
  IF auth.uid() IS NOT NULL AND NOT private.fiscal02_worker_company(s.tenant_id,s.company_id) THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='sandbox_requires_guarded_worker'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION private.fiscal02_guard_financial_write() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fiscal02_guard_financial_write BEFORE INSERT OR UPDATE OR DELETE ON public.finance_payments FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_financial_write();
CREATE TRIGGER fiscal02_guard_financial_write BEFORE INSERT OR UPDATE OR DELETE ON public.billing_credit_notes FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_financial_write();
CREATE TRIGGER fiscal02_guard_financial_write BEFORE INSERT OR UPDATE OR DELETE ON public.billing_payment_complements FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_financial_write();

CREATE FUNCTION private.fiscal02_guard_linked_child() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $guard$
DECLARE ids uuid[]:='{}'; s private.fiscal01_draft_scope;
BEGIN
 IF TG_OP<>'DELETE' THEN ids:=array_append(ids,(to_jsonb(NEW)->>TG_ARGV[0])::uuid); END IF;
 IF TG_OP<>'INSERT' THEN ids:=array_append(ids,(to_jsonb(OLD)->>TG_ARGV[0])::uuid); END IF;
 FOR s IN SELECT * FROM private.fiscal01_draft_scope WHERE cfdi_id=ANY(ids) LOOP
  IF auth.uid() IS NOT NULL AND NOT private.fiscal02_worker_company(s.tenant_id,s.company_id) THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='sandbox_requires_guarded_worker'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION private.fiscal02_guard_linked_child() FROM PUBLIC,anon,authenticated,service_role;
DO $linked_children$
DECLARE r record;
BEGIN
 FOR r IN SELECT DISTINCT n.nspname,c.relname,a.attname FROM pg_constraint f JOIN pg_class c ON c.oid=f.conrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=f.conkey[1]
  WHERE f.contype='f' AND f.confrelid='public.billing_cfdis'::regclass AND n.nspname='public' AND cardinality(f.conkey)=1 LOOP
  EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION private.fiscal02_guard_linked_child(%L)','fiscal02_guard_cfdi_link_'||md5(r.attname),r.nspname,r.relname,r.attname);
 END LOOP;
END $linked_children$;

CREATE VIEW private.fiscal02_readable_cfdis WITH(security_barrier=true) AS
 SELECT c.* FROM public.billing_cfdis c WHERE NOT private.fiscal02_is_lab_entity('cfdi',c.id)
 OR EXISTS(SELECT FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=c.id AND
  (private.fiscal01_authorized(s.tenant_id,s.company_id,'read')
   OR (pg_catalog.current_setting('fiscal02.cfdi',true)=c.id::text AND private.fiscal02_worker_company(s.tenant_id,s.company_id))));
CREATE VIEW private.fiscal02_legacy_finance_invoices WITH(security_barrier=true) AS SELECT i.* FROM public.finance_invoices i WHERE NOT private.fiscal02_is_lab_entity('invoice',i.id);
CREATE VIEW private.fiscal02_legacy_finance_payments WITH(security_barrier=true) AS SELECT p.* FROM public.finance_payments p WHERE NOT private.fiscal02_is_lab_entity('payment',p.id);
CREATE VIEW private.fiscal02_legacy_billing_documents WITH(security_barrier=true) AS SELECT b.* FROM public.billing_documents b WHERE NOT private.fiscal02_is_lab_entity('document',b.id);
CREATE VIEW private.fiscal02_legacy_billing_credit_notes WITH(security_barrier=true) AS SELECT c.* FROM public.billing_credit_notes c WHERE NOT private.fiscal02_is_lab_entity('credit',c.id);
CREATE VIEW private.fiscal02_legacy_billing_payment_complements WITH(security_barrier=true) AS SELECT c.* FROM public.billing_payment_complements c WHERE NOT private.fiscal02_is_lab_entity('complement',c.id);
REVOKE ALL ON private.fiscal02_readable_cfdis,private.fiscal02_legacy_finance_invoices,private.fiscal02_legacy_finance_payments,
 private.fiscal02_legacy_billing_documents,private.fiscal02_legacy_billing_credit_notes,private.fiscal02_legacy_billing_payment_complements FROM PUBLIC,anon,authenticated,service_role;

-- Preserve signatures, owners and ACL. Only FROM/JOIN is redirected: never
-- rewrite INSERT/UPDATE targets, row types or grant a new API. The views affect
-- explicitly scoped test rows only. Trusted new workers retain their raw source.
DO $legacy_readers$
DECLARE r record; definition text; next_definition text; rel text; target text;
BEGIN
 FOR r IN SELECT p.oid FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname IN ('public','private') AND p.prokind='f' AND pg_catalog.pg_get_userbyid(p.proowner)=current_user
   AND p.proname !~ '^(rpc_)?fiscal0[12]_' LOOP
  definition:=pg_catalog.pg_get_functiondef(r.oid);next_definition:=definition;
  FOREACH rel IN ARRAY ARRAY['billing_cfdis','finance_invoices','finance_payments','billing_documents','billing_credit_notes','billing_payment_complements'] LOOP
   target:=CASE WHEN rel='billing_cfdis' THEN 'fiscal02_readable_cfdis' ELSE 'fiscal02_legacy_'||rel END;
   next_definition:=pg_catalog.regexp_replace(next_definition,
    '(?i)(\mFROM|\mJOIN)[[:space:]]+(?:"?public"?[[:space:]]*[.][[:space:]]*)?"?'||rel||'"?(?=[[:space:];,)])',
    '\1 private.'||target,'g');
  END LOOP;
  IF next_definition<>definition THEN EXECUTE next_definition; END IF;
 END LOOP;
 IF pg_catalog.pg_get_functiondef('public.rpc_get_cfdi_detail(uuid)'::regprocedure) NOT LIKE '%fiscal02_readable_cfdis%' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_legacy_cfdi_reader'; END IF;
END $legacy_readers$;

-- Only the exact inspected, still-uncommitted MULTI-07 helper is compatible.
DO $multi_bridge$ DECLARE proc oid:=to_regprocedure('private.multi07_row_allowed(text,uuid)'); definition text; actor text:=current_user; temporary_create boolean;
BEGIN
 IF proc IS NOT NULL THEN
  IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(prosrc)=ANY(ARRAY['2544c3c684da3e436c9ed090c68c469d','7b40761fbb78bb90175e70e572be2de0']) AND prosecdef
   AND pg_get_userbyid(proowner)='rotero_finance_scope_owner') THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_multi07_lab_bridge'; END IF;
  GRANT EXECUTE ON FUNCTION private.fiscal02_is_lab_entity(text,uuid) TO rotero_finance_scope_owner;
  definition:=replace(pg_get_functiondef(proc),E'\r\n',E'\n');
  definition:=replace(definition,'SELECT EXISTS','SELECT NOT private.fiscal02_is_lab_entity(p_kind,p_id) AND EXISTS');
  IF definition NOT LIKE '%private.fiscal02_is_lab_entity(p_kind,p_id)%' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_multi07_lab_bridge'; END IF;
  temporary_create:=NOT has_schema_privilege('rotero_finance_scope_owner','private','CREATE');
  IF temporary_create THEN GRANT CREATE ON SCHEMA private TO rotero_finance_scope_owner; END IF;
  SET LOCAL ROLE rotero_finance_scope_owner;
  EXECUTE definition;
  EXECUTE format('SET LOCAL ROLE %I',actor);
  IF temporary_create THEN REVOKE CREATE ON SCHEMA private FROM rotero_finance_scope_owner; END IF;
 END IF;
END $multi_bridge$;

-- Only the exact inspected, still-uncommitted MULTI-07 helper is compatible.
DO $multi_bridge$ DECLARE proc oid:=to_regprocedure('private.multi07_legacy_visible(text,uuid,text)'); definition text; actor text:=current_user; temporary_create boolean;
BEGIN
 IF proc IS NOT NULL THEN
  IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(prosrc)=ANY(ARRAY['fc9dad0189c513000553b286cd6609f4','bf7fe07c5d363cea01ead4391769da41']) AND prosecdef
   AND pg_get_userbyid(proowner)='rotero_finance_scope_owner') THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_multi07_lab_bridge'; END IF;
  GRANT EXECUTE ON FUNCTION private.fiscal02_is_lab_entity(text,uuid) TO rotero_finance_scope_owner;
  definition:=replace(pg_get_functiondef(proc),E'\r\n',E'\n');
  definition:=replace(definition,E'BEGIN\n',E'BEGIN\n    IF private.fiscal02_is_lab_entity(p_kind,p_id) THEN RETURN false; END IF;\n');
  IF definition NOT LIKE '%private.fiscal02_is_lab_entity(p_kind,p_id)%' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_multi07_lab_bridge'; END IF;
  temporary_create:=NOT has_schema_privilege('rotero_finance_scope_owner','private','CREATE');
  IF temporary_create THEN GRANT CREATE ON SCHEMA private TO rotero_finance_scope_owner; END IF;
  SET LOCAL ROLE rotero_finance_scope_owner;
  EXECUTE definition;
  EXECUTE format('SET LOCAL ROLE %I',actor);
  IF temporary_create THEN REVOKE CREATE ON SCHEMA private FROM rotero_finance_scope_owner; END IF;
 END IF;
END $multi_bridge$;

CREATE OR REPLACE FUNCTION public.rpc_fiscal01_context(p_cfdi_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$ DECLARE d private.fiscal01_documents; c public.billing_cfdis; actions jsonb;
BEGIN
 SELECT * INTO d FROM private.fiscal01_documents WHERE cfdi_id=p_cfdi_id;
 IF d.cfdi_id IS NULL THEN SELECT s.cfdi_id,s.tenant_id,s.company_id INTO d.cfdi_id,d.tenant_id,d.company_id FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=p_cfdi_id; END IF;
 IF d.cfdi_id IS NULL OR NOT private.fiscal01_authorized(d.tenant_id,d.company_id,'read') THEN RETURN jsonb_build_object('available',false); END IF;
 SELECT * INTO c FROM public.billing_cfdis WHERE id=p_cfdi_id;
 SELECT jsonb_object_agg(a,private.fiscal01_authorized(d.tenant_id,d.company_id,a)) INTO actions FROM unnest(ARRAY['prepare','issue','read','cancel','payment']) a;
 RETURN jsonb_build_object('cfdi_id',c.id,'company_id',d.company_id,'company_name',(SELECT display_name FROM public.companies WHERE id=d.company_id AND tenant_id=d.tenant_id),
  'issuer_rfc','EKU9003173C9','environment','sandbox','status',c.fiscal_status,'uuid',c.uuid,'provider_document_id',d.provider_document_id,
  'document_type',CASE WHEN c.has_complemento_pago THEN 'payment' ELSE 'invoice' END,'payment_recorded',EXISTS(SELECT FROM private.fiscal01_receipts WHERE cfdi_id=c.id),
  'remote_cancel_status',d.remote_cancel_status,'cancellation_ack_state',d.cancellation_ack_state,
  'uncertain',d.uncertain,'xml_available',d.xml_path IS NOT NULL,'cancellation_available',d.cancellation_path IS NOT NULL,'busy',d.busy_token IS NOT NULL,'actions',actions,
  'draft_summary',jsonb_build_object('receiver_rfc',c.rfc_receptor,'subtotal',c.subtotal,'total',c.total,'currency',c.currency,'serie',c.serie,'folio',c.folio));
END $$;

CREATE OR REPLACE FUNCTION public.rpc_fiscal01_worker(p_cfdi_id uuid,p_actor uuid,p_action text,p_data jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE d private.fiscal01_documents; c public.billing_cfdis; r public.fiscal_requests; tok uuid; cap text; hash text; info jsonb; request_kind text;
BEGIN
 IF p_actor IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 -- Fiscal task grants do not use a financial principal binding. Do not invent
 -- an issuer claim; this worker never checks/grants financial.full.read.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fiscal01:'||p_cfdi_id::text,0));
 SELECT * INTO c FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
 SELECT * INTO d FROM private.fiscal01_documents WHERE cfdi_id=p_cfdi_id FOR UPDATE;
 cap:=CASE WHEN p_action='prepare' THEN 'prepare' WHEN p_action IN ('cancel','cancelled','cancel_confirmed','cancel_ack_invalid') THEN 'cancel' WHEN p_action IN ('load','source','status','xml','ack') THEN 'read'
  WHEN p_action IN ('identified','verified','uncertain','release','cancel_observed') AND d.busy_action='status' THEN 'read'
  WHEN p_action IN ('uncertain','release') AND d.busy_action='cancel' THEN 'cancel' ELSE 'issue' END;
 PERFORM private.fiscal02_set_worker(p_cfdi_id,p_actor,CASE WHEN p_action='source' THEN 'prepare' ELSE cap END);
 IF p_action='source' THEN
  SELECT s.cfdi_id,s.tenant_id,s.company_id INTO d.cfdi_id,d.tenant_id,d.company_id FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=p_cfdi_id;
  IF d.cfdi_id IS NULL OR NOT private.fiscal01_authorized(d.tenant_id,d.company_id,'prepare') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
  RETURN jsonb_build_object('company_id',d.company_id,'fiscal_input',c.fiscal_input,'serie',c.serie,'folio',c.folio,'subtotal',c.subtotal,'total',c.total,'currency',c.currency);
 END IF;
 IF p_action='prepare' AND d.cfdi_id IS NULL THEN
  IF c.id IS NULL OR c.fiscal_status<>'draft' OR c.uuid IS NOT NULL OR to_jsonb(c)->>'operation_id' IS NOT NULL
    OR EXISTS(SELECT FROM public.billing_documents b WHERE b.linked_cfdi_id=c.id AND b.operation_id IS NOT NULL)
    OR NOT EXISTS(SELECT FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=c.id AND s.tenant_id=c.tenant_id AND s.company_id=(p_data->>'company_id')::uuid)
    OR NOT private.fiscal01_authorized(c.tenant_id,(p_data->>'company_id')::uuid,'prepare') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
  hash:=encode(extensions.digest(convert_to((p_data->'payload')::text,'UTF8'),'sha256'),'hex');
  -- Issuer cannot be selected by free text. Adapter also validates every scalar.
  IF p_data#>>'{payload,Issuer,Rfc}' IS DISTINCT FROM 'EKU9003173C9' OR c.rfc_emisor<>'EKU9003173C9' OR c.rfc_receptor<>'URE180429TM6'
    OR p_data#>>'{payload,Receiver,Rfc}' IS DISTINCT FROM c.rfc_receptor OR p_data#>>'{payload,CfdiType}' NOT IN ('I','P')
    OR ((p_data#>>'{payload,CfdiType}'='P') IS DISTINCT FROM c.has_complemento_pago)
    OR (c.has_complemento_pago AND (c.total<>0 OR c.subtotal<>0 OR NOT EXISTS(SELECT FROM private.fiscal01_receipts WHERE cfdi_id=c.id)))
    THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_test_document'; END IF;
  INSERT INTO private.fiscal01_documents(cfdi_id,tenant_id,company_id,provider_payload,payload_sha256) VALUES(c.id,c.tenant_id,(p_data->>'company_id')::uuid,p_data->'payload',hash);
  UPDATE public.billing_cfdis SET fiscal_status='ready_for_api',fiscal_provider='facturama',fiscal_snapshot=jsonb_build_object('schema','rotero.fiscal-input','billing_cfdi_id',c.id,'company_id',p_data->>'company_id'),request_fingerprint=hash WHERE id=c.id;
  PERFORM public.rpc_write_audit(c.tenant_id,'facturama_sandbox_prepared','billing_cfdi',c.id,jsonb_build_object('payload_sha256',hash));
  RETURN jsonb_build_object('prepared',true,'payload_sha256',hash);
 END IF;
 IF d.cfdi_id IS NULL OR c.tenant_id IS DISTINCT FROM d.tenant_id OR NOT private.fiscal01_authorized(d.tenant_id,d.company_id,cap) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 IF p_action='prepare' THEN RETURN jsonb_build_object('prepared',true,'payload_sha256',d.payload_sha256); END IF;
 IF p_action='load' THEN RETURN to_jsonb(d)||jsonb_build_object('fiscal_uuid',c.uuid,'fiscal_status',c.fiscal_status); END IF;
 IF p_action IN ('claim','status','cancel') THEN
  IF d.busy_token IS NOT NULL AND NOT(p_action='status' AND d.busy_since<now()-interval '2 minutes') THEN RETURN jsonb_build_object('busy',true,'uncertain',d.uncertain); END IF;
  IF p_action='cancel' AND c.fiscal_status='cancellation_requested' THEN
   IF p_data->>'recover_ack' IS DISTINCT FROM 'true' THEN RETURN jsonb_build_object('cancellation_pending',true); END IF;
   -- Explicit recovery reuses the original cancellation parameters. Server must
   -- confirm cancellation by GET before retrieving another cancellation response.
   SELECT payload_snapshot->'cancellation' INTO info FROM public.fiscal_requests
    WHERE billing_cfdi_id=c.id AND request_type='cancel' ORDER BY created_at,id LIMIT 1;
   IF info->>'motive' NOT IN ('01','02','03','04') OR info IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='missing_original_cancellation'; END IF;
   p_data:=info||jsonb_build_object('recover_ack',true);
  END IF;
  IF p_action='claim' AND (d.uncertain OR d.provider_document_id IS NOT NULL OR c.fiscal_status NOT IN ('ready_for_api','queued')) THEN
   RETURN jsonb_build_object('reconcile_required',true,'provider_document_id',d.provider_document_id);
  END IF;
  IF c.request_fingerprint IS DISTINCT FROM d.payload_sha256 OR c.fiscal_provider IS DISTINCT FROM 'facturama' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='frozen_fiscal_source_conflict'; END IF;
  tok:=gen_random_uuid();
  IF p_action='claim' THEN
   INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,requested_by,max_attempts)
    VALUES(d.tenant_id,d.cfdi_id,'stamp',d.payload_sha256,jsonb_build_object('schema','rotero.fiscal-input','billing_cfdi_id',d.cfdi_id,'company_id',d.company_id),p_actor,1)
    ON CONFLICT(tenant_id,billing_cfdi_id,request_type,idempotency_key) DO NOTHING;
   UPDATE public.billing_cfdis SET fiscal_status='queued' WHERE id=c.id AND fiscal_status='ready_for_api';
   UPDATE public.billing_cfdis SET fiscal_status='submitting' WHERE id=c.id AND fiscal_status='queued';
  ELSIF p_action='cancel' THEN
   IF c.fiscal_status NOT IN ('stamped','cancellation_requested') OR d.provider_document_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_cancellation'; END IF;
   UPDATE public.billing_cfdis SET fiscal_status='cancellation_requested' WHERE id=c.id AND fiscal_status='stamped';
   UPDATE private.fiscal01_documents SET remote_cancel_status=COALESCE(remote_cancel_status,'pending') WHERE cfdi_id=c.id;
  END IF;
  IF p_action='claim' THEN
   SELECT * INTO r FROM public.fiscal_requests WHERE billing_cfdi_id=c.id AND request_type='stamp' AND idempotency_key=d.payload_sha256;
  ELSE
   request_kind:=CASE WHEN p_action='cancel' THEN 'cancel' ELSE 'status' END;
   SELECT * INTO r FROM public.fiscal_requests WHERE billing_cfdi_id=c.id AND request_type=request_kind
    AND status IN ('queued','submitting','processing') ORDER BY created_at,id LIMIT 1 FOR UPDATE;
   IF NOT FOUND THEN
   hash:=encode(extensions.digest(convert_to(request_kind||':'||gen_random_uuid()::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,requested_by,max_attempts)
    VALUES(d.tenant_id,c.id,request_kind,hash,jsonb_build_object('schema','rotero.fiscal-input','billing_cfdi_id',c.id,'company_id',d.company_id,'cancellation',CASE WHEN p_action='cancel' THEN p_data ELSE NULL END),p_actor,1) RETURNING * INTO r;
   END IF;
  END IF;
  UPDATE private.fiscal01_documents SET busy_token=tok,busy_since=now(),busy_actor=p_actor,busy_action=p_action,active_request_id=r.id,uncertain=CASE WHEN p_action='claim' THEN true ELSE uncertain END WHERE cfdi_id=c.id;
  UPDATE public.fiscal_requests SET status='submitting',locked_at=now() WHERE id=r.id AND status IN ('queued','processing');
  RETURN to_jsonb(d)||jsonb_build_object('busy_token',tok,'active_request_id',r.id,'cancellation_options',CASE WHEN p_action='cancel' THEN p_data ELSE NULL END,'fiscal_uuid',c.uuid,'fiscal_status',c.fiscal_status);
 END IF;
 IF p_action IN ('xml','ack') THEN RETURN jsonb_build_object('path',CASE WHEN p_action='xml' THEN d.xml_path ELSE d.cancellation_path END); END IF;
 -- A unique lease is required to persist any result. Never trust browser status.
 IF d.busy_token IS NULL OR d.busy_actor IS DISTINCT FROM p_actor OR d.busy_token IS DISTINCT FROM (p_data->>'busy_token')::uuid THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='stale_fiscal_lease'; END IF;
 IF p_action='identified' THEN
  UPDATE private.fiscal01_documents SET provider_document_id=p_data->>'provider_document_id' WHERE cfdi_id=c.id;
  UPDATE public.billing_cfdis SET provider_document_id=p_data->>'provider_document_id' WHERE id=c.id;
  RETURN jsonb_build_object('saved',true);
 ELSIF p_action='verified' THEN
  IF p_data->>'provider_document_id' IS DISTINCT FROM d.provider_document_id OR p_data->>'xml_path' IS DISTINCT FROM d.tenant_id::text||'/'||d.company_id::text||'/'||d.cfdi_id::text||'/invoice.xml' OR p_data->>'xml_sha256' !~ '^[0-9a-f]{64}$' OR p_data->>'uuid' !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_verified_result'; END IF;
  SELECT * INTO r FROM public.fiscal_requests WHERE id=d.active_request_id;
   info:=private.fiscal0_apply_provider_result(r.id,jsonb_build_object('outcome','stamped','provider_code','facturama','provider_document_id',d.provider_document_id,'fiscal_uuid',p_data->>'uuid','http_status',200));
   IF info ? 'error' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_result_failed'; END IF;
  UPDATE public.billing_cfdis SET fiscal_stamped_at=(p_data->>'stamped_at')::timestamp AT TIME ZONE 'America/Mexico_City' WHERE id=c.id;
  UPDATE private.fiscal01_documents SET uncertain=false,busy_token=NULL,busy_since=NULL,xml_path=p_data->>'xml_path',xml_sha256=p_data->>'xml_sha256' WHERE cfdi_id=c.id;
  UPDATE public.billing_payment_complements b SET status='issued'
   WHERE b.tenant_id=d.tenant_id AND b.finance_payment_id IN
    (SELECT a.finance_payment_id FROM private.fiscal01_applications a JOIN private.fiscal01_receipts h ON h.id=a.receipt_id
     WHERE h.cfdi_id=c.id AND h.tenant_id=d.tenant_id AND h.company_id=d.company_id);
 ELSIF p_action='cancel_confirmed' THEN
  IF d.busy_action<>'cancel' OR p_data->>'uuid' IS DISTINCT FROM c.uuid OR p_data->>'provider_document_id' IS DISTINCT FROM d.provider_document_id THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='uncorrelated_cancellation_confirmation'; END IF;
  UPDATE private.fiscal01_documents SET remote_cancel_status='canceled',cancellation_ack_state='unverified',uncertain=false WHERE cfdi_id=c.id;
 ELSIF p_action='cancel_ack_invalid' THEN
  IF d.busy_action<>'cancel' OR d.remote_cancel_status IS DISTINCT FROM 'canceled' OR p_data->>'ack_sha256' !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_acknowledgement_evidence'; END IF;
  UPDATE private.fiscal01_documents SET cancellation_ack_state='mismatch',cancellation_ack_sha256=p_data->>'ack_sha256' WHERE cfdi_id=c.id;
 ELSIF p_action='cancelled' THEN
  IF p_data->>'uuid' IS DISTINCT FROM c.uuid OR p_data->>'ack_path' IS DISTINCT FROM d.tenant_id::text||'/'||d.company_id::text||'/'||d.cfdi_id::text||'/cancellation.xml' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_cancellation_evidence'; END IF;
  info:=private.fiscal0_apply_provider_result(d.active_request_id,jsonb_build_object('outcome','cancelled','provider_code','facturama','http_status',200));
  IF info?'error' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_result_failed'; END IF;
  UPDATE private.fiscal01_documents SET cancellation_path=p_data->>'ack_path',remote_cancel_status='canceled',cancellation_ack_state='validated',cancellation_ack_sha256=p_data->>'ack_sha256',busy_token=NULL,busy_since=NULL WHERE cfdi_id=c.id;
 ELSIF p_action='rejected' THEN
  IF d.provider_document_id IS NOT NULL OR d.busy_action<>'claim' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='cannot_reject_identified_document'; END IF;
  SELECT * INTO r FROM public.fiscal_requests WHERE id=d.active_request_id;
  info:=private.fiscal0_apply_provider_result(r.id,jsonb_build_object('outcome','business_rejection','provider_code','facturama','http_status',400));
  IF info?'error' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_result_failed'; END IF;
  UPDATE private.fiscal01_documents SET busy_token=NULL,busy_since=NULL,uncertain=false WHERE cfdi_id=c.id;
 ELSIF p_action IN ('uncertain','release','cancel_observed') THEN
  SELECT * INTO r FROM public.fiscal_requests WHERE id=d.active_request_id;
  INSERT INTO public.fiscal_provider_attempts(tenant_id,request_id,attempt_no,started_at,completed_at,provider_code,normalized_result,safe_error_code,http_status)
   VALUES(d.tenant_id,r.id,r.attempt_count+1,COALESCE(d.busy_since,now()),now(),'facturama',jsonb_build_object('outcome','processing'),'status_conflict',
    CASE WHEN p_data->>'http_status' ~ '^[1-5][0-9][0-9]$' THEN (p_data->>'http_status')::integer ELSE NULL END);
  UPDATE private.fiscal01_documents SET busy_token=NULL,busy_since=NULL,uncertain=CASE WHEN p_action='uncertain' THEN true ELSE uncertain END WHERE cfdi_id=c.id;
  UPDATE public.fiscal_requests SET status='processing',attempt_count=attempt_count+1,safe_error_code='status_conflict',next_attempt_at=NULL WHERE id=r.id AND status='submitting';
  UPDATE public.billing_cfdis SET fiscal_status='processing' WHERE id=c.id AND fiscal_status='submitting';
  IF p_action='cancel_observed' THEN
   UPDATE public.billing_cfdis SET fiscal_status='cancellation_requested' WHERE id=c.id AND fiscal_status='stamped';
   UPDATE private.fiscal01_documents SET remote_cancel_status='canceled' WHERE cfdi_id=c.id;
  END IF;
 ELSE RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='unknown_worker_action'; END IF;
 PERFORM public.rpc_write_audit(c.tenant_id,'facturama_sandbox_'||p_action,'billing_cfdi',c.id,jsonb_build_object('provider_document_id',d.provider_document_id));
 RETURN jsonb_build_object('saved',true);
END $$;

CREATE OR REPLACE FUNCTION public.rpc_fiscal01_record_payment(p_cfdi_id uuid,p_actor uuid,p_paid_at timestamp,p_applications jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE s private.fiscal01_draft_scope; c public.billing_cfdis; f public.finance_invoices;
 link private.fiscal01_invoice_links; source public.billing_cfdis; receipt uuid; payment uuid; item jsonb; docs jsonb:='[]';
 amount numeric; prior numeric; remainder numeric; part integer; base numeric; sum_paid numeric:=0; payload jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 PERFORM private.fiscal02_set_worker(p_cfdi_id,p_actor,'payment');
 SELECT * INTO s FROM private.fiscal01_draft_scope WHERE cfdi_id=p_cfdi_id;
 IF s.cfdi_id IS NULL OR p_actor IS NULL OR NOT private.fiscal01_authorized(s.tenant_id,s.company_id,'payment') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 -- Serialize only this synthetic company. Legacy accounting is not activated.
 PERFORM pg_advisory_xact_lock(hashtextextended('fiscal01-payments:'||s.company_id::text,0));
 SELECT * INTO c FROM public.billing_cfdis WHERE id=s.cfdi_id FOR UPDATE;
 IF EXISTS(SELECT FROM private.fiscal01_receipts WHERE cfdi_id=c.id) THEN RETURN jsonb_build_object('already_recorded',true); END IF;
 IF c.tenant_id<>s.tenant_id OR c.fiscal_status<>'draft' OR c.uuid IS NOT NULL OR to_jsonb(c)->>'operation_id' IS NOT NULL
   OR EXISTS(SELECT FROM public.billing_documents b WHERE b.linked_cfdi_id=c.id AND b.operation_id IS NOT NULL)
   OR p_paid_at IS NULL OR NOT c.has_complemento_pago OR c.total<>0 OR c.subtotal<>0
   OR p_paid_at>(now() AT TIME ZONE 'America/Mexico_City')+interval '1 minute'
   OR jsonb_typeof(p_applications) IS DISTINCT FROM 'array' OR jsonb_array_length(p_applications) NOT BETWEEN 1 AND 25 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_payment'; END IF;
 -- Reserve a receipt first; the whole transaction rolls back on any mismatch.
 receipt:=gen_random_uuid();
 INSERT INTO private.fiscal01_receipts(id,tenant_id,company_id,cfdi_id,amount,paid_at,method,administrative_reference)
 VALUES(receipt,s.tenant_id,s.company_id,c.id,0.01,p_paid_at,'03','QA-RECEIPT-'||receipt::text);
 FOR item IN SELECT value FROM jsonb_array_elements(p_applications) ORDER BY value->>'invoice_id' LOOP
  IF item->>'amount' !~ '^\d{1,12}(\.\d{1,2})?$' OR (item->>'amount')::numeric<=0 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_payment_amount'; END IF;
  amount:=(item->>'amount')::numeric;
  SELECT * INTO link FROM private.fiscal01_invoice_links WHERE finance_invoice_id=(item->>'invoice_id')::uuid AND tenant_id=s.tenant_id AND company_id=s.company_id;
  SELECT * INTO f FROM public.finance_invoices WHERE id=link.finance_invoice_id FOR UPDATE;
  SELECT * INTO source FROM public.billing_cfdis WHERE id=link.cfdi_id;
  IF link.cfdi_id IS NULL OR f.tenant_id<>s.tenant_id OR f.linked_cfdi_id IS DISTINCT FROM source.id OR f.direction<>'ar' OR f.currency<>'MXN' OR f.amount<>source.total
    OR f.status IN ('draft','void') OR f.operation_id IS NOT NULL OR f.payroll_period_id IS NOT NULL
    OR source.fiscal_status<>'stamped' OR source.uuid IS NULL OR source.fiscal_input#>>'{payment,method}' IS DISTINCT FROM 'PPD'
    OR EXISTS(SELECT FROM public.billing_credit_notes n WHERE n.finance_invoice_id=f.id)
    OR EXISTS(SELECT FROM public.finance_payments p WHERE p.invoice_id=f.id AND NOT EXISTS(SELECT FROM private.fiscal01_applications a WHERE a.finance_payment_id=p.id))
    THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unclassified_or_incompatible_invoice'; END IF;
  SELECT source.total-COALESCE(sum(a.paid),0),COALESCE(max(a.partiality),0)+1 INTO prior,part FROM private.fiscal01_applications a WHERE a.invoice_cfdi_id=source.id;
  remainder:=prior-amount;
  IF remainder<0 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='payment_exceeds_balance'; END IF;
  INSERT INTO public.finance_payments(tenant_id,invoice_id,amount,paid_at,method,currency,created_by,note)
   VALUES(s.tenant_id,f.id,amount,p_paid_at AT TIME ZONE 'America/Mexico_City','transfer','MXN',p_actor,'FACTURAMA-01 synthetic sandbox application') RETURNING id INTO payment;
  -- Preserve F4's existing settlement rule, without changing accounting policy.
  IF remainder=0 THEN UPDATE public.finance_invoices SET status='paid',paid_at=p_paid_at AT TIME ZONE 'America/Mexico_City' WHERE id=f.id; END IF;
  PERFORM public.rpc_write_audit(s.tenant_id,'finance_payment_recorded','finance_payment',payment,
   jsonb_build_object('invoice_id',f.id,'amount',amount,'currency','MXN','remaining_balance',remainder,'sandbox_receipt_id',receipt));
  INSERT INTO private.fiscal01_applications(tenant_id,company_id,receipt_id,invoice_cfdi_id,finance_invoice_id,finance_payment_id,previous_balance,paid,remaining,partiality)
   VALUES(s.tenant_id,s.company_id,receipt,source.id,f.id,payment,prior,amount,remainder,part);
  INSERT INTO public.billing_payment_complements(tenant_id,finance_invoice_id,finance_payment_id,cfdi_id,payment_date,method,currency,amount,created_by,notes)
   VALUES(s.tenant_id,f.id,payment,source.id,p_paid_at AT TIME ZONE 'America/Mexico_City','transfer','MXN',amount,p_actor,'FACTURAMA-01 sandbox REP; header is the explicit receipt');
  base:=round(amount/1.16,2);
  docs:=docs||jsonb_build_array(jsonb_build_object('Uuid',source.uuid,'Serie',source.serie,'Folio',source.folio,'Currency','MXN','PartialityNumber',part,
   'PreviousBalanceAmount',prior,'AmountPaid',amount,'ImpSaldoInsoluto',remainder,'TaxObject','02',
   'Taxes',jsonb_build_array(jsonb_build_object('Name','IVA','Base',base,'Rate',0.16,'Total',amount-base,'IsRetention',false))));
  sum_paid:=sum_paid+amount;
 END LOOP;
 UPDATE private.fiscal01_receipts SET amount=sum_paid WHERE id=receipt;
 payload:=jsonb_build_object('NameId','14','CfdiType','P','Serie',c.serie,'Folio',c.folio,'Date',to_char(now() AT TIME ZONE 'America/Mexico_City','YYYY-MM-DD"T"HH24:MI:SS'),'ExpeditionPlace','42501','Exportation','01',
  'Issuer',jsonb_build_object('Rfc','EKU9003173C9','Name','ESCUELA KEMPER URGATE','FiscalRegime','601'),
  'Receiver',jsonb_build_object('Rfc','URE180429TM6','Name','UNIVERSIDAD ROBOTICA ESPAÑOLA','FiscalRegime','601','TaxZipCode','86991','CfdiUse','CP01'),
  'Complemento',jsonb_build_object('Payments',jsonb_build_array(jsonb_build_object('Date',to_char(p_paid_at,'YYYY-MM-DD"T"HH24:MI:SS'),'PaymentForm','03','Currency','MXN','Amount',sum_paid,'RelatedDocuments',docs))));
 UPDATE public.billing_cfdis SET fiscal_input=jsonb_build_object('payment_payload',payload) WHERE id=c.id;
 PERFORM public.rpc_write_audit(s.tenant_id,'facturama_sandbox_payment_recorded','billing_cfdi',c.id,jsonb_build_object('receipt_id',receipt,'application_count',jsonb_array_length(docs)));
 RETURN jsonb_build_object('recorded',true,'receipt_id',receipt,'application_count',jsonb_array_length(docs));
END $$;
-- Replacement retains the existing API ACL/owner; private helpers remain closed.
COMMIT;
