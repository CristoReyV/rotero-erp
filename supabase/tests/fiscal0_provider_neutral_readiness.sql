\set ON_ERROR_STOP on
BEGIN;

DO $contract$
DECLARE s text; o oid; t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fiscal_provider_configs','fiscal_requests','fiscal_provider_attempts'] LOOP
    IF to_regclass('public.'||t) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||t) AND relrowsecurity) THEN RAISE EXCEPTION 'FISCAL0 table/RLS %',t; END IF;
    IF has_table_privilege('authenticated','public.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','public.'||t,'SELECT') OR has_table_privilege('service_role','public.'||t,'SELECT') THEN RAISE EXCEPTION 'FISCAL0 direct ACL %',t; END IF;
  END LOOP;
  FOREACH s IN ARRAY ARRAY[
    'public.rpc_get_fiscal_readiness(uuid)','public.rpc_update_cfdi_fiscal_input(uuid,jsonb,text)',
    'public.rpc_prepare_cfdi_for_api(uuid)','public.rpc_queue_fiscal_stamp(uuid)',
    'public.rpc_retry_fiscal_request(uuid)','public.rpc_reset_cfdi_fiscal_draft(uuid,text)','public.rpc_request_fiscal_cancellation(uuid,text)',
    'public.rpc_queue_fiscal_status_check(uuid)','public.rpc_get_fiscal_operational_status(uuid)',
    'public.rpc_get_fiscal_provider_config(uuid)','public.rpc_update_fiscal_provider_config(uuid,text,boolean,text,jsonb)'
  ] LOOP
    o:=to_regprocedure(s); IF o IS NULL THEN RAISE EXCEPTION 'FISCAL0 missing RPC %',s; END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=o AND prosecdef AND proconfig@>ARRAY['search_path=pg_catalog, public']::text[]) THEN RAISE EXCEPTION 'FISCAL0 unsafe RPC %',s; END IF;
    IF NOT has_function_privilege('authenticated',o,'EXECUTE') OR has_function_privilege('anon',o,'EXECUTE') OR has_function_privilege('service_role',o,'EXECUTE') OR pg_get_functiondef(o)~*'\mSQLERRM\M' THEN RAISE EXCEPTION 'FISCAL0 RPC ACL/error %',s; END IF;
  END LOOP;
  FOREACH s IN ARRAY ARRAY[
    'private.fiscal0_status_transition_allowed(text,text)','private.fiscal0_guard_cfdi()',
    'private.fiscal0_attempts_immutable()','private.fiscal0_validate(public.billing_cfdis)',
    'private.fiscal0_snapshot(public.billing_cfdis)','private.fiscal0_claim_requests(integer)',
    'private.fiscal0_apply_provider_result(uuid,jsonb,timestamptz)','private.fiscal0_link_artifact(uuid,text,uuid)'
  ] LOOP
    o:=to_regprocedure(s); IF o IS NULL OR has_function_privilege('authenticated',o,'EXECUTE') OR has_function_privilege('anon',o,'EXECUTE') OR has_function_privilege('service_role',o,'EXECUTE') THEN RAISE EXCEPTION 'FISCAL0 private ACL %',s; END IF;
  END LOOP;
  IF pg_get_functiondef('public.rpc_queue_fiscal_stamp(uuid)'::regprocedure)!~'pg_advisory_xact_lock'
     OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='fiscal_requests_identity_uidx')
     OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='fiscal_requests_one_active_type_uidx') THEN RAISE EXCEPTION 'FISCAL0 concurrency/idempotency boundary'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.document_files'::regclass AND conname='document_files_source_type_check' AND pg_get_constraintdef(oid) LIKE '%billing_cfdi%') THEN RAISE EXCEPTION 'FISCAL0 F3 extension'; END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobname LIKE 'rotero-f7-%')<>2 THEN RAISE EXCEPTION 'FISCAL0 changed F7 cron'; END IF;
  IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'rpc_%fiscal%' AND pg_get_functiondef(oid)~*'(http://|https://|soap|wsdl|authorization:)') THEN RAISE EXCEPTION 'FISCAL0 speculative provider transport'; END IF;
