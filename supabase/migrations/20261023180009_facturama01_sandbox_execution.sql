-- FACTURAMA-01: sandbox extension of FISCAL.0, never a second fiscal aggregate.
-- Depends only on the reviewed MULTI-04/05 commits. No seeds or real grants.
BEGIN;
SELECT set_config('fiscal01.migration_role',current_user,true);
SET LOCAL ROLE rotero_company_access_owner;
ALTER TABLE public.membership_company_capabilities DROP CONSTRAINT membership_company_capabilities_capability_code_check;
ALTER TABLE public.membership_company_capabilities ADD CONSTRAINT membership_company_capabilities_capability_code_check CHECK (capability_code IN (
 'operations.read','operations.capture','billing.draft','billing.document.read','receivables.read',
 'export.operational','export.receivables','companies.manage','memberships.manage','company_access.manage',
 'financial.full.read','export.financial','fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment'
));
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('fiscal01.migration_role')); END $$;
DO $references$
DECLARE actor text:=current_user; cols text;
BEGIN
 SELECT string_agg(quote_ident(c),',') INTO cols FROM unnest(ARRAY['tenant_id','id']) c
 WHERE NOT has_column_privilege(actor,'public.companies',c,'REFERENCES');
 PERFORM set_config('fiscal01.references',COALESCE(cols,''),true);
 IF cols IS NOT NULL THEN
  EXECUTE 'SET LOCAL ROLE rotero_company_access_owner';
  EXECUTE format('GRANT REFERENCES (%s) ON public.companies TO %I',cols,actor);
  EXECUTE format('SET LOCAL ROLE %I',actor);
 END IF;
