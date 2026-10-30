\set ON_ERROR_STOP on
-- Disposable local replay only. No live users, provider calls or persistent grants.
BEGIN;
CREATE FUNCTION pg_temp.m08_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MULTI08 failed: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.m08_error(q text,code text,message text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>code OR (message IS NOT NULL AND SQLERRM<>message) THEN RAISE EXCEPTION 'MULTI08 expected %, got %: %',code,SQLSTATE,SQLERRM; END IF; RETURN; END;
 RAISE EXCEPTION 'MULTI08 expected denial: %',code; END $$;
CREATE FUNCTION pg_temp.m08_actor(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','iss','https://synthetic-access.invalid/auth/v1')::text,true); END $$;

DO $acl$ DECLARE f record; r text; t text; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.m08_check(NOT pg_has_role(r,'rotero_fiscal_policy_owner','MEMBER'),'no API owner membership');
  FOREACH t IN ARRAY ARRAY['company_fiscal_provider_configs','fiscal_document_origins','fiscal_stamp_lanes','fiscal_request_origins'] LOOP
   PERFORM pg_temp.m08_check(NOT has_any_column_privilege(r,'private.'||t,'SELECT,INSERT,UPDATE,REFERENCES'),'closed effective column ACL');
   PERFORM pg_temp.m08_check(NOT has_table_privilege(r,'private.'||t,'DELETE,TRUNCATE,TRIGGER'),'closed effective table ACL');
   PERFORM pg_temp.m08_check((SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||t)::regclass),'RLS enabled');
  END LOOP;
  FOR f IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname LIKE 'multi08_%' LOOP
   PERFORM pg_temp.m08_check(NOT has_function_privilege(r,f.oid,'EXECUTE'),'no direct helper execution');
  END LOOP;
 END LOOP;
 PERFORM pg_temp.m08_check(NOT has_column_privilege('rotero_fiscal_policy_owner','private.fiscal01_documents','provider_payload','SELECT'),'no frozen payload access');
 PERFORM pg_temp.m08_check(NOT has_table_privilege('rotero_fiscal_policy_owner','public.finance_invoices','SELECT'),'no financial table access');
 PERFORM pg_temp.m08_check(NOT has_schema_privilege('rotero_fiscal_policy_owner','private','CREATE'),'no persistent schema CREATE');
 FOR f IN SELECT proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname LIKE 'multi08_%' LOOP
  PERFORM pg_temp.m08_check(f.proconfig=ARRAY['search_path=""'],'qualified helper search_path');
 END LOOP;
END $acl$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_error('SELECT * FROM private.fiscal_document_origins','42501');
SELECT pg_temp.m08_error('SELECT private.multi08_begin_stamp(NULL,NULL,NULL,NULL)','42501');
SELECT pg_temp.m08_error('UPDATE private.company_fiscal_provider_configs SET provider_code=''facturama''','42501');
RESET ROLE;
SET LOCAL ROLE rotero_company_access_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,public.membership_company_capabilities TO %I',SESSION_USER); END $$;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT ON private.financial_principal_bindings TO %I',SESSION_USER); END $$;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT ON private.operation_company_classification_events TO %I',SESSION_USER); END $$;
RESET ROLE;
SET LOCAL ROLE rotero_finance_scope_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT ON private.finance_invoices_company_evidence TO %I',SESSION_USER); END $$;
RESET ROLE;
DO $fixture$ DECLARE t uuid; x uuid; a uuid; b uuid; xc uuid; u uuid:=gen_random_uuid(); admin uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 o uuid; i uuid; pending uuid; evidence uuid; pay uuid; c uuid; c2 uuid; cx uuid; BEGIN
 INSERT INTO public.tenants(name,slug) VALUES('M08 synthetic','m08-'||gen_random_uuid()) RETURNING id INTO t;
 INSERT INTO public.tenants(name,slug) VALUES('M08 other','m08-'||gen_random_uuid()) RETURNING id INTO x;
 INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(admin,t,'admin'),(outsider,x,'finance');
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
 INSERT INTO public.operations(tenant_id,reference_code,customer_price_amount,provider_cost_amount) VALUES(t,'M08-A',100,60) RETURNING id INTO o;
 INSERT INTO private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,evidence_kind,evidence_reference,recorded_by)
  VALUES(t,o,a,'resolved','verified_source_record','synthetic-only',admin) RETURNING id INTO evidence;
 UPDATE public.operations SET company_id=a,company_classification_status='resolved',company_classification_event_id=evidence WHERE id=o;
 INSERT INTO public.finance_invoices(tenant_id,operation_id,direction,counterparty_name,amount) VALUES(t,o,'ar','Synthetic A',100) RETURNING id INTO i;
 INSERT INTO private.finance_invoices_company_evidence(tenant_id,entity_id,company_id,decision,evidence_kind,evidence_reference,recorded_by)
  VALUES(t,i,a,'resolved','verified_source_record','synthetic-only',admin) RETURNING id INTO evidence;
 UPDATE public.finance_invoices SET company_id=a,company_classification_status='resolved',company_classification_event_id=evidence WHERE id=i;
 INSERT INTO public.finance_payments(tenant_id,invoice_id,amount,paid_at) VALUES(t,i,10,now()) RETURNING id INTO pay;
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,amount) VALUES(t,'ar','Unknown historical',25) RETURNING id INTO pending;
 INSERT INTO public.billing_cfdis(tenant_id,rfc_emisor,rfc_receptor,total,status) VALUES(t,'AAA010101AA1','XXX010101XX1',116,'draft') RETURNING id INTO c;
 INSERT INTO public.billing_cfdis(tenant_id,rfc_emisor,rfc_receptor,total,status) VALUES(t,'BBB010101BB1','XXX010101XX1',116,'draft') RETURNING id INTO c2;
 INSERT INTO public.billing_cfdis(tenant_id,rfc_emisor,rfc_receptor,total,status) VALUES(x,'XXX010101XX1','AAA010101AA1',116,'draft') RETURNING id INTO cx;
 PERFORM set_config('m08.t',t::text,true); PERFORM set_config('m08.x',x::text,true); PERFORM set_config('m08.a',a::text,true); PERFORM set_config('m08.b',b::text,true); PERFORM set_config('m08.xc',xc::text,true);
 PERFORM set_config('m08.u',u::text,true); PERFORM set_config('m08.admin',admin::text,true); PERFORM set_config('m08.outsider',outsider::text,true);
 PERFORM set_config('m08.o',o::text,true); PERFORM set_config('m08.i',i::text,true); PERFORM set_config('m08.pending',pending::text,true); PERFORM set_config('m08.pay',pay::text,true);
 PERFORM set_config('m08.c',c::text,true); PERFORM set_config('m08.c2',c2::text,true); PERFORM set_config('m08.cx',cx::text,true);
