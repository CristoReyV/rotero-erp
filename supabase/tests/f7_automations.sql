\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE v_signature text; v_oid oid; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_list_automation_rules(uuid)',
        'public.rpc_update_automation_rule(uuid,uuid,jsonb)',
        'public.rpc_evaluate_automations(uuid)',
        'public.rpc_get_automation_health(uuid)',
        'public.rpc_get_daily_digest(uuid)'
    ] LOOP
        v_oid:=to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F7 missing RPC %',v_signature; END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc WHERE oid=v_oid AND prosecdef
              AND proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
        ) THEN RAISE EXCEPTION 'F7 unsafe RPC %',v_signature; END IF;
        IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
           OR has_function_privilege('anon',v_oid,'EXECUTE')
           OR has_function_privilege('service_role',v_oid,'EXECUTE') THEN
            RAISE EXCEPTION 'F7 RPC ACL %',v_signature;
        END IF;
        IF pg_get_functiondef(v_oid) ~* '\mSQLERRM\M' THEN RAISE EXCEPTION 'F7 raw SQLERRM %',v_signature; END IF;
    END LOOP;
    FOREACH v_signature IN ARRAY ARRAY[
        'private.f7_seed_rules(uuid)',
        'private.f7_operation_dispatch_readiness(uuid)',
        'private.f7_materialize_automation_notifications(uuid,uuid,text,timestamptz)',
        'private.f7_generate_tenant_digests(uuid,timestamptz)',
        'private.run_f7_automations()',
        'private.run_f7_daily_digest()'
    ] LOOP
        v_oid:=to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F7 missing private function %',v_signature; END IF;
        IF EXISTS (
               SELECT 1 FROM pg_proc p,
                    LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
               WHERE p.oid=v_oid AND a.grantee=0 AND a.privilege_type='EXECUTE'
           )
           OR has_function_privilege('anon',v_oid,'EXECUTE')
           OR has_function_privilege('authenticated',v_oid,'EXECUTE')
           OR has_function_privilege('service_role',v_oid,'EXECUTE') THEN
            RAISE EXCEPTION 'F7 private ACL %',v_signature;
        END IF;
    END LOOP;
    FOREACH v_table IN ARRAY ARRAY['automation_rules','automation_runs','automation_daily_digests'] LOOP
        IF to_regclass('public.'||v_table) IS NULL
           OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||v_table) AND relrowsecurity) THEN
            RAISE EXCEPTION 'F7 missing table/RLS %',v_table;
        END IF;
        IF has_table_privilege('authenticated','public.'||v_table,'SELECT')
           OR has_table_privilege('authenticated','public.'||v_table,'INSERT')
           OR has_table_privilege('anon','public.'||v_table,'SELECT')
           OR has_table_privilege('service_role','public.'||v_table,'SELECT') THEN
            RAISE EXCEPTION 'F7 direct table privilege %',v_table;
        END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
        RAISE EXCEPTION 'F7 pg_cron not installed';
    END IF;
    IF (SELECT count(*) FROM cron.job WHERE jobname IN ('rotero-f7-automation-hourly','rotero-f7-daily-digest'))<>2
       OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='rotero-f7-automation-hourly' AND schedule='0 * * * *' AND command='SELECT private.run_f7_automations();')
       OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='rotero-f7-daily-digest' AND schedule='15 12 * * *' AND command='SELECT private.run_f7_daily_digest();')
       OR EXISTS (SELECT 1 FROM cron.job WHERE jobname LIKE 'rotero-f7-%' AND command ~* '(http|net|vault|edge)') THEN
        RAISE EXCEPTION 'F7 cron contract failed';
    END IF;
END;
$contract$;

DO $cron_idempotency$
DECLARE v_job record;
BEGIN
    FOR v_job IN
        SELECT jobid FROM cron.job
        WHERE jobname IN ('rotero-f7-automation-hourly','rotero-f7-daily-digest')
    LOOP
        PERFORM cron.unschedule(v_job.jobid);
    END LOOP;
    PERFORM cron.schedule('rotero-f7-automation-hourly','0 * * * *','SELECT private.run_f7_automations();');
    PERFORM cron.schedule('rotero-f7-daily-digest','15 12 * * *','SELECT private.run_f7_daily_digest();');
    IF (SELECT count(*) FROM cron.job WHERE jobname LIKE 'rotero-f7-%')<>2 THEN
        RAISE EXCEPTION 'F7 cron reapply created duplicate jobs';
    END IF;
