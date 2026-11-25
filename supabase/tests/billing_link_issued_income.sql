\set ON_ERROR_STOP on
-- Disposable local DB only. All identities, grants, rows and objects roll back.
BEGIN;
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'delivery assertion: %',label; END IF;
 PERFORM set_config('d.assertions',(COALESCE(NULLIF(current_setting('d.assertions',true),''),'0')::int+1)::text,true);
END $$;
CREATE FUNCTION pg_temp.actor(u uuid,c uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated',
 'iss','https://synthetic-access.invalid/auth/v1','user_metadata',jsonb_build_object('financial_full',true))::text,true);
 PERFORM set_config('request.headers',CASE WHEN c IS NULL THEN '{}' ELSE jsonb_build_object('x-rotero-scope','company','x-rotero-company-id',c) END::text,true);
END $$;
SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
 public.membership_company_capabilities,private.financial_principal_bindings TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
GRANT SELECT,INSERT ON private.operation_company_classification_events TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_finance_scope_owner;
GRANT SELECT,INSERT ON private.finance_invoices_company_evidence,private.billing_documents_company_evidence TO postgres;
RESET ROLE;
CREATE FUNCTION pg_temp.resolve(root text,entity uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t uuid;e uuid;ledger text;idcol text;
BEGIN
 IF root NOT IN('operations','finance_invoices','billing_documents') THEN RAISE EXCEPTION 'fixture root'; END IF;
 EXECUTE format('SELECT tenant_id FROM public.%I WHERE id=$1',root) INTO t USING entity;
 ledger:=CASE root WHEN 'operations' THEN 'operation_company_classification_events' ELSE root||'_company_evidence' END;
 idcol:=CASE root WHEN 'operations' THEN 'operation_id' ELSE 'entity_id' END;
 EXECUTE format('INSERT INTO private.%I(tenant_id,%I,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES($1,$2,$3,''resolved'',''verified_source_record'',''synthetic-only'',$4) RETURNING id',ledger,idcol)
 INTO e USING t,entity,c,current_setting('d.u')::uuid;
 EXECUTE format('UPDATE public.%I SET company_id=$1,company_classification_status=''resolved'',company_classification_event_id=$2 WHERE id=$3',root)
 USING c,e,entity;
END $$;
DO $fixtures$
DECLARE t uuid; a uuid; b uuid; operator_id uuid := gen_random_uuid(); accountant uuid := gen_random_uuid();
 partial uuid := gen_random_uuid(); binding uuid; op uuid; ref text; e uuid; fiscal_uuid uuid := gen_random_uuid();
 cfdi uuid; cancelled uuid; doc uuid; receivable uuid; file_id uuid; xml_bytes bytea;
BEGIN
 INSERT INTO public.tenants(name,slug) VALUES('Synthetic multifolio','multifolio-local') RETURNING id INTO t;
 INSERT INTO auth.users(id,email) SELECT id,id||'@example.test' FROM unnest(ARRAY[operator_id,accountant,partial]) AS ids(id);
 INSERT INTO public.memberships(tenant_id,user_id,role)
 VALUES(t,operator_id,'operator'),(t,accountant,'finance'),(t,partial,'finance');
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
 VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status)
 VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
 INSERT INTO private.delivery_tenant_cutovers(tenant_id,enabled,approval_reference,approved_by)
 VALUES(t,true,'synthetic-only',accountant);
 INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by)
 SELECT t,id,a,accountant FROM unnest(ARRAY[operator_id,accountant,partial]) AS ids(id);
 INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,
  identity_issuer,approval_reference,verified_by,verified_at)
 VALUES(t,accountant,'approved_financial_01','verified_human','https://synthetic-access.invalid/auth/v1',
  'synthetic-only',accountant,now()-interval '1 minute') RETURNING id INTO binding;
 INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
 SELECT t,user_id,a,cap,CASE WHEN cap='financial.full.read' THEN binding END,'synthetic-only',accountant
 FROM (VALUES(operator_id,'operations.read'),(operator_id,'operations.transition'),
  (accountant,'financial.full.read'),(accountant,'finance.write'),(accountant,'billing.document.read'),(partial,'finance.write')) AS grants(user_id,cap);
 PERFORM set_config('d.u',accountant::text,true);
 FOREACH ref IN ARRAY ARRAY['A1','A2','B1','A10','A3','A4','a1'] LOOP
  INSERT INTO public.operations(tenant_id,reference_code,status) VALUES(t,ref,CASE WHEN ref='A3' THEN 'planned' ELSE 'delivered' END) RETURNING id INTO op;
  PERFORM pg_temp.resolve('operations',op,CASE WHEN ref='B1' THEN b ELSE a END);
  IF ref<>'a1' THEN PERFORM set_config('d.'||lower(ref),op::text,true); END IF;
 END LOOP;
 INSERT INTO public.operation_billing(tenant_id,operation_id,status) VALUES(t,current_setting('d.a2')::uuid,'draft');

 INSERT INTO public.billing_cfdis(tenant_id,uuid,rfc_emisor,rfc_receptor,subtotal,total,status,issued_at,fiscal_status,fiscal_stamped_at)
 VALUES(t,fiscal_uuid::text,'AAA010101AA1','CCC010101CC1',100,116,'timbrado',now(),'stamped',now()) RETURNING id INTO cfdi;
 INSERT INTO public.billing_cfdis(tenant_id,uuid,rfc_emisor,rfc_receptor,subtotal,total,status,issued_at,fiscal_status,fiscal_stamped_at,fiscal_cancelled_at)
 VALUES(t,gen_random_uuid()::text,'AAA010101AA1','CCC010101CC1',100,116,'cancelado',now(),'cancelled',now(),now()) RETURNING id INTO cancelled;
 FOR op IN SELECT id FROM public.billing_cfdis WHERE id IN(cfdi,cancelled) LOOP
  INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,evidence_reference,recorded_by)
  VALUES(t,'billing_cfdis',op,a,'synthetic-only',accountant) RETURNING id INTO e;
  UPDATE public.billing_cfdis SET company_id=a,company_classification_status='resolved',company_classification_event_id=e WHERE id=op;
 END LOOP;

 xml_bytes:=convert_to(format(
  '<cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" xmlns:tfd="http://www.sat.gob.mx/TimbreFiscalDigital" Version="4.0" TipoDeComprobante="I" Moneda="MXN" Total="116.00">
   <cfdi:Emisor Rfc="AAA010101AA1"/><cfdi:Receptor Rfc="CCC010101CC1"/>
   <cfdi:Conceptos><cfdi:Concepto NoIdentificacion="A1" Descripcion="A10"/><cfdi:Concepto NoIdentificacion="A2"/>
   <cfdi:Concepto NoIdentificacion="B1"/><cfdi:Concepto NoIdentificacion="A3"/><cfdi:Concepto NoIdentificacion="A4"/></cfdi:Conceptos>
   <cfdi:Complemento><tfd:TimbreFiscalDigital UUID="%s"/></cfdi:Complemento>
   </cfdi:Comprobante>',fiscal_uuid),'UTF8');
 INSERT INTO public.document_files(tenant_id,storage_bucket,storage_path,file_name,mime_type,size_bytes,checksum_sha256,
  file_kind,source_module,source_entity_type,source_entity_id,status)
 VALUES(t,'tenant-documents',t||'/billing/'||cfdi||'/synthetic.xml','synthetic.xml','application/xml',octet_length(xml_bytes),
  encode(sha256(xml_bytes),'hex'),'fiscal_xml','billing','billing_cfdi',cfdi,'active') RETURNING id INTO file_id;
 INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,access_class,evidence_reference,recorded_by)
 VALUES(t,'document_files',file_id,a,'financial','synthetic-only',accountant) RETURNING id INTO e;
 UPDATE public.document_files SET company_id=a,company_classification_status='resolved',company_classification_event_id=e,access_class='financial'
 WHERE id=file_id;
 UPDATE public.billing_cfdis SET xml_document_file_id=file_id WHERE id=cfdi;

 INSERT INTO public.billing_documents(tenant_id,linked_cfdi_id,status,subtotal,total,created_by)
 VALUES(t,cfdi,'stamped',100,116,accountant) RETURNING id INTO doc;
 PERFORM pg_temp.resolve('billing_documents',doc,a);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,linked_cfdi_id,billing_document_id,created_by)
 VALUES(t,'ar','Synthetic customer','MULTIFOLIO-AR',116,'MXN','open',cfdi,doc,accountant) RETURNING id INTO receivable;
 PERFORM pg_temp.resolve('finance_invoices',receivable,a);

 PERFORM set_config('d.t',t::text,true); PERFORM set_config('d.a',a::text,true);
 PERFORM set_config('d.operator',operator_id::text,true); PERFORM set_config('d.partial',partial::text,true);
 PERFORM set_config('d.cfdi',cfdi::text,true); PERFORM set_config('d.cancelled',cancelled::text,true);
 PERFORM set_config('d.doc',doc::text,true); PERFORM set_config('d.ar',receivable::text,true);
 PERFORM set_config('d.f',file_id::text,true);
 INSERT INTO public.operation_billing(tenant_id,operation_id,status,linked_cfdi_id)
 VALUES(t,current_setting('d.a4')::uuid,'draft',cancelled);
 PERFORM set_config('d.xml',encode(xml_bytes,'base64'),true);