END $fixture$;
SET LOCAL ROLE authenticated;
DO $writes$ DECLARE u uuid; t uuid:=current_setting('m08.t')::uuid; i uuid:=current_setting('m08.i')::uuid; r jsonb; BEGIN
 FOREACH u IN ARRAY ARRAY[current_setting('m08.u')::uuid,current_setting('m08.admin')::uuid] LOOP
  PERFORM pg_temp.m08_actor(u);
  -- Check exact envelopes: no balance/expected/registered values in denials.
  PERFORM pg_temp.m08_check(public.rpc_record_payment(t,jsonb_build_object('invoice_id',i,'amount',9999))=jsonb_build_object('error','company_finance_write_pending'),'no payment balance oracle');
  PERFORM pg_temp.m08_check(public.rpc_create_finance_invoice(t,jsonb_build_object('operation_id',current_setting('m08.o'),'amount',9999))=jsonb_build_object('error','company_finance_write_pending'),'no operation remainder oracle');
  PERFORM pg_temp.m08_check(public.rpc_update_finance_invoice_status(t,i,'open')=jsonb_build_object('error','company_finance_write_pending'),'status guard');
  PERFORM pg_temp.m08_check(public.rpc_void_finance_invoice(t,i,'synthetic')=jsonb_build_object('error','company_finance_write_pending'),'void guard');
  PERFORM pg_temp.m08_check(public.rpc_create_payment_complement(t,jsonb_build_object('finance_payment_id',current_setting('m08.pay')))=jsonb_build_object('error','company_finance_write_pending'),'complement guard');
 END LOOP;
 PERFORM pg_temp.m08_actor(current_setting('m08.u')::uuid);
 PERFORM pg_temp.m08_check(public.rpc_record_payment(t,jsonb_build_object('invoice_id',gen_random_uuid(),'amount',1))=jsonb_build_object('error','company_finance_write_pending'),'missing and inaccessible targets share denial');
 PERFORM pg_temp.m08_check(public.rpc_record_payment(t,jsonb_build_object('invoice_id','bad','amount',1))->>'error'='invalid_payload','malformed UUID safe');
 PERFORM pg_temp.m08_check(public.rpc_create_finance_invoice(t,jsonb_build_object('company_id',current_setting('m08.b')))->>'error'='invalid_payload','no self-classification');
 r:=public.rpc_record_payment(t,jsonb_build_object('invoice_id',current_setting('m08.pending'),'amount',5,'prepare_complement',false));
 PERFORM pg_temp.m08_check(r->>'success'='true' AND (r->>'remaining_balance')::numeric=20,'unclassified legacy positive preserved explicitly');
 PERFORM pg_temp.m08_actor(current_setting('m08.outsider')::uuid);
 PERFORM pg_temp.m08_check(public.rpc_record_payment(t,jsonb_build_object('invoice_id',i,'amount',1))=jsonb_build_object('error','unauthorized'),'cross-tenant write no leakage');
