\set ON_ERROR_STOP on
BEGIN;

DO $contract$
DECLARE s text;o oid;t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['partner_compliance_requirements','partner_compliance_records','partner_contracts','provider_compliance_overrides'] LOOP
  IF to_regclass('public.'||t) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||t) AND relrowsecurity) THEN RAISE EXCEPTION 'F9 table/RLS %',t;END IF;
  IF has_table_privilege('authenticated','public.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','public.'||t,'SELECT') OR has_table_privilege('service_role','public.'||t,'SELECT') THEN RAISE EXCEPTION 'F9 direct ACL %',t;END IF;
 END LOOP;
 FOREACH s IN ARRAY ARRAY[
  'public.rpc_list_compliance_requirements(uuid,jsonb)','public.rpc_upsert_compliance_requirement(uuid,uuid,jsonb)','public.rpc_archive_compliance_requirement(uuid)','public.rpc_submit_partner_compliance_record(uuid,jsonb)','public.rpc_review_partner_compliance_record(uuid,text,text)','public.rpc_waive_partner_requirement(uuid,jsonb)','public.rpc_get_partner_compliance_status(uuid,text,uuid,date)','public.rpc_get_provider_operational_eligibility(uuid,uuid)','public.rpc_upsert_partner_contract(uuid,uuid,jsonb)','public.rpc_activate_partner_contract(uuid)','public.rpc_renew_partner_contract(uuid,jsonb)','public.rpc_terminate_partner_contract(uuid,text)','public.rpc_get_partner_compliance_bundle(uuid,text,uuid)','public.rpc_list_compliance_matrix(uuid,jsonb)','public.rpc_list_compliance_expirations(uuid,integer)','public.rpc_get_provider_compliance_badges(uuid,uuid[])','public.rpc_get_compliance_dashboard(uuid)','public.rpc_list_compliance_attention_items(uuid)','public.rpc_search_compliance(uuid,text,integer)','public.rpc_export_partner_compliance(uuid,jsonb)','public.rpc_create_provider_compliance_override(uuid,uuid,text)','public.rpc_refresh_compliance_notifications(uuid)'
 ] LOOP
  o:=to_regprocedure(s);IF o IS NULL THEN RAISE EXCEPTION 'F9 missing RPC %',s;END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=o AND prosecdef AND proconfig@>ARRAY['search_path=pg_catalog, public']::text[]) THEN RAISE EXCEPTION 'F9 unsafe RPC %',s;END IF;
  IF NOT has_function_privilege('authenticated',o,'EXECUTE') OR has_function_privilege('anon',o,'EXECUTE') OR has_function_privilege('service_role',o,'EXECUTE') THEN RAISE EXCEPTION 'F9 RPC ACL %',s;END IF;
  IF pg_get_functiondef(o)~*'\mSQLERRM\M' THEN RAISE EXCEPTION 'F9 raw SQLERRM %',s;END IF;
 END LOOP;
 FOREACH s IN ARRAY ARRAY['private.f9_admin(uuid)','private.f9_record_status(text,date,integer,date,date)','private.f9_partner_status(uuid,text,uuid,date)','private.f9_guard_provider_assignment()','private.f9_materialize_notifications(uuid,timestamptz)'] LOOP
  o:=to_regprocedure(s);IF o IS NULL OR has_function_privilege('authenticated',o,'EXECUTE') OR has_function_privilege('anon',o,'EXECUTE') OR has_function_privilege('service_role',o,'EXECUTE') THEN RAISE EXCEPTION 'F9 private ACL %',s;END IF;
 END LOOP;
 o:='public.rpc_get_operation_dispatch_readiness(uuid)'::regprocedure;
 IF (SELECT proargnames FROM pg_proc WHERE oid=o)<>ARRAY['p_operation_id'] OR (SELECT pronargdefaults FROM pg_proc WHERE oid=o)<>0 OR pg_get_function_result(o)<>'jsonb' THEN RAISE EXCEPTION 'F9 readiness collision contract';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.operations'::regclass AND tgname='trg_f9_provider_assignment_gate' AND tgenabled='O') THEN RAISE EXCEPTION 'F9 assignment gate missing';END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobname LIKE 'rotero-f7-%')<>2 OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='rotero-f7-automation-hourly' AND schedule='0 * * * *') OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='rotero-f7-daily-digest' AND schedule='15 12 * * *') OR EXISTS(SELECT 1 FROM cron.job WHERE command~*'(http|net|vault|edge)') THEN RAISE EXCEPTION 'F9 changed F7 cron';END IF;
 IF pg_get_functiondef('public.rpc_get_public_tracking(text)'::regprocedure)~*'(compliance|partner_contract)' OR pg_get_functiondef('public.rpc_get_driver_view(text)'::regprocedure)~*'(compliance|partner_contract)' THEN RAISE EXCEPTION 'F9 Tracking leak';END IF;