END $contract$;

DO $fixtures$
DECLARE tenant uuid; other uuid; admin_id uuid:=gen_random_uuid(); finance_id uuid:=gen_random_uuid(); operator_id uuid:=gen_random_uuid(); customer uuid; operation_id uuid; cfdi1 uuid; cfdi2 uuid; cfdi3 uuid; cfdi4 uuid;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
   ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','fiscal0-admin@example.invalid',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',finance_id,'authenticated','authenticated','fiscal0-finance@example.invalid',now(),'{}','{}',now(),now()),
   ('00000000-0000-0000-0000-000000000000',operator_id,'authenticated','authenticated','fiscal0-operator@example.invalid',now(),'{}','{}',now(),now());
  INSERT INTO public.tenants(name,slug) VALUES('Fiscal0 Tenant','fiscal0-tenant'),('Fiscal0 Other','fiscal0-other');
  SELECT id INTO tenant FROM public.tenants WHERE slug='fiscal0-tenant'; SELECT id INTO other FROM public.tenants WHERE slug='fiscal0-other';
  INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(tenant,admin_id,'admin'),(tenant,finance_id,'finance'),(tenant,operator_id,'operator');
  INSERT INTO public.customers(tenant_id,display_name) VALUES(tenant,'Cliente Fiscal0') RETURNING id INTO customer;
  INSERT INTO public.operations(tenant_id,reference_code,customer_id,status,execution_type,customer_price_amount,provider_cost_amount,pricing_currency)
    VALUES(tenant,'OP-FISCAL0',customer,'planned','third_party',1160,700,'MXN') RETURNING id INTO operation_id;
  INSERT INTO public.billing_cfdis(tenant_id,operation_id,serie,folio,rfc_emisor,rfc_receptor,receptor_name,subtotal,total,currency)
    SELECT tenant,operation_id,'F0',n::text,'AAA010101AAA','BBB010101BBB','Cliente Fiscal0',1000,1160,'MXN' FROM generate_series(1,4)n ORDER BY n;
  SELECT id INTO cfdi1 FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='1';
  SELECT id INTO cfdi2 FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='2';
  SELECT id INTO cfdi3 FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='3';
  SELECT id INTO cfdi4 FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='4';
  PERFORM set_config('fiscal0.tenant',tenant::text,true); PERFORM set_config('fiscal0.other',other::text,true);
  PERFORM set_config('fiscal0.admin',admin_id::text,true); PERFORM set_config('fiscal0.finance',finance_id::text,true); PERFORM set_config('fiscal0.operator',operator_id::text,true);
  PERFORM set_config('fiscal0.operation',operation_id::text,true); PERFORM set_config('fiscal0.cfdi1',cfdi1::text,true); PERFORM set_config('fiscal0.cfdi2',cfdi2::text,true); PERFORM set_config('fiscal0.cfdi3',cfdi3::text,true); PERFORM set_config('fiscal0.cfdi4',cfdi4::text,true);
END $fixtures$;

