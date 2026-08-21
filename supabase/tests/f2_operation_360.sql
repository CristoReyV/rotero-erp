\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE v_signature text; v_oid oid; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_complete_operation_planning_v2(uuid,text,jsonb,jsonb,timestamptz,timestamptz,text,jsonb,text,text,timestamptz,text,text,text,numeric,numeric,text,uuid,jsonb,integer,timestamptz,text)',
        'public.rpc_update_operation_operational_control(uuid,jsonb)',
        'public.rpc_assign_operation_v3(uuid,uuid,text,uuid,text,jsonb,jsonb,uuid,text,uuid,text,timestamptz,text,text,boolean)',
        'public.rpc_list_operation_assignment_history(uuid)',
        'public.rpc_get_operation_dispatch_readiness(uuid)',
        'public.rpc_get_operation_requirements(uuid)',
        'public.rpc_list_operation_tracking_events(uuid)',
        'public.rpc_create_operation_incident(uuid,text,text,text,boolean,uuid)',
        'public.rpc_list_operation_incidents(uuid)',
        'public.rpc_get_operation_incident_summary(uuid)',
        'public.rpc_resolve_operation_incident(uuid,text)',
        'public.rpc_dismiss_operation_incident(uuid,text)',
        'public.rpc_add_operation_evidence(uuid,uuid,text,text,text,text)',
        'public.rpc_list_operation_evidence(uuid,uuid)',
        'public.rpc_list_operation_documents(uuid)',
        'public.rpc_get_operation_document_summary(uuid)',
        'public.rpc_upsert_operation_document(uuid,text,text,text,text,text,text,text)',
        'public.rpc_list_operation_crossings(uuid)',
        'public.rpc_upsert_operation_crossing(uuid,jsonb)',
        'public.rpc_delete_operation_crossing(uuid)',
        'public.rpc_get_operation_billing(uuid)',
        'public.rpc_get_operation_billing_summary(uuid)',
        'public.rpc_transition_operation_status(uuid,text)',
        'public.rpc_override_operation_status(uuid,text,text)',
        'public.rpc_close_operation(uuid)',
        'public.rpc_close_operation_override(uuid,text)',
        'public.rpc_cancel_operation(uuid)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F2 CONTRACT FAILED: missing %', v_signature; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = v_oid AND p.prosecdef
            AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]) THEN
            RAISE EXCEPTION 'F2 CONTRACT FAILED: unsafe attributes %', v_signature;
        END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F2 CONTRACT FAILED: unexpected ACL %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY['operation_assignment_history','operation_incidents','operation_evidence','operation_documents','operation_crossings'] LOOP
        IF to_regclass('public.' || v_table) IS NULL THEN RAISE EXCEPTION 'F2 CONTRACT FAILED: missing table %', v_table; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid = to_regclass('public.' || v_table) AND c.relrowsecurity) THEN
            RAISE EXCEPTION 'F2 CONTRACT FAILED: RLS disabled %', v_table;
        END IF;
        IF has_table_privilege('authenticated', 'public.' || v_table, 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('anon', 'public.' || v_table, 'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'F2 CONTRACT FAILED: direct table privileges %', v_table;
        END IF;
    END LOOP;
    IF to_regclass('public.operation_timeline') IS NOT NULL THEN
        RAISE EXCEPTION 'F2 CONTRACT FAILED: duplicated persisted timeline exists';
    END IF;
END;
$catalog$;

DO $trigger_reconciliation$
DECLARE
    v_table regclass;
    v_expected_name text;
    v_count integer;
    v_helper_oid oid;
    v_helper_owner oid;
BEGIN
    v_helper_oid := to_regprocedure('public.tanda1_touch_updated_at()');
    IF v_helper_oid IS NULL THEN
        RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: canonical helper missing';
    END IF;
    SELECT p.proowner INTO v_helper_owner FROM pg_proc AS p WHERE p.oid = v_helper_oid;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc AS p
        WHERE p.oid = v_helper_oid
          AND p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
    ) THEN
        RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: canonical helper search_path is unsafe';
    END IF;
    IF has_function_privilege('anon', v_helper_oid, 'EXECUTE')
       OR has_function_privilege('authenticated', v_helper_oid, 'EXECUTE')
       OR has_function_privilege('service_role', v_helper_oid, 'EXECUTE')
       OR EXISTS (
           SELECT 1
           FROM pg_proc AS p
           CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) AS acl
           WHERE p.oid = v_helper_oid AND acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
       ) THEN
        RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: canonical helper has direct client execution';
    END IF;
    IF NOT has_function_privilege(v_helper_owner, v_helper_oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: canonical helper owner cannot execute';
    END IF;

    FOR v_table, v_expected_name IN
        SELECT * FROM (VALUES
            ('public.operation_incidents'::regclass, 'trg_operation_incidents_touch_updated_at'::text),
            ('public.operation_documents'::regclass, 'trg_operation_documents_touch_updated_at'::text),
            ('public.operation_crossings'::regclass, 'trg_operation_crossings_touch_updated_at'::text)
        ) AS expected(table_oid, trigger_name)
    LOOP
        SELECT count(*) INTO v_count
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE t.tgrelid = v_table
          AND t.tgname = v_expected_name
          AND NOT t.tgisinternal
          AND (t.tgtype & 1) = 1
          AND (t.tgtype & 2) = 2
          AND (t.tgtype & 16) = 16
          AND n.nspname = 'public'
          AND p.proname = 'tanda1_touch_updated_at'
          AND p.pronargs = 0;

        IF v_count <> 1 THEN
            RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: expected named canonical touch trigger on %, found %', v_table, v_count;
        END IF;

        SELECT count(*) INTO v_count
        FROM pg_trigger AS t
        JOIN pg_proc AS p ON p.oid = t.tgfoid
        JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE t.tgrelid = v_table
          AND NOT t.tgisinternal
          AND (t.tgtype & 1) = 1
          AND (t.tgtype & 2) = 2
          AND (t.tgtype & 16) = 16
          AND n.nspname = 'public'
          AND p.proname IN ('tanda1_touch_updated_at', 'touch_updated_at')
          AND p.pronargs = 0;
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: expected exactly one equivalent touch trigger on %, found %', v_table, v_count;
        END IF;
        IF EXISTS (
            SELECT 1
            FROM pg_trigger AS t
            JOIN pg_proc AS p ON p.oid = t.tgfoid
            JOIN pg_namespace AS n ON n.oid = p.pronamespace
            WHERE t.tgrelid = v_table
              AND NOT t.tgisinternal
              AND n.nspname = 'public'
              AND p.proname = 'touch_updated_at'
              AND p.pronargs = 0
        ) THEN
            RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: F2 target trigger depends on historical touch_updated_at on %', v_table;
        END IF;
    END LOOP;

    -- A second semantic reconciliation pass must see all three equivalents and remain a no-op.
    IF EXISTS (
        SELECT 1
        FROM (VALUES
            ('public.operation_incidents'::regclass),
            ('public.operation_documents'::regclass),
            ('public.operation_crossings'::regclass)
        ) AS target(table_oid)
        WHERE NOT EXISTS (
            SELECT 1
            FROM pg_trigger t
            JOIN pg_proc p ON p.oid = t.tgfoid
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE t.tgrelid = target.table_oid
              AND NOT t.tgisinternal
              AND (t.tgtype & 1) = 1
              AND (t.tgtype & 2) = 2
              AND (t.tgtype & 16) = 16
              AND n.nspname = 'public'
              AND p.proname = 'tanda1_touch_updated_at'
              AND p.pronargs = 0
        )
    ) THEN
        RAISE EXCEPTION 'F2 TRIGGER CONTRACT FAILED: reconciliation would create a duplicate on rerun';
    END IF;
END;
$trigger_reconciliation$;

DO $fixtures$
DECLARE
    v_tenant_a uuid; v_tenant_b uuid;
    v_admin uuid := gen_random_uuid(); v_operator uuid := gen_random_uuid();
    v_finance uuid := gen_random_uuid(); v_viewer uuid := gen_random_uuid(); v_nonmember uuid := gen_random_uuid();
    v_customer uuid; v_provider uuid; v_provider_2 uuid; v_service uuid;
    v_driver uuid; v_driver_inactive uuid; v_vehicle uuid; v_vehicle_inactive uuid;
    v_national uuid; v_busy_operation uuid; v_foreign_operation uuid; v_foreign_incident uuid;
BEGIN
    INSERT INTO auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f2-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_operator,'authenticated','authenticated','f2-operator@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f2-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_viewer,'authenticated','authenticated','f2-viewer@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_nonmember,'authenticated','authenticated','f2-none@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES ('F2 A','f2-a'),('F2 B','f2-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug='f2-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug='f2-b';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES
      (v_tenant_a,v_admin,'admin'),(v_tenant_a,v_operator,'operator'),
      (v_tenant_a,v_finance,'finance'),(v_tenant_a,v_viewer,'viewer');
    INSERT INTO public.customers(tenant_id,display_name) VALUES (v_tenant_a,'Cliente F2') RETURNING id INTO v_customer;
    INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES (v_tenant_a,'Proveedor Uno') RETURNING id INTO v_provider;
    INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES (v_tenant_a,'Proveedor Dos') RETURNING id INTO v_provider_2;
    INSERT INTO public.drivers(tenant_id,display_name,status) VALUES (v_tenant_a,'Chofer disponible','available') RETURNING id INTO v_driver;
    INSERT INTO public.drivers(tenant_id,display_name,status) VALUES (v_tenant_a,'Chofer inactivo','inactive') RETURNING id INTO v_driver_inactive;
    INSERT INTO public.vehicles(tenant_id,unit_code,status) VALUES (v_tenant_a,'F2-UNIT-1','available') RETURNING id INTO v_vehicle;
    INSERT INTO public.vehicles(tenant_id,unit_code,status) VALUES (v_tenant_a,'F2-UNIT-X','inactive') RETURNING id INTO v_vehicle_inactive;
    INSERT INTO public.service_catalog_items(tenant_id,service_type,service_class,presentation,packaging,modality)
      VALUES(v_tenant_a,'Carga terrestre','FTL','Seca','Caja','Puerta a puerta') RETURNING id INTO v_service;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,operation_scope,status)
      VALUES(v_tenant_a,'F2-NATIONAL','Cliente F2','national','planned') RETURNING id INTO v_national;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,operation_scope,status,execution_type,driver_id,vehicle_id)
      VALUES(v_tenant_a,'F2-BUSY','Cliente F2','national','assigned','own_fleet',v_driver,v_vehicle) RETURNING id INTO v_busy_operation;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,operation_scope,status)
      VALUES(v_tenant_b,'F2-FOREIGN','Otro','international','planned') RETURNING id INTO v_foreign_operation;
    INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,is_blocking,reported_by)
      VALUES(v_tenant_b,v_foreign_operation,'general','Ajena',false,v_admin) RETURNING id INTO v_foreign_incident;
    PERFORM set_config('f2.tenant_a',v_tenant_a::text,true); PERFORM set_config('f2.tenant_b',v_tenant_b::text,true);
    PERFORM set_config('f2.admin',v_admin::text,true); PERFORM set_config('f2.operator',v_operator::text,true);
    PERFORM set_config('f2.finance',v_finance::text,true); PERFORM set_config('f2.viewer',v_viewer::text,true);
    PERFORM set_config('f2.nonmember',v_nonmember::text,true); PERFORM set_config('f2.customer',v_customer::text,true);
    PERFORM set_config('f2.provider',v_provider::text,true); PERFORM set_config('f2.provider2',v_provider_2::text,true);
    PERFORM set_config('f2.service',v_service::text,true); PERFORM set_config('f2.national',v_national::text,true);
    PERFORM set_config('f2.driver',v_driver::text,true); PERFORM set_config('f2.driver_inactive',v_driver_inactive::text,true);
    PERFORM set_config('f2.vehicle',v_vehicle::text,true); PERFORM set_config('f2.vehicle_inactive',v_vehicle_inactive::text,true);
    PERFORM set_config('f2.foreign_operation',v_foreign_operation::text,true);
    PERFORM set_config('f2.foreign_incident',v_foreign_incident::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin_f1_compatibility$
DECLARE
    v_tenant uuid := current_setting('f2.tenant_a')::uuid; v_customer uuid := current_setting('f2.customer')::uuid;
    v_provider uuid := current_setting('f2.provider')::uuid; v_service uuid := current_setting('f2.service')::uuid;
    v_quote jsonb; v_quote_id uuid; v_result jsonb; v_operation uuid; v_detail jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.admin'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f2.admin'),'role','authenticated')::text,true);
    v_quote := public.rpc_upsert_quote(v_tenant,NULL,jsonb_build_object(
      'title','F2 desde F1','customer_id',v_customer,'provider_id',v_provider,
      'operation_scope','international','execution_type','third_party','service_type','Carga terrestre',
      'service_catalog_item_id',v_service,'service_catalog_snapshot',jsonb_build_object('service_type','Carga terrestre','source','F1-F2 QA'),
      'pricing_currency','USD','provider_cost_amount',800,'customer_price_amount',1000,
      'origin_place',jsonb_build_object('municipality','Monterrey','state','Nuevo León','countryCode','MX'),
      'destination_place',jsonb_build_object('municipality','Laredo','state','Texas','countryCode','US'),
      'operational_window_start','2026-09-01T15:00:00Z','operational_window_end','2026-09-01T21:00:00Z',
      'cargo_summary',jsonb_build_object('description','Autopartes','pieces',24),
      'external_driver',jsonb_build_object('name','Operador proveedor'),
      'external_vehicle',jsonb_build_object('unit','EXT-77'),
      'eta','2026-09-02T04:00:00Z','eta_display','02 sep, 04:00','valid_until','2026-08-31'
    ));
    IF v_quote ? 'error' THEN RAISE EXCEPTION 'F2 F1 COMPAT FAILED: quote %',v_quote; END IF;
    v_quote_id := (v_quote->>'id')::uuid;
    IF public.rpc_submit_quote_for_review(v_quote_id) ? 'error' OR public.rpc_approve_quote(v_quote_id,'Aprobada') ? 'error' THEN
      RAISE EXCEPTION 'F2 F1 COMPAT FAILED: lifecycle'; END IF;
    v_result := public.rpc_convert_quote_to_operation(v_quote_id,'F2 handoff');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 F1 COMPAT FAILED: convert %',v_result; END IF;
    v_operation := (v_result->>'operation_id')::uuid; PERFORM set_config('f2.operation',v_operation::text,true);
    v_detail := public.rpc_get_operation(v_operation);
    IF (v_detail->>'customer_id')::uuid <> v_customer OR (v_detail->>'provider_id')::uuid <> v_provider
       OR v_detail->>'execution_type' <> 'third_party' OR v_detail#>>'{cargo_summary,description}' <> 'Autopartes'
       OR (v_detail->>'operational_window_start')::timestamptz <> '2026-09-01T15:00:00Z'::timestamptz
       OR v_detail#>>'{service_catalog_snapshot,source}' <> 'F1-F2 QA'
       OR (v_detail->>'provider_cost_amount')::numeric <> 800 OR (v_detail->>'customer_price_amount')::numeric <> 1000
       OR v_detail->>'pricing_currency' <> 'USD' OR (v_detail->>'source_deal_id')::uuid <> v_quote_id THEN
      RAISE EXCEPTION 'F2 F1 COMPAT FAILED: rich fields %',v_detail; END IF;
