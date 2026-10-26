\set ON_ERROR_STOP on
BEGIN;
-- Entire fixture is synthetic and rolled back; no provider, mail or login.
DO $auth_fixture$ BEGIN
 IF EXISTS(SELECT FROM pg_constraint WHERE conrelid='public.audit_log'::regclass AND confrelid='auth.users'::regclass AND contype='f') THEN
  INSERT INTO auth.users(id) VALUES('62000000-0000-4000-8000-000000000301');
 END IF;
END $auth_fixture$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'RECONCILIATION failed: %',label; END IF; END $$;
INSERT INTO public.tenants(id,name,slug) VALUES('62000000-0000-4000-8000-000000000101','Synthetic reconciliation QA','synthetic-fiscal-reconciliation');
INSERT INTO public.memberships(tenant_id,user_id,role) VALUES('62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000301','finance');
SET LOCAL ROLE rotero_company_access_owner;
INSERT INTO public.companies(id,tenant_id,display_name,legal_name,rfc_normalized,status) VALUES('62000000-0000-4000-8000-000000000201','62000000-0000-4000-8000-000000000101','Synthetic A','Synthetic A','AAA010101AA1','active');
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES('62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000301','62000000-0000-4000-8000-000000000201','62000000-0000-4000-8000-000000000301');
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT '62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000301','62000000-0000-4000-8000-000000000201',cap,'synthetic reconciliation fixture','62000000-0000-4000-8000-000000000301' FROM unnest(ARRAY['fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel']) cap;
RESET ROLE;
INSERT INTO private.fiscal01_company_bindings(tenant_id,company_id,issuer_rfc,enabled,approval_reference) VALUES('62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000201','EKU9003173C9',true,'synthetic reconciliation fixture');
INSERT INTO private.fiscal01_lab_actors(tenant_id,user_id,expires_at,approval_reference) VALUES('62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000301',now()+interval '1 hour','synthetic reconciliation fixture');
INSERT INTO public.billing_cfdis(id,tenant_id,rfc_emisor,rfc_receptor,serie,folio,subtotal,total,status,fiscal_status,fiscal_input) VALUES('62000000-0000-4000-8000-000000000401','62000000-0000-4000-8000-000000000101','EKU9003173C9','URE180429TM6','QARECON','RECON-1',100,116,'draft','draft','{"concepts":[{"amount":100,"description":"Synthetic"}]}');
INSERT INTO private.fiscal01_draft_scope(cfdi_id,tenant_id,company_id,approval_reference) VALUES('62000000-0000-4000-8000-000000000401','62000000-0000-4000-8000-000000000101','62000000-0000-4000-8000-000000000201','synthetic reconciliation fixture');
DO $flow$
DECLARE v_cfdi uuid:='62000000-0000-4000-8000-000000000401'; actor uuid:='62000000-0000-4000-8000-000000000301'; lease jsonb; status_lease jsonb; cancel_lease jsonb; old_attempts bigint; stamp_id uuid;
BEGIN
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'prepare',jsonb_build_object('company_id','62000000-0000-4000-8000-000000000201','payload',jsonb_build_object('Issuer',jsonb_build_object('Rfc','EKU9003173C9'),'Receiver',jsonb_build_object('Rfc','URE180429TM6'),'CfdiType','I','Serie','QARECON','Folio','RECON-1','Date','2026-10-24T10:00:00')));
 lease:=public.rpc_fiscal01_worker(v_cfdi,actor,'claim');stamp_id:=(lease->>'active_request_id')::uuid;
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'identified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-reconciliation-provider'));
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'uncertain',jsonb_build_object('busy_token',lease->>'busy_token'));
 PERFORM pg_temp.check_it((SELECT status='processing' FROM public.fiscal_requests WHERE id=stamp_id),'initial stamp retained pending unavailable XML');
 IF to_regprocedure('private.fiscal02_finish_reconciled_stamp(uuid)') IS NOT NULL THEN
  PERFORM pg_temp.check_it(private.fiscal02_finish_reconciled_stamp(v_cfdi)=0,'HTTP identity without verified XML cannot close stamp');
 END IF;
 status_lease:=public.rpc_fiscal01_worker(v_cfdi,actor,'status');
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'verified',jsonb_build_object('busy_token',status_lease->>'busy_token','provider_document_id','synthetic-reconciliation-provider','uuid',v_cfdi,'stamped_at','2026-10-24T10:00:01','xml_path','62000000-0000-4000-8000-000000000101/62000000-0000-4000-8000-000000000201/'||v_cfdi||'/invoice.xml','xml_sha256',repeat('b',64)));
 -- The old worker fails HERE: it completes only the active status request.
 PERFORM pg_temp.check_it((SELECT status='completed' AND completed_at IS NOT NULL AND next_attempt_at IS NULL AND safe_error_code IS NULL FROM public.fiscal_requests WHERE id=stamp_id),'canonical_stamp_completed_after_status');
 PERFORM pg_temp.check_it((SELECT status='completed' FROM public.fiscal_requests WHERE id=(status_lease->>'active_request_id')::uuid),'status request separately completed');
 SELECT count(*) INTO old_attempts FROM public.fiscal_provider_attempts a JOIN public.fiscal_requests r ON r.id=a.request_id WHERE r.billing_cfdi_id=v_cfdi;
 PERFORM pg_temp.check_it(old_attempts=2,'no extra provider attempt invented for ledger repair');
 PERFORM pg_temp.check_it(private.fiscal02_finish_reconciled_stamp(v_cfdi)=0,'idempotent reconciliation');
 PERFORM pg_temp.check_it((public.rpc_fiscal01_worker(v_cfdi,actor,'claim')->>'reconcile_required')::boolean,'closing original stamp never enables another issuance');
 PERFORM pg_temp.check_it((SELECT count(*)=old_attempts FROM public.fiscal_provider_attempts a JOIN public.fiscal_requests r ON r.id=a.request_id WHERE r.billing_cfdi_id=v_cfdi),'attempt history preserved');
 PERFORM pg_temp.check_it(private.fiscal02_finish_reconciled_stamp('62000000-0000-4000-8000-000000000499')=0,'unrelated ID does not change requests');
 cancel_lease:=public.rpc_fiscal01_worker(v_cfdi,actor,'cancel','{"motive":"03"}');
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'cancel_confirmed',jsonb_build_object('busy_token',cancel_lease->>'busy_token','provider_document_id','synthetic-reconciliation-provider','uuid',v_cfdi));
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'cancel_ack_invalid',jsonb_build_object('busy_token',cancel_lease->>'busy_token','ack_sha256',repeat('c',64)));
 PERFORM public.rpc_fiscal01_worker(v_cfdi,actor,'release',jsonb_build_object('busy_token',cancel_lease->>'busy_token'));
 PERFORM pg_temp.check_it(private.fiscal02_finish_reconciled_stamp(v_cfdi)=0,'terminal stamp never reprocessed');
 PERFORM pg_temp.check_it((SELECT fiscal_status='cancellation_requested' FROM public.billing_cfdis WHERE billing_cfdis.id=v_cfdi),'cancellation remains pending');
 PERFORM pg_temp.check_it((SELECT cancellation_ack_state='mismatch' AND cancellation_path IS NULL FROM private.fiscal01_documents WHERE cfdi_id=v_cfdi),'foreign ack never approved by stamp reconciliation');
 PERFORM pg_temp.check_it((SELECT status='processing' FROM public.fiscal_requests WHERE id=(cancel_lease->>'active_request_id')::uuid),'no automatic cancellation completion');
END $flow$;
DO $acl$ DECLARE role_name text; BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'private.fiscal02_finish_reconciled_stamp(uuid)','EXECUTE'),'internal helper not public');
 END LOOP;
 PERFORM pg_temp.check_it(NOT (SELECT prosecdef FROM pg_proc WHERE oid='private.fiscal02_finish_reconciled_stamp(uuid)'::regprocedure),'helper uses invoker');
 PERFORM pg_temp.check_it(NOT has_function_privilege('authenticated','public.rpc_fiscal01_worker(uuid,uuid,text,jsonb)','EXECUTE'),'worker ACL retained');
END $acl$;
SELECT 'PASS delayed XML closes original stamp; proof required; attempts and pending cancellation preserved; effective ACL closed';
ROLLBACK;