END $fixtures$;

CREATE FUNCTION pg_temp.id(name text) RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT current_setting('d.'||name)::uuid
$$;
CREATE FUNCTION pg_temp.link(invoice text,names text[],xml_base64 text DEFAULT current_setting('d.xml')) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.rpc_delivery_link_issued_income(pg_temp.id('t'),pg_temp.id(invoice),
  ARRAY(SELECT pg_temp.id(name) FROM unnest(names) AS items(name)),xml_base64)
$$;
CREATE FUNCTION pg_temp.review(names text[], invoice text DEFAULT 'cfdi') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.rpc_delivery_review_issued_income(pg_temp.id('t'),pg_temp.id(invoice),names,
  CASE WHEN names IS NOT NULL THEN current_setting('d.xml') END)
$$;
CREATE FUNCTION pg_temp.confirm_review(items jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.rpc_delivery_link_issued_income(pg_temp.id('t'),pg_temp.id('cfdi'),
  ARRAY(SELECT (item->>'operation_id')::uuid FROM jsonb_array_elements(items->'results') item WHERE item->>'status'='ready'),
  current_setting('d.xml'))
$$;
CREATE FUNCTION pg_temp.close_operation(name text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.rpc_delivery_operation_action(pg_temp.id('t'),pg_temp.id(name),'transition','{"to_status":"closed"}',
  gen_random_uuid(),(public.rpc_delivery_operation_workflow(pg_temp.id('t'),pg_temp.id(name))->>'workflow_revision')::bigint)
$$;
CREATE FUNCTION pg_temp.expect(actual jsonb,expected jsonb,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF NOT COALESCE(actual @> expected,false) THEN RAISE EXCEPTION '%: expected %, got %',label,expected,actual; END IF;
 PERFORM pg_temp.ok(true,label);
END $$;

SELECT pg_temp.ok(has_function_privilege('authenticated','public.rpc_delivery_link_issued_income(uuid,uuid,uuid[],text)','EXECUTE')
 AND NOT has_function_privilege('anon','public.rpc_delivery_link_issued_income(uuid,uuid,uuid[],text)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.rpc_delivery_link_issued_income(uuid,uuid,uuid[],text)','EXECUTE')
 AND has_function_privilege('authenticated','public.rpc_delivery_review_issued_income(uuid,uuid,text[],text)','EXECUTE')
 AND NOT has_function_privilege('anon','public.rpc_delivery_review_issued_income(uuid,uuid,text[],text)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.rpc_delivery_review_issued_income(uuid,uuid,text[],text)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.delivery_issued_income_links(uuid,uuid,uuid[],text[],text,boolean)','EXECUTE'),
 'public grants restricted and private implementation closed');
SET LOCAL ROLE authenticated;
SELECT pg_temp.actor(pg_temp.id('operator'),pg_temp.id('a'));
SELECT pg_temp.expect(pg_temp.close_operation('a1'),'{"error":"billing_not_issued"}','first folio denied before link');
SELECT pg_temp.expect(pg_temp.close_operation('a2'),'{"error":"billing_not_issued"}','second folio denied before link');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a2']),'{"error":"unauthorized"}','operator cannot link invoice');
SELECT pg_temp.actor(pg_temp.id('partial'),pg_temp.id('a'));
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a2']),'{"error":"unauthorized"}','finance role and write alone insufficient');
SELECT pg_temp.expect(pg_temp.review(NULL),'{"error":"unauthorized"}','finance role and write cannot read link context');
SELECT pg_temp.actor(pg_temp.id('u'),pg_temp.id('a'));
SELECT pg_temp.expect(pg_temp.link('cancelled',ARRAY['a1','a2']),'{"error":"invoice_not_issued"}','cancelled invoice rejected');
SELECT pg_temp.expect(pg_temp.review(NULL,'cancelled'),'{"error":"invoice_not_issued"}','cancelled invoice cannot be selected for linking');
SELECT pg_temp.expect(pg_temp.review(NULL),jsonb_build_object('xml_file_id',pg_temp.id('f')),'eligible invoice returns authorized XML identity');
SELECT pg_temp.ok(pg_temp.review(NULL)->'linked_folios'='[]'::jsonb,'empty prior links read before confirmation');
SELECT pg_temp.expect(public.rpc_get_fiscal_readiness(pg_temp.id('cfdi')),'{"fiscal_status":"stamped"}',
 'existing Facturacion detail recognises this invoice as emitted');
SELECT pg_temp.expect(public.rpc_delivery_file_download(pg_temp.id('t'),pg_temp.id('f')),
 jsonb_build_object('id',pg_temp.id('f')),'existing private download authorizes the registered XML');
DO $$ BEGIN
 PERFORM set_config('d.review',pg_temp.review(ARRAY['A1','A2','A10','B1','A3','A4','a1',' A1'])::text,true);
END $$;
SELECT pg_temp.ok(current_setting('d.review')::jsonb->'results'=jsonb_build_array(
 jsonb_build_object('folio','A1','operation_id',pg_temp.id('a1'),'status','ready','reason',NULL),
 jsonb_build_object('folio','A2','operation_id',pg_temp.id('a2'),'status','ready','reason',NULL),
 jsonb_build_object('folio','A10','operation_id',NULL,'status','rejected','reason','folio_missing_from_invoice'),
 jsonb_build_object('folio','B1','operation_id',NULL,'status','rejected','reason','folio_not_available'),
 jsonb_build_object('folio','A3','operation_id',NULL,'status','rejected','reason','operation_not_delivered'),
 jsonb_build_object('folio','A4','operation_id',NULL,'status','rejected','reason','billing_link_conflict'),
 jsonb_build_object('folio','a1','operation_id',NULL,'status','rejected','reason','folio_missing_from_invoice'),
 jsonb_build_object('folio',' A1','operation_id',NULL,'status','rejected','reason','folio_not_available')
 ),'review lists exact accepted folios and every denial without disclosing other-company IDs');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','b1']),'{"error":"unauthorized"}','other company denied even with folio in XML');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a10']),'{"error":"folio_missing_from_invoice"}','description or prefix is not exact folio evidence');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a1']),'{"error":"invalid_payload"}','duplicate selection rejected');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a2'],encode(convert_to('<altered/>','UTF8'),'base64')),
 '{"error":"xml_integrity_mismatch"}','substituted XML rejected');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.operation_billing WHERE tenant_id=pg_temp.id('t') AND status='issued'),
 'denied batches have no partial link');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.audit_log WHERE tenant_id=pg_temp.id('t') AND action='operation_income_invoice_linked'),
 'denials have no success audits');