END;
$admin_f1_compatibility$;

DO $admin_vertical$
DECLARE
    v_operation uuid := current_setting('f2.operation')::uuid; v_tenant uuid := current_setting('f2.tenant_a')::uuid;
    v_national uuid := current_setting('f2.national')::uuid;
    v_provider uuid := current_setting('f2.provider')::uuid; v_provider2 uuid := current_setting('f2.provider2')::uuid;
    v_service uuid := current_setting('f2.service')::uuid; v_result jsonb; v_detail jsonb; v_incident uuid; v_dismiss uuid; v_crossing uuid;
    v_driver uuid := current_setting('f2.driver')::uuid; v_driver_inactive uuid := current_setting('f2.driver_inactive')::uuid;
    v_vehicle uuid := current_setting('f2.vehicle')::uuid; v_vehicle_inactive uuid := current_setting('f2.vehicle_inactive')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.admin'),true);
    v_result := public.rpc_complete_operation_planning_v2(v_national,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León"}',
      '{"municipality":"Saltillo","state":"Coahuila","countryCode":"MX"}',
      '2026-09-01T15:00:00Z','2026-09-01T21:00:00Z',NULL,'{"description":"Carga"}');
    IF v_result->>'error' <> 'incomplete_places' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: incomplete place accepted %',v_result; END IF;
    v_result := public.rpc_complete_operation_planning_v2(v_national,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León","countryCode":"MX"}',
      '{"municipality":"Austin","state":"Texas","countryCode":"US"}',
      '2026-09-01T15:00:00Z','2026-09-01T21:00:00Z',NULL,'{"description":"Carga"}');
    IF v_result->>'error' <> 'invalid_national_country' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: foreign national route accepted %',v_result; END IF;
    v_result := public.rpc_complete_operation_planning_v2(v_national,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León","countryCode":"MX"}',
      '{"municipality":"Saltillo","state":"Coahuila","countryCode":"MX"}',
      '2026-09-01T15:00:00Z','2026-09-01T21:00:00Z',NULL,'{}');
    IF v_result->>'error' <> 'missing_cargo_summary' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: empty cargo accepted %',v_result; END IF;
    v_result := public.rpc_complete_operation_planning_v2(v_national,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León","countryCode":"MX"}',
      '{"municipality":"Saltillo","state":"Coahuila","countryCode":"MX"}',
      '2026-09-01T15:00:00Z','2026-09-01T21:00:00Z',NULL,'{"description":"Carga"}');
    v_detail := public.rpc_get_operation(v_national);
    IF v_result ? 'error' OR v_detail->>'route_summary' <> 'Monterrey, Nuevo León -> Saltillo, Coahuila'
       OR v_detail->>'destination_city' <> 'Saltillo' THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: planning fallbacks %, %',v_result,v_detail; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_national,'own_fleet',NULL,NULL,'{}','{}',v_driver_inactive,NULL,v_vehicle_inactive,NULL,'2026-09-01T14:00:00Z');
    IF v_result->>'error' <> 'driver_unavailable' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: unavailable fleet accepted %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_national,'own_fleet',NULL,NULL,'{}','{}',v_driver,NULL,v_vehicle,NULL,'2026-09-01T14:00:00Z');
    IF v_result->>'error' <> 'driver_occupied' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: occupied fleet accepted %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_national,'own_fleet',NULL,NULL,'{}','{}',v_driver,NULL,v_vehicle,NULL,'2026-09-01T14:00:00Z','normal','Override controlado',true);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: admin fleet override %',v_result; END IF;
    v_result := public.rpc_complete_operation_planning_v2(v_operation,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León","countryCode":"MX"}',
      '{"municipality":"Laredo","state":"Texas","countryCode":"US"}',
      '2026-09-01T15:00:00Z','2026-09-01T14:00:00Z',NULL,'{}','Monterrey → Laredo','Laredo',
      '2026-09-02T04:00:00Z','02 sep','international','third_party',800,1000,'USD',v_service,'{"source":"F1-F2 QA"}',2,NULL,'Recibida');
    IF v_result->>'error' <> 'invalid_operational_window' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: invalid chronology accepted %',v_result; END IF;
    v_result := public.rpc_complete_operation_planning_v2(v_operation,'Carga terrestre',
      '{"municipality":"Monterrey","state":"Nuevo León","countryCode":"MX"}',
      '{"municipality":"Laredo","state":"Texas","countryCode":"US"}',
      '2026-09-01T15:00:00Z','2026-09-01T21:00:00Z','Notas','{"description":"Autopartes"}','Monterrey → Laredo','Laredo',
      '2026-09-02T04:00:00Z','02 sep','international','third_party',800,1000,'USD',v_service,'{"source":"F1-F2 QA"}',2,NULL,'Recibida');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: planning %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',v_provider,NULL,'{}','{}',NULL,NULL,NULL,NULL,'2026-09-01T14:00:00Z','high',NULL,false);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: third-party assignment %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',v_provider2,NULL,'{"name":"Chofer externo","phone":"555"}','{"plates":"EXT-2"}',NULL,NULL,NULL,NULL,'2026-09-01T14:30:00Z','high',NULL,false);
    IF v_result->>'error' <> 'missing_reassignment_reason' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: reason not required %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',v_provider2,NULL,'{"name":"Chofer externo"}','{"plates":"EXT-2"}',NULL,NULL,NULL,NULL,'2026-09-01T14:30:00Z','high','Cambio confirmado',false);
    IF v_result ? 'error' OR jsonb_array_length(public.rpc_list_operation_assignment_history(v_operation)) <> 2 THEN RAISE EXCEPTION 'F2 ADMIN FAILED: reassignment/history %',v_result; END IF;
    v_result := public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',v_provider2,NULL,'{"name":"Chofer externo"}','{"plates":"EXT-2"}',NULL,NULL,NULL,NULL,'2026-09-01T14:30:00Z','high',NULL,false);
    IF v_result ? 'error' OR jsonb_array_length(public.rpc_list_operation_assignment_history(v_operation)) <> 2 THEN RAISE EXCEPTION 'F2 ADMIN FAILED: no-op history duplicated %',v_result; END IF;
    IF public.rpc_update_operation_operational_control(v_operation,'{"boxes_placed_days":-1}')->>'error' <> 'invalid_boxes_placed_days'
       OR public.rpc_update_operation_operational_control(v_operation,'{"documentation_received_note":"Control actualizado"}') ? 'error' THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: operational control reconciliation'; END IF;

    v_result := public.rpc_create_operation_incident(v_operation,'delay','Demora aduanal','Fila',true,NULL);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: create incident %',v_result; END IF; v_incident := (v_result->>'id')::uuid;
    PERFORM set_config('f2.incident', v_incident::text, true);
    v_result := public.rpc_add_operation_evidence(v_operation,v_incident,'external_link',NULL,NULL,'ftp://invalid');
    IF v_result->>'error' <> 'invalid_external_url' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: invalid URL accepted %',v_result; END IF;
    v_result := public.rpc_add_operation_evidence(v_operation,current_setting('f2.foreign_incident')::uuid,'operational_note','Ajena',NULL,NULL);
    IF v_result->>'error' <> 'invalid_incident' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: foreign incident accepted %',v_result; END IF;
    IF public.rpc_add_operation_evidence(v_operation,v_incident,'operational_note','Seguimiento activo',NULL,NULL) ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: evidence'; END IF;
    IF public.rpc_resolve_operation_incident(v_incident,'Liberado') ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: resolve'; END IF;
    v_result := public.rpc_create_operation_incident(v_operation,'general','Aviso','No bloquea',false,NULL); v_dismiss := (v_result->>'id')::uuid;
    IF public.rpc_dismiss_operation_incident(v_dismiss,'No aplica') ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: dismiss'; END IF;

    v_result := public.rpc_upsert_operation_document(v_operation,'proof_of_delivery','required','present',NULL,NULL,NULL,NULL);
    IF v_result->>'error' <> 'missing_content' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: empty present doc accepted %',v_result; END IF;
    v_result := public.rpc_upsert_operation_document(v_operation,'proof_of_delivery','required','present','POD-001',NULL,'https://example.invalid/pod','Entregado');
    IF v_result ? 'error'
       OR COALESCE((public.rpc_get_operation_document_summary(v_operation)->>'pod_present')::boolean,false) IS NOT TRUE THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: POD %, %', v_result, public.rpc_get_operation_document_summary(v_operation); END IF;

    v_result := public.rpc_upsert_operation_crossing(v_operation,'{"crossed_at":"2026-09-01T20:00:00Z","crossing_point":"Colombia","crossing_type":"exit"}');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: crossing %',v_result; END IF; v_crossing := v_result#>>'{item,id}';
    IF jsonb_array_length(public.rpc_list_operation_crossings(v_operation)) <> 1 THEN RAISE EXCEPTION 'F2 ADMIN FAILED: list crossings'; END IF;
    IF public.rpc_upsert_operation_crossing(current_setting('f2.national')::uuid,'{"crossing_point":"N/A","crossing_type":"other"}')->>'error' <> 'national_operation' THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: national crossing accepted'; END IF;

    v_result := public.rpc_get_operation_dispatch_readiness(v_operation);
    IF COALESCE((v_result->>'is_minimum_planned_complete')::boolean,false) IS NOT TRUE
       OR COALESCE((v_result->>'is_assignment_complete')::boolean,false) IS NOT TRUE
       OR COALESCE((v_result->>'is_tracking_ready')::boolean,true) IS NOT FALSE
       OR NOT (v_result ? 'has_incident' AND v_result ? 'last_signal_at' AND v_result ? 'current_tracking_status') THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: readiness %',v_result; END IF;
    IF public.rpc_transition_operation_status(v_operation,'in_transit')->>'error' <> 'tracking_not_ready' THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: tracking guard weakened'; END IF;
    IF public.rpc_delete_operation_crossing(v_crossing) ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: delete crossing'; END IF;
    v_result := public.rpc_upsert_operation_crossing(v_operation,'{"crossed_at":"2026-09-01T20:30:00Z","crossing_point":"Laredo","crossing_type":"entry"}');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F2 ADMIN FAILED: finance denial crossing fixture %',v_result; END IF;
    PERFORM set_config('f2.finance_crossing',v_result#>>'{item,id}',true);
    IF public.rpc_get_operation(gen_random_uuid())->>'error' <> 'not_found'
       OR public.rpc_list_operation_incidents(gen_random_uuid())->>'error' <> 'not_found' THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: invalid IDs'; END IF;
END;
$admin_vertical$;

RESET ROLE;

DO $close_fixture$
DECLARE v_operation uuid := current_setting('f2.operation')::uuid; v_tenant uuid := current_setting('f2.tenant_a')::uuid;
BEGIN
    UPDATE public.operations SET status = 'delivered' WHERE id = v_operation;
    INSERT INTO public.operation_billing(tenant_id, operation_id, status, billing_reference, issued_at)
    VALUES(v_tenant, v_operation, 'issued', 'F2-BILL-001', now())
    ON CONFLICT (operation_id) DO UPDATE SET status = 'issued', billing_reference = 'F2-BILL-001', issued_at = now();
END;
$close_fixture$;

SET LOCAL ROLE authenticated;

DO $admin_close$
DECLARE v_operation uuid := current_setting('f2.operation')::uuid; v_result jsonb; v_billing jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.admin'),true);
    v_result := public.rpc_close_operation(v_operation);
    v_billing := public.rpc_get_operation_billing(v_operation);
    IF v_result ? 'error' OR v_billing->>'status' <> 'issued'
       OR v_billing->>'admin_closed_at' IS NULL
       OR COALESCE((v_billing->>'admin_close_override')::boolean,true) IS NOT FALSE THEN
      RAISE EXCEPTION 'F2 ADMIN FAILED: guarded close metadata %, %', v_result, v_billing;
    END IF;
END;
$admin_close$;

DO $finance_read_only$
DECLARE v_operation uuid := current_setting('f2.operation')::uuid; v_tenant uuid := current_setting('f2.tenant_a')::uuid; v_provider uuid := current_setting('f2.provider')::uuid; v_incident uuid := current_setting('f2.incident')::uuid; v_crossing uuid := current_setting('f2.finance_crossing')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.finance'),true);
    IF public.rpc_get_operation(v_operation) ? 'error' OR public.rpc_get_operation(v_operation)->>'pricing_currency' <> 'USD'
       OR public.rpc_list_operations(v_tenant) ? 'error' OR public.rpc_list_operation_incidents(v_operation) ? 'error'
       OR public.rpc_list_operation_evidence(v_operation,NULL) ? 'error' OR public.rpc_list_operation_documents(v_operation) ? 'error'
       OR public.rpc_list_operation_crossings(v_operation) ? 'error' OR public.rpc_get_operation_dispatch_readiness(v_operation) ? 'error'
       OR public.rpc_get_operation_billing_summary(v_operation) ? 'error' THEN RAISE EXCEPTION 'F2 FINANCE FAILED: read denied'; END IF;
    IF public.rpc_complete_operation_planning_v2(v_operation,'X','{}','{}',now(),now()+interval '1 hour')->>'error' <> 'unauthorized'
       OR public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',v_provider)->>'error' <> 'unauthorized'
       OR public.rpc_create_operation_incident(v_operation,'general','No')->>'error' <> 'unauthorized'
       OR public.rpc_resolve_operation_incident(v_incident,'No')->>'error' <> 'unauthorized'
       OR public.rpc_dismiss_operation_incident(v_incident,'No')->>'error' <> 'unauthorized'
       OR public.rpc_add_operation_evidence(v_operation,NULL,'operational_note','No')->>'error' <> 'unauthorized'
       OR public.rpc_upsert_operation_document(v_operation,'loading_order','optional','missing')->>'error' <> 'unauthorized'
       OR public.rpc_upsert_operation_crossing(v_operation,'{"crossing_point":"No"}')->>'error' <> 'unauthorized'
       OR public.rpc_delete_operation_crossing(v_crossing)->>'error' <> 'unauthorized'
       OR public.rpc_transition_operation_status(v_operation,'in_transit')->>'error' <> 'unauthorized'
       OR public.rpc_override_operation_status(v_operation,'cancelled','Motivo financiero inválido')->>'error' <> 'unauthorized'
       OR public.rpc_close_operation(v_operation)->>'error' <> 'unauthorized'
       OR public.rpc_close_operation_override(v_operation,'Motivo financiero inválido')->>'error' <> 'unauthorized'
       OR public.rpc_cancel_operation(v_operation)->>'error' <> 'unauthorized' THEN
      RAISE EXCEPTION 'F2 FINANCE FAILED: mutation allowed'; END IF;
END;
$finance_read_only$;

DO $product_roles_and_isolation$
DECLARE v_operation uuid := current_setting('f2.operation')::uuid; v_foreign uuid := current_setting('f2.foreign_operation')::uuid; v_tenant uuid := current_setting('f2.tenant_a')::uuid;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.viewer'),true);
    IF public.rpc_get_operation(v_operation) ? 'error' OR public.rpc_list_operation_documents(v_operation) ? 'error'
       OR public.rpc_add_operation_evidence(v_operation,NULL,'operational_note','No')->>'error' <> 'unauthorized' THEN
      RAISE EXCEPTION 'F2 PRODUCT FAILED: viewer contract'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.operator'),true);
    IF public.rpc_add_operation_evidence(v_operation,NULL,'operational_note','Operador permitido') ? 'error' THEN
      RAISE EXCEPTION 'F2 PRODUCT FAILED: operator semantics removed'; END IF;
    IF public.rpc_assign_operation_v3(v_tenant,v_operation,'third_party',NULL,NULL,'{}','{}',NULL,NULL,NULL,NULL,now(),'normal','Razón',true)->>'error' <> 'unauthorized' THEN
      RAISE EXCEPTION 'F2 PRODUCT FAILED: operator force override allowed'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.admin'),true);
    IF public.rpc_get_operation(v_foreign)->>'error' <> 'unauthorized' THEN RAISE EXCEPTION 'F2 ISOLATION FAILED: cross tenant'; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f2.nonmember'),true);
    IF public.rpc_list_operations(v_tenant)->>'error' <> 'unauthorized' OR public.rpc_get_operation(v_operation)->>'error' <> 'unauthorized' THEN
      RAISE EXCEPTION 'F2 ISOLATION FAILED: nonmember'; END IF;
END;
$product_roles_and_isolation$;

RESET ROLE;

DO $regression_shape$
BEGIN
    IF (SELECT count(*) FROM public.operations WHERE source_deal_id IS NOT NULL) <> 1 THEN
      RAISE EXCEPTION 'F2 REGRESSION FAILED: F1 conversion duplicated'; END IF;
    IF EXISTS (SELECT 1 FROM public.operation_evidence e JOIN public.operation_incidents i ON i.id=e.incident_id WHERE e.operation_id<>i.operation_id) THEN
      RAISE EXCEPTION 'F2 REGRESSION FAILED: invalid evidence relation'; END IF;
END;
$regression_shape$;

ROLLBACK;