END $writes$;
RESET ROLE;
SELECT pg_temp.m08_check((SELECT amount=100 AND status='open' FROM public.finance_invoices WHERE id=current_setting('m08.i')::uuid),'denials changed no classified invoice');
SELECT pg_temp.m08_check((SELECT count(*)=1 FROM public.finance_payments WHERE invoice_id=current_setting('m08.i')::uuid),'denials created no payments');
SELECT 'PASS: five classified write routes deny before values/errors, unknown legacy positive, no role shortcut or writes';

SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_actor(current_setting('m08.admin')::uuid);
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'facturama','sandbox','synthetic')->>'error'='unauthorized','admin without explicit capability denied');
RESET ROLE;
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,current_setting('m08.a')::uuid,current_setting('m08.admin')::uuid);
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,current_setting('m08.a')::uuid,'companies.manage','synthetic',current_setting('m08.admin')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_actor(current_setting('m08.u')::uuid);
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.b')::uuid,'facturama','sandbox','synthetic')->>'error'='unauthorized','other company denied');
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.x')::uuid,current_setting('m08.xc')::uuid,'facturama','sandbox','synthetic')->>'error'='unauthorized','other tenant denied');
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'facturama','production','synthetic')->>'error'='invalid_provider_selection','Facturama production forbidden');
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'https://arbitrary.invalid','sandbox','synthetic')->>'error'='invalid_provider_selection','no arbitrary provider or endpoint');
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'soft_management','sandbox','synthetic')->>'enabled'='false','Soft configuration never enables');
SELECT pg_temp.m08_check(public.rpc_get_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid)->>'provider_code'='soft_management','explicit selection available');
SELECT pg_temp.m08_check(public.rpc_update_fiscal_provider_config(current_setting('m08.t')::uuid,'facturama',true,'sandbox','{}')->>'error'='company_provider_configuration_required','old toggle cannot enable');
SELECT pg_temp.m08_check(public.rpc_queue_fiscal_stamp(current_setting('m08.c')::uuid)->>'error'='company_fiscal_transport_disabled','direct neutral queue cannot enable transport');
RESET ROLE;
DO $full_read_not_write$ DECLARE binding uuid; BEGIN
 INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,identity_issuer,approval_reference,verified_by,verified_at)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,'approved_financial_01','verified_human','https://synthetic-access.invalid/auth/v1','synthetic-only',current_setting('m08.admin')::uuid,now()-interval '1 minute') RETURNING id INTO binding;
 INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,current_setting('m08.a')::uuid,'financial.full.read',binding,'synthetic-only',current_setting('m08.admin')::uuid);
END $full_read_not_write$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_check(public.rpc_get_finance_invoice_detail(current_setting('m08.t')::uuid,current_setting('m08.i')::uuid)->'invoice'->>'id'=current_setting('m08.i'),'explicit verified full read is positive');
SELECT pg_temp.m08_check(public.rpc_record_payment(current_setting('m08.t')::uuid,jsonb_build_object('invoice_id',current_setting('m08.i'),'amount',1))=jsonb_build_object('error','company_finance_write_pending'),'full read never substitutes a work write grant');
RESET ROLE;
SET LOCAL ROLE rotero_fiscal_policy_owner;
-- Provenance insertion is owner-only; there is no public origin binder.
INSERT INTO private.fiscal_document_origins(cfdi_id,tenant_id,company_id,provider_code,environment,credential_profile)
 VALUES(current_setting('m08.c')::uuid,current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'facturama','sandbox','facturama_sandbox_lab_v1'),
 (current_setting('m08.c2')::uuid,current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'soft_management','sandbox','soft_management_sandbox_v1');
