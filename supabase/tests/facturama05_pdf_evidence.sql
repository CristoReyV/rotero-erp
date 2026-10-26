\set ON_ERROR_STOP on
BEGIN;
-- Local only: all identities/data are synthetic and transactionally removed.
-- The restored staging shape has an audit actor FK to Auth, unlike the canonical
-- replay. In that shape only, create inert UUID stubs in this same transaction;
-- no password, login, session, email, remote Auth call or persistent identity.
DO $audit_actor_fixture$ BEGIN
 IF EXISTS(SELECT FROM pg_constraint WHERE conrelid='public.audit_log'::regclass AND confrelid='auth.users'::regclass AND contype='f') THEN
  INSERT INTO auth.users(id) VALUES
   ('65000000-0000-4000-8000-000000000301'),('65000000-0000-4000-8000-000000000302'),('65000000-0000-4000-8000-000000000303');
 END IF;
END $audit_actor_fixture$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FACTURAMA01 failed: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.error_it(q text,state text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>state THEN RAISE EXCEPTION 'expected %, got %: %',state,SQLSTATE,SQLERRM; END IF; RETURN; END; RAISE EXCEPTION 'expected denial: %',state; END $$;
INSERT INTO public.tenants(id,name,slug) VALUES('65000000-0000-4000-8000-000000000101','Synthetic fiscal QA','synthetic-pdf-qa'),('65000000-0000-4000-8000-000000000102','Synthetic other tenant','synthetic-pdf-other');
INSERT INTO public.memberships(user_id,tenant_id,role) VALUES
 ('65000000-0000-4000-8000-000000000301','65000000-0000-4000-8000-000000000101','finance'),
 ('65000000-0000-4000-8000-000000000302','65000000-0000-4000-8000-000000000101','admin'),
 ('65000000-0000-4000-8000-000000000303','65000000-0000-4000-8000-000000000102','finance');
SET LOCAL ROLE rotero_company_access_owner;
INSERT INTO public.companies(id,tenant_id,display_name,legal_name,rfc_normalized,status) VALUES
 ('65000000-0000-4000-8000-000000000201','65000000-0000-4000-8000-000000000101','Synthetic A','Synthetic legal A','AAA010101AA1','active'),
 ('65000000-0000-4000-8000-000000000202','65000000-0000-4000-8000-000000000101','Synthetic B','Synthetic legal B','BBB010101BB1','active'),
 ('65000000-0000-4000-8000-000000000203','65000000-0000-4000-8000-000000000102','Synthetic X','Synthetic legal X','CCC010101CC1','active');
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
 VALUES('65000000-0000-4000-8000-000000000101','65000000-0000-4000-8000-000000000301','65000000-0000-4000-8000-000000000201','65000000-0000-4000-8000-000000000302');
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT '65000000-0000-4000-8000-000000000101','65000000-0000-4000-8000-000000000301','65000000-0000-4000-8000-000000000201',code,'synthetic-fiscal-only','65000000-0000-4000-8000-000000000302' FROM unnest(ARRAY['fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment']) code;
RESET ROLE;
INSERT INTO private.fiscal01_company_bindings(tenant_id,company_id,issuer_rfc,enabled,approval_reference)
 SELECT tenant_id,id,'EKU9003173C9',true,'synthetic-lab-only' FROM public.companies
 WHERE tenant_id IN ('65000000-0000-4000-8000-000000000101','65000000-0000-4000-8000-000000000102');
INSERT INTO private.fiscal01_lab_actors(tenant_id,user_id,expires_at,approval_reference)
 SELECT tenant_id,user_id,now()+interval '1 hour','synthetic-lab-only' FROM public.memberships WHERE user_id IN ('65000000-0000-4000-8000-000000000301','65000000-0000-4000-8000-000000000302');
INSERT INTO public.billing_cfdis(id,tenant_id,rfc_emisor,rfc_receptor,serie,folio,subtotal,total,status,fiscal_input)
 SELECT ('65000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '65000000-0000-4000-8000-000000000101','EKU9003173C9','URE180429TM6','QATEST','QA-'||n,100,116,'draft',
 '{"concepts":[{"amount":100,"description":"Synthetic service"}],"payment":{"method":"PPD"}}'::jsonb FROM generate_series(401,407) n;
UPDATE public.billing_cfdis SET has_complemento_pago=true,total=0,subtotal=0 WHERE folio IN ('QA-405','QA-406','QA-407');
INSERT INTO private.fiscal01_draft_scope(cfdi_id,tenant_id,company_id,approval_reference)
 SELECT id,tenant_id,CASE WHEN folio='QA-403' THEN '65000000-0000-4000-8000-000000000202'::uuid ELSE '65000000-0000-4000-8000-000000000201'::uuid END,'synthetic-explicit-source' FROM public.billing_cfdis WHERE tenant_id='65000000-0000-4000-8000-000000000101';


DO $flow$
DECLARE doc uuid:='65000000-0000-4000-8000-000000000401'; actor uuid:='65000000-0000-4000-8000-000000000301';
 lease jsonb; original uuid; attempts bigint; token uuid; proof jsonb; prefix text;
BEGIN
 PERFORM public.rpc_fiscal01_worker(doc,actor,'prepare',jsonb_build_object('company_id','65000000-0000-4000-8000-000000000201',
  'payload',jsonb_build_object('Issuer',jsonb_build_object('Rfc','EKU9003173C9'),'Receiver',jsonb_build_object('Rfc','URE180429TM6'),'CfdiType','I')));
 lease:=public.rpc_fiscal01_worker(doc,actor,'claim');
 PERFORM public.rpc_fiscal01_worker(doc,actor,'identified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-pdf-document'));
 PERFORM public.rpc_fiscal01_worker(doc,actor,'verified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-pdf-document',
  'uuid',doc,'stamped_at','2026-10-26T10:00:00','xml_path','65000000-0000-4000-8000-000000000101/65000000-0000-4000-8000-000000000201/'||doc||'/invoice.xml','xml_sha256',repeat('b',64)));
 lease:=public.rpc_fiscal01_worker(doc,actor,'cancel','{"motive":"02"}'); original:=(lease->>'active_request_id')::uuid;
 PERFORM public.rpc_fiscal01_worker(doc,actor,'cancel_confirmed',jsonb_build_object('busy_token',lease->>'busy_token','uuid',doc,'provider_document_id','synthetic-pdf-document'));
 PERFORM public.rpc_fiscal01_worker(doc,actor,'cancel_ack_invalid',jsonb_build_object('busy_token',lease->>'busy_token','ack_sha256',repeat('e',64)));
 PERFORM public.rpc_fiscal01_worker(doc,actor,'release',jsonb_build_object('busy_token',lease->>'busy_token'));
 SELECT count(*) INTO attempts FROM public.fiscal_provider_attempts;
 proof:=jsonb_build_object('provider_document_id','synthetic-pdf-document','uuid',doc,'remote_status','canceled','http_status',200,
  'request_identifier','0088b8e0-00de-43d7-a590-8328b803839f','xml_source_sha256',repeat('e',64));
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''observe_cancel'',%L)',doc,actor,proof-'remote_status'),'23514');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''observe_cancel'',%L)',doc,actor,proof||'{"uuid":"65000000-0000-4000-8000-000000000499"}'),'23514');
 PERFORM public.rpc_fiscal05_evidence(doc,actor,'observe_cancel',proof);
 PERFORM pg_temp.check_it((SELECT fiscal_status='cancelled' AND uuid=doc::text FROM public.billing_cfdis WHERE id=doc),'correlated remote evidence finalizes without replacing fiscal UUID');
 PERFORM pg_temp.check_it((SELECT status='completed' AND attempt_count=1 AND payload_snapshot#>>'{cancellation,motive}'='02' FROM public.fiscal_requests WHERE id=original),'historical cancel completed with original motive and attempts');
 PERFORM pg_temp.check_it((SELECT count(*)=attempts FROM public.fiscal_provider_attempts),'no invented HTTP attempt during reconciliation');
 PERFORM pg_temp.check_it((SELECT cancellation_ack_state='mismatch' AND cancellation_ack_sha256=repeat('e',64) AND cancellation_path IS NULL AND
  cancellation_request_id='0088b8e0-00de-43d7-a590-8328b803839f' AND cancellation_xml_interpretation='sandbox_request_identifier'
  AND xml_sha256=repeat('b',64) AND cancellation_pdf_path IS NULL FROM private.fiscal01_documents WHERE cfdi_id=doc),'XML history retained and request ID distinct; PDF still unavailable');
 lease:=public.rpc_fiscal05_evidence(doc,actor,'pdf_claim'); token:=(lease->>'busy_token')::uuid;
 PERFORM pg_temp.check_it((public.rpc_fiscal05_evidence(doc,actor,'pdf_claim')->>'busy')='true','double activation has one PDF lease');
 PERFORM public.rpc_fiscal05_evidence(doc,actor,'pdf_release',jsonb_build_object('busy_token',token));
 PERFORM pg_temp.check_it((SELECT fiscal_status='cancelled' FROM public.billing_cfdis WHERE id=doc),'PDF failure cannot rewind confirmed cancellation');
 lease:=public.rpc_fiscal05_evidence(doc,actor,'pdf_claim'); token:=(lease->>'busy_token')::uuid;
 prefix:='65000000-0000-4000-8000-000000000101/65000000-0000-4000-8000-000000000201/'||doc||'/cancellation-'||repeat('a',64)||'.pdf';
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_save'',%L)',doc,actor,jsonb_build_object('busy_token',token,'provider_document_id','wrong','sha256',repeat('a',64),'bytes',100,'path',prefix)),'23514');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_save'',%L)',doc,actor,jsonb_build_object('busy_token',token,'provider_document_id','synthetic-pdf-document','sha256',repeat('a',64),'bytes',100,'path','other/company/file.pdf')),'23514');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_save'',%L)',doc,actor,jsonb_build_object('busy_token',token,'provider_document_id','synthetic-pdf-document')),'23514');
 PERFORM public.rpc_fiscal05_evidence(doc,actor,'pdf_save',jsonb_build_object('busy_token',token,'provider_document_id','synthetic-pdf-document','sha256',repeat('a',64),'bytes',100,'path',prefix));
 PERFORM pg_temp.check_it(public.rpc_fiscal05_evidence(doc,actor,'pdf_load')->>'path'=prefix,'read uses only private server path');
 PERFORM pg_temp.check_it(public.rpc_fiscal01_context(doc)->>'cancellation_pdf_available'='true','context persists PDF separately');
 PERFORM pg_temp.check_it(public.rpc_fiscal01_context(doc)->>'uuid'=doc::text,'context retains fiscal UUID');
 PERFORM pg_temp.check_it(public.rpc_fiscal01_context(doc)->>'cancellation_request_id'='0088b8e0-00de-43d7-a590-8328b803839f','context separates request identifier');
 PERFORM pg_temp.check_it(public.rpc_fiscal05_evidence(doc,actor,'pdf_claim')->>'available'='true','cached PDF has no extra lease');
 PERFORM public.rpc_fiscal05_evidence(doc,actor,'observe_cancel',proof);
 PERFORM pg_temp.check_it((SELECT count(*)=attempts FROM public.fiscal_provider_attempts),'repeated observation has no duplicate requests or attempts');