END;
$cron_idempotency$;

DO $fixtures$
DECLARE
    v_tenant uuid; v_other uuid;
    v_admin uuid:=gen_random_uuid(); v_finance uuid:=gen_random_uuid(); v_outsider uuid:=gen_random_uuid();
    v_customer uuid; v_provider uuid;
    v_dispatch uuid; v_stale uuid; v_future uuid; v_delivered uuid;
    v_incident uuid; v_required_doc uuid; v_pod uuid;
    v_review uuid; v_approved uuid;
    v_ar uuid; v_ap uuid; v_today uuid; v_soon uuid;
    v_now timestamptz:=clock_timestamp();
    v_business_date date;
    v_result jsonb; v_result_2 jsonb;
BEGIN
    v_business_date:=(v_now AT TIME ZONE 'America/Tijuana')::date;
    INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f7-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f7-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_outsider,'authenticated','authenticated','f7-outsider@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES('F7 Tenant','f7-tenant'),('F7 Other','f7-other');
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f7-tenant';
    SELECT id INTO v_other FROM public.tenants WHERE slug='f7-other';
    INSERT INTO public.tenant_settings(tenant_id,timezone) VALUES(v_tenant,'America/Tijuana');
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES
      (v_tenant,v_admin,'admin'),(v_tenant,v_finance,'finance');
    INSERT INTO public.customers(tenant_id,display_name,legal_name,tax_id)
      VALUES(v_tenant,'Cliente F7','Cliente F7 SA','CF700101AA1') RETURNING id INTO v_customer;
    INSERT INTO public.logistics_providers(tenant_id,display_name,legal_name,tax_id)
      VALUES(v_tenant,'Proveedor F7','Proveedor F7 SA','PF700101AA1') RETURNING id INTO v_provider;

    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,status,created_at,updated_at)
      VALUES(v_tenant,'OP-F7-DISPATCH','Cliente F7','planned',v_now-interval '3 days',v_now-interval '2 days')
      RETURNING id INTO v_dispatch;
    INSERT INTO public.operations(
        tenant_id,reference_code,client_display_name,destination_city,status,provider_id,
        service_type,origin_place,destination_place,operational_window_start,operational_window_end,
        planned_departure,created_at,updated_at
    ) VALUES (
        v_tenant,'OP-F7-STALE','Cliente F7','Monterrey','in_transit',v_provider,
        'Carga terrestre','{"municipality":"CDMX","state":"CDMX"}','{"municipality":"Monterrey","state":"NL"}',
        v_now-interval '4 days',v_now-interval '3 days',v_now-interval '4 days',
        v_now-interval '4 days',v_now-interval '3 days'
    ) RETURNING id INTO v_stale;
    INSERT INTO public.operations(
        tenant_id,reference_code,client_display_name,status,operational_window_start,
        planned_departure,created_at,updated_at
    ) VALUES (
        v_tenant,'OP-F7-FUTURE','Cliente F7','planned',v_now+interval '2 days',
        v_now+interval '2 days',v_now-interval '4 days',v_now-interval '3 days'
    ) RETURNING id INTO v_future;
    INSERT INTO public.operations(
        tenant_id,reference_code,client_display_name,destination_city,status,customer_id,provider_id,
        service_type,origin_place,destination_place,operational_window_start,operational_window_end,
        created_at,updated_at
    ) VALUES (
        v_tenant,'OP-F7-DELIVERED','Cliente F7','Guadalajara','delivered',v_customer,v_provider,
        'Carga terrestre','{"municipality":"CDMX","state":"CDMX"}','{"municipality":"Guadalajara","state":"JAL"}',
        v_now-interval '4 days',v_now-interval '3 days',v_now-interval '4 days',v_now-interval '2 days'
    ) RETURNING id INTO v_delivered;
    INSERT INTO public.operation_incidents(
        tenant_id,operation_id,category,title,description,status,is_blocking,reported_by,created_at,updated_at
    ) VALUES (
        v_tenant,v_delivered,'documents_issue','Incidencia bloqueante F7','POD detenido','open',true,v_admin,
        v_now-interval '2 days',v_now-interval '2 days'
    ) RETURNING id INTO v_incident;
    INSERT INTO public.operation_documents(
        tenant_id,operation_id,document_type,requirement_level,status,updated_by,created_at,updated_at
    ) VALUES
      (v_tenant,v_delivered,'loading_order','required','missing',v_admin,v_now-interval '2 days',v_now-interval '2 days')
      RETURNING id INTO v_required_doc;
    INSERT INTO public.operation_documents(
        tenant_id,operation_id,document_type,requirement_level,status,updated_by,created_at,updated_at
    ) VALUES
      (v_tenant,v_delivered,'proof_of_delivery','required','missing',v_admin,v_now-interval '2 days',v_now-interval '2 days')
      RETURNING id INTO v_pod;

    INSERT INTO public.crm_deals(
        tenant_id,customer_id,title,company,stage,quote_status,quote_reference,quote_payload,created_at,updated_at
    ) VALUES (
        v_tenant,v_customer,'Revisión F7','Cliente F7','proposal','in_review','Q-F7-REVIEW','{}',
        v_now-interval '4 days',v_now-interval '3 days'
    ) RETURNING id INTO v_review;
    INSERT INTO public.crm_deals(
        tenant_id,customer_id,title,company,stage,quote_status,quote_reference,quote_payload,
        approved_at,approved_by,created_at,updated_at
    ) VALUES (
        v_tenant,v_customer,'Aprobada F7','Cliente F7','proposal','approved','Q-F7-APPROVED','{}',
        v_now-interval '2 days',v_admin,v_now-interval '3 days',v_now-interval '2 days'
    ) RETURNING id INTO v_approved;

    INSERT INTO public.finance_invoices(
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,customer_id,operation_id,created_at
    ) VALUES (
        v_tenant,'ar','Cliente F7','AR-F7',1000,'MXN','open',v_business_date-4,v_customer,v_delivered,v_now-interval '10 days'
    ) RETURNING id INTO v_ar;
    INSERT INTO public.finance_payments(tenant_id,invoice_id,amount,currency,paid_at,created_by)
      VALUES(v_tenant,v_ar,300,'MXN',v_now-interval '1 day',v_admin);
    INSERT INTO public.finance_invoices(
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,provider_id,operation_id,created_at
    ) VALUES (
        v_tenant,'ap','Proveedor F7','AP-F7',500,'MXN','open',v_business_date-5,v_provider,v_delivered,v_now-interval '10 days'
    ) RETURNING id INTO v_ap;
    INSERT INTO public.finance_invoices(
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,customer_id,created_at
    ) VALUES (
        v_tenant,'ar','Cliente hoy F7','TODAY-F7',250,'MXN','open',v_business_date,v_customer,v_now-interval '2 days'
    ) RETURNING id INTO v_today;
    INSERT INTO public.finance_invoices(
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,provider_id,created_at
    ) VALUES (
        v_tenant,'ap','Proveedor pronto F7','SOON-F7',350,'MXN','open',v_business_date+4,v_provider,v_now-interval '2 days'
    ) RETURNING id INTO v_soon;

    PERFORM private.f7_seed_rules(v_tenant);
    PERFORM private.f7_seed_rules(v_tenant);
    IF (SELECT count(*) FROM public.automation_rules WHERE tenant_id=v_tenant)<>16
       OR (SELECT count(*) FROM public.automation_rules WHERE tenant_id=v_tenant AND code IN ('claim_first_response_overdue','claim_resolution_overdue','claim_action_overdue','critical_claim_open'))<>4 THEN
        RAISE EXCEPTION 'F7 + F9 + F10 default seed not idempotent';
    END IF;
    v_result:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now);
    IF v_result->>'success'<>'true' OR (v_result->>'created')::integer<16 THEN
        RAISE EXCEPTION 'F7 first evaluation failed %',v_result;
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND automation_rule_code='operation_stale' AND related_entity_id=v_future::text
    ) THEN RAISE EXCEPTION 'F7 future operation marked stale'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND user_id=v_admin AND automation_rule_code='operation_stale'
          AND related_entity_id=v_stale::text AND resolved_at IS NULL
    ) THEN RAISE EXCEPTION 'F7 stale operation missing'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND user_id=v_admin AND automation_rule_code='ar_overdue'
          AND related_entity_id=v_ar::text AND (metadata->>'remaining_balance')::numeric=700
    ) THEN RAISE EXCEPTION 'F7 partial AR balance failed'; END IF;
    IF (SELECT count(*) FROM public.internal_notifications WHERE tenant_id=v_tenant AND automation_rule_code='operation_pod_missing')<>2
       OR EXISTS (
           SELECT 1 FROM public.internal_notifications
           WHERE tenant_id=v_tenant AND automation_rule_code='operation_missing_document' AND related_entity_id=v_pod::text
       ) THEN RAISE EXCEPTION 'F7 POD canonical path duplicated'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND user_id=v_finance AND area='commercial'
    ) THEN RAISE EXCEPTION 'F7 Finance Commercial leak'; END IF;
    v_result_2:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now);
    IF (v_result_2->>'created')::integer<>0
       OR EXISTS (
           SELECT 1 FROM public.internal_notifications
           GROUP BY tenant_id,user_id,fingerprint HAVING count(*)>1
       ) THEN RAISE EXCEPTION 'F7 evaluation idempotency failed %',v_result_2; END IF;

    PERFORM private.f7_generate_tenant_digests(v_tenant,v_now);
    PERFORM private.f7_generate_tenant_digests(v_tenant,v_now);
    IF (SELECT count(*) FROM public.automation_daily_digests WHERE tenant_id=v_tenant)<>2
       OR EXISTS (
           SELECT 1 FROM public.automation_daily_digests
           WHERE tenant_id=v_tenant AND business_date<>v_business_date
       ) THEN RAISE EXCEPTION 'F7 digest idempotency/timezone failed'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.automation_daily_digests d,
             LATERAL jsonb_array_elements(d.items) x
        WHERE d.tenant_id=v_tenant AND d.user_id=v_finance AND x->>'module'='commercial'
    ) THEN RAISE EXCEPTION 'F7 Finance digest leak'; END IF;

    PERFORM set_config('f7.tenant',v_tenant::text,true);
    PERFORM set_config('f7.other',v_other::text,true);
    PERFORM set_config('f7.admin',v_admin::text,true);
    PERFORM set_config('f7.finance',v_finance::text,true);
    PERFORM set_config('f7.outsider',v_outsider::text,true);
    PERFORM set_config('f7.incident',v_incident::text,true);
    PERFORM set_config('f7.required_doc',v_required_doc::text,true);
    PERFORM set_config('f7.pod',v_pod::text,true);
    PERFORM set_config('f7.review',v_review::text,true);
    PERFORM set_config('f7.approved',v_approved::text,true);
    PERFORM set_config('f7.ar',v_ar::text,true);
    PERFORM set_config('f7.ap',v_ap::text,true);
    PERFORM set_config('f7.today',v_today::text,true);
    PERFORM set_config('f7.soon',v_soon::text,true);
    PERFORM set_config('f7.now',v_now::text,true);
    PERFORM set_config('f7.business_date',v_business_date::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin$
DECLARE v_tenant uuid:=current_setting('f7.tenant')::uuid; v_rule uuid; v_notification uuid; v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f7.admin'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f7.admin'),'role','authenticated')::text,true);
    v_result:=public.rpc_list_automation_rules(v_tenant);
    IF jsonb_array_length(v_result->'items')<>20
       OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_result->'items') x
           WHERE x->>'code' IN ('partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring')
           HAVING count(*)=4
       ) OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_result->'items') x
           WHERE x->>'code' IN ('claim_first_response_overdue','claim_resolution_overdue','claim_action_overdue','critical_claim_open')
           HAVING count(*)=4
       ) THEN RAISE EXCEPTION 'F7 + F9 + F10 Admin rules list failed %',v_result; END IF;
    SELECT (x->>'id')::uuid INTO v_rule
    FROM jsonb_array_elements(v_result->'items') x WHERE x->>'code'='operation_stale';
    v_result:=public.rpc_update_automation_rule(v_tenant,v_rule,jsonb_build_object(
        'threshold_value',48,'threshold_unit','hours','severity','high',
        'escalation_delay_value',24,'escalation_delay_unit','hours',
        'escalation_severity','critical','target_role','admin_finance',
        'is_enabled',true,'digest_enabled',true
    ));
    IF v_result?'error' OR (v_result->>'threshold_value')::integer<>48 THEN
        RAISE EXCEPTION 'F7 Admin rule update failed %',v_result;
    END IF;
    v_result:=public.rpc_list_automation_rules(v_tenant);
    SELECT (x->>'id')::uuid INTO v_rule
    FROM jsonb_array_elements(v_result->'items') x WHERE x->>'code'='quote_review_stale';
    IF public.rpc_update_automation_rule(v_tenant,v_rule,'{"target_role":"admin_finance"}')->>'error'<>'invalid_payload' THEN
        RAISE EXCEPTION 'F7 unsafe Commercial target accepted';
    END IF;
    v_result:=public.rpc_evaluate_automations(v_tenant);
    IF v_result->>'success'<>'true' OR NOT v_result?'rules_evaluated' THEN
        RAISE EXCEPTION 'F7 manual evaluation failed %',v_result;
    END IF;
    v_result:=public.rpc_get_automation_health(v_tenant);
    IF v_result->>'scheduler_contract_status'<>'ready'
       OR (v_result->>'scheduler_enabled')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'F7 health failed %',v_result;
    END IF;
    v_result:=public.rpc_get_daily_digest(v_tenant);
    IF v_result->'digest' IS NULL
       OR v_result->>'business_date'<>current_setting('f7.business_date') THEN
        RAISE EXCEPTION 'F7 Admin digest failed %',v_result;
    END IF;
    v_result:=public.rpc_list_internal_notifications(v_tenant,100,false);
    SELECT (x->>'id')::uuid INTO v_notification
    FROM jsonb_array_elements(v_result->'items') x
    WHERE (x->>'is_automated')::boolean AND (x->>'escalation_level')::integer=0
    LIMIT 1;
    IF public.rpc_dismiss_internal_notification(v_tenant,v_notification)->>'success'<>'true' THEN
        RAISE EXCEPTION 'F7 dismiss failed';
    END IF;
    PERFORM set_config('f7.dismissed',v_notification::text,true);
