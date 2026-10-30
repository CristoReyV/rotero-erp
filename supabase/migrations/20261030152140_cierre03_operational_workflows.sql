-- Explicit work grants, guarded operation commands and durable retry receipts.
-- No assignments, historical classification or activation is performed here.
BEGIN;
DO $source53$
DECLARE f record;
BEGIN
 SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.oid='public.rpc_delivery_context(uuid)'::regprocedure;
 IF f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.prorettype<>'jsonb'::regtype
  OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""']
  OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>'5c9d1c47a766dde5211bff8da50f7d8e'
 THEN RAISE EXCEPTION 'c03_context_source_drift';END IF;
 IF (SELECT md5(pg_get_constraintdef(oid,true)) FROM pg_constraint WHERE conrelid='public.membership_company_capabilities'::regclass
  AND conname='membership_company_capabilities_capability_code_check') IS DISTINCT FROM '46a8de390deb2b0d9b9d6f7ffdbbd25e'
 THEN RAISE EXCEPTION 'c03_capability_source_drift';END IF;
END $source53$;
SET LOCAL ROLE rotero_company_access_owner;
ALTER TABLE public.membership_company_capabilities DROP CONSTRAINT membership_company_capabilities_capability_code_check;
ALTER TABLE public.membership_company_capabilities ADD CONSTRAINT membership_company_capabilities_capability_code_check CHECK(capability_code IN(
 'operations.read','operations.capture','operations.edit','operations.plan','operations.assign','operations.transition','operations.evidence.write',
 'billing.draft','billing.document.read','documents.upload','documents.manage','receivables.read','export.operational','export.receivables',
 'companies.manage','memberships.manage','company_access.manage','financial.full.read','export.financial',
 'fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment','receivables.collect','finance.write','pipeline.read','inventory.read','automations.manage'));
GRANT EXECUTE ON FUNCTION private.multi05_request_actor() TO rotero_delivery_capture_owner;
SET LOCAL ROLE postgres;
ALTER TABLE public.operations ADD COLUMN workflow_revision bigint NOT NULL DEFAULT 0 CHECK(workflow_revision>=0);
-- Revision bookkeeping is not a business-time update. Preserve the clock used
-- by the existing duration metric; actual core writes retain their old rules.
CREATE FUNCTION private.c03_operation_revision_clock() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.workflow_revision IS DISTINCT FROM OLD.workflow_revision
  AND (to_jsonb(NEW)-ARRAY['workflow_revision','updated_at']) IS NOT DISTINCT FROM(to_jsonb(OLD)-ARRAY['workflow_revision','updated_at'])
 THEN NEW.updated_at:=OLD.updated_at;END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.c03_operation_revision_clock() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER zzzz_c03_operation_revision_clock BEFORE UPDATE ON public.operations
 FOR EACH ROW EXECUTE FUNCTION private.c03_operation_revision_clock();
SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO postgres;
SET LOCAL ROLE postgres;

-- Only the already limited capture owner may use these receipts. Request hashes
-- and minimal outcomes are retained; bodies/notes/financial payloads are not.
CREATE TABLE private.c03_operation_commands(
 tenant_id uuid NOT NULL,company_id uuid NOT NULL,actor_id uuid NOT NULL,request_id uuid NOT NULL,
 operation_id uuid NOT NULL,action text NOT NULL,request_hash text NOT NULL CHECK(request_hash ~ '^[a-f0-9]{64}$'),
 outcome jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,actor_id,request_id),
 FOREIGN KEY(tenant_id,operation_id) REFERENCES public.operations(tenant_id,id) ON DELETE RESTRICT,
 FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT);
SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES(tenant_id,id) ON public.companies FROM postgres;
SET LOCAL ROLE postgres;
ALTER TABLE private.c03_operation_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c03_operation_commands FROM PUBLIC,anon,authenticated,service_role;
GRANT CREATE ON SCHEMA private TO rotero_delivery_capture_owner;
ALTER TABLE private.c03_operation_commands OWNER TO rotero_delivery_capture_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_delivery_capture_owner;

