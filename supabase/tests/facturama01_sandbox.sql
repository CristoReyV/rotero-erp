\set ON_ERROR_STOP on
BEGIN;
-- Local only: all identities/data are synthetic and transactionally removed.
-- The restored staging shape has an audit actor FK to Auth, unlike the canonical
-- replay. In that shape only, create inert UUID stubs in this same transaction;
-- no password, login, session, email, remote Auth call or persistent identity.
DO $audit_actor_fixture$ BEGIN
 IF EXISTS(SELECT FROM pg_constraint WHERE conrelid='public.audit_log'::regclass AND confrelid='auth.users'::regclass AND contype='f') THEN
  INSERT INTO auth.users(id) VALUES
   ('61000000-0000-4000-8000-000000000301'),('61000000-0000-4000-8000-000000000302'),('61000000-0000-4000-8000-000000000303');
 END IF;
END $audit_actor_fixture$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FACTURAMA01 failed: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.error_it(q text,state text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>state THEN RAISE EXCEPTION 'expected %, got %: %',state,SQLSTATE,SQLERRM; END IF; RETURN; END; RAISE EXCEPTION 'expected denial: %',state; END $$;
INSERT INTO public.tenants(id,name,slug) VALUES('61000000-0000-4000-8000-000000000101','Synthetic fiscal QA','synthetic-fiscal-qa'),('61000000-0000-4000-8000-000000000102','Synthetic other tenant','synthetic-fiscal-other');
INSERT INTO public.memberships(user_id,tenant_id,role) VALUES
 ('61000000-0000-4000-8000-000000000301','61000000-0000-4000-8000-000000000101','finance'),
 ('61000000-0000-4000-8000-000000000302','61000000-0000-4000-8000-000000000101','admin'),
 ('61000000-0000-4000-8000-000000000303','61000000-0000-4000-8000-000000000102','finance');
SET LOCAL ROLE rotero_company_access_owner;
INSERT INTO public.companies(id,tenant_id,display_name,legal_name,rfc_normalized,status) VALUES
 ('61000000-0000-4000-8000-000000000201','61000000-0000-4000-8000-000000000101','Synthetic A','Synthetic legal A','AAA010101AA1','active'),
 ('61000000-0000-4000-8000-000000000202','61000000-0000-4000-8000-000000000101','Synthetic B','Synthetic legal B','BBB010101BB1','active'),
 ('61000000-0000-4000-8000-000000000203','61000000-0000-4000-8000-000000000102','Synthetic X','Synthetic legal X','CCC010101CC1','active');
INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
 VALUES('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000301','61000000-0000-4000-8000-000000000201','61000000-0000-4000-8000-000000000302');
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT '61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000301','61000000-0000-4000-8000-000000000201',code,'synthetic-fiscal-only','61000000-0000-4000-8000-000000000302' FROM unnest(ARRAY['fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment']) code;
RESET ROLE;
INSERT INTO private.fiscal01_company_bindings(tenant_id,company_id,issuer_rfc,enabled,approval_reference)
 SELECT tenant_id,id,'EKU9003173C9',true,'synthetic-lab-only' FROM public.companies
 WHERE tenant_id IN ('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000102');
INSERT INTO private.fiscal01_lab_actors(tenant_id,user_id,expires_at,approval_reference)
 SELECT tenant_id,user_id,now()+interval '1 hour','synthetic-lab-only' FROM public.memberships WHERE user_id IN ('61000000-0000-4000-8000-000000000301','61000000-0000-4000-8000-000000000302');
INSERT INTO public.billing_cfdis(id,tenant_id,rfc_emisor,rfc_receptor,serie,folio,subtotal,total,status,fiscal_input)
 SELECT ('61000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 '61000000-0000-4000-8000-000000000101','EKU9003173C9','URE180429TM6','QATEST','QA-'||n,100,116,'draft',
 '{"concepts":[{"amount":100,"description":"Synthetic service"}],"payment":{"method":"PPD"}}'::jsonb FROM generate_series(401,407) n;
UPDATE public.billing_cfdis SET has_complemento_pago=true,total=0,subtotal=0 WHERE folio IN ('QA-405','QA-406','QA-407');
INSERT INTO private.fiscal01_draft_scope(cfdi_id,tenant_id,company_id,approval_reference)
 SELECT id,tenant_id,CASE WHEN folio='QA-403' THEN '61000000-0000-4000-8000-000000000202'::uuid ELSE '61000000-0000-4000-8000-000000000201'::uuid END,'synthetic-explicit-source' FROM public.billing_cfdis WHERE tenant_id='61000000-0000-4000-8000-000000000101';

DO $acl$ DECLARE role_name text; rel text; BEGIN
 FOREACH rel IN ARRAY ARRAY['fiscal01_company_bindings','fiscal01_lab_actors','fiscal01_documents','fiscal01_draft_scope','fiscal01_invoice_links','fiscal01_receipts','fiscal01_applications'] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.check_it(NOT has_table_privilege(role_name,'private.'||rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'closed table effective ACL');
  END LOOP;
  PERFORM pg_temp.check_it((SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||rel)::regclass),'RLS enabled');
 END LOOP;
 PERFORM pg_temp.check_it(NOT has_function_privilege('authenticated','public.rpc_fiscal01_worker(uuid,uuid,text,jsonb)','EXECUTE'),'worker not public');
 PERFORM pg_temp.check_it(has_function_privilege('service_role','public.rpc_fiscal01_worker(uuid,uuid,text,jsonb)','EXECUTE'),'server worker available');
 PERFORM pg_temp.check_it(NOT(SELECT public FROM storage.buckets WHERE id='fiscal-sandbox'),'private bucket');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'private.fiscal01_guard()','EXECUTE'),'no direct trigger helper execute');
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'private.fiscal01_guard_canonical()','EXECUTE'),'no direct privileged guard execute');
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'private.fiscal02_set_worker(uuid,uuid,text)','EXECUTE'),'no public marker setter');
  PERFORM pg_temp.check_it(NOT has_function_privilege(role_name,'private.fiscal02_worker_company(uuid,uuid)','EXECUTE'),'no public marker capability oracle');
  PERFORM pg_temp.check_it(NOT has_table_privilege(role_name,'private.fiscal02_readable_cfdis','SELECT'),'no direct view route');
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM pg_temp.check_it(NOT has_table_privilege(role_name,'public.billing_cfdis','SELECT,INSERT,UPDATE,DELETE'),'ordinary direct CFDI routes closed');
  PERFORM pg_temp.check_it(NOT has_table_privilege(role_name,'public.finance_invoices','SELECT,INSERT,UPDATE,DELETE'),'ordinary direct finance routes closed');
 END LOOP;