END;
$admin$;

DO $finance$
DECLARE v_tenant uuid:=current_setting('f7.tenant')::uuid; v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f7.finance'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f7.finance'),'role','authenticated')::text,true);
    IF public.rpc_list_automation_rules(v_tenant)->>'error'<>'unauthorized'
       OR public.rpc_evaluate_automations(v_tenant)->>'error'<>'unauthorized'
       OR public.rpc_get_automation_health(v_tenant)->>'error'<>'unauthorized' THEN
        RAISE EXCEPTION 'F7 Finance configuration/manual deny failed';
    END IF;
    v_result:=public.rpc_refresh_internal_notifications(v_tenant);
    IF v_result?'error' THEN RAISE EXCEPTION 'F7 Finance own refresh failed %',v_result; END IF;
    v_result:=public.rpc_list_internal_notifications(v_tenant,100,false);
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_result->'items') x WHERE x->>'module'='commercial') THEN
        RAISE EXCEPTION 'F7 Finance feed leak';
    END IF;
    v_result:=public.rpc_get_daily_digest(v_tenant);
    IF v_result->'digest'->>'role'<>'finance'
       OR (v_result#>>'{digest,summary,quotes_pending}')::integer<>0 THEN
        RAISE EXCEPTION 'F7 Finance digest contract failed %',v_result;
    END IF;
END;
$finance$;

DO $outsider$
DECLARE v_tenant uuid:=current_setting('f7.tenant')::uuid; v_other uuid:=current_setting('f7.other')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f7.outsider'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f7.outsider'),'role','authenticated')::text,true);
    IF public.rpc_list_automation_rules(v_tenant)->>'error'<>'unauthorized'
       OR public.rpc_get_daily_digest(v_tenant)->>'error'<>'unauthorized'
       OR public.rpc_evaluate_automations(v_other)->>'error'<>'unauthorized' THEN
        RAISE EXCEPTION 'F7 nonmember/cross-tenant failed';
    END IF;