CREATE FUNCTION private.c03_financial_change(p_tenant uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT private.delivery_cap(p_tenant,'financial.full.read') AND private.delivery_cap(p_tenant,'finance.write');
$$;
REVOKE ALL ON FUNCTION private.c03_financial_change(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.c03_lock_assignment_resources(p_tenant uuid,p_driver uuid,p_vehicle uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT(private.delivery_cap(p_tenant,'operations.assign') OR private.delivery_cap(p_tenant,'operations.transition')) OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
  OR NOT public.tanda1_user_has_role(p_tenant,ARRAY['admin','operator']) THEN RAISE insufficient_privilege;END IF;
 PERFORM 1 FROM public.drivers WHERE id=p_driver AND tenant_id=p_tenant FOR UPDATE;
 PERFORM 1 FROM public.vehicles WHERE id=p_vehicle AND tenant_id=p_tenant FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION private.c03_lock_assignment_resources(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.c03_lock_assignment_resources(uuid,uuid,uuid) TO rotero_delivery_capture_owner;

CREATE FUNCTION private.c03_lock_transition_resources(p_tenant uuid,p_operation uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d uuid;v uuid;
BEGIN
 IF NOT private.delivery_cap(p_tenant,'operations.transition') OR NOT private.delivery_entity_allowed(p_tenant,'operation',p_operation)
 THEN RAISE insufficient_privilege;END IF;
 SELECT driver_id,vehicle_id INTO d,v FROM public.operations WHERE tenant_id=p_tenant AND id=p_operation;
 PERFORM private.c03_lock_assignment_resources(p_tenant,d,v);
END $$;
REVOKE ALL ON FUNCTION private.c03_lock_transition_resources(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.c03_lock_transition_resources(uuid,uuid) TO rotero_delivery_capture_owner;

-- Pin each reviewed core before cloning; unknown changes must abort, not be
-- admitted by a blanket new hash. Same normalized bodies were checked on A/B53.
DO $reviewed_cores$
DECLARE r record;f record;d text;key text;financial text;assignment text;
BEGIN
 FOR r IN SELECT * FROM(VALUES
  ('39930cd5b2225b32b375','edit','77faba19eda0a480f0987497dc12307f'),
  ('9e95f351b63d1aeda4cb','plan','b315b4ecc499f5a07e129a778fe1d9fa'),
  ('21432671d8399568207c','assign','890ff3b76e336c8093cc8f681a6432e8'),
  ('a073d61eea6a26b9f8da','transition','bc317002949eedc3bc262b0fa40db61a'),
  ('9b6a7143f718bd678d48','control','e09eb7cf1622c25e02a693b4d7e9b568'))v(tag,action,body_md5)
 LOOP
  SELECT p.*,pg_get_function_identity_arguments(p.oid) identity_args INTO STRICT f
  FROM pg_proc p WHERE p.pronamespace='private'::regnamespace AND p.proname='delivery_core_'||r.tag;
  IF f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.prorettype<>'jsonb'::regtype
   OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public']
   OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.body_md5
   OR has_function_privilege('anon',f.oid,'EXECUTE') OR has_function_privilege('authenticated',f.oid,'EXECUTE')
  THEN RAISE EXCEPTION 'c03_operation_core_drift: %',r.action; END IF;
  d:=replace(pg_get_functiondef(f.oid),'FUNCTION private.delivery_core_'||r.tag||'(','FUNCTION private.c03_core_'||r.action||'(');
  IF r.action='plan' THEN
   financial:='private.c03_financial_change(v_operation.tenant_id)';
   FOREACH key IN ARRAY ARRAY['provider_cost_amount','customer_price_amount','service_catalog_item_id'] LOOP
    assignment:=key||' = p_'||key;
    IF position(assignment IN d)=0 THEN RAISE EXCEPTION 'c03_plan_assignment_drift: %',key;END IF;
    d:=replace(d,assignment,key||' = CASE WHEN '||financial||' THEN p_'||key||' ELSE v_operation.'||key||' END');
   END LOOP;
   IF position('pricing_currency = v_currency' IN d)=0 OR position('service_catalog_snapshot = COALESCE(p_service_catalog_snapshot' IN d)=0
   OR position('notes = NULLIF(btrim(COALESCE(p_notes' IN d)=0 THEN RAISE EXCEPTION 'c03_plan_financial_drift';END IF;
   d:=replace(d,'pricing_currency = v_currency','pricing_currency = CASE WHEN '||financial||' THEN v_currency ELSE v_operation.pricing_currency END');
   d:=replace(d,'service_catalog_snapshot = COALESCE(p_service_catalog_snapshot, ''{}''::jsonb)',
    'service_catalog_snapshot = CASE WHEN '||financial||' THEN COALESCE(p_service_catalog_snapshot, ''{}''::jsonb) ELSE v_operation.service_catalog_snapshot END');
   d:=replace(d,'notes = NULLIF(btrim(COALESCE(p_notes, '''')), '''')',
    'notes = CASE WHEN '||financial||' THEN NULLIF(btrim(COALESCE(p_notes, '''')), '''') ELSE v_operation.notes END');
   d:=replace(d,'''currency'', v_currency','''currency'', CASE WHEN '||financial||' THEN v_currency ELSE NULL END');
   d:=replace(d,'cargo_summary = p_cargo_summary',
    'cargo_summary = (CASE WHEN jsonb_typeof(v_operation.cargo_summary)=''object'' THEN v_operation.cargo_summary ELSE ''{}''::jsonb END)||p_cargo_summary');
  ELSIF r.action='control' THEN
   d:=replace(d,'THEN COALESCE(p_payload->''cargo_summary'', ''{}''::jsonb) ELSE cargo_summary END',
    'THEN (CASE WHEN jsonb_typeof(v_operation.cargo_summary)=''object'' THEN v_operation.cargo_summary ELSE ''{}''::jsonb END)||COALESCE(p_payload->''cargo_summary'', ''{}''::jsonb) ELSE cargo_summary END');
  END IF;
  EXECUTE d;
  EXECUTE format('REVOKE ALL ON FUNCTION private.c03_core_%I(%s) FROM PUBLIC,anon,authenticated,service_role',r.action,f.identity_args);
  EXECUTE format('GRANT EXECUTE ON FUNCTION private.c03_core_%I(%s) TO rotero_delivery_capture_owner',r.action,f.identity_args);
 END LOOP;
END $reviewed_cores$;

CREATE FUNCTION public.rpc_delivery_operation_action(p_tenant_id uuid,p_operation_id uuid,p_action text,p_payload jsonb,
 p_request_id uuid,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;op record;cap text;allowed text[];financial_keys text[]:=ARRAY['provider_cost_amount','customer_price_amount','pricing_currency','service_catalog_item_id','service_catalog_snapshot','notes'];
 digest text;old private.c03_operation_commands%ROWTYPE;r jsonb;detail text;keys text[];
BEGIN
 SELECT user_id INTO actor FROM private.multi05_request_actor();
 cap:=CASE p_action WHEN 'edit' THEN 'operations.edit' WHEN 'plan' THEN 'operations.plan' WHEN 'assign' THEN 'operations.assign'
  WHEN 'transition' THEN 'operations.transition' WHEN 'control' THEN 'operations.edit' END;
 IF cap IS NULL OR actor IS NULL OR p_request_id IS NULL OR p_expected_revision IS NULL
  OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
  OR NOT private.delivery_required(p_tenant_id) OR NOT private.delivery_cap(p_tenant_id,'operations.read')
  OR NOT private.delivery_cap(p_tenant_id,cap) OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator'])
 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>24000 THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 allowed:=CASE p_action
  WHEN 'edit' THEN ARRAY['route_summary','client_display_name','destination_city','eta_display','priority','provider_cost_amount','customer_price_amount','notes']
  WHEN 'plan' THEN ARRAY['service_type','origin_place','destination_place','operational_window_start','operational_window_end','route_summary','destination_city','eta','eta_display',
   'operation_scope','execution_type','cargo_summary','boxes_placed_days','documentation_received_at','documentation_received_note']||financial_keys
  WHEN 'assign' THEN ARRAY['execution_type','provider_id','provider_name','external_driver','external_vehicle','driver_id','driver_name','vehicle_id','vehicle_ref','planned_departure','priority','reason','force_override']
  WHEN 'transition' THEN ARRAY['to_status']
  WHEN 'control' THEN ARRAY['service_type','cargo_summary','boxes_placed_days','documentation_received_at','documentation_received_note'] END;
 SELECT array_agg(k) INTO keys FROM jsonb_object_keys(p_payload)k;
 IF EXISTS(SELECT FROM unnest(keys)k WHERE NOT(k=ANY(allowed))) THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 IF EXISTS(SELECT FROM jsonb_each(p_payload)e WHERE e.key NOT IN('origin_place','destination_place','cargo_summary','external_driver','external_vehicle','service_catalog_snapshot')
  AND jsonb_typeof(e.value) NOT IN('string','number','boolean','null')) THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 IF p_payload ?| financial_keys AND NOT private.c03_financial_change(p_tenant_id) THEN RETURN jsonb_build_object('error','financial_write_forbidden'); END IF;
 -- JSON containers use explicit operational keys. No snapshots with arbitrary
 -- prices, contacts from another operation or economic fields are copied back.
 IF p_payload ? 'cargo_summary' AND (jsonb_typeof(p_payload->'cargo_summary')<>'object'
  OR (p_payload->'cargo_summary')-ARRAY['description','weight_kg','volume_m3','packages','pallets','commodity','hazardous']<>'{}'::jsonb)
 THEN RETURN jsonb_build_object('error','invalid_cargo_summary'); END IF;
 IF p_payload ? 'cargo_summary' AND EXISTS(SELECT FROM jsonb_each(p_payload->'cargo_summary')e
  WHERE jsonb_typeof(e.value) NOT IN('string','number','boolean','null')) THEN RETURN jsonb_build_object('error','invalid_cargo_summary');END IF;
 IF p_payload ? 'external_driver' AND (jsonb_typeof(p_payload->'external_driver')<>'object' OR (p_payload->'external_driver')-ARRAY['name','phone']<>'{}'::jsonb)
 OR p_payload ? 'external_vehicle' AND (jsonb_typeof(p_payload->'external_vehicle')<>'object' OR (p_payload->'external_vehicle')-ARRAY['unit_code','plate_ref','reference','plates']<>'{}'::jsonb)
 THEN RETURN jsonb_build_object('error','invalid_external_snapshot'); END IF;
 IF EXISTS(SELECT FROM unnest(ARRAY['external_driver','external_vehicle'])k CROSS JOIN LATERAL jsonb_each(p_payload->k)e
  WHERE jsonb_typeof(e.value) NOT IN('string','null')) THEN RETURN jsonb_build_object('error','invalid_external_snapshot');END IF;
 IF p_action='plan' AND EXISTS(SELECT FROM unnest(ARRAY['origin_place','destination_place'])k WHERE jsonb_typeof(p_payload->k)<>'object'
  OR (p_payload->k)-ARRAY['countryCode','country','state','municipality','label','lat','lng','address','postalCode','placeId']<>'{}'::jsonb)
 THEN RETURN jsonb_build_object('error','invalid_places'); END IF;
 IF p_action='plan' AND EXISTS(SELECT FROM unnest(ARRAY['origin_place','destination_place'])k CROSS JOIN LATERAL jsonb_each(p_payload->k)e
  WHERE jsonb_typeof(e.value) NOT IN('string','number','null')) THEN RETURN jsonb_build_object('error','invalid_places');END IF;
 SELECT id,tenant_id,company_id,workflow_revision INTO op FROM public.operations
 WHERE id=p_operation_id AND tenant_id=p_tenant_id;
 IF NOT FOUND OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 digest:=encode(pg_catalog.sha256(pg_catalog.convert_to(jsonb_build_array(p_operation_id,p_action,p_payload,p_expected_revision)::text,'UTF8')),'hex');
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text||actor::text||p_request_id::text,0));
 SELECT * INTO old FROM private.c03_operation_commands WHERE tenant_id=p_tenant_id AND actor_id=actor AND request_id=p_request_id;
 IF FOUND THEN
  IF old.request_hash<>digest OR old.company_id<>op.company_id THEN RETURN jsonb_build_object('error','request_conflict');END IF;
  RETURN old.outcome;
 END IF;
 SELECT id,tenant_id,company_id,workflow_revision INTO op FROM public.operations WHERE id=p_operation_id AND tenant_id=p_tenant_id FOR UPDATE;
 IF NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF op.workflow_revision<>p_expected_revision THEN RETURN jsonb_build_object('error','stale_operation');END IF;
 BEGIN
  CASE p_action
   WHEN 'edit' THEN r:=private.c03_core_edit(p_operation_id,p_payload);
   WHEN 'control' THEN r:=private.c03_core_control(p_operation_id,p_payload);
   WHEN 'transition' THEN
    PERFORM private.c03_lock_transition_resources(p_tenant_id,p_operation_id);
    r:=private.c03_core_transition(p_operation_id,p_payload->>'to_status');
   WHEN 'assign' THEN
    -- Stable order also serializes occupancy checks shared by companies. It
    -- reveals no foreign operation IDs and does not remove legacy busy checks.
    PERFORM private.c03_lock_assignment_resources(p_tenant_id,NULLIF(p_payload->>'driver_id','')::uuid,NULLIF(p_payload->>'vehicle_id','')::uuid);
    r:=private.c03_core_assign(p_tenant_id,p_operation_id,COALESCE(p_payload->>'execution_type','third_party'),NULLIF(p_payload->>'provider_id','')::uuid,
     p_payload->>'provider_name',COALESCE(p_payload->'external_driver','{}'),COALESCE(p_payload->'external_vehicle','{}'),NULLIF(p_payload->>'driver_id','')::uuid,
     p_payload->>'driver_name',NULLIF(p_payload->>'vehicle_id','')::uuid,p_payload->>'vehicle_ref',NULLIF(p_payload->>'planned_departure','')::timestamptz,
     COALESCE(p_payload->>'priority','normal'),p_payload->>'reason',COALESCE((p_payload->>'force_override')::boolean,false));
   WHEN 'plan' THEN
    r:=private.c03_core_plan(p_operation_id,p_payload->>'service_type',p_payload->'origin_place',p_payload->'destination_place',
     NULLIF(p_payload->>'operational_window_start','')::timestamptz,NULLIF(p_payload->>'operational_window_end','')::timestamptz,
     p_payload->>'notes',p_payload->'cargo_summary',p_payload->>'route_summary',p_payload->>'destination_city',NULLIF(p_payload->>'eta','')::timestamptz,
     p_payload->>'eta_display',COALESCE(p_payload->>'operation_scope','national'),COALESCE(p_payload->>'execution_type','third_party'),
     NULLIF(p_payload->>'provider_cost_amount','')::numeric,NULLIF(p_payload->>'customer_price_amount','')::numeric,COALESCE(p_payload->>'pricing_currency','MXN'),
     NULLIF(p_payload->>'service_catalog_item_id','')::uuid,COALESCE(p_payload->'service_catalog_snapshot','{}'),NULLIF(p_payload->>'boxes_placed_days','')::integer,
     NULLIF(p_payload->>'documentation_received_at','')::timestamptz,p_payload->>'documentation_received_note');
  END CASE;
  IF r ? 'error' THEN RAISE SQLSTATE 'P0301' USING MESSAGE='c03_rejected',DETAIL=r->>'error';END IF;
  UPDATE public.operations SET workflow_revision=workflow_revision+1 WHERE id=p_operation_id AND tenant_id=p_tenant_id RETURNING workflow_revision INTO op.workflow_revision;
  r:=jsonb_build_object('success',true,'id',p_operation_id,'company_id',op.company_id,'workflow_revision',op.workflow_revision);
 EXCEPTION WHEN SQLSTATE 'P0301' THEN
  GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_DETAIL;
  r:=jsonb_build_object('error',CASE WHEN detail ~ '^[a-z_]{1,80}$' THEN detail ELSE 'operation_rejected' END);
 WHEN invalid_text_representation OR numeric_value_out_of_range OR datetime_field_overflow OR check_violation OR foreign_key_violation
 THEN r:=jsonb_build_object('error','invalid_payload');
 END;
 INSERT INTO private.c03_operation_commands(tenant_id,company_id,actor_id,request_id,operation_id,action,request_hash,outcome)
 VALUES(p_tenant_id,op.company_id,actor,p_request_id,p_operation_id,p_action,digest,r);
 RETURN r;
END $$;
GRANT CREATE ON SCHEMA public TO rotero_delivery_capture_owner;
ALTER FUNCTION public.rpc_delivery_operation_action(uuid,uuid,text,jsonb,uuid,bigint) OWNER TO rotero_delivery_capture_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_delivery_capture_owner;
SET LOCAL ROLE rotero_delivery_capture_owner;
REVOKE ALL ON FUNCTION public.rpc_delivery_operation_action(uuid,uuid,text,jsonb,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operation_action(uuid,uuid,text,jsonb,uuid,bigint) TO authenticated;
SET LOCAL ROLE postgres;
GRANT SELECT(workflow_revision),UPDATE(workflow_revision) ON public.operations TO rotero_delivery_capture_owner;
SET LOCAL ROLE rotero_delivery_scope_owner;
GRANT EXECUTE ON FUNCTION private.delivery_cap(uuid,text),private.delivery_entity_allowed(uuid,text,uuid),private.delivery_required(uuid) TO rotero_delivery_capture_owner;
SET LOCAL ROLE postgres;
GRANT EXECUTE ON FUNCTION private.c03_financial_change(uuid),public.tanda1_user_has_role(uuid,text[]) TO rotero_delivery_capture_owner;
CREATE POLICY c03_operation_writer_select ON public.operations FOR SELECT TO rotero_delivery_capture_owner
USING(private.delivery_entity_allowed(tenant_id,'operation',id) AND private.delivery_cap(tenant_id,'operations.read'));
CREATE POLICY c03_operation_writer_revision ON public.operations FOR UPDATE TO rotero_delivery_capture_owner
USING(private.delivery_entity_allowed(tenant_id,'operation',id) AND cardinality(private.delivery_company_ids())=1
 AND (private.delivery_cap(tenant_id,'operations.edit') OR private.delivery_cap(tenant_id,'operations.plan')
  OR private.delivery_cap(tenant_id,'operations.assign') OR private.delivery_cap(tenant_id,'operations.transition')))
WITH CHECK(private.delivery_entity_allowed(tenant_id,'operation',id) AND cardinality(private.delivery_company_ids())=1);

CREATE FUNCTION private.c03_object_dto(p_data jsonb,p_keys text[]) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT COALESCE(jsonb_object_agg(e.key,e.value),'{}'::jsonb)
 FROM jsonb_each(CASE WHEN jsonb_typeof(p_data)='object' THEN p_data ELSE '{}'::jsonb END)e
 WHERE e.key=ANY(p_keys) AND jsonb_typeof(e.value) IN('string','number','boolean','null');
$$;
REVOKE ALL ON FUNCTION private.c03_object_dto(jsonb,text[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.rpc_delivery_operation_workflow(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE o public.operations%ROWTYPE;r jsonb;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT * INTO o FROM public.operations WHERE id=p_operation_id AND tenant_id=p_tenant_id;
 r:=private.delivery_operation_dto(to_jsonb(o))||jsonb_build_object('workflow_revision',o.workflow_revision,'provider_id',o.provider_id,
  'driver_id',o.driver_id,'vehicle_id',o.vehicle_id,'driver_name',o.driver_name,'vehicle_ref',o.vehicle_ref,'assigned_at',o.assigned_at,
  'origin_place',private.c03_object_dto(o.origin_place,ARRAY['countryCode','country','state','municipality','label','lat','lng','address','postalCode','placeId']),
  'destination_place',private.c03_object_dto(o.destination_place,ARRAY['countryCode','country','state','municipality','label','lat','lng','address','postalCode','placeId']),
  'cargo_summary',private.c03_object_dto(o.cargo_summary,ARRAY['description','weight_kg','volume_m3','packages','pallets','commodity','hazardous']),
  'external_driver',private.c03_object_dto(o.external_driver,ARRAY['name','phone']),
  'external_vehicle',private.c03_object_dto(o.external_vehicle,ARRAY['unit_code','plate_ref','reference','plates']),
  'boxes_placed_days',o.boxes_placed_days,'documentation_received_at',o.documentation_received_at);
 IF private.delivery_cap(p_tenant_id,'financial.full.read') THEN
  r:=r||jsonb_build_object('provider_cost_amount',o.provider_cost_amount,'customer_price_amount',o.customer_price_amount,'pricing_currency',o.pricing_currency,
   'notes',o.notes,'service_catalog_item_id',o.service_catalog_item_id,'service_catalog_snapshot',o.service_catalog_snapshot);
 END IF;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_operation_workflow(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operation_workflow(uuid,uuid) TO authenticated;

-- Reference parties/resources are tenant-shared in the existing schema. This
-- minimal chooser exposes no other company's operations, terms or economics.
CREATE FUNCTION public.rpc_delivery_assignment_choices(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.assign') OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator'])
  OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN jsonb_build_object('providers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'display_name',display_name) ORDER BY display_name)
  FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND is_active),'[]'),
  'drivers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'display_name',display_name) ORDER BY display_name)
  FROM public.drivers WHERE tenant_id=p_tenant_id AND status='available'),'[]'),
  'vehicles',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'unit_code',unit_code) ORDER BY unit_code)
  FROM public.vehicles WHERE tenant_id=p_tenant_id AND status='available'),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_assignment_choices(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_assignment_choices(uuid) TO authenticated;

CREATE FUNCTION public.rpc_delivery_provider_eligibility(p_tenant_id uuid,p_provider_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE s jsonb;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.assign') OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
 OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator'])
 OR NOT EXISTS(SELECT FROM public.logistics_providers WHERE id=p_provider_id AND tenant_id=p_tenant_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 s:=private.f9_partner_status(p_tenant_id,'provider',p_provider_id,current_date);
 RETURN jsonb_build_object('provider_id',p_provider_id,'eligible',COALESCE((s->>'provider_compliance_ready')::boolean,false),
  'badge',s->>'badge','blocking',COALESCE((s->>'blocking')::integer,0),'reasons',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'requirement_id',x->>'id','code',x->>'code','name',x->>'name','status',x->>'derived_status'))
   FROM jsonb_array_elements(s->'requirements')x WHERE COALESCE((x->>'assignment_blocker')::boolean,false)),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_provider_eligibility(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_provider_eligibility(uuid,uuid) TO authenticated;

-- Advertise only actually granted capabilities, preserving the existing context
-- contract and exact consolidation checks. This is not an assignment API.
DO $context$ DECLARE d text;BEGIN
 d:=pg_get_functiondef('public.rpc_delivery_context(uuid)'::regprocedure);
 IF position('''operations.read'',''operations.capture''' IN d)=0 THEN RAISE EXCEPTION 'c03_context_drift';END IF;
 d:=replace(d,'''operations.read'',''operations.capture''','''operations.read'',''operations.capture'',''operations.edit'',''operations.plan'',''operations.assign'',''operations.transition'',''operations.evidence.write'',''documents.upload'',''documents.manage'',''automations.manage''');
 EXECUTE d;
END $context$;
COMMIT;