SELECT pg_temp.m08_error(format('INSERT INTO private.fiscal_document_origins(cfdi_id,tenant_id,company_id,provider_code,environment,credential_profile) VALUES(%L,%L,%L,''facturama'',''sandbox'',''facturama_sandbox_lab_v1'')',current_setting('m08.cx'),current_setting('m08.t'),current_setting('m08.a')),'23514');
SELECT pg_temp.m08_error(format('UPDATE private.fiscal_document_origins SET provider_code=''soft_management'' WHERE cfdi_id=%L',current_setting('m08.c')),'23514');
SELECT pg_temp.m08_error(format('UPDATE private.fiscal_document_origins SET environment=''production'' WHERE cfdi_id=%L',current_setting('m08.c')),'23514');
SELECT private.multi08_begin_stamp(current_setting('m08.c')::uuid,'facturama','sandbox','facturama_sandbox_lab_v1') IS NOT NULL;
SELECT pg_temp.m08_error(format('SELECT private.multi08_begin_stamp(%L,''facturama'',''sandbox'',''facturama_sandbox_lab_v1'')',current_setting('m08.c')),'23514');
SELECT pg_temp.m08_error(format('SELECT private.multi08_begin_stamp(%L,''soft_management'',''sandbox'',''soft_management_sandbox_v1'')',current_setting('m08.c')),'23514');
SELECT pg_temp.m08_error(format('DELETE FROM private.fiscal_stamp_lanes WHERE cfdi_id=%L',current_setting('m08.c')),'23514','immutable_fiscal_stamp_lane');
SELECT pg_temp.m08_error(format('UPDATE private.fiscal_stamp_lanes SET lease_id=gen_random_uuid() WHERE cfdi_id=%L',current_setting('m08.c')),'23514','immutable_fiscal_stamp_lane');
UPDATE private.fiscal_document_origins SET external_id='same-external-id' WHERE cfdi_id IN(current_setting('m08.c')::uuid,current_setting('m08.c2')::uuid);
SELECT pg_temp.m08_check((SELECT count(*)=2 FROM private.fiscal_document_origins WHERE external_id='same-external-id'),'same ID across providers is namespaced');
SELECT pg_temp.m08_error(format('UPDATE private.fiscal_document_origins SET external_id=''replacement'' WHERE cfdi_id=%L',current_setting('m08.c')),'23514');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'facturama','sandbox','synthetic-change')->>'enabled'='false','configuration change remains disabled');
SELECT pg_temp.m08_check(public.rpc_record_payment(current_setting('m08.t')::uuid,jsonb_build_object('invoice_id',current_setting('m08.i'),'amount',1))->>'error'='company_finance_write_pending','companies.manage is not financial write');
SELECT pg_temp.m08_check(public.rpc_create_finance_invoice(current_setting('m08.t')::uuid,jsonb_build_object('linked_cfdi_id',current_setting('m08.c'),'amount',1))->>'error'='company_finance_write_pending','origin cannot be linked via legacy write');
RESET ROLE;
UPDATE public.billing_cfdis SET fiscal_provider='facturama',provider_document_id='same-external-id' WHERE id=current_setting('m08.c')::uuid;
UPDATE public.billing_cfdis SET fiscal_provider='soft_management',provider_document_id='same-external-id' WHERE id=current_setting('m08.c2')::uuid;
SELECT pg_temp.m08_error(format('UPDATE public.billing_cfdis SET fiscal_provider=''soft_management'' WHERE id=%L',current_setting('m08.c')),'23514');
SELECT pg_temp.m08_error(format('UPDATE public.billing_cfdis SET tenant_id=%L WHERE id=%L',current_setting('m08.x'),current_setting('m08.c')),'23514');
SET LOCAL ROLE rotero_fiscal_policy_owner;
SELECT pg_temp.m08_check((SELECT provider_code='soft_management' AND environment='sandbox' FROM private.fiscal_document_origins WHERE cfdi_id=current_setting('m08.c2')::uuid),'origin survives future selection change');
SELECT pg_temp.m08_check((SELECT state='uncertain' FROM private.fiscal_stamp_lanes WHERE cfdi_id=current_setting('m08.c')::uuid),'uncertain send not released by configuration');
RESET ROLE;
INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.c')::uuid,'status',repeat('a',64),'{}');
SELECT pg_temp.m08_error(format('INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot) VALUES(%L,%L,''status'',repeat(''b'',64),''{}'')',current_setting('m08.x'),current_setting('m08.c')),'23514','fiscal_request_tenant_conflict');
SELECT pg_temp.m08_error(format('UPDATE public.fiscal_requests SET billing_cfdi_id=%L WHERE billing_cfdi_id=%L',current_setting('m08.c2'),current_setting('m08.c')),'23514','immutable_fiscal_request_origin');
INSERT INTO public.fiscal_provider_attempts(tenant_id,request_id,attempt_no,started_at,completed_at,provider_code,normalized_result)
 SELECT tenant_id,id,1,now(),now(),'facturama','{"outcome":"processing"}' FROM public.fiscal_requests WHERE billing_cfdi_id=current_setting('m08.c')::uuid;