END;
$outsider$;

RESET ROLE;

DO $lifecycle$
DECLARE
    v_tenant uuid:=current_setting('f7.tenant')::uuid;
    v_now timestamptz:=current_setting('f7.now')::timestamptz;
    v_dismissed uuid:=current_setting('f7.dismissed')::uuid;
    v_result jsonb;
BEGIN
    v_result:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now);
    IF (SELECT dismissed_at FROM public.internal_notifications WHERE id=v_dismissed) IS NULL THEN
        RAISE EXCEPTION 'F7 dismissal loop protection failed';
    END IF;
    v_result:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now+interval '3 days');
    IF (v_result->>'escalated')::integer=0
       OR (SELECT dismissed_at FROM public.internal_notifications WHERE id=v_dismissed) IS NOT NULL THEN
        RAISE EXCEPTION 'F7 escalation/idempotent redisplay failed %',v_result;
    END IF;
    v_result:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now+interval '3 days');
    IF (v_result->>'escalated')::integer<>0 THEN RAISE EXCEPTION 'F7 repeated escalation failed %',v_result; END IF;

    UPDATE public.operation_incidents SET status='resolved',resolved_at=v_now,resolved_by=current_setting('f7.admin')::uuid
    WHERE id=current_setting('f7.incident')::uuid;
    UPDATE public.operation_documents
    SET status='present',document_reference='F7-READY',updated_by=current_setting('f7.admin')::uuid
    WHERE id IN (current_setting('f7.required_doc')::uuid,current_setting('f7.pod')::uuid);
    UPDATE public.crm_deals SET quote_status='rejected',updated_at=v_now
    WHERE id=current_setting('f7.review')::uuid;
    UPDATE public.crm_deals
    SET quote_status='converted',converted_operation_id=(
        SELECT related_entity_id::uuid FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND related_entity_type='operation'
        ORDER BY first_seen_at LIMIT 1
    ),converted_at=v_now,updated_at=v_now
    WHERE id=current_setting('f7.approved')::uuid;
    UPDATE public.finance_invoices SET status='paid',paid_at=v_now WHERE id=current_setting('f7.ar')::uuid;
    UPDATE public.finance_invoices
    SET status='void',voided_at=v_now,voided_by=current_setting('f7.admin')::uuid,
        void_reason='Resolución contractual F7'
    WHERE id=current_setting('f7.ap')::uuid;
    v_result:=private.f7_materialize_automation_notifications(v_tenant,NULL,'scheduled',v_now+interval '3 days 1 hour');
    IF EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND resolved_at IS NULL AND (
            related_entity_id IN (
                current_setting('f7.incident'),current_setting('f7.required_doc'),
                current_setting('f7.review'),current_setting('f7.approved'),
                current_setting('f7.ar'),current_setting('f7.ap')
            )
            OR automation_rule_code='operation_pod_missing'
        )
    ) THEN RAISE EXCEPTION 'F7 automatic resolution failed'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.internal_notifications
        WHERE tenant_id=v_tenant AND resolved_at IS NOT NULL
    ) THEN RAISE EXCEPTION 'F7 historical resolution missing'; END IF;
END;
$lifecycle$;

DO $final$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.internal_notifications
        GROUP BY tenant_id,user_id,fingerprint HAVING count(*)>1
    ) THEN RAISE EXCEPTION 'F7 duplicate notification fingerprint'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.automation_daily_digests
        GROUP BY tenant_id,user_id,business_date HAVING count(*)>1
    ) THEN RAISE EXCEPTION 'F7 duplicate daily digest'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.automation_rules
        GROUP BY tenant_id,code HAVING count(*)>1
    ) THEN RAISE EXCEPTION 'F7 duplicate default rule'; END IF;
END;
$final$;

ROLLBACK;