END $flow$;
SELECT 'PASS confirmation, original motive, immutable history, PDF leases, path/hash integrity and separate availability';
DO $initial_confirmation$
DECLARE doc uuid:='65000000-0000-4000-8000-000000000402'; actor uuid:='65000000-0000-4000-8000-000000000301'; lease jsonb; cancel_request uuid;
BEGIN
 PERFORM public.rpc_fiscal01_worker(doc,actor,'prepare',jsonb_build_object('company_id','65000000-0000-4000-8000-000000000201',
  'payload',jsonb_build_object('Issuer',jsonb_build_object('Rfc','EKU9003173C9'),'Receiver',jsonb_build_object('Rfc','URE180429TM6'),'CfdiType','I')));
 lease:=public.rpc_fiscal01_worker(doc,actor,'claim');
 PERFORM public.rpc_fiscal01_worker(doc,actor,'identified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-initial-pdf'));
 PERFORM public.rpc_fiscal01_worker(doc,actor,'verified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-initial-pdf',
  'uuid',doc,'stamped_at','2026-10-26T10:00:00','xml_path','65000000-0000-4000-8000-000000000101/65000000-0000-4000-8000-000000000201/'||doc||'/invoice.xml','xml_sha256',repeat('b',64)));
 lease:=public.rpc_fiscal01_worker(doc,actor,'cancel','{"motive":"02"}'); cancel_request:=(lease->>'active_request_id')::uuid;
 PERFORM public.rpc_fiscal05_evidence(doc,actor,'observe_cancel',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-initial-pdf','uuid',doc,'remote_status','canceled','http_status',200));
 PERFORM pg_temp.check_it((SELECT status='completed' AND attempt_count=1 FROM public.fiscal_requests WHERE id=cancel_request),'initial confirmed cancellation completes without any XML or PDF');
 PERFORM pg_temp.check_it((SELECT count(*)=1 FROM public.fiscal_provider_attempts a WHERE a.request_id=cancel_request),'one actual operation attempt');
 PERFORM pg_temp.check_it((SELECT fiscal_status='cancelled' FROM public.billing_cfdis WHERE id=doc),'initial cancellation terminal state independent of receipt');
END $initial_confirmation$;
SELECT 'PASS initial cancellation finalizes without XML or PDF';
DO $denials$ DECLARE actor uuid:='65000000-0000-4000-8000-000000000301'; doc uuid:='65000000-0000-4000-8000-000000000401'; role_name text; BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'public.rpc_fiscal05_evidence(uuid,uuid,text,jsonb)','EXECUTE'),'new RPC closed to ordinary users');
  PERFORM pg_temp.check_it(NOT has_table_privilege(role_name,'private.fiscal01_documents','SELECT,INSERT,UPDATE,DELETE'),'no direct artifact/permission route');
 END LOOP;
 PERFORM pg_temp.check_it(has_function_privilege('service_role','public.rpc_fiscal05_evidence(uuid,uuid,text,jsonb)','EXECUTE'),'only guarded server worker');
 PERFORM pg_temp.check_it((SELECT prosecdef AND proconfig=ARRAY['search_path=""'] FROM pg_proc WHERE oid='public.rpc_fiscal05_evidence(uuid,uuid,text,jsonb)'::regprocedure),'qualified privileged code and safe path');
 PERFORM pg_temp.check_it((SELECT NOT public AND file_size_limit=2000000 AND allowed_mime_types=ARRAY['application/xml','application/pdf'] FROM storage.buckets WHERE id='fiscal-sandbox'),'PDF bucket remains private and bounded');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,NULL,''pdf_load'')',doc),'42501');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_load'')',doc,'65000000-0000-4000-8000-000000000302'),'42501');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_load'')',doc,'65000000-0000-4000-8000-000000000303'),'42501');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal05_evidence(%L,%L,''pdf_load'')','65000000-0000-4000-8000-000000000403',actor),'42501');
END $denials$;
SET LOCAL ROLE rotero_company_access_owner;
UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by='65000000-0000-4000-8000-000000000302' WHERE user_id='65000000-0000-4000-8000-000000000301' AND capability_code='fiscal.read';
RESET ROLE;
SELECT pg_temp.error_it($q$SELECT public.rpc_fiscal05_evidence('65000000-0000-4000-8000-000000000401','65000000-0000-4000-8000-000000000301','pdf_load')$q$,'42501');
SELECT 'PASS identity, admin without grants, cross-company/tenant, capability revocation and effective ACL';
ROLLBACK;
