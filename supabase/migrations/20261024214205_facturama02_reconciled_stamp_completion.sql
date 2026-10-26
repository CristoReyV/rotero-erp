-- FACTURAMA-02: reconcile the original stamp ledger only from verified status
-- evidence. No provider call, new grant, financial reclassification or retry.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE FUNCTION private.fiscal02_finish_reconciled_stamp(p_cfdi uuid) RETURNS integer
LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE r record; changed integer:=0;
BEGIN
 FOR r IN
  SELECT s.id,s.tenant_id,d.cfdi_id,d.xml_sha256,proof.id AS status_request_id
  FROM public.fiscal_requests s
  JOIN private.fiscal01_documents d ON d.cfdi_id=s.billing_cfdi_id AND d.tenant_id=s.tenant_id
  JOIN private.fiscal01_draft_scope scope ON scope.cfdi_id=d.cfdi_id AND scope.tenant_id=d.tenant_id AND scope.company_id=d.company_id
  JOIN private.fiscal01_company_bindings binding ON binding.tenant_id=d.tenant_id AND binding.company_id=d.company_id
  JOIN public.billing_cfdis c ON c.id=d.cfdi_id AND c.tenant_id=d.tenant_id
  JOIN LATERAL (
   SELECT sr.id FROM public.fiscal_requests sr
   JOIN public.fiscal_provider_attempts a ON a.request_id=sr.id AND a.tenant_id=sr.tenant_id
   WHERE sr.billing_cfdi_id=d.cfdi_id AND sr.tenant_id=d.tenant_id AND sr.request_type='status' AND sr.status='completed'
    AND a.provider_code='facturama' AND a.normalized_result->>'outcome'='stamped'
    AND a.normalized_result->>'provider_document_id'=d.provider_document_id
    AND pg_catalog.lower(a.normalized_result->>'fiscal_uuid')=pg_catalog.lower(c.uuid)
   ORDER BY a.completed_at DESC,a.id LIMIT 1
  ) proof ON true
  WHERE d.cfdi_id=p_cfdi AND s.request_type='stamp' AND s.idempotency_key=d.payload_sha256
   AND s.status IN ('queued','submitting','processing','technical_error')
   AND c.fiscal_provider='facturama' AND c.rfc_emisor='EKU9003173C9' AND binding.environment='sandbox' AND binding.issuer_rfc='EKU9003173C9'
   AND c.provider_document_id=d.provider_document_id AND c.request_fingerprint=d.payload_sha256
   AND c.uuid ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
   AND c.fiscal_status IN ('stamped','cancellation_requested','cancellation_rejected','cancelled')
   AND d.xml_path=d.tenant_id::text||'/'||d.company_id::text||'/'||d.cfdi_id::text||'/invoice.xml'
   AND d.xml_sha256 ~ '^[0-9a-f]{64}$' AND NOT d.uncertain AND d.busy_token IS NULL
  FOR UPDATE OF s
 LOOP
  -- This closes bookkeeping, not an HTTP attempt. Preserve every existing
  -- provider attempt and link the successful status observation in audit.
  UPDATE public.fiscal_requests SET status='completed',completed_at=COALESCE(completed_at,now()),
   next_attempt_at=NULL,safe_error_code=NULL,locked_at=NULL,updated_at=now() WHERE id=r.id;
  PERFORM public.rpc_write_audit(r.tenant_id,'facturama_sandbox_stamp_reconciled','fiscal_request',r.id,
   pg_catalog.jsonb_build_object('billing_cfdi_id',r.cfdi_id,'verified_status_request_id',r.status_request_id,'verified_xml_sha256',r.xml_sha256));
  changed:=changed+1;
 END LOOP;
 RETURN changed;
END $fn$;
REVOKE ALL ON FUNCTION private.fiscal02_finish_reconciled_stamp(uuid) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION private.fiscal02_finish_reconciled_stamp(uuid) IS
 'Closed INVOKER ledger reconciliation: verified sandbox XML plus a matching completed status result; no new provider attempt or cancellation approval.';

DO $worker_patch$
DECLARE proc oid:='public.rpc_fiscal01_worker(uuid,uuid,text,jsonb)'::regprocedure; definition text;
 needle text:='  UPDATE public.billing_payment_complements b SET status=''issued''';
BEGIN
 IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=proc AND pg_catalog.md5(prosrc)='9e7c7fcedc4deb1c946e9433cbde478c'
  AND prosecdef AND pg_catalog.pg_get_userbyid(proowner)=current_user AND proconfig=ARRAY['search_path=""']) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_fiscal02_worker_for_reconciliation'; END IF;
 definition:=pg_catalog.pg_get_functiondef(proc);
 IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,needle,'')))/pg_catalog.length(needle)<>1 THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='unsupported_fiscal02_verified_anchor'; END IF;
 definition:=pg_catalog.replace(definition,needle,E'  PERFORM private.fiscal02_finish_reconciled_stamp(c.id);\n'||needle);
 EXECUTE definition;
END $worker_patch$;

-- Apply the same rule to already verified laboratory history only. This does
-- not change a CFDI, payment, XML, cancellation or permission, and does not infer
-- company ownership. Current rollout gates identify the four owned QA rows.
DO $verified_history$ DECLARE d record;
BEGIN
 FOR d IN SELECT cfdi_id FROM private.fiscal01_documents LOOP
  PERFORM private.fiscal02_finish_reconciled_stamp(d.cfdi_id);
 END LOOP;
END $verified_history$;
COMMIT;