END $contract$;

DO $fixtures$
DECLARE tenant uuid;other uuid;admin_id uuid:=gen_random_uuid();finance_id uuid:=gen_random_uuid();operator_id uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();customer uuid;provider uuid;provider2 uuid;other_provider uuid;contact uuid;file_id uuid;service uuid;lane uuid;rate uuid;version uuid;
BEGIN
 INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','f9-admin@example.invalid',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',finance_id,'authenticated','authenticated','f9-finance@example.invalid',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',operator_id,'authenticated','authenticated','f9-operator@example.invalid',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000',outsider,'authenticated','authenticated','f9-outsider@example.invalid',now(),'{}','{}',now(),now());
 INSERT INTO public.tenants(name,slug) VALUES('F9 Tenant','f9-tenant'),('F9 Other','f9-other');SELECT id INTO tenant FROM public.tenants WHERE slug='f9-tenant';SELECT id INTO other FROM public.tenants WHERE slug='f9-other';
 INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(tenant,admin_id,'admin'),(tenant,finance_id,'finance'),(tenant,operator_id,'operator');
 INSERT INTO public.customers(tenant_id,display_name) VALUES(tenant,'Cliente F9') RETURNING id INTO customer;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(tenant,'Proveedor F9') RETURNING id INTO provider;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(tenant,'Proveedor bloqueado F9') RETURNING id INTO provider2;
 INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(other,'Proveedor ajeno F9') RETURNING id INTO other_provider;
 INSERT INTO public.business_contacts(tenant_id,provider_id,name,contact_role,created_by) VALUES(tenant,provider,'Responsable F9','operations',admin_id) RETURNING id INTO contact;
 file_id:=gen_random_uuid();INSERT INTO public.document_files(id,tenant_id,storage_path,file_name,mime_type,size_bytes,file_kind,source_module,source_entity_type,source_entity_id,uploaded_by) VALUES(file_id,tenant,tenant||'/commercial/provider/'||provider||'/'||gen_random_uuid()||'.pdf','evidencia-f9.pdf','application/pdf',100,'provider_upload','commercial','provider',provider,admin_id);
 INSERT INTO public.service_catalog_items(tenant_id,service_type) VALUES(tenant,'FTL F9') RETURNING id INTO service;
 INSERT INTO public.commercial_lanes(tenant_id,scope,origin_place,destination_place,origin_key,destination_key,label,created_by) VALUES(tenant,'national','{"municipality":"A"}','{"municipality":"B"}','a|mx','b|mx','A → B',admin_id) RETURNING id INTO lane;
 INSERT INTO public.commercial_rate_cards(tenant_id,rate_type,provider_id,lane_id,service_catalog_item_id,reference,status,created_by) VALUES(tenant,'BUY',provider,lane,service,'BUY-F9-EXP','active',admin_id) RETURNING id INTO rate;
 INSERT INTO public.commercial_rate_versions(tenant_id,rate_card_id,version,currency,valid_from,valid_to,created_by) VALUES(tenant,rate,1,'MXN',current_date,current_date+10,admin_id) RETURNING id INTO version;UPDATE public.commercial_rate_cards SET current_version_id=version WHERE id=rate;
 PERFORM set_config('f9.tenant',tenant::text,true);PERFORM set_config('f9.other',other::text,true);PERFORM set_config('f9.admin',admin_id::text,true);PERFORM set_config('f9.finance',finance_id::text,true);PERFORM set_config('f9.operator',operator_id::text,true);PERFORM set_config('f9.outsider',outsider::text,true);PERFORM set_config('f9.customer',customer::text,true);PERFORM set_config('f9.provider',provider::text,true);PERFORM set_config('f9.provider2',provider2::text,true);PERFORM set_config('f9.other_provider',other_provider::text,true);PERFORM set_config('f9.contact',contact::text,true);PERFORM set_config('f9.file',file_id::text,true);