END $references$;
CREATE TABLE private.fiscal01_company_bindings (
 tenant_id uuid NOT NULL, company_id uuid NOT NULL, environment text NOT NULL DEFAULT 'sandbox' CHECK(environment='sandbox'),
 issuer_rfc text NOT NULL CHECK(issuer_rfc='EKU9003173C9'), enabled boolean NOT NULL DEFAULT false,
 approval_reference text NOT NULL CHECK(length(approval_reference)>0),
 PRIMARY KEY(tenant_id,company_id), FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id)
);
CREATE TABLE private.fiscal01_lab_actors (
 tenant_id uuid NOT NULL, user_id uuid NOT NULL, expires_at timestamptz NOT NULL,
 approval_reference text NOT NULL CHECK(length(approval_reference)>0), PRIMARY KEY(tenant_id,user_id),
 FOREIGN KEY(user_id,tenant_id) REFERENCES public.memberships(user_id,tenant_id)
);
CREATE TABLE private.fiscal01_documents (
 cfdi_id uuid PRIMARY KEY REFERENCES public.billing_cfdis(id), tenant_id uuid NOT NULL, company_id uuid NOT NULL,
 provider_payload jsonb NOT NULL CHECK(jsonb_typeof(provider_payload)='object'), payload_sha256 text NOT NULL CHECK(payload_sha256~'^[0-9a-f]{64}$'),
 provider_document_id text, xml_path text, xml_sha256 text CHECK(xml_sha256 IS NULL OR xml_sha256~'^[0-9a-f]{64}$'),
 uncertain boolean NOT NULL DEFAULT false, busy_token uuid, busy_since timestamptz, busy_actor uuid, busy_action text, cancellation_path text,
 active_request_id uuid REFERENCES public.fiscal_requests(id), remote_cancel_status text CHECK(remote_cancel_status IN ('pending','canceled')),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id,company_id,cfdi_id),
 UNIQUE(provider_document_id),
 FOREIGN KEY(tenant_id,company_id) REFERENCES private.fiscal01_company_bindings(tenant_id,company_id),
 CHECK((xml_path IS NULL)=(xml_sha256 IS NULL)),
 CHECK((provider_payload#>>'{Issuer,Rfc}') IS NOT DISTINCT FROM 'EKU9003173C9')
);
CREATE TABLE private.fiscal01_draft_scope (
 cfdi_id uuid PRIMARY KEY REFERENCES public.billing_cfdis(id),tenant_id uuid NOT NULL,company_id uuid NOT NULL,
 approval_reference text NOT NULL CHECK(length(approval_reference)>0),
 UNIQUE(tenant_id,company_id,cfdi_id),
 FOREIGN KEY(tenant_id,company_id) REFERENCES private.fiscal01_company_bindings(tenant_id,company_id)
);
ALTER TABLE private.fiscal01_documents ADD CONSTRAINT fiscal01_document_explicit_scope
 FOREIGN KEY(tenant_id,company_id,cfdi_id) REFERENCES private.fiscal01_draft_scope(tenant_id,company_id,cfdi_id);
CREATE TABLE private.fiscal01_invoice_links (
 finance_invoice_id uuid PRIMARY KEY REFERENCES public.finance_invoices(id),tenant_id uuid NOT NULL,company_id uuid NOT NULL,cfdi_id uuid NOT NULL UNIQUE,
 FOREIGN KEY(tenant_id,company_id,cfdi_id) REFERENCES private.fiscal01_documents(tenant_id,company_id,cfdi_id),
 UNIQUE(tenant_id,company_id,finance_invoice_id,cfdi_id)
);
ALTER TABLE public.finance_invoices ADD CONSTRAINT fiscal01_invoice_scope_parent UNIQUE(tenant_id,id,linked_cfdi_id);
ALTER TABLE private.fiscal01_invoice_links ADD CONSTRAINT fiscal01_invoice_exact_parent FOREIGN KEY(tenant_id,finance_invoice_id,cfdi_id) REFERENCES public.finance_invoices(tenant_id,id,linked_cfdi_id);
ALTER TABLE public.finance_payments ADD CONSTRAINT fiscal01_payment_scope_parent UNIQUE(tenant_id,invoice_id,id);
CREATE UNIQUE INDEX fiscal01_immutable_identity ON private.fiscal01_documents((provider_payload#>>'{Issuer,Rfc}'),(provider_payload->>'Serie'),(provider_payload->>'Folio'),(provider_payload->>'Date'));
CREATE TABLE private.fiscal01_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, company_id uuid NOT NULL, cfdi_id uuid NOT NULL UNIQUE,
 amount numeric(14,2) NOT NULL CHECK(amount>0), currency text NOT NULL DEFAULT 'MXN' CHECK(currency='MXN'),
 paid_at timestamp NOT NULL, method text NOT NULL CHECK(method='03'), administrative_reference text NOT NULL,
 UNIQUE(tenant_id,company_id,id), FOREIGN KEY(tenant_id,company_id,cfdi_id) REFERENCES private.fiscal01_draft_scope(tenant_id,company_id,cfdi_id)
);
CREATE TABLE private.fiscal01_applications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, company_id uuid NOT NULL, receipt_id uuid NOT NULL,
 invoice_cfdi_id uuid NOT NULL, finance_invoice_id uuid NOT NULL REFERENCES public.finance_invoices(id), finance_payment_id uuid NOT NULL UNIQUE REFERENCES public.finance_payments(id),
 previous_balance numeric(14,2) NOT NULL CHECK(previous_balance>0), paid numeric(14,2) NOT NULL CHECK(paid>0),
 remaining numeric(14,2) NOT NULL CHECK(remaining>=0), partiality integer NOT NULL CHECK(partiality>0),
 CHECK(previous_balance-paid=remaining), UNIQUE(receipt_id,invoice_cfdi_id), UNIQUE(invoice_cfdi_id,partiality),
 FOREIGN KEY(tenant_id,company_id,receipt_id) REFERENCES private.fiscal01_receipts(tenant_id,company_id,id),
 FOREIGN KEY(tenant_id,company_id,invoice_cfdi_id) REFERENCES private.fiscal01_documents(tenant_id,company_id,cfdi_id),
 FOREIGN KEY(tenant_id,company_id,finance_invoice_id,invoice_cfdi_id) REFERENCES private.fiscal01_invoice_links(tenant_id,company_id,finance_invoice_id,cfdi_id),
 FOREIGN KEY(tenant_id,finance_invoice_id,finance_payment_id) REFERENCES public.finance_payments(tenant_id,invoice_id,id)
);
CREATE INDEX fiscal01_applications_scope ON private.fiscal01_applications(tenant_id,company_id,invoice_cfdi_id);
DO $close$
DECLARE name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['fiscal01_company_bindings','fiscal01_lab_actors','fiscal01_documents','fiscal01_draft_scope','fiscal01_invoice_links','fiscal01_receipts','fiscal01_applications'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role',name);
 END LOOP;
END $close$;

CREATE FUNCTION private.fiscal01_authorized(p_tenant uuid,p_company uuid,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT p_action IN ('prepare','issue','read','cancel','payment')
 AND EXISTS(SELECT FROM private.fiscal01_lab_actors a WHERE a.tenant_id=p_tenant AND a.user_id=(SELECT auth.uid()) AND a.expires_at>now())
 AND EXISTS(SELECT FROM private.fiscal01_company_bindings b WHERE b.tenant_id=p_tenant AND b.company_id=p_company AND b.enabled AND b.environment='sandbox')
 AND private.multi05_has_company_capability(p_tenant,p_company,'fiscal.'||p_action) $$;
REVOKE ALL ON FUNCTION private.fiscal01_authorized(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.fiscal01_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=''
AS $$ BEGIN
 IF TG_TABLE_NAME='fiscal01_documents' THEN
  IF TG_OP='UPDATE' AND ROW(NEW.cfdi_id,NEW.tenant_id,NEW.company_id,NEW.provider_payload,NEW.payload_sha256) IS DISTINCT FROM ROW(OLD.cfdi_id,OLD.tenant_id,OLD.company_id,OLD.provider_payload,OLD.payload_sha256) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='frozen_fiscal_payload';
  END IF;
 END IF;
 IF NOT EXISTS(SELECT FROM public.billing_cfdis c WHERE c.id=NEW.cfdi_id AND c.tenant_id=NEW.tenant_id AND c.rfc_emisor='EKU9003173C9' AND c.rfc_receptor='URE180429TM6' AND c.operation_id IS NULL) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='sandbox_fixture_required';
 END IF;
 RETURN NEW; END $$;
CREATE TRIGGER fiscal01_documents_guard BEFORE INSERT OR UPDATE ON private.fiscal01_documents FOR EACH ROW EXECUTE FUNCTION private.fiscal01_guard();
CREATE TRIGGER fiscal01_draft_scope_guard BEFORE INSERT OR UPDATE ON private.fiscal01_draft_scope FOR EACH ROW EXECUTE FUNCTION private.fiscal01_guard();

-- Legacy draft editors must not change a document underneath a frozen sandbox
-- request. This guard is a no-op for every document outside this closed scope.
CREATE FUNCTION private.fiscal01_guard_canonical() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d private.fiscal01_documents;
BEGIN
 SELECT * INTO d FROM private.fiscal01_documents WHERE cfdi_id=OLD.id;
 IF d.cfdi_id IS NULL THEN RETURN NEW; END IF;
 IF ROW(NEW.id,NEW.tenant_id,NEW.operation_id,NEW.rfc_emisor,NEW.rfc_receptor,NEW.receptor_name,NEW.serie,NEW.folio,NEW.subtotal,NEW.total,NEW.currency,NEW.fiscal_input,NEW.has_complemento_pago)
 IS DISTINCT FROM ROW(OLD.id,OLD.tenant_id,OLD.operation_id,OLD.rfc_emisor,OLD.rfc_receptor,OLD.receptor_name,OLD.serie,OLD.folio,OLD.subtotal,OLD.total,OLD.currency,OLD.fiscal_input,OLD.has_complemento_pago) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='frozen_canonical_fiscal_source';
 END IF;
 IF OLD.request_fingerprint IS NOT NULL AND ROW(NEW.request_fingerprint,NEW.fiscal_snapshot,NEW.fiscal_provider) IS DISTINCT FROM ROW(OLD.request_fingerprint,OLD.fiscal_snapshot,OLD.fiscal_provider) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='frozen_canonical_fiscal_source';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.fiscal01_guard_canonical() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER fiscal01_guard_canonical BEFORE UPDATE ON public.billing_cfdis FOR EACH ROW EXECUTE FUNCTION private.fiscal01_guard_canonical();

-- API only gets a minimal task DTO. No raw provider bodies or shared Storage URL.
CREATE FUNCTION public.rpc_fiscal01_context(p_cfdi_id uuid) RETURNS jsonb
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
  'uncertain',d.uncertain,'xml_available',d.xml_path IS NOT NULL,'cancellation_available',d.cancellation_path IS NOT NULL,'busy',d.busy_token IS NOT NULL,'actions',actions,
  'draft_summary',jsonb_build_object('receiver_rfc',c.rfc_receptor,'subtotal',c.subtotal,'total',c.total,'currency',c.currency,'serie',c.serie,'folio',c.folio));
END $$;
REVOKE ALL ON FUNCTION public.rpc_fiscal01_context(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_fiscal01_context(uuid) TO authenticated;

-- Worker functions are service-only; actor comes exclusively from server getUser.
-- They recheck current grants; callers cannot grant themselves fiscal powers.
CREATE FUNCTION public.rpc_fiscal01_worker(p_cfdi_id uuid,p_actor uuid,p_action text,p_data jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
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
 cap:=CASE WHEN p_action='prepare' THEN 'prepare' WHEN p_action IN ('cancel','cancelled') THEN 'cancel' WHEN p_action IN ('load','source','status','xml','ack') THEN 'read'
  WHEN p_action IN ('identified','verified','uncertain','release','cancel_observed') AND d.busy_action='status' THEN 'read'
  WHEN p_action IN ('uncertain','release') AND d.busy_action='cancel' THEN 'cancel' ELSE 'issue' END;
 IF p_action='source' THEN
  SELECT s.cfdi_id,s.tenant_id,s.company_id INTO d.cfdi_id,d.tenant_id,d.company_id FROM private.fiscal01_draft_scope s WHERE s.cfdi_id=p_cfdi_id;
  IF d.cfdi_id IS NULL OR NOT private.fiscal01_authorized(d.tenant_id,d.company_id,'prepare') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
  RETURN jsonb_build_object('company_id',d.company_id,'fiscal_input',c.fiscal_input,'serie',c.serie,'folio',c.folio,'subtotal',c.subtotal,'total',c.total,'currency',c.currency);
 END IF;
 IF p_action='prepare' AND d.cfdi_id IS NULL THEN
  IF c.id IS NULL OR c.fiscal_status<>'draft' OR c.uuid IS NOT NULL OR c.operation_id IS NOT NULL
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
  IF p_action='cancel' AND c.fiscal_status='cancellation_requested' THEN RETURN jsonb_build_object('cancellation_pending',true); END IF;
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
  END IF;
  IF p_action='claim' THEN
   SELECT * INTO r FROM public.fiscal_requests WHERE billing_cfdi_id=c.id AND request_type='stamp' AND idempotency_key=d.payload_sha256;
  ELSE
   request_kind:=CASE WHEN p_action='cancel' THEN 'cancel' ELSE 'status' END;
   hash:=encode(extensions.digest(convert_to(request_kind||':'||gen_random_uuid()::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,requested_by,max_attempts)
    VALUES(d.tenant_id,c.id,request_kind,hash,jsonb_build_object('schema','rotero.fiscal-input','billing_cfdi_id',c.id,'company_id',d.company_id,'cancellation',CASE WHEN p_action='cancel' THEN p_data ELSE NULL END),p_actor,1) RETURNING * INTO r;
  END IF;
  UPDATE private.fiscal01_documents SET busy_token=tok,busy_since=now(),busy_actor=p_actor,busy_action=p_action,active_request_id=r.id,uncertain=CASE WHEN p_action='claim' THEN true ELSE uncertain END WHERE cfdi_id=c.id;
  UPDATE public.fiscal_requests SET status='submitting',locked_at=now() WHERE id=r.id AND status='queued';
  RETURN to_jsonb(d)||jsonb_build_object('busy_token',tok,'active_request_id',r.id,'fiscal_uuid',c.uuid,'fiscal_status',c.fiscal_status);
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
 ELSIF p_action='cancelled' THEN
  IF p_data->>'uuid' IS DISTINCT FROM c.uuid OR p_data->>'ack_path' IS DISTINCT FROM d.tenant_id::text||'/'||d.company_id::text||'/'||d.cfdi_id::text||'/cancellation.xml' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_cancellation_evidence'; END IF;
  info:=private.fiscal0_apply_provider_result(d.active_request_id,jsonb_build_object('outcome','cancelled','provider_code','facturama','http_status',200));
  IF info?'error' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_result_failed'; END IF;
  UPDATE private.fiscal01_documents SET cancellation_path=p_data->>'ack_path',busy_token=NULL,busy_since=NULL WHERE cfdi_id=c.id;
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
REVOKE ALL ON FUNCTION public.rpc_fiscal01_worker(uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_fiscal01_worker(uuid,uuid,text,jsonb) TO service_role;

-- Private bucket is deliberately separate from legacy tenant-documents policies.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('fiscal-sandbox','fiscal-sandbox',false,2000000,ARRAY['application/xml']) ON CONFLICT(id) DO NOTHING;
DO $$ BEGIN IF NOT EXISTS(SELECT FROM storage.buckets WHERE id='fiscal-sandbox' AND NOT public) THEN RAISE EXCEPTION 'fiscal_bucket_not_private'; END IF; END $$;
-- No Storage policies grant application roles access. Server streams after auth.

CREATE FUNCTION public.rpc_fiscal01_record_payment(p_cfdi_id uuid,p_actor uuid,p_paid_at timestamp,p_applications jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE s private.fiscal01_draft_scope; c public.billing_cfdis; f public.finance_invoices;
 link private.fiscal01_invoice_links; source public.billing_cfdis; receipt uuid; payment uuid; item jsonb; docs jsonb:='[]';
 amount numeric; prior numeric; remainder numeric; part integer; base numeric; sum_paid numeric:=0; payload jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 SELECT * INTO s FROM private.fiscal01_draft_scope WHERE cfdi_id=p_cfdi_id;
 IF s.cfdi_id IS NULL OR p_actor IS NULL OR NOT private.fiscal01_authorized(s.tenant_id,s.company_id,'payment') THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 -- Serialize only this synthetic company. Legacy accounting is not activated.
 PERFORM pg_advisory_xact_lock(hashtextextended('fiscal01-payments:'||s.company_id::text,0));
 SELECT * INTO c FROM public.billing_cfdis WHERE id=s.cfdi_id FOR UPDATE;
 IF EXISTS(SELECT FROM private.fiscal01_receipts WHERE cfdi_id=c.id) THEN RETURN jsonb_build_object('already_recorded',true); END IF;
 IF c.tenant_id<>s.tenant_id OR c.fiscal_status<>'draft' OR c.uuid IS NOT NULL OR c.operation_id IS NOT NULL OR p_paid_at IS NULL OR NOT c.has_complemento_pago OR c.total<>0 OR c.subtotal<>0
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
REVOKE ALL ON FUNCTION public.rpc_fiscal01_record_payment(uuid,uuid,timestamp,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_fiscal01_record_payment(uuid,uuid,timestamp,jsonb) TO service_role;
DO $references$
DECLARE actor text:=current_setting('fiscal01.migration_role'); cols text:=current_setting('fiscal01.references');
BEGIN
 IF cols<>'' THEN
  EXECUTE 'SET LOCAL ROLE rotero_company_access_owner';
  EXECUTE format('REVOKE REFERENCES (%s) ON public.companies FROM %I',cols,actor);
  EXECUTE format('SET LOCAL ROLE %I',actor);
 END IF;
END $references$;
REVOKE ALL ON FUNCTION private.fiscal01_guard() FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
