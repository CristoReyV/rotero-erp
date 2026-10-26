-- FACTURAMA-05: sandbox cancellation confirmation and private PDF evidence are
-- independent. No history is rewritten or reconciled by applying this migration.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $bucket$
BEGIN
 UPDATE storage.buckets SET allowed_mime_types=ARRAY['application/xml','application/pdf']
 WHERE id='fiscal-sandbox' AND NOT public AND file_size_limit=2000000 AND allowed_mime_types=ARRAY['application/xml'];
 IF NOT FOUND THEN RAISE EXCEPTION 'unsupported_fiscal05_private_bucket'; END IF;
END $bucket$;
ALTER TABLE private.fiscal01_documents
 ADD COLUMN cancellation_request_id uuid,
 ADD COLUMN cancellation_xml_interpretation text CHECK(cancellation_xml_interpretation='sandbox_request_identifier'),
 ADD COLUMN cancellation_confirmed_at timestamptz,
 ADD COLUMN cancellation_evidence jsonb CHECK(cancellation_evidence IS NULL OR jsonb_typeof(cancellation_evidence)='object'),
 ADD COLUMN cancellation_pdf_path text,
 ADD COLUMN cancellation_pdf_sha256 text CHECK(cancellation_pdf_sha256 ~ '^[0-9a-f]{64}$'),
 ADD COLUMN cancellation_pdf_bytes integer CHECK(cancellation_pdf_bytes BETWEEN 16 AND 2000000),
 ADD COLUMN cancellation_pdf_fetched_at timestamptz,
 ADD COLUMN cancellation_pdf_provider_id text,
 ADD COLUMN cancellation_pdf_token uuid,
 ADD COLUMN cancellation_pdf_actor uuid,
 ADD COLUMN cancellation_pdf_since timestamptz,
 ADD CONSTRAINT fiscal05_pdf_complete CHECK(
  (cancellation_pdf_path IS NULL AND cancellation_pdf_sha256 IS NULL AND cancellation_pdf_bytes IS NULL AND cancellation_pdf_fetched_at IS NULL AND cancellation_pdf_provider_id IS NULL)
  OR (cancellation_pdf_path IS NOT NULL AND cancellation_pdf_sha256 IS NOT NULL AND cancellation_pdf_bytes IS NOT NULL AND cancellation_pdf_fetched_at IS NOT NULL
   AND cancellation_pdf_provider_id IS NOT NULL AND cancellation_pdf_provider_id=provider_document_id
   AND cancellation_pdf_path=tenant_id::text||'/'||company_id::text||'/'||cfdi_id::text||'/cancellation-'||cancellation_pdf_sha256||'.pdf')),
 ADD CONSTRAINT fiscal05_pdf_lease_complete CHECK(
  (cancellation_pdf_token IS NULL AND cancellation_pdf_actor IS NULL AND cancellation_pdf_since IS NULL)
  OR (cancellation_pdf_token IS NOT NULL AND cancellation_pdf_actor IS NOT NULL AND cancellation_pdf_since IS NOT NULL));

