BEGIN;
-- Existing business cores stay private. Only the scoped command below can
-- reach them; legacy public entry points retain their cutover denial.
DO $$DECLARE r record;f record;BEGIN
 FOR r IN SELECT * FROM(VALUES
 ('delivery_core_0915e18f07eac7aae77d','04b018261c28212e4c0c9089c2defa5f'),
 ('delivery_core_d429ef817187577364df','0d2fafea5235773ba655f5d16bfceb0b'),
 ('delivery_core_719110b179a9b6922e84','15c444d8be74e2407331c080f6130593'),
 ('delivery_core_858e88dcd8810a3be8d7','60247773a4d42248d6b38da3c5c48047'),
 ('delivery_core_7916b5a033e445227cc2','0e7704f2c37dfca3a92e1965671e1bce'),
 ('delivery_core_ba443d65dc2ef369c631','c1bfe4376540b760bf93bcb285f07fda'),
 ('delivery_core_b826e0bf3d2bc7e83d22','7ea7a9542da247ba0f78180f8660755d'),
 ('delivery_core_ebde3aaa7dd9d7f01b99','678477bd6ec75b2662e4bacc4cb7ac17'))v(name,body_md5) LOOP
  SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.pronamespace='private'::regnamespace AND p.proname=r.name;
  IF f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.prorettype<>'jsonb'::regtype
   OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public'] OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.body_md5
   OR has_function_privilege('anon',f.oid,'EXECUTE') OR has_function_privilege('authenticated',f.oid,'EXECUTE')
  THEN RAISE EXCEPTION 'c03_child_source_drift: %',r.name;END IF;
 END LOOP;
END $$;
SET LOCAL ROLE rotero_delivery_capture_owner;
GRANT SELECT,INSERT ON private.c03_operation_commands TO postgres;
SET LOCAL ROLE postgres;
CREATE TABLE private.c03_child_facts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),fact_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,tenant_id uuid NOT NULL,operation_id uuid NOT NULL,
 entity_kind text NOT NULL CHECK(entity_kind IN('incident','evidence','document','crossing','override')),
 entity_id uuid NOT NULL,actor_id uuid NOT NULL,action text NOT NULL,
 projection jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(tenant_id,operation_id) REFERENCES public.operations(tenant_id,id));
ALTER TABLE private.c03_child_facts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c03_child_facts FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX c03_child_facts_lookup ON private.c03_child_facts(operation_id,entity_kind,entity_id,created_at DESC,id DESC);
CREATE TRIGGER c03_child_facts_immutable BEFORE UPDATE OR DELETE ON private.c03_child_facts
 FOR EACH ROW EXECUTE FUNCTION private.c03_document_event_immutable();