SAVEPOINT ambiguous_receivable;
DO $duplicate$
DECLARE duplicate_id uuid;
BEGIN
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,billing_document_id)
 VALUES(pg_temp.id('t'),'ar','Synthetic customer','DUPLICATE-AR',116,'MXN','open',pg_temp.id('doc')) RETURNING id INTO duplicate_id;
 PERFORM pg_temp.resolve('finance_invoices',duplicate_id,pg_temp.id('a'));
END $duplicate$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a2']),'{"error":"single_receivable_required"}',
 'second active receivable rejected even when connected through document only');
SELECT pg_temp.expect(pg_temp.review(NULL),'{"error":"single_receivable_required"}','ambiguous balance blocks invoice selection');
SELECT 'BILLING_MULTIFOLIO_DUPLICATE_AR=PASS';
ROLLBACK TO SAVEPOINT ambiguous_receivable;
RELEASE SAVEPOINT ambiguous_receivable;

SET LOCAL ROLE authenticated;
SELECT pg_temp.expect(pg_temp.confirm_review(current_setting('d.review')::jsonb),'{"success":true,"linked_count":2}',
 'confirm links only the two ready operations from mixed review');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(pg_temp.review(NULL)->'linked_folios'='["A1","A2"]'::jsonb,
 'fresh invoice context reloads the two persisted folios without XML or review state');