END $fixtures$;

DO $admin$
DECLARE tenant uuid:=current_setting('f9.tenant')::uuid;provider uuid:=current_setting('f9.provider')::uuid;provider2 uuid:=current_setting('f9.provider2')::uuid;customer uuid:=current_setting('f9.customer')::uuid;file_id uuid:=current_setting('f9.file')::uuid;contact uuid:=current_setting('f9.contact')::uuid;req_warning uuid;req_block uuid;req_expired uuid;record1 uuid;record2 uuid;contract1 uuid;contract2 uuid;operation1 uuid;operation2 uuid;r jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f9.admin'),'role','authenticated')::text,true);
 IF (SELECT count(*) FROM public.partner_compliance_requirements WHERE tenant_id=tenant)<>4 OR EXISTS(SELECT 1 FROM public.partner_compliance_requirements WHERE tenant_id=tenant AND (is_required OR is_blocking OR blocks_operation_assignment)) THEN RAISE EXCEPTION 'F9 safe defaults failed';END IF;
 r:=public.rpc_upsert_compliance_requirement(tenant,NULL,'{"code":"provider_warning","name":"Aviso no bloqueante","partner_type":"provider","category":"operational","is_required":true,"is_blocking":false,"blocks_operation_assignment":false,"has_expiration":true,"warning_days":30}');req_warning:=(r->>'id')::uuid;
 r:=public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date);IF (r->>'missing')::int<>1 OR NOT(r->>'provider_compliance_ready')::boolean THEN RAISE EXCEPTION 'F9 nonblocking missing %',r;END IF;
 r:=public.rpc_upsert_compliance_requirement(tenant,NULL,'{"code":"provider_assignment_gate","name":"Gate operativo","partner_type":"provider","category":"insurance","is_required":true,"is_blocking":true,"blocks_operation_assignment":true,"has_expiration":true,"warning_days":30}');req_block:=(r->>'id')::uuid;
 r:=public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date);IF (r->>'blocking')::int<>1 OR (r->>'provider_compliance_ready')::boolean THEN RAISE EXCEPTION 'F9 blocking missing %',r;END IF;
 IF public.rpc_get_partner_compliance_status(tenant,'provider',current_setting('f9.other_provider')::uuid,current_date)->>'error'<>'not_found' THEN RAISE EXCEPTION 'F9 cross tenant evaluation';END IF;
 r:=public.rpc_submit_partner_compliance_record(tenant,jsonb_build_object('requirement_id',req_block,'provider_id',provider,'document_file_id',file_id,'responsible_contact_id',contact,'valid_from',current_date,'valid_to',current_date+60));record1:=(r->>'id')::uuid;
 IF (public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date)->>'blocking')::int<>1 THEN RAISE EXCEPTION 'F9 pending must block configured gate';END IF;
 PERFORM public.rpc_review_partner_compliance_record(record1,'accepted','Revisión F9');r:=public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date);IF NOT(r->>'provider_compliance_ready')::boolean THEN RAISE EXCEPTION 'F9 accepted valid %',r;END IF;
 r:=public.rpc_submit_partner_compliance_record(tenant,jsonb_build_object('requirement_id',req_block,'provider_id',provider,'document_file_id',file_id,'valid_to',current_date+5));record2:=(r->>'id')::uuid;PERFORM public.rpc_review_partner_compliance_record(record2,'accepted','Renovación F9');
 r:=public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date);IF (SELECT count(*) FROM public.partner_compliance_records WHERE provider_id=provider AND requirement_id=req_block)<>2 OR (r->>'expiring')::int<>1 THEN RAISE EXCEPTION 'F9 replacement/expiring history %',r;END IF;
 r:=public.rpc_upsert_compliance_requirement(tenant,NULL,'{"code":"provider_expired_gate","name":"Gate vencido","partner_type":"provider","category":"insurance","is_required":true,"is_blocking":true,"blocks_operation_assignment":true,"has_expiration":true,"warning_days":30}');req_expired:=(r->>'id')::uuid;
 INSERT INTO public.partner_compliance_records(tenant_id,requirement_id,provider_id,document_file_id,review_status,valid_to,reviewed_at,reviewed_by,created_by) VALUES(tenant,req_expired,provider,file_id,'accepted',current_date-1,now(),current_setting('f9.admin')::uuid,current_setting('f9.admin')::uuid);
 IF (public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date)->>'expired')::int<>1 THEN RAISE EXCEPTION 'F9 expired derived';END IF;
 r:=public.rpc_waive_partner_requirement(tenant,jsonb_build_object('requirement_id',req_expired,'provider_id',provider,'waiver_until',current_date+2,'reason','Continuidad revisada por Admin'));IF (public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date)->>'waived')::int<>1 OR (public.rpc_get_partner_compliance_status(tenant,'provider',provider,current_date+3)->>'blocking')::int=0 THEN RAISE EXCEPTION 'F9 waiver lifecycle';END IF;
 r:=public.rpc_upsert_partner_contract(tenant,NULL,jsonb_build_object('provider_id',provider,'contract_type','commercial','title','Contrato F9','reference','C-F9-1','document_file_id',file_id,'responsible_contact_id',contact,'starts_on',current_date,'ends_on',current_date+10,'notice_days',30));contract1:=(r->>'id')::uuid;PERFORM public.rpc_activate_partner_contract(contract1);
 IF public.rpc_get_partner_compliance_bundle(tenant,'provider',provider)#>>'{contracts,0,derived_status}'<>'expiring' THEN RAISE EXCEPTION 'F9 contract derived expiry';END IF;
 r:=public.rpc_renew_partner_contract(contract1,jsonb_build_object('title','Contrato F9 renovación','contract_type','commercial','reference','C-F9-2','document_file_id',file_id,'starts_on',current_date+11,'ends_on',current_date+100));contract2:=(r->>'id')::uuid;
 IF (SELECT status FROM public.partner_contracts WHERE id=contract1)<>'archived' OR (SELECT renewed_from_id FROM public.partner_contracts WHERE id=contract2)<>contract1 OR (SELECT count(*) FROM public.partner_contracts WHERE provider_id=provider)<>2 THEN RAISE EXCEPTION 'F9 renewal history';END IF;PERFORM public.rpc_terminate_partner_contract(contract2,'Terminación controlada F9');
 r:=public.rpc_upsert_compliance_requirement(tenant,NULL,'{"code":"provider2_block","name":"Bloqueo proveedor 2","partner_type":"provider","category":"operational","is_required":true,"is_blocking":true,"blocks_operation_assignment":true}');
 INSERT INTO public.operations(tenant_id,reference_code,status,execution_type) VALUES(tenant,'OP-F9-GATE','planned','third_party') RETURNING id INTO operation1;
 BEGIN PERFORM public.rpc_assign_operation_v3(tenant,operation1,p_provider_id=>provider2,p_planned_departure=>now()+interval '1 day');RAISE EXCEPTION 'F9 blocked assignment allowed';EXCEPTION WHEN raise_exception THEN IF SQLERRM='F9 blocked assignment allowed' THEN RAISE;END IF;IF SQLERRM<>'provider_compliance_blocked' THEN RAISE;END IF;END;
 r:=public.rpc_create_provider_compliance_override(operation1,provider2,'Excepción específica F9');IF r->>'success'<>'true' THEN RAISE EXCEPTION 'F9 override create %',r;END IF;r:=public.rpc_assign_operation_v3(tenant,operation1,p_provider_id=>provider2,p_planned_departure=>now()+interval '1 day',p_reason=>'Override F9');IF r->>'success'<>'true' THEN RAISE EXCEPTION 'F9 override assignment %',r;END IF;
 INSERT INTO public.operations(tenant_id,reference_code,status,execution_type,provider_id,provider_name) VALUES(tenant,'OP-F9-CONVERTED','planned','third_party',provider2,'Proveedor bloqueado F9') RETURNING id INTO operation2;
 r:=public.rpc_get_operation_dispatch_readiness(operation2);IF (r->>'provider_compliance_ready')::boolean OR NOT(r->'blocking_reasons'?'provider_compliance_blocked') THEN RAISE EXCEPTION 'F9 planned conversion readiness %',r;END IF;UPDATE public.operations SET notes='Historia sin desasignar' WHERE id=operation1;IF (SELECT provider_id FROM public.operations WHERE id=operation1)<>provider2 THEN RAISE EXCEPTION 'F9 historical assignment changed';END IF;
 IF jsonb_array_length(public.rpc_list_compliance_matrix(tenant,'{}'))<>3 OR jsonb_array_length(public.rpc_export_partner_compliance(tenant,'{}'))=0 OR jsonb_array_length(public.rpc_search_compliance(tenant,'gate',10))=0 OR jsonb_array_length(public.rpc_list_compliance_attention_items(tenant))=0 THEN RAISE EXCEPTION 'F9 matrix/export/search/attention';END IF;
 INSERT INTO public.partner_contracts(tenant_id,provider_id,contract_type,title,starts_on,ends_on,status,created_by) VALUES(tenant,provider,'operational','Contrato automatización F9',current_date,current_date+7,'active',current_setting('f9.admin')::uuid);
 PERFORM set_config('f9.operation',operation1::text,true);PERFORM set_config('f9.expired_record',record1::text,true);