CREATE FUNCTION public.rpc_delivery_operation_child_action(p_tenant_id uuid,p_operation_id uuid,p_action text,p_payload jsonb,
 p_request_id uuid,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid;op public.operations%ROWTYPE;cap text;keys text[];child uuid;incident uuid;file uuid;provider uuid;
 old private.c03_operation_commands%ROWTYPE;digest text;r jsonb;outcome jsonb;entity_kind text;entity uuid;projection jsonb;business_error text;
BEGIN
 u:=(SELECT auth.uid());
 cap:=CASE WHEN p_action LIKE 'incident.%' OR p_action LIKE 'crossing.%' THEN 'operations.edit'
  WHEN p_action IN('evidence.add','document.save') THEN 'operations.evidence.write'
  WHEN p_action='compliance.override' THEN 'operations.assign' END;
 IF u IS NULL OR cap IS NULL OR p_request_id IS NULL OR p_expected_revision IS NULL OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
  OR NOT private.delivery_required(p_tenant_id) OR NOT private.delivery_cap(p_tenant_id,'operations.read')
  OR NOT private.delivery_cap(p_tenant_id,cap) OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator'])
  OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16000 THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 keys:=CASE p_action
  WHEN 'incident.create' THEN ARRAY['category','title','description','is_blocking','tracking_event_id']
  WHEN 'incident.resolve' THEN ARRAY['id','note'] WHEN 'incident.dismiss' THEN ARRAY['id','note']
  WHEN 'evidence.add' THEN ARRAY['incident_id','kind','note','file_id']
  WHEN 'document.save' THEN ARRAY['document_type','requirement_level','status','document_reference','note','file_id']
  WHEN 'crossing.save' THEN ARRAY['id','crossed_at','crossing_point','crossing_type','note']
  WHEN 'crossing.delete' THEN ARRAY['id'] WHEN 'compliance.override' THEN ARRAY['provider_id','reason'] END;
 IF keys IS NULL OR p_payload-keys<>'{}'::jsonb OR EXISTS(SELECT FROM jsonb_each(p_payload)e WHERE jsonb_typeof(e.value) NOT IN('string','number','boolean','null'))
 THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 BEGIN child:=nullif(p_payload->>'id','')::uuid;incident:=nullif(p_payload->>'incident_id','')::uuid;
  file:=nullif(p_payload->>'file_id','')::uuid;provider:=nullif(p_payload->>'provider_id','')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');END;
 digest:=encode(sha256(convert_to(jsonb_build_array(p_operation_id,p_action,p_payload,p_expected_revision)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||u::text||p_request_id::text,0));
 SELECT * INTO old FROM private.c03_operation_commands WHERE tenant_id=p_tenant_id AND actor_id=u AND request_id=p_request_id;
 IF FOUND THEN IF old.request_hash<>digest THEN RETURN jsonb_build_object('error','request_conflict');END IF;RETURN old.outcome;END IF;
 SELECT * INTO op FROM public.operations WHERE id=p_operation_id AND tenant_id=p_tenant_id FOR UPDATE;
 IF NOT FOUND OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_action IN('incident.resolve','incident.dismiss') AND NOT EXISTS(SELECT FROM public.operation_incidents WHERE id=child AND operation_id=p_operation_id AND tenant_id=p_tenant_id)
  OR p_action IN('crossing.save','crossing.delete') AND child IS NOT NULL AND NOT EXISTS(SELECT FROM public.operation_crossings WHERE id=child AND operation_id=p_operation_id AND tenant_id=p_tenant_id)
  OR incident IS NOT NULL AND NOT EXISTS(SELECT FROM public.operation_incidents WHERE id=incident AND operation_id=p_operation_id AND tenant_id=p_tenant_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF file IS NOT NULL AND NOT EXISTS(SELECT FROM public.document_files f WHERE f.id=file AND f.tenant_id=p_tenant_id AND f.source_entity_type='operation'
  AND f.source_entity_id=p_operation_id AND f.access_class='operational' AND private.delivery_file_allowed(f.id))
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_action='evidence.add' AND COALESCE(p_payload->>'kind','operational_note') NOT IN('operational_note','file_reference')
  OR p_action='evidence.add' AND p_payload->>'kind'='file_reference' AND file IS NULL
 THEN RETURN jsonb_build_object('error','managed_file_required');END IF;
 IF p_action='compliance.override' AND (NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) OR NOT EXISTS(
  SELECT FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND id=provider)) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF op.workflow_revision<>p_expected_revision THEN RETURN jsonb_build_object('error','stale_operation');END IF;
 BEGIN
  CASE p_action
  WHEN 'incident.create' THEN
   r:=private.delivery_core_0915e18f07eac7aae77d(p_operation_id,p_payload->>'category',p_payload->>'title',p_payload->>'description',COALESCE((p_payload->>'is_blocking')::boolean,false),nullif(p_payload->>'tracking_event_id','')::uuid);
   entity_kind:='incident';entity:=(r->>'id')::uuid;
  WHEN 'incident.resolve' THEN r:=private.delivery_core_d429ef817187577364df(child,p_payload->>'note');entity_kind:='incident';entity:=child;
  WHEN 'incident.dismiss' THEN r:=private.delivery_core_719110b179a9b6922e84(child,p_payload->>'note');entity_kind:='incident';entity:=child;
  WHEN 'evidence.add' THEN r:=private.delivery_core_858e88dcd8810a3be8d7(p_operation_id,incident,COALESCE(p_payload->>'kind','operational_note'),p_payload->>'note',file::text,NULL);entity_kind:='evidence';entity:=(r->>'id')::uuid;
  WHEN 'document.save' THEN
   r:=private.delivery_core_b826e0bf3d2bc7e83d22(p_operation_id,p_payload->>'document_type',p_payload->>'requirement_level',p_payload->>'status',p_payload->>'document_reference',file::text,NULL,p_payload->>'note');
   entity_kind:='document';entity:=(r->>'id')::uuid;
  WHEN 'crossing.save' THEN r:=private.delivery_core_7916b5a033e445227cc2(p_operation_id,p_payload);entity_kind:='crossing';entity:=(r->'item'->>'id')::uuid;
  WHEN 'crossing.delete' THEN r:=private.delivery_core_ba443d65dc2ef369c631(child);entity_kind:='crossing';entity:=child;
  WHEN 'compliance.override' THEN r:=private.delivery_core_ebde3aaa7dd9d7f01b99(p_operation_id,provider,p_payload->>'reason');entity_kind:='override';entity:=(r->>'id')::uuid;
  END CASE;
  IF r ? 'error' THEN business_error:=r->>'error';RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='c03_child_rejected';END IF;
  IF r->>'success' IS DISTINCT FROM 'true' OR entity IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0002',MESSAGE='c03_child_rejected';END IF;
  projection:=CASE entity_kind
   WHEN 'incident' THEN (SELECT jsonb_build_object('description',description,'resolution_note',resolution_note,'dismiss_note',dismiss_note) FROM public.operation_incidents WHERE id=entity)
   WHEN 'evidence' THEN jsonb_build_object('note',p_payload->>'note','file_id',file)
   WHEN 'document' THEN jsonb_build_object('note',p_payload->>'note','document_reference',p_payload->>'document_reference','file_id',file)
   WHEN 'crossing' THEN jsonb_build_object('note',p_payload->>'note','crossing_point',p_payload->>'crossing_point') ELSE '{}' END;
  INSERT INTO private.c03_child_facts(tenant_id,operation_id,entity_kind,entity_id,actor_id,action,projection)
  VALUES(p_tenant_id,p_operation_id,entity_kind,entity,u,p_action,COALESCE(projection,'{}'));
  UPDATE public.operations SET workflow_revision=workflow_revision+1 WHERE id=p_operation_id RETURNING workflow_revision INTO op.workflow_revision;
  outcome:=jsonb_build_object('success',true,'id',entity,'workflow_revision',op.workflow_revision);
  INSERT INTO private.c03_operation_commands(tenant_id,company_id,actor_id,request_id,operation_id,action,request_hash,outcome)
  VALUES(p_tenant_id,op.company_id,u,p_request_id,p_operation_id,p_action,digest,outcome);
 EXCEPTION WHEN no_data_found THEN
  IF business_error=ANY(ARRAY['invalid_category','missing_title','invalid_tracking_event','invalid_incident','missing_content','invalid_kind',
   'invalid_document_type','invalid_requirement_level','invalid_status','invalid_crossing_type','missing_crossing_point','national_operation',
   'missing_resolution_note','missing_dismiss_note','incident_not_open','missing_override_reason','provider_not_blocked']) THEN RETURN jsonb_build_object('error',business_error);END IF;
  RETURN jsonb_build_object('error','action_rejected');
 WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format OR check_violation OR foreign_key_violation
 THEN RETURN jsonb_build_object('error','invalid_payload');END;
 RETURN outcome;
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_operation_child_action(uuid,uuid,text,jsonb,uuid,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operation_child_action(uuid,uuid,text,jsonb,uuid,bigint) TO authenticated;

-- Historical text/URLs have no field-level financial classification. Keep
-- their structural projections, adding only facts recorded by this workflow.
CREATE FUNCTION public.rpc_delivery_operation_children(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE incidents jsonb;evidence jsonb;documents jsonb;crossings jsonb;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT COALESCE(jsonb_agg(private.delivery_pick_dto(to_jsonb(i),ARRAY['id','operation_id','category','title','is_blocking','status','reported_at','created_at','updated_at','resolved_at'])||COALESCE(f.projection,'{}') ORDER BY i.created_at,i.id),'[]') INTO incidents
 FROM public.operation_incidents i LEFT JOIN LATERAL(SELECT projection FROM private.c03_child_facts WHERE entity_kind='incident' AND entity_id=i.id AND operation_id=p_operation_id ORDER BY fact_sequence DESC LIMIT 1)f ON true
 WHERE i.operation_id=p_operation_id AND i.tenant_id=p_tenant_id;
 SELECT COALESCE(jsonb_agg(private.delivery_pick_dto(to_jsonb(e),ARRAY['id','operation_id','incident_id','kind','created_at'])||
  (COALESCE(f.projection,'{}')-'file_id')||jsonb_build_object('file_ref',CASE WHEN private.delivery_file_allowed((f.projection->>'file_id')::uuid) THEN f.projection->>'file_id' END) ORDER BY e.created_at,e.id),'[]') INTO evidence
 FROM public.operation_evidence e LEFT JOIN LATERAL(SELECT projection FROM private.c03_child_facts WHERE entity_kind='evidence' AND entity_id=e.id AND operation_id=p_operation_id ORDER BY fact_sequence DESC LIMIT 1)f ON true
 WHERE e.operation_id=p_operation_id AND e.tenant_id=p_tenant_id;
 -- Reuse the canonical catalog/readiness rules, never invent requirements.
 SELECT public.rpc_list_operation_documents(p_operation_id) INTO documents;
 IF jsonb_typeof(documents)<>'array' THEN documents:='[]';END IF;
 SELECT COALESCE(jsonb_agg(d||COALESCE(f.projection-'file_id','{}')||jsonb_build_object('file_ref',CASE WHEN EXISTS(SELECT FROM public.document_files df WHERE df.id::text=od.file_ref AND df.source_entity_type='operation' AND df.source_entity_id=p_operation_id AND private.delivery_file_allowed(df.id)) THEN od.file_ref END)),'[]') INTO documents
 FROM jsonb_array_elements(documents)d LEFT JOIN public.operation_documents od ON od.id::text=d->>'id' AND od.operation_id=p_operation_id AND od.tenant_id=p_tenant_id LEFT JOIN LATERAL(SELECT projection FROM private.c03_child_facts WHERE entity_kind='document' AND entity_id=(d->>'id')::uuid AND operation_id=p_operation_id ORDER BY fact_sequence DESC LIMIT 1)f ON true;
 SELECT COALESCE(jsonb_agg(private.delivery_pick_dto(to_jsonb(c),ARRAY['id','operation_id','crossing_type','crossed_at','created_at','updated_at'])||COALESCE(f.projection,'{}') ORDER BY c.crossed_at,c.id),'[]') INTO crossings
 FROM public.operation_crossings c LEFT JOIN LATERAL(SELECT projection FROM private.c03_child_facts WHERE entity_kind='crossing' AND entity_id=c.id AND operation_id=p_operation_id ORDER BY fact_sequence DESC LIMIT 1)f ON true
 WHERE c.operation_id=p_operation_id AND c.tenant_id=p_tenant_id;
 RETURN jsonb_build_object('incidents',incidents,'evidence',evidence,'documents',documents,'crossings',crossings);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_operation_children(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operation_children(uuid,uuid) TO authenticated;
CREATE FUNCTION public.rpc_delivery_create_operation_once(p_tenant_id uuid,p_request_id uuid,p_reference text,p_route text DEFAULT NULL,p_customer text DEFAULT NULL,p_destination_city text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid;c uuid;digest text;prior private.c03_operation_commands%ROWTYPE;r jsonb;
BEGIN
 u:=(SELECT auth.uid());c:=(private.delivery_company_ids())[1];
 IF u IS NULL OR p_request_id IS NULL OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
  OR NOT private.delivery_required(p_tenant_id) OR NOT private.delivery_cap(p_tenant_id,'operations.capture')
  OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 digest:=encode(sha256(convert_to(jsonb_build_array('create',p_reference,p_route,p_customer,p_destination_city)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||u::text||p_request_id::text,0));
 SELECT * INTO prior FROM private.c03_operation_commands WHERE tenant_id=p_tenant_id AND actor_id=u AND request_id=p_request_id;
 IF FOUND THEN
  IF prior.request_hash<>digest OR prior.company_id<>c THEN RETURN jsonb_build_object('error','request_conflict');END IF;RETURN prior.outcome;
 END IF;
 r:=public.rpc_delivery_create_operation(p_tenant_id,p_reference,p_route,p_customer,p_destination_city);
 IF r ? 'error' THEN RETURN jsonb_build_object('error',r->>'error');END IF;
 r:=jsonb_build_object('success',true,'id',r->>'id','company_id',c,'workflow_revision',0);
 INSERT INTO private.c03_operation_commands(tenant_id,company_id,actor_id,request_id,operation_id,action,request_hash,outcome)
 VALUES(p_tenant_id,c,u,p_request_id,(r->>'id')::uuid,'create',digest,r);
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_create_operation_once(uuid,uuid,text,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_create_operation_once(uuid,uuid,text,text,text,text) TO authenticated;
CREATE FUNCTION public.rpc_delivery_operation_history(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(private.delivery_pick_dto(to_jsonb(h),ARRAY['id','operation_id','change_type','old_execution_type','new_execution_type',
  'old_provider_name_snapshot','new_provider_name_snapshot','old_driver_name_snapshot','new_driver_name_snapshot','old_vehicle_ref_snapshot','new_vehicle_ref_snapshot','changed_at']) ORDER BY h.changed_at,h.id)
 FROM public.operation_assignment_history h WHERE h.operation_id=p_operation_id AND h.tenant_id=p_tenant_id),'[]');
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_operation_history(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operation_history(uuid,uuid) TO authenticated;

COMMIT;