SELECT pg_temp.ok((pg_temp.review(ARRAY['A1','A2'])->'results') @> '[{"folio":"A1","status":"already_linked"},{"folio":"A2","status":"already_linked"}]'::jsonb,
 'review after reload distinguishes the existing links');
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a2','a1']),'{"success":true,"linked_count":0}','retry is idempotent');
SELECT pg_temp.actor(pg_temp.id('operator'),pg_temp.id('a'));
SELECT pg_temp.expect(pg_temp.close_operation('a1'),'{"success":true}','first folio closes through normal workflow');
SELECT pg_temp.expect(pg_temp.close_operation('a2'),'{"success":true}','second folio closes through normal workflow');
SELECT pg_temp.ok(NOT(public.rpc_delivery_operational_billing(pg_temp.id('t'),pg_temp.id('a1'))
 ?| ARRAY['billing_reference','linked_cfdi_id','amount','finance_invoice_id']),'operator billing status does not expose invoice or amount');
SELECT pg_temp.actor(pg_temp.id('u'),pg_temp.id('a'));
SELECT pg_temp.expect(pg_temp.link('cfdi',ARRAY['a1','a2']),'{"success":true,"linked_count":0}','retry after normal close is idempotent');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=2 AND bool_and(status='issued' AND linked_cfdi_id=pg_temp.id('cfdi')
 AND issued_by=pg_temp.id('u') AND NOT admin_close_override) FROM public.operation_billing WHERE tenant_id=pg_temp.id('t') AND status='issued'),
 'two links share the same CFDI without override');