SET LOCAL ROLE authenticated;
DO $admin_prepare$
DECLARE tenant uuid:=current_setting('fiscal0.tenant')::uuid; c uuid; r jsonb; fiscal_input jsonb:=jsonb_build_object(
 'issuer',jsonb_build_object('rfc','AAA010101AAA'),'receiver',jsonb_build_object('rfc','BBB010101BBB','name','Cliente Fiscal0'),
 'concepts',jsonb_build_array(jsonb_build_object('description','Servicio logístico contratado','amount',1000)),
 'taxes',jsonb_build_array(jsonb_build_object('kind','IVA','amount',160)),'payment',jsonb_build_object('method','PUE'));
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fiscal0.admin'),'role','authenticated')::text,true);
  c:=current_setting('fiscal0.cfdi1')::uuid;
  r:=public.rpc_prepare_cfdi_for_api(c); IF r->>'error'<>'validation_failed' OR NOT (r#>'{validation,missing_fields}') ? 'concepts' THEN RAISE EXCEPTION 'FISCAL0 preflight missing %',r; END IF;
  FOREACH c IN ARRAY ARRAY[current_setting('fiscal0.cfdi1')::uuid,current_setting('fiscal0.cfdi2')::uuid,current_setting('fiscal0.cfdi3')::uuid,current_setting('fiscal0.cfdi4')::uuid] LOOP
    IF public.rpc_update_cfdi_fiscal_input(c,fiscal_input,'4.0')?'error' OR public.rpc_prepare_cfdi_for_api(c)?'error' THEN RAISE EXCEPTION 'FISCAL0 prepare %',c; END IF;
  END LOOP;
  c:=current_setting('fiscal0.cfdi1')::uuid; r:=public.rpc_queue_fiscal_stamp(c);
  IF r->>'error'<>'provider_not_configured' OR public.rpc_get_fiscal_readiness(c)->>'fiscal_status'<>'ready_for_api' THEN RAISE EXCEPTION 'FISCAL0 fail closed %',r; END IF;
  IF public.rpc_update_fiscal_provider_config(tenant,'soft_management',true,'sandbox','{"status_polling":true}')?'error' THEN RAISE EXCEPTION 'FISCAL0 config'; END IF;
  r:=public.rpc_queue_fiscal_stamp(c); IF NOT (r->>'accepted')::boolean THEN RAISE EXCEPTION 'FISCAL0 first queue %',r; END IF; PERFORM set_config('fiscal0.req1',r->>'request_id',true);
  r:=public.rpc_queue_fiscal_stamp(c); IF (r->>'accepted')::boolean OR r->>'error'<>'already_processing' THEN RAISE EXCEPTION 'FISCAL0 duplicate queue %',r; END IF;
  IF public.rpc_get_fiscal_operational_status(tenant)->>'queue_depth'<>'1' THEN RAISE EXCEPTION 'FISCAL0 observability'; END IF;
  IF public.rpc_update_fiscal_provider_config(tenant,'soft_management',true,'production','{}')?'error' THEN RAISE EXCEPTION 'FISCAL0 production config'; END IF;
  r:=public.rpc_queue_fiscal_stamp(current_setting('fiscal0.cfdi4')::uuid); IF r->>'error'<>'provider_not_configured' THEN RAISE EXCEPTION 'FISCAL0 staging production fallthrough %',r; END IF;
  PERFORM public.rpc_update_fiscal_provider_config(tenant,'soft_management',true,'sandbox','{}');
END $admin_prepare$;
RESET ROLE;

DO $provider_results$
DECLARE req uuid:=current_setting('fiscal0.req1')::uuid; c uuid:=current_setting('fiscal0.cfdi1')::uuid; r jsonb; xml_id uuid; pdf_id uuid; payment_count bigint;
BEGIN
  SELECT count(*) INTO payment_count FROM public.finance_payments WHERE tenant_id=current_setting('fiscal0.tenant')::uuid;
  PERFORM private.fiscal0_claim_requests(10);
  r:=private.fiscal0_apply_provider_result(req,'{"outcome":"processing","provider_document_id":"provider-doc-1"}',now()-interval '1 second'); IF r?'error' THEN RAISE EXCEPTION 'FISCAL0 processing %',r; END IF;
  r:=private.fiscal0_apply_provider_result(req,'{"outcome":"stamped","provider_document_id":"provider-doc-1","fiscal_uuid":"11111111-1111-4111-8111-111111111111"}',now()-interval '1 second'); IF r?'error' THEN RAISE EXCEPTION 'FISCAL0 stamped %',r; END IF;
  IF (SELECT fiscal_status FROM public.billing_cfdis WHERE id=c)<>'stamped' OR (SELECT count(*) FROM public.finance_payments WHERE tenant_id=current_setting('fiscal0.tenant')::uuid)<>payment_count THEN RAISE EXCEPTION 'FISCAL0 stamped/accounting separation'; END IF;
  INSERT INTO public.document_files(tenant_id,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,source_module,source_entity_type,source_entity_id)
    VALUES(current_setting('fiscal0.tenant')::uuid,current_setting('fiscal0.tenant')||'/billing/billing_cfdi/'||c||'/11111111-1111-4111-8111-111111111111.xml','cfdi.xml','application/xml',4,repeat('a',64),'fiscal_xml','billing','billing_cfdi',c) RETURNING id INTO xml_id;
  INSERT INTO public.document_files(tenant_id,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,source_module,source_entity_type,source_entity_id)
    VALUES(current_setting('fiscal0.tenant')::uuid,current_setting('fiscal0.tenant')||'/billing/billing_cfdi/'||c||'/22222222-2222-4222-8222-222222222222.pdf','cfdi.pdf','application/pdf',4,repeat('b',64),'fiscal_pdf','billing','billing_cfdi',c) RETURNING id INTO pdf_id;
  IF private.fiscal0_link_artifact(req,'xml',xml_id)?'error' OR private.fiscal0_link_artifact(req,'pdf',pdf_id)?'error' THEN RAISE EXCEPTION 'FISCAL0 artifacts'; END IF;
  IF (SELECT xml_document_file_id<>xml_id OR pdf_document_file_id<>pdf_id FROM public.billing_cfdis WHERE id=c) THEN RAISE EXCEPTION 'FISCAL0 artifact links'; END IF;
  BEGIN UPDATE public.fiscal_provider_attempts SET safe_error_code='tampered' WHERE request_id=req; RAISE EXCEPTION 'FISCAL0 attempt mutable'; EXCEPTION WHEN check_violation THEN NULL; END;
END $provider_results$;

SET LOCAL ROLE authenticated;
DO $status_cancel_and_failures$
DECLARE tenant uuid:=current_setting('fiscal0.tenant')::uuid; c1 uuid:=current_setting('fiscal0.cfdi1')::uuid; c2 uuid:=current_setting('fiscal0.cfdi2')::uuid; c3 uuid:=current_setting('fiscal0.cfdi3')::uuid; r jsonb; req uuid;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fiscal0.finance'),'role','authenticated')::text,true);
  r:=public.rpc_queue_fiscal_status_check(c1); IF r?'error' THEN RAISE EXCEPTION 'FISCAL0 status queue %',r; END IF; PERFORM set_config('fiscal0.statusreq',r->>'request_id',true);
  r:=public.rpc_request_fiscal_cancellation(c1,''); IF r->>'error'<>'validation_failed' THEN RAISE EXCEPTION 'FISCAL0 cancellation reason'; END IF;
  r:=public.rpc_request_fiscal_cancellation(c1,'Error en datos fiscales'); IF NOT (r->>'accepted')::boolean THEN RAISE EXCEPTION 'FISCAL0 cancel queue %',r; END IF; PERFORM set_config('fiscal0.cancelreq',r->>'request_id',true);
  r:=public.rpc_request_fiscal_cancellation(c1,'Error en datos fiscales'); IF (r->>'accepted')::boolean OR r->>'error'<>'already_processing' THEN RAISE EXCEPTION 'FISCAL0 cancel duplicate %',r; END IF;
  r:=public.rpc_queue_fiscal_stamp(c2); req:=(r->>'request_id')::uuid; PERFORM set_config('fiscal0.techreq',req::text,true);
  r:=public.rpc_queue_fiscal_stamp(c3); req:=(r->>'request_id')::uuid; PERFORM set_config('fiscal0.rejectreq',req::text,true);
  IF public.rpc_get_fiscal_readiness(c1)->>'fiscal_status'<>'cancellation_requested' THEN RAISE EXCEPTION 'FISCAL0 finance read'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fiscal0.operator'),'role','authenticated')::text,true);
  IF public.rpc_get_fiscal_readiness(c1)->>'error'<>'unauthorized' OR public.rpc_queue_fiscal_stamp(c2)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'FISCAL0 role isolation'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  IF public.rpc_get_fiscal_operational_status(tenant)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'FISCAL0 tenant isolation'; END IF;
END $status_cancel_and_failures$;
RESET ROLE;

DO $finish$
DECLARE r jsonb; c1 uuid:=current_setting('fiscal0.cfdi1')::uuid; c2 uuid:=current_setting('fiscal0.cfdi2')::uuid; c3 uuid:=current_setting('fiscal0.cfdi3')::uuid; original_uuid text;
BEGIN
  SELECT uuid INTO original_uuid FROM public.billing_cfdis WHERE id=c1;
  PERFORM private.fiscal0_claim_requests(10);
  r:=private.fiscal0_apply_provider_result(current_setting('fiscal0.statusreq')::uuid,'{"outcome":"stamped","provider_document_id":"provider-doc-1","fiscal_uuid":"11111111-1111-4111-8111-111111111111"}'); IF r?'error' THEN RAISE EXCEPTION 'FISCAL0 reconcile stamped'; END IF;
  r:=private.fiscal0_apply_provider_result(current_setting('fiscal0.cancelreq')::uuid,'{"outcome":"cancelled"}'); IF r?'error' OR (SELECT fiscal_status FROM public.billing_cfdis WHERE id=c1)<>'cancelled' THEN RAISE EXCEPTION 'FISCAL0 cancel confirm %',r; END IF;
  r:=private.fiscal0_apply_provider_result(current_setting('fiscal0.techreq')::uuid,'{"outcome":"technical_error","safe_error_code":"provider_timeout"}'); IF r?'error' OR (SELECT fiscal_status FROM public.billing_cfdis WHERE id=c2)<>'api_error' THEN RAISE EXCEPTION 'FISCAL0 technical %',r; END IF;
  r:=private.fiscal0_apply_provider_result(current_setting('fiscal0.rejectreq')::uuid,'{"outcome":"business_rejection"}'); IF r?'error' OR (SELECT fiscal_status FROM public.billing_cfdis WHERE id=c3)<>'rejected' THEN RAISE EXCEPTION 'FISCAL0 rejection %',r; END IF;
  IF (SELECT uuid FROM public.billing_cfdis WHERE id=c1)<>original_uuid THEN RAISE EXCEPTION 'FISCAL0 reconcile changed UUID'; END IF;
END $finish$;

SET LOCAL ROLE authenticated;
DO $retry_policy$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fiscal0.finance'),'role','authenticated')::text,true);
  r:=public.rpc_retry_fiscal_request(current_setting('fiscal0.techreq')::uuid); IF r?'error' THEN RAISE EXCEPTION 'FISCAL0 technical retry %',r; END IF;
  r:=public.rpc_retry_fiscal_request(current_setting('fiscal0.rejectreq')::uuid); IF r->>'error'<>'invalid_transition' THEN RAISE EXCEPTION 'FISCAL0 business retry %',r; END IF;
  r:=public.rpc_reset_cfdi_fiscal_draft(current_setting('fiscal0.cfdi3')::uuid,'Corregir datos rechazados'); IF r?'error' OR public.rpc_get_fiscal_readiness(current_setting('fiscal0.cfdi3')::uuid)->>'fiscal_status'<>'draft' THEN RAISE EXCEPTION 'FISCAL0 rejected correction %',r; END IF;
END $retry_policy$;
RESET ROLE;

DO $immutability$
DECLARE c uuid:=current_setting('fiscal0.cfdi2')::uuid;
BEGIN
  BEGIN UPDATE public.billing_cfdis SET fiscal_snapshot='{"tampered":true}' WHERE id=c; RAISE EXCEPTION 'FISCAL0 snapshot mutable'; EXCEPTION WHEN check_violation THEN NULL; END;
  IF EXISTS(SELECT 1 FROM public.fiscal_provider_configs WHERE capabilities::text~*'(secret|password|authorization)') THEN RAISE EXCEPTION 'FISCAL0 secret metadata'; END IF;
END $immutability$;

ROLLBACK;