END $acl$;
SELECT 'PASS effective ACLs, RLS and separate private bucket';
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000302',true);
SELECT pg_temp.check_it(NOT(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000401')?'cfdi_id'),'admin denied without causing global Auth logout');
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000301',true);
SELECT pg_temp.check_it(NOT private.multi05_has_company_capability('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000201','financial.full.read'),'QA not given financial full read');
SELECT pg_temp.check_it(NOT(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000403')?'cfdi_id'),'cross-company context denied');
SELECT pg_temp.check_it(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000401')->>'environment'='sandbox','explicit task read');
SELECT pg_temp.error_it($q$ SELECT public.rpc_fiscal01_worker('61000000-0000-4000-8000-000000000401','61000000-0000-4000-8000-000000000301','prepare','{"company_id":"61000000-0000-4000-8000-000000000202","payload":{}}') $q$,'42501');
SELECT 'PASS no role shortcut, financial full, cross-company or remapping';
SELECT pg_temp.check_it(public.rpc_get_cfdi_detail('61000000-0000-4000-8000-000000000401')->>'id'='61000000-0000-4000-8000-000000000401','explicit fiscal reader uses existing Billing detail');
SELECT pg_temp.check_it(public.rpc_get_cfdi_detail('61000000-0000-4000-8000-000000000403')->>'id' IS NULL,'legacy detail cannot bypass company access');
SELECT pg_temp.check_it(public.rpc_get_fiscal_readiness('61000000-0000-4000-8000-000000000403')->>'error' IS NOT NULL,'legacy readiness cannot bypass company access');
SELECT pg_temp.check_it(NOT EXISTS(SELECT FROM jsonb_array_elements(public.rpc_list_cfdis('61000000-0000-4000-8000-000000000101','{}')) r WHERE r->>'id'='61000000-0000-4000-8000-000000000403'),'legacy list filters before returning rows');
-- Canonical RPC propagates 42501; the inspected staging variant catches it
-- and returns the same guard message as JSON. Require the exact denial plus
-- unchanged data, then test the SQL route independently; no accepted success.
DO $legacy_denial$ DECLARE result jsonb; before_notes text;
BEGIN
 SELECT notes INTO before_notes FROM public.billing_cfdis WHERE id='61000000-0000-4000-8000-000000000404';
 BEGIN
  result:=public.rpc_update_cfdi('61000000-0000-4000-8000-000000000404','{"notes":"must not change laboratory source"}');
  PERFORM pg_temp.check_it(result->>'error'='sandbox_requires_guarded_worker','legacy error envelope must contain exact authorization denial');
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM pg_temp.check_it((SELECT notes IS NOT DISTINCT FROM before_notes FROM public.billing_cfdis WHERE id='61000000-0000-4000-8000-000000000404'),'denied legacy call changed no row');
END $legacy_denial$;
SELECT pg_temp.error_it($q$ UPDATE public.billing_cfdis SET notes='direct route must not write' WHERE id='61000000-0000-4000-8000-000000000404' $q$,'42501');
SELECT 'PASS legacy Billing detail/list and mutation routes are scoped for laboratory documents';
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000303',true);
SELECT pg_temp.check_it(NOT(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000401')?'cfdi_id'),'cross-tenant context denied');
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000301',true);
SELECT pg_temp.error_it($q$ UPDATE private.fiscal01_draft_scope SET tenant_id='61000000-0000-4000-8000-000000000102',company_id='61000000-0000-4000-8000-000000000203' WHERE cfdi_id='61000000-0000-4000-8000-000000000401' $q$,'23514');

-- Simulated trusted worker results only. Real XML/provider verification is in TS.
DO $flow$ DECLARE n int; id uuid; payload jsonb; lease jsonb; again jsonb; before_hash text; BEGIN
 FOR n IN 401..402 LOOP
  id:=('61000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;
  payload:=jsonb_build_object('Issuer',jsonb_build_object('Rfc','EKU9003173C9'),'Receiver',jsonb_build_object('Rfc','URE180429TM6'),'CfdiType','I','Serie','QATEST','Folio','QA-'||n,'Date','2026-10-23T12:00:00');
  PERFORM public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','prepare',jsonb_build_object('company_id','61000000-0000-4000-8000-000000000201','payload',payload));
  lease:=public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','claim');
  again:=public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','claim');
  PERFORM pg_temp.check_it((again->>'busy')::boolean,'second claim cannot send');
  PERFORM public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','identified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-'||n));
  PERFORM public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','verified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-'||n,'uuid',id::text,'stamped_at','2026-10-23T12:00:01','xml_path','61000000-0000-4000-8000-000000000101/61000000-0000-4000-8000-000000000201/'||id||'/invoice.xml','xml_sha256',repeat('a',64)));
  PERFORM pg_temp.check_it((public.rpc_fiscal01_worker(id,'61000000-0000-4000-8000-000000000301','claim')->>'reconcile_required')::boolean,'no second emission after success');
  PERFORM pg_temp.error_it(format('UPDATE private.fiscal01_documents SET provider_payload=provider_payload||''{"Folio":"other"}''::jsonb WHERE cfdi_id=%L',id),'23514');
 END LOOP;
END $flow$;
SELECT pg_temp.check_it((SELECT count(*)=2 FROM public.fiscal_requests WHERE tenant_id='61000000-0000-4000-8000-000000000101'),'canonical FISCAL0 queue reused');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM public.fiscal_provider_attempts WHERE tenant_id='61000000-0000-4000-8000-000000000101'),'canonical attempt history reused');
SELECT 'PASS frozen payload, lease, queue, attempts and no double issuance';
-- The public route guard rejects ordinary writes first. Exercise the separate
-- immutable-source invariant inside the same private worker boundary as server.
SELECT private.fiscal02_set_worker('61000000-0000-4000-8000-000000000401','61000000-0000-4000-8000-000000000301','issue');
SELECT pg_temp.error_it($q$ UPDATE public.billing_cfdis SET total=117 WHERE id='61000000-0000-4000-8000-000000000401' $q$,'23514');
SELECT pg_temp.error_it($q$ UPDATE public.billing_cfdis SET rfc_emisor='WLS110325JH8' WHERE id='61000000-0000-4000-8000-000000000401' $q$,'23514');
SELECT 'PASS legacy source edits cannot invalidate frozen fiscal correspondence';

INSERT INTO public.finance_invoices(id,tenant_id,direction,counterparty_name,amount,currency,status,linked_cfdi_id)
 SELECT ('61000000-0000-4000-8000-'||lpad((replace(folio,'QA-','')::int+100)::text,12,'0'))::uuid,tenant_id,'ar','Synthetic receiver',total,'MXN','open',id FROM public.billing_cfdis WHERE folio IN ('QA-401','QA-402');
INSERT INTO private.fiscal01_invoice_links(finance_invoice_id,tenant_id,company_id,cfdi_id)
 SELECT id,tenant_id,'61000000-0000-4000-8000-000000000201',linked_cfdi_id FROM public.finance_invoices WHERE tenant_id='61000000-0000-4000-8000-000000000101';
SELECT public.rpc_fiscal01_record_payment('61000000-0000-4000-8000-000000000405','61000000-0000-4000-8000-000000000301','2026-10-23T12:00:00','[{"invoice_id":"61000000-0000-4000-8000-000000000501","amount":58}]');
SELECT public.rpc_fiscal01_record_payment('61000000-0000-4000-8000-000000000406','61000000-0000-4000-8000-000000000301','2026-10-23T12:01:00','[{"invoice_id":"61000000-0000-4000-8000-000000000501","amount":58},{"invoice_id":"61000000-0000-4000-8000-000000000502","amount":116}]');
SELECT pg_temp.check_it((SELECT fiscal_input#>>'{payment_payload,Receiver,Name}'=U&'UNIVERSIDAD ROBOTICA ESPA\00D1OLA' FROM public.billing_cfdis WHERE id='61000000-0000-4000-8000-000000000406'),'official test receiver preserved as UTF-8');
SELECT pg_temp.check_it((SELECT previous_balance=58 AND remaining=0 AND partiality=2 FROM private.fiscal01_applications WHERE invoice_cfdi_id='61000000-0000-4000-8000-000000000401' AND partiality=2),'partial payment frozen balances');
SELECT pg_temp.check_it((SELECT count(*)=3 FROM public.finance_payments WHERE tenant_id='61000000-0000-4000-8000-000000000101'),'one receipt, multiple existing finance payments');
SELECT pg_temp.check_it((SELECT bool_and(status='paid') FROM public.finance_invoices WHERE tenant_id='61000000-0000-4000-8000-000000000101'),'F4 settled-invoice rule preserved');
SELECT pg_temp.check_it((public.rpc_fiscal01_record_payment('61000000-0000-4000-8000-000000000406','61000000-0000-4000-8000-000000000301','2026-10-23T12:01:00','[]')->>'already_recorded')::boolean,'duplicate receipt cannot duplicate applications');
SELECT pg_temp.error_it($q$ SELECT public.rpc_fiscal01_record_payment('61000000-0000-4000-8000-000000000407','61000000-0000-4000-8000-000000000301','2026-10-23T12:02:00','[{"invoice_id":"61000000-0000-4000-8000-000000000501","amount":1}]') $q$,'23514');
SELECT 'PASS partial and multiple-invoice applications, balances and duplicate guard';
SELECT set_config('fiscal02.cfdi','',true);
SELECT pg_temp.check_it(NOT COALESCE(jsonb_path_exists(public.rpc_get_finance_invoice_detail('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000501'),'$.**.amount'),false),'sandbox invoices absent from legacy finance detail');
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000302',true);
SELECT pg_temp.check_it(NOT COALESCE(jsonb_path_exists(public.rpc_export_data_page('61000000-0000-4000-8000-000000000101','finance_ar','{}','{}',100),'$.**.amount'),false),'sandbox invoices absent from legacy finance CSV source even for admin');
SELECT set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000301',true);
SELECT 'PASS sandbox finance separated from legacy detail and export; no full-financial grant';
-- Task capabilities stay distinct: the trusted issue flow does not acquire a
-- general read grant merely because legacy readers are now filtered.
SET LOCAL ROLE rotero_company_access_owner;
UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by='61000000-0000-4000-8000-000000000302'
 WHERE user_id='61000000-0000-4000-8000-000000000301' AND capability_code='fiscal.read';
RESET ROLE;
DO $issue_without_read$ DECLARE id uuid:='61000000-0000-4000-8000-000000000404'; actor uuid:='61000000-0000-4000-8000-000000000301'; lease jsonb; payload jsonb; BEGIN
 payload:=jsonb_build_object('Issuer',jsonb_build_object('Rfc','EKU9003173C9'),'Receiver',jsonb_build_object('Rfc','URE180429TM6'),'CfdiType','I','Serie','QATEST','Folio','QA-404','Date','2026-10-23T12:00:00');
 PERFORM public.rpc_fiscal01_worker(id,actor,'prepare',jsonb_build_object('company_id','61000000-0000-4000-8000-000000000201','payload',payload));
 lease:=public.rpc_fiscal01_worker(id,actor,'claim');
 PERFORM public.rpc_fiscal01_worker(id,actor,'identified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-404'));
 PERFORM public.rpc_fiscal01_worker(id,actor,'verified',jsonb_build_object('busy_token',lease->>'busy_token','provider_document_id','synthetic-404','uuid',id,'stamped_at','2026-10-23T12:00:01','xml_path','61000000-0000-4000-8000-000000000101/61000000-0000-4000-8000-000000000201/'||id||'/invoice.xml','xml_sha256',repeat('d',64)));
 PERFORM set_config('fiscal02.cfdi','',true);
 PERFORM pg_temp.check_it(public.rpc_get_cfdi_detail(id)->>'id' IS NULL,'issue capability does not authorize legacy read');
END $issue_without_read$;
SET LOCAL ROLE rotero_company_access_owner;
UPDATE public.membership_company_capabilities SET status='active',revoked_at=NULL,revoked_by=NULL
 WHERE user_id='61000000-0000-4000-8000-000000000301' AND capability_code='fiscal.read';
RESET ROLE;
SELECT 'PASS explicit issue works without adding read or full-financial capability';

-- FACTURAMA-02: confirmed remote cancellation and XML identity remain distinct.
DO $cancel_states$ DECLARE lease jsonb; id uuid:='61000000-0000-4000-8000-000000000401'; actor uuid:='61000000-0000-4000-8000-000000000301'; BEGIN
 lease:=public.rpc_fiscal01_worker(id,actor,'cancel','{"motive":"03"}');
 PERFORM pg_temp.error_it(format('SELECT public.rpc_fiscal01_worker(%L,%L,''cancel_confirmed'',%L::jsonb)',id,actor,jsonb_build_object('busy_token',lease->>'busy_token','uuid','wrong','provider_document_id','synthetic-401')),'23514');
 PERFORM public.rpc_fiscal01_worker(id,actor,'cancel_confirmed',jsonb_build_object('busy_token',lease->>'busy_token','uuid',id,'provider_document_id','synthetic-401'));
 PERFORM public.rpc_fiscal01_worker(id,actor,'cancel_ack_invalid',jsonb_build_object('busy_token',lease->>'busy_token','ack_sha256',repeat('b',64)));
 PERFORM public.rpc_fiscal01_worker(id,actor,'release',jsonb_build_object('busy_token',lease->>'busy_token'));
 PERFORM pg_temp.check_it((public.rpc_fiscal01_context(id)->>'remote_cancel_status')='canceled','remote confirmation persisted');
 PERFORM pg_temp.check_it((public.rpc_fiscal01_context(id)->>'cancellation_ack_state')='mismatch','foreign acknowledgement not approved');
 PERFORM pg_temp.check_it(NOT(public.rpc_fiscal01_context(id)->>'cancellation_available')::boolean,'foreign acknowledgement unavailable');
 PERFORM pg_temp.check_it((public.rpc_fiscal01_worker(id,actor,'cancel','{"motive":"03"}')->>'cancellation_pending')::boolean,'no automatic cancellation resubmission');
 lease:=public.rpc_fiscal01_worker(id,actor,'cancel','{"motive":"02","recover_ack":true}');
 PERFORM pg_temp.check_it(lease#>>'{cancellation_options,motive}'='03','recovery uses original cancellation parameters');
 PERFORM public.rpc_fiscal01_worker(id,actor,'release',jsonb_build_object('busy_token',lease->>'busy_token'));
END $cancel_states$;
SELECT 'PASS remote confirmation, strict XML pending, explicit recovery without issuance';

-- In a combined candidate, use MULTI-07 evidence, never infer a company. This
-- branch is absent in the standalone M04/05+fiscal deployment, not a fake grant.
SELECT to_regclass('private.finance_invoices_company_evidence') IS NOT NULL AS has_multi07 \gset
\if :has_multi07
SET LOCAL ROLE rotero_finance_scope_owner;
INSERT INTO private.finance_invoices_company_evidence(id,tenant_id,entity_id,company_id,decision,evidence_kind,evidence_reference,recorded_by) VALUES
 ('61000000-0000-4000-8000-000000000991','61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000501','61000000-0000-4000-8000-000000000201','resolved','verified_source_record','FACTURAMA02 synthetic A','61000000-0000-4000-8000-000000000302'),
 ('61000000-0000-4000-8000-000000000992','61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000501','61000000-0000-4000-8000-000000000202','resolved','verified_source_record','FACTURAMA02 synthetic B','61000000-0000-4000-8000-000000000302');
RESET ROLE;
UPDATE public.finance_invoices SET company_id='61000000-0000-4000-8000-000000000201',company_classification_status='resolved',company_classification_event_id='61000000-0000-4000-8000-000000000991' WHERE id='61000000-0000-4000-8000-000000000501';
SELECT pg_temp.error_it($q$ UPDATE public.finance_invoices SET company_id='61000000-0000-4000-8000-000000000202',company_classification_status='resolved',company_classification_event_id='61000000-0000-4000-8000-000000000992' WHERE id='61000000-0000-4000-8000-000000000501' $q$,'23514');
SELECT pg_temp.error_it($q$ UPDATE private.fiscal01_draft_scope SET company_id='61000000-0000-4000-8000-000000000202' WHERE cfdi_id='61000000-0000-4000-8000-000000000401' $q$,'23514');
SELECT pg_temp.check_it((SELECT company_id IS NULL FROM public.finance_invoices WHERE id='61000000-0000-4000-8000-000000000502'),'pending history is not backfilled');
SELECT 'PASS combined MULTI07 known company and fiscal company cannot disagree';
\endif

-- Effective direct API denial, no self-assignment or arbitrary server calls.
SET LOCAL ROLE authenticated;
SELECT pg_temp.error_it($q$ INSERT INTO private.fiscal01_lab_actors VALUES('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000302',now()+interval '1 day','self') $q$,'42501');
SELECT pg_temp.error_it($q$ SELECT public.rpc_fiscal01_worker('61000000-0000-4000-8000-000000000401','61000000-0000-4000-8000-000000000301','claim') $q$,'42501');
RESET ROLE;
SET LOCAL ROLE rotero_company_access_owner;
UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by='61000000-0000-4000-8000-000000000302' WHERE user_id='61000000-0000-4000-8000-000000000301';
RESET ROLE;
SELECT pg_temp.check_it(NOT(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000401')?'cfdi_id'),'revoked context denied');
SELECT 'PASS direct-route denial, self-assignment blocked and effective revocation';
SET LOCAL ROLE rotero_company_access_owner;
UPDATE public.membership_company_access SET status='active',revoked_at=NULL,revoked_by=NULL WHERE user_id='61000000-0000-4000-8000-000000000301';
UPDATE public.companies SET status='inactive' WHERE id='61000000-0000-4000-8000-000000000201';
RESET ROLE;
SELECT pg_temp.check_it(NOT(public.rpc_fiscal01_context('61000000-0000-4000-8000-000000000401')?'cfdi_id'),'inactive company invalidates fiscal read');
-- Prove RLS denial even under accidental grants, then roll the grants back.
GRANT SELECT,INSERT,UPDATE ON private.fiscal01_lab_actors TO authenticated;
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_it((SELECT count(*)=0 FROM private.fiscal01_lab_actors),'RLS effective SELECT denial');
SELECT pg_temp.error_it($q$ INSERT INTO private.fiscal01_lab_actors VALUES('61000000-0000-4000-8000-000000000101','61000000-0000-4000-8000-000000000303',now()+interval '1 day','self') $q$,'42501');
RESET ROLE;
SELECT 'PASS inactive company and RLS under temporary accidental grants';
ROLLBACK;