SELECT pg_temp.m08_error(format('INSERT INTO public.fiscal_provider_attempts(tenant_id,request_id,attempt_no,started_at,completed_at,provider_code,normalized_result) SELECT tenant_id,id,2,now(),now(),''soft_management'',''{"outcome":"processing"}'' FROM public.fiscal_requests WHERE billing_cfdi_id=%L',current_setting('m08.c')),'23514','fiscal_attempt_origin_conflict');
SET LOCAL ROLE rotero_fiscal_policy_owner;
SELECT pg_temp.m08_check((SELECT provider_code='facturama' AND environment='sandbox' FROM private.fiscal_request_origins WHERE cfdi_id=current_setting('m08.c')::uuid),'request retains exact original provider and environment');
RESET ROLE;
SELECT 'PASS: owner/API ACL, explicit company configuration, sandbox restriction, immutable provider/environment, namespaced IDs and uncertain single lane';
-- Existing sandbox origin remains usable after a future selection changes.
-- Only simulated database worker results; no transport/issuance/cancellation.
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,current_setting('m08.b')::uuid,current_setting('m08.admin')::uuid);
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,current_setting('m08.b')::uuid,code,'synthetic-lab',current_setting('m08.admin')::uuid
 FROM unnest(ARRAY['fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','companies.manage']) code;
INSERT INTO private.fiscal01_lab_actors(tenant_id,user_id,expires_at,approval_reference)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.u')::uuid,now()+interval '1 hour','synthetic');
INSERT INTO private.fiscal01_company_bindings(tenant_id,company_id,issuer_rfc,enabled,approval_reference)
 VALUES(current_setting('m08.t')::uuid,current_setting('m08.b')::uuid,'EKU9003173C9',true,'synthetic');
DO $lab$ DECLARE id uuid; payload jsonb; r jsonb; BEGIN
 INSERT INTO public.billing_cfdis(tenant_id,rfc_emisor,rfc_receptor,serie,folio,subtotal,total,status)
  VALUES(current_setting('m08.t')::uuid,'EKU9003173C9','URE180429TM6','M08','SYNTHETIC',100,116,'draft') RETURNING public.billing_cfdis.id INTO id;
 INSERT INTO private.fiscal01_draft_scope(cfdi_id,tenant_id,company_id,approval_reference)
  VALUES(id,current_setting('m08.t')::uuid,current_setting('m08.b')::uuid,'synthetic');
 payload:='{"Issuer":{"Rfc":"EKU9003173C9"},"Receiver":{"Rfc":"URE180429TM6"},"CfdiType":"I","Serie":"M08","Folio":"SYNTHETIC","Date":"2026-10-26T12:00:00"}';
 r:=public.rpc_fiscal01_worker(id,current_setting('m08.u')::uuid,'prepare',jsonb_build_object('company_id',current_setting('m08.b'),'payload',payload));
 PERFORM pg_temp.m08_check(r->>'prepared'='true','existing sandbox compatibility prepare');
 PERFORM set_config('m08.lab',id::text,true);