SELECT pg_temp.ok((SELECT count(*)=2 AND bool_and(status='closed') FROM public.operations WHERE id IN(pg_temp.id('a1'),pg_temp.id('a2'))),
 'both normal closes persist');
SELECT pg_temp.ok((SELECT count(*)=1 FROM public.billing_cfdis WHERE tenant_id=pg_temp.id('t') AND id<>pg_temp.id('cancelled')),
 'one canonical live CFDI remains');
SELECT pg_temp.ok((SELECT count(*)=1 AND bool_and(id=pg_temp.id('doc') AND total=116)
 FROM public.billing_documents WHERE tenant_id=pg_temp.id('t')),'one original income document and no supplier document');
SELECT pg_temp.ok((SELECT count(*)=1 AND bool_and(id=pg_temp.id('ar') AND direction='ar' AND amount=116 AND status='open')
 FROM public.finance_invoices WHERE tenant_id=pg_temp.id('t')),'one original balance and no payables');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM public.finance_payments WHERE tenant_id=pg_temp.id('t')),'no payments posted');
SELECT pg_temp.ok((SELECT count(*)=2 AND count(DISTINCT entity_id)=2 AND bool_and(
 entity_id IN(pg_temp.id('a1'),pg_temp.id('a2')) AND actor_user_id=pg_temp.id('u')
 AND metadata=jsonb_build_object('cfdi_id',pg_temp.id('cfdi'),'finance_invoice_id',pg_temp.id('ar')))
 FROM public.audit_log WHERE tenant_id=pg_temp.id('t') AND action='operation_income_invoice_linked'),'one audit per folio with actor and canonical references');
SELECT 'BILLING_MULTIFOLIO_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
DO $$ BEGIN
 IF EXISTS(SELECT FROM public.tenants WHERE slug='multifolio-local') THEN RAISE EXCEPTION 'local fixtures remained'; END IF;
END $$;