END $admin$;

DO $denials$
DECLARE tenant uuid:=current_setting('f9.tenant')::uuid;r jsonb;
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f9.finance'),'role','authenticated')::text,true);IF public.rpc_list_compliance_requirements(tenant,'{}')->>'error'<>'unauthorized' OR public.rpc_get_compliance_dashboard(tenant)->>'error'<>'unauthorized' OR public.rpc_list_compliance_attention_items(tenant)->>'error'<>'unauthorized' OR public.rpc_create_provider_compliance_override(current_setting('f9.operation')::uuid,current_setting('f9.provider2')::uuid,'Finance override')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F9 Finance denial';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f9.outsider'),'role','authenticated')::text,true);IF public.rpc_list_compliance_matrix(tenant,'{}')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F9 outsider denial';END IF;
END $denials$;

DO $automation$
DECLARE tenant uuid:=current_setting('f9.tenant')::uuid;r jsonb;admin_id uuid:=current_setting('f9.admin')::uuid;finance_id uuid:=current_setting('f9.finance')::uuid;
BEGIN
 r:=private.f9_materialize_notifications(tenant,now());r:=private.f9_materialize_notifications(tenant,now());
 IF (SELECT count(*) FROM public.automation_rules WHERE tenant_id=tenant AND code IN ('partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring'))<>4 THEN RAISE EXCEPTION 'F9 automation rule seed';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.internal_notifications WHERE tenant_id=tenant AND user_id=admin_id AND automation_rule_code='partner_contract_expiring' AND resolved_at IS NULL) OR NOT EXISTS(SELECT 1 FROM public.internal_notifications WHERE tenant_id=tenant AND user_id=admin_id AND automation_rule_code='rate_expiring' AND resolved_at IS NULL) THEN RAISE EXCEPTION 'F9 automation materialization %',r;END IF;
 IF EXISTS(SELECT 1 FROM public.internal_notifications WHERE tenant_id=tenant AND user_id=finance_id AND automation_rule_code IN ('partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring')) THEN RAISE EXCEPTION 'F9 Finance notification leak';END IF;
 IF EXISTS(SELECT 1 FROM public.internal_notifications GROUP BY tenant_id,user_id,fingerprint HAVING count(*)>1) THEN RAISE EXCEPTION 'F9 notification fingerprint duplicate';END IF;
 PERFORM private.f7_generate_tenant_digests(tenant,now());IF EXISTS(SELECT 1 FROM public.automation_daily_digests d,LATERAL jsonb_array_elements(d.items)x WHERE d.user_id=finance_id AND x->>'rule_code' IN ('partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring')) THEN RAISE EXCEPTION 'F9 Finance digest leak';END IF;
 UPDATE public.partner_contracts SET status='terminated' WHERE tenant_id=tenant AND title='Contrato automatización F9';UPDATE public.commercial_rate_versions SET valid_to=current_date+100 WHERE rate_card_id=(SELECT id FROM public.commercial_rate_cards WHERE tenant_id=tenant AND reference='BUY-F9-EXP');PERFORM private.f9_materialize_notifications(tenant,now());
 IF EXISTS(SELECT 1 FROM public.internal_notifications WHERE tenant_id=tenant AND automation_rule_code IN ('partner_contract_expiring','rate_expiring') AND resolved_at IS NULL) THEN RAISE EXCEPTION 'F9 automation resolution';END IF;
END $automation$;

ROLLBACK;