END $lab$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.b')::uuid,'soft_management','sandbox','synthetic-change')->>'enabled'='false','lab future selection stays disabled');
SELECT pg_temp.m08_check(public.rpc_fiscal01_context(current_setting('m08.lab')::uuid)#>>'{future_provider,code}'='soft_management','same UI reports future selection');
SELECT pg_temp.m08_check(public.rpc_fiscal01_context(current_setting('m08.lab')::uuid)#>>'{actions,issue}'='false','UI does not imply configured means enabled');
RESET ROLE;
SELECT pg_temp.m08_error(format('SELECT public.rpc_fiscal01_worker(%L,%L,''claim'',''{}'')',current_setting('m08.lab'),current_setting('m08.u')),'23514','company_fiscal_transport_disabled');
SELECT pg_temp.m08_check(public.rpc_fiscal01_worker(current_setting('m08.lab')::uuid,current_setting('m08.u')::uuid,'load')->>'cfdi_id'=current_setting('m08.lab'),'historical origin still loads');
DO $status$ DECLARE r jsonb; BEGIN
 r:=public.rpc_fiscal01_worker(current_setting('m08.lab')::uuid,current_setting('m08.u')::uuid,'status');
 PERFORM pg_temp.m08_check(r->>'busy_token' IS NOT NULL,'status lease remains origin route');
 PERFORM public.rpc_fiscal01_worker(current_setting('m08.lab')::uuid,current_setting('m08.u')::uuid,'release',jsonb_build_object('busy_token',r->>'busy_token'));
END $status$;
SET LOCAL ROLE rotero_fiscal_policy_owner;
SELECT pg_temp.m08_check((SELECT provider_code='facturama' AND environment='sandbox' FROM private.fiscal_document_origins WHERE cfdi_id=current_setting('m08.lab')::uuid),'future Soft selection did not alter original Facturama');
RESET ROLE;
SELECT 'PASS: existing Facturama lab origin/read/status survives future Soft selection; new stamp denied in backend and UI';
-- Prove RLS independently from ACL with actual rows present. These temporary
-- grants are revoked here and also rolled back with the complete fixture.
SET LOCAL ROLE rotero_fiscal_policy_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.company_fiscal_provider_configs,private.fiscal_document_origins,private.fiscal_stamp_lanes,private.fiscal_request_origins TO authenticated;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_check((SELECT count(*)=0 FROM private.company_fiscal_provider_configs),'RLS config rows remain hidden under accidental SELECT grant');
SELECT pg_temp.m08_check((SELECT count(*)=0 FROM private.fiscal_document_origins),'RLS origin rows remain hidden under accidental SELECT grant');
SELECT pg_temp.m08_check((SELECT count(*)=0 FROM private.fiscal_stamp_lanes),'RLS lane rows remain hidden under accidental SELECT grant');
SELECT pg_temp.m08_check((SELECT count(*)=0 FROM private.fiscal_request_origins),'RLS request binding rows remain hidden under accidental SELECT grant');
SELECT pg_temp.m08_error(format('INSERT INTO private.company_fiscal_provider_configs(tenant_id,company_id,provider_code,environment,configured_by,approval_reference) VALUES(%L,%L,''facturama'',''sandbox'',%L,''self'')',current_setting('m08.x'),current_setting('m08.xc'),current_setting('m08.u')),'42501');
RESET ROLE;
SET LOCAL ROLE rotero_fiscal_policy_owner;
REVOKE SELECT,INSERT,UPDATE,DELETE ON private.company_fiscal_provider_configs,private.fiscal_document_origins,private.fiscal_stamp_lanes,private.fiscal_request_origins FROM authenticated;
RESET ROLE;
SELECT 'PASS: effective RLS under accidental grants; grants removed again';
UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by=current_setting('m08.admin')::uuid WHERE user_id=current_setting('m08.u')::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m08_check(public.rpc_configure_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid,'soft_management','sandbox','revoked')->>'error'='unauthorized','revocation invalidates administrative selection');
SELECT pg_temp.m08_check(public.rpc_get_company_fiscal_provider(current_setting('m08.t')::uuid,current_setting('m08.a')::uuid)->>'error'='unauthorized','revocation invalidates read');
RESET ROLE;
SELECT 'PASS: configuration and grants roll back, no provider transport or real identity';
ROLLBACK;