-- Only the authenticated Edge worker may submit a correlated observation.
-- Ordinary users cannot invoke this RPC, forge status or administer grants.
CREATE FUNCTION public.rpc_fiscal05_evidence(p_cfdi_id uuid,p_actor uuid,p_action text,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE d private.fiscal01_documents; c public.billing_cfdis; r public.fiscal_requests;
 cap text:='read'; tok uuid; result jsonb; proof jsonb; target record;
BEGIN
 IF p_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('observe_cancel','pdf_claim','pdf_save','pdf_release','pdf_load') THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 PERFORM pg_catalog.set_config('request.jwt.claim.sub',p_actor::text,true);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fiscal01:'||p_cfdi_id::text,0));
 SELECT * INTO c FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
 SELECT * INTO d FROM private.fiscal01_documents WHERE cfdi_id=p_cfdi_id FOR UPDATE;
 IF p_action='observe_cancel' AND d.busy_token IS NOT NULL AND d.busy_action='cancel' THEN cap:='cancel'; END IF;
 PERFORM private.fiscal02_set_worker(p_cfdi_id,p_actor,cap);
 IF d.cfdi_id IS NULL OR c.tenant_id IS DISTINCT FROM d.tenant_id OR c.fiscal_provider IS DISTINCT FROM 'facturama'
  OR c.rfc_emisor IS DISTINCT FROM 'EKU9003173C9' OR c.provider_document_id IS DISTINCT FROM d.provider_document_id
  OR d.provider_document_id IS NULL OR d.provider_document_id !~ '^[A-Za-z0-9_-]+$'
  OR c.uuid IS NULL OR c.request_fingerprint IS DISTINCT FROM d.payload_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='fiscal_forbidden'; END IF;
 IF p_action='observe_cancel' THEN
  IF p_data->>'provider_document_id' IS DISTINCT FROM d.provider_document_id OR lower(p_data->>'uuid') IS DISTINCT FROM lower(c.uuid)
   OR NOT COALESCE(p_data->>'remote_status' IN ('cancel','canceled'),false) OR p_data->>'http_status' IS DISTINCT FROM '200'
   OR c.fiscal_status NOT IN ('stamped','cancellation_requested','cancelled') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='uncorrelated_cancellation_confirmation'; END IF;
  IF d.busy_token IS NOT NULL AND (d.busy_actor IS DISTINCT FROM p_actor OR d.busy_token IS DISTINCT FROM (p_data->>'busy_token')::uuid
   OR d.busy_action NOT IN ('cancel','status')) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='stale_fiscal_lease'; END IF;
  IF p_data->>'request_identifier' IS NOT NULL THEN
   IF p_data->>'request_identifier' !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    OR p_data->>'xml_source_sha256' IS DISTINCT FROM d.cancellation_ack_sha256
    OR d.cancellation_ack_sha256 IS NULL
    OR (d.cancellation_request_id IS NOT NULL AND d.cancellation_request_id IS DISTINCT FROM (p_data->>'request_identifier')::uuid) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_historical_identifier'; END IF;
   UPDATE private.fiscal01_documents SET cancellation_request_id=(p_data->>'request_identifier')::uuid,
    cancellation_xml_interpretation='sandbox_request_identifier' WHERE cfdi_id=c.id;
  END IF;
  proof:=jsonb_build_object('provider','facturama','environment','sandbox','method','GET','host','apisandbox.facturama.mx',
   'path','/api-lite/cfdis/'||d.provider_document_id,'provider_document_id',d.provider_document_id,'fiscal_uuid',c.uuid,
   'remote_status',p_data->>'remote_status','http_status',200,'observed_at',now());
  UPDATE public.billing_cfdis SET fiscal_status='cancellation_requested' WHERE id=c.id AND fiscal_status='stamped';
  IF d.busy_token IS NOT NULL THEN
   SELECT * INTO r FROM public.fiscal_requests WHERE id=d.active_request_id FOR UPDATE;
   IF r.billing_cfdi_id IS DISTINCT FROM c.id OR r.tenant_id IS DISTINCT FROM d.tenant_id OR r.request_type NOT IN ('cancel','status') OR r.status<>'submitting' THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_cancellation_request'; END IF;
   -- An actual current HTTP operation has a real attempt. Historical closure
   -- below deliberately creates no attempt and never fabricates an HTTP result.
   result:=private.fiscal0_apply_provider_result(r.id,jsonb_build_object('outcome','cancelled','provider_code','facturama',
    'provider_document_id',d.provider_document_id,'fiscal_uuid',c.uuid,'http_status',200),d.busy_since);
   IF result?'error' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='fiscal_result_failed'; END IF;
  ELSE
   UPDATE public.billing_cfdis SET fiscal_status='cancelled',fiscal_last_checked_at=now(),fiscal_error_code=NULL,fiscal_error_message_safe=NULL WHERE id=c.id;
  END IF;
  FOR target IN SELECT id FROM public.fiscal_requests WHERE billing_cfdi_id=c.id AND tenant_id=d.tenant_id AND request_type='cancel'
   AND status IN ('queued','submitting','processing','technical_error') AND payload_snapshot->>'company_id'=d.company_id::text
   AND payload_snapshot#>>'{cancellation,motive}' IN ('01','02','03','04') FOR UPDATE LOOP
   UPDATE public.fiscal_requests SET status='completed',completed_at=now(),next_attempt_at=NULL,safe_error_code=NULL,locked_at=NULL,updated_at=now() WHERE id=target.id;
   PERFORM public.rpc_write_audit(d.tenant_id,'facturama_sandbox_cancel_reconciled','fiscal_request',target.id,proof||jsonb_build_object('no_attempt_created',true));
  END LOOP;
  UPDATE private.fiscal01_documents SET remote_cancel_status='canceled',cancellation_confirmed_at=COALESCE(cancellation_confirmed_at,now()),
   cancellation_evidence=COALESCE(cancellation_evidence,proof),uncertain=false,busy_token=NULL,busy_since=NULL WHERE cfdi_id=c.id;
  PERFORM public.rpc_write_audit(d.tenant_id,'facturama_sandbox_cancellation_observed','billing_cfdi',c.id,proof);
  RETURN jsonb_build_object('status','cancelled','remoteCancellation','confirmed','pdfAvailable',d.cancellation_pdf_path IS NOT NULL);
 END IF;
 IF d.remote_cancel_status IS DISTINCT FROM 'canceled' OR c.fiscal_status<>'cancelled' OR d.cancellation_evidence IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='cancellation_not_confirmed'; END IF;
 IF p_action='pdf_load' THEN RETURN jsonb_build_object('path',d.cancellation_pdf_path,'sha256',d.cancellation_pdf_sha256); END IF;
 IF p_action='pdf_claim' THEN
  IF d.cancellation_pdf_path IS NOT NULL THEN RETURN jsonb_build_object('available',true); END IF;
  IF d.cancellation_pdf_token IS NOT NULL AND d.cancellation_pdf_since>now()-interval '2 minutes' THEN RETURN jsonb_build_object('busy',true); END IF;
  tok:=gen_random_uuid();
  UPDATE private.fiscal01_documents SET cancellation_pdf_token=tok,cancellation_pdf_actor=p_actor,cancellation_pdf_since=now() WHERE cfdi_id=c.id;
  RETURN jsonb_build_object('busy_token',tok,'tenant_id',d.tenant_id,'company_id',d.company_id,'provider_document_id',d.provider_document_id);
 END IF;
 IF d.cancellation_pdf_token IS NULL OR d.cancellation_pdf_actor IS DISTINCT FROM p_actor OR d.cancellation_pdf_token IS DISTINCT FROM (p_data->>'busy_token')::uuid THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='stale_fiscal_lease'; END IF;
 IF p_action='pdf_save' THEN
  IF p_data->>'provider_document_id' IS DISTINCT FROM d.provider_document_id OR NOT COALESCE(p_data->>'sha256' ~ '^[0-9a-f]{64}$',false)
   OR NOT COALESCE(p_data->>'bytes' ~ '^[0-9]{1,7}$',false) OR (p_data->>'bytes')::integer NOT BETWEEN 16 AND 2000000
   OR p_data->>'path' IS DISTINCT FROM d.tenant_id::text||'/'||d.company_id::text||'/'||d.cfdi_id::text||'/cancellation-'||(p_data->>'sha256')||'.pdf' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='invalid_pdf_evidence'; END IF;
  UPDATE private.fiscal01_documents SET cancellation_pdf_path=p_data->>'path',cancellation_pdf_sha256=p_data->>'sha256',cancellation_pdf_bytes=(p_data->>'bytes')::integer,
   cancellation_pdf_fetched_at=now(),cancellation_pdf_provider_id=d.provider_document_id WHERE cfdi_id=c.id;
  PERFORM public.rpc_write_audit(d.tenant_id,'facturama_sandbox_ack_pdf_stored','billing_cfdi',c.id,
   jsonb_build_object('method','GET','host','apisandbox.facturama.mx','path','/acuse/pdf/issuedLite/'||d.provider_document_id,
    'sha256',p_data->>'sha256','bytes',(p_data->>'bytes')::integer,'validation','PDF format and requested persisted ID only; no internal or cryptographic correlation'));
 END IF;
 UPDATE private.fiscal01_documents SET cancellation_pdf_token=NULL,cancellation_pdf_actor=NULL,cancellation_pdf_since=NULL WHERE cfdi_id=c.id;
 RETURN jsonb_build_object('saved',true,'pdfAvailable',p_action='pdf_save');
END $fn$;
REVOKE ALL ON FUNCTION public.rpc_fiscal05_evidence(uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_fiscal05_evidence(uuid,uuid,text,jsonb) TO service_role;

-- Keep existing context authorization/DTO, adding distinct evidence fields.
DO $context_patch$
DECLARE proc oid:='public.rpc_fiscal01_context(uuid)'::regprocedure; def text;
 needle text:='''remote_cancel_status'',d.remote_cancel_status,''cancellation_ack_state'',d.cancellation_ack_state,';
BEGIN
 def:=pg_catalog.pg_get_functiondef(proc);
 IF (length(def)-length(replace(def,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'unsupported_fiscal05_context'; END IF;
 def:=replace(def,needle,needle||E'\n  ''cancellation_request_id'',d.cancellation_request_id,''cancellation_xml_interpretation'',d.cancellation_xml_interpretation,\n  ''cancellation_pdf_available'',d.cancellation_pdf_path IS NOT NULL,''cancellation_pdf_sha256'',d.cancellation_pdf_sha256,\n  ''cancellation_pdf_fetched_at'',d.cancellation_pdf_fetched_at,''cancellation_confirmed_at'',d.cancellation_confirmed_at,');
 EXECUTE def;
END $context_patch$;
COMMIT;
