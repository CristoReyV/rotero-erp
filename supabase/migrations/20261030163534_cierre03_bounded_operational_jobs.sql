BEGIN;
DO $$DECLARE r record;f record;BEGIN FOR r IN SELECT * FROM(VALUES ('delivery_job_f7_materialize_automation_notifications','c9b59b006784a2d1e6e9a6b784687d84'),('f7_seed_rules','adf9407e165534de56a6160e2c738db8'),('f7_operation_dispatch_readiness','f2894d967fbc5c5411097411a8f8efb4'),('f7_target_allows_role','766ee00ead17090e7a3e76992a479f9c'))v(name,body_md5) LOOP SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.pronamespace='private'::regnamespace AND p.proname=r.name;IF md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.body_md5 OR f.proowner<>'postgres'::regrole THEN RAISE EXCEPTION 'c03_job_source_drift: %',r.name;END IF;END LOOP;END $$;
CREATE TABLE private.c03_automation_scopes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES public.tenants(id),company_id uuid NOT NULL,
 approved_by uuid NOT NULL,request_id uuid NOT NULL,recipient_ids uuid[] NOT NULL CHECK(cardinality(recipient_ids) BETWEEN 1 AND 20),
 enabled boolean NOT NULL DEFAULT true,valid_until timestamptz NOT NULL DEFAULT now()+interval '7 days',
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(tenant_id,approved_by,request_id));
CREATE TABLE private.c03_automation_runs(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),scope_id uuid NOT NULL REFERENCES private.c03_automation_scopes(id),
 request_id uuid NOT NULL,evaluated_at timestamptz NOT NULL,outcome jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(scope_id,request_id));
ALTER TABLE private.c03_automation_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.c03_automation_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c03_automation_scopes,private.c03_automation_runs FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c03_automation_runs_immutable BEFORE UPDATE OR DELETE ON private.c03_automation_runs
 FOR EACH ROW EXECUTE FUNCTION private.c03_document_event_immutable();
-- Nonfinancial delegation checks use the existing grant tables and validity
-- contract. No request identity is installed or impersonated for a worker.
CREATE FUNCTION private.c03_operational_grant(t uuid,c uuid,u uuid,code text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT code IN('operations.read','automations.manage','billing.document.read')
 AND EXISTS(SELECT FROM public.memberships WHERE tenant_id=t AND user_id=u)
 AND EXISTS(SELECT FROM auth.users WHERE id=u)
 AND EXISTS(SELECT FROM public.companies WHERE tenant_id=t AND id=c AND status='active')
 AND EXISTS(SELECT FROM public.membership_company_access a WHERE a.tenant_id=t AND a.company_id=c AND a.user_id=u
  AND a.status='active' AND a.revoked_at IS NULL AND a.valid_from<=statement_timestamp() AND(a.valid_until IS NULL OR a.valid_until>statement_timestamp()))
 AND EXISTS(SELECT FROM public.membership_company_capabilities a WHERE a.tenant_id=t AND a.company_id=c AND a.user_id=u AND a.capability_code=code
  AND a.status='active' AND a.revoked_at IS NULL AND a.valid_from<=statement_timestamp() AND(a.valid_until IS NULL OR a.valid_until>statement_timestamp()));
$$;
REVOKE ALL ON FUNCTION private.c03_operational_grant(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.rpc_delivery_prepare_automation(p_tenant_id uuid,p_request_id uuid,p_recipient_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;u uuid;s private.c03_automation_scopes%ROWTYPE;recipients uuid[];
BEGIN
 u:=(SELECT auth.uid());c:=(private.delivery_company_ids())[1];
 IF u IS NULL OR p_request_id IS NULL OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1
  OR NOT private.delivery_required(p_tenant_id) OR NOT private.delivery_cap(p_tenant_id,'automations.manage')
  OR NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin'])
  OR EXISTS(SELECT FROM private.fiscal01_lab_actors WHERE tenant_id=p_tenant_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT array_agg(DISTINCT x ORDER BY x) INTO recipients FROM unnest(p_recipient_ids)x;
 IF cardinality(recipients) NOT BETWEEN 1 AND 20 OR cardinality(recipients) IS NULL OR EXISTS(SELECT FROM unnest(recipients)x
  WHERE x IS NULL OR NOT private.c03_operational_grant(p_tenant_id,c,x,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||u::text||p_request_id::text,3));
 SELECT * INTO s FROM private.c03_automation_scopes WHERE tenant_id=p_tenant_id AND approved_by=u AND request_id=p_request_id;
 IF FOUND THEN IF s.company_id<>c OR s.recipient_ids<>recipients THEN RETURN jsonb_build_object('error','request_conflict');END IF;
 ELSE
    INSERT INTO public.automation_rules (
        tenant_id, code, name, module, target_role, severity,
        threshold_value, threshold_unit, escalation_config, digest_enabled
    )
    SELECT p_tenant_id, d.code, d.name, d.module, d.target_role, d.severity,
           d.threshold_value, d.threshold_unit,
           jsonb_build_object(
               'delay_value', d.escalation_delay,
               'delay_unit', d.escalation_unit,
               'severity', d.escalation_severity
           ),
           true
    FROM (VALUES
        ('operation_dispatch_blocked','Despacho bloqueado','operations','admin_finance','high',0,'hours',4,'hours','critical'),
        ('operation_blocking_incident','Incidencia bloqueante','operations','admin_finance','critical',0,'hours',2,'hours','critical'),
        ('operation_missing_document','Documento operativo requerido faltante','documents','admin_finance','high',0,'hours',12,'hours','critical'),
        ('operation_pod_missing','POD pendiente después de entrega','documents','admin_finance','high',12,'hours',12,'hours','critical'),
        ('operation_billing_blocked','Facturación operativa bloqueada','operations','admin_finance','high',0,'hours',12,'hours','critical'),
        ('operation_stale','Operación sin progreso significativo','operations','admin_finance','high',24,'hours',12,'hours','critical')
    ) AS d(code,name,module,target_role,severity,threshold_value,threshold_unit,escalation_delay,escalation_unit,escalation_severity)
    ON CONFLICT (tenant_id, code) DO NOTHING;

  INSERT INTO private.c03_automation_scopes(tenant_id,company_id,approved_by,request_id,recipient_ids)
  VALUES(p_tenant_id,c,u,p_request_id,recipients) RETURNING * INTO s;
  PERFORM public.rpc_write_audit(p_tenant_id,'c03_operational_scope_prepared','automation_scope',s.id,jsonb_build_object('company_id',c,'recipient_count',cardinality(recipients),'valid_until',s.valid_until));
 END IF;
 RETURN jsonb_build_object('id',s.id,'company_id',s.company_id,'valid_until',s.valid_until,'recipient_count',cardinality(s.recipient_ids),'scheduled',false);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_prepare_automation(uuid,uuid,uuid[]) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_prepare_automation(uuid,uuid,uuid[]) TO authenticated;

CREATE TABLE private.c03_automation_rule_overrides(
 tenant_id uuid NOT NULL REFERENCES public.tenants(id),company_id uuid NOT NULL,rule_id uuid NOT NULL REFERENCES public.automation_rules(id),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),updated_by uuid NOT NULL,updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,company_id,rule_id));
ALTER TABLE private.c03_automation_rule_overrides ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c03_automation_rule_overrides FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO postgres;
SET LOCAL ROLE postgres;
ALTER TABLE private.c03_automation_scopes ADD CONSTRAINT c03_automation_scope_company FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id);
ALTER TABLE private.c03_automation_rule_overrides ADD CONSTRAINT c03_automation_rule_company FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id);
SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES(tenant_id,id) ON public.companies FROM postgres;
SET LOCAL ROLE postgres;
ALTER TABLE public.automation_rules ADD CONSTRAINT c03_automation_rule_tenant_id UNIQUE(tenant_id,id);
ALTER TABLE private.c03_automation_rule_overrides ADD CONSTRAINT c03_automation_rule_tenant FOREIGN KEY(tenant_id,rule_id) REFERENCES public.automation_rules(tenant_id,id);
CREATE FUNCTION private.c03_operational_rules(t uuid,c uuid) RETURNS SETOF public.automation_rules
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT (jsonb_populate_record(NULL::public.automation_rules,to_jsonb(r)||COALESCE(o.payload,'{}'))).*
 FROM public.automation_rules r LEFT JOIN private.c03_automation_rule_overrides o ON o.tenant_id=r.tenant_id AND o.company_id=c AND o.rule_id=r.id
 WHERE r.tenant_id=t AND r.code IN('operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale');
$$;
REVOKE ALL ON FUNCTION private.c03_operational_rules(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.rpc_delivery_update_automation(p_tenant_id uuid,p_rule_id uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;v jsonb;prior jsonb;
BEGIN
 c:=(private.delivery_company_ids())[1];
 IF cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1 OR NOT private.delivery_cap(p_tenant_id,'automations.manage')
  OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) OR EXISTS(SELECT FROM private.fiscal01_lab_actors WHERE tenant_id=p_tenant_id)
  OR NOT EXISTS(SELECT FROM private.c03_operational_rules(p_tenant_id,c) WHERE id=p_rule_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_payload-ARRAY['is_enabled','target_role','severity','threshold_value','threshold_unit','escalation_delay_value','escalation_delay_unit','escalation_severity','digest_enabled']<>'{}'
  OR jsonb_typeof(p_payload->'is_enabled') IS DISTINCT FROM 'boolean' OR jsonb_typeof(p_payload->'digest_enabled') IS DISTINCT FROM 'boolean'
  OR COALESCE(p_payload->>'target_role','') NOT IN('admin','finance','admin_finance')
  OR COALESCE(p_payload->>'severity','') NOT IN('critical','high','medium','low') OR COALESCE(p_payload->>'escalation_severity','') NOT IN('critical','high','medium','low')
  OR COALESCE(p_payload->>'threshold_unit','') NOT IN('hours','days') OR COALESCE(p_payload->>'escalation_delay_unit','') NOT IN('hours','days')
 THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 BEGIN
  IF (p_payload->>'threshold_value')::int NOT BETWEEN 0 AND 10000 OR (p_payload->>'escalation_delay_value')::int NOT BETWEEN 0 AND 10000
   OR p_payload->>'threshold_value' IS NULL OR p_payload->>'escalation_delay_value' IS NULL THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
  v:=jsonb_build_object('is_enabled',(p_payload->>'is_enabled')::boolean,'target_role',p_payload->>'target_role','severity',p_payload->>'severity',
   'threshold_value',(p_payload->>'threshold_value')::int,'threshold_unit',p_payload->>'threshold_unit','digest_enabled',(p_payload->>'digest_enabled')::boolean,
   'escalation_config',jsonb_build_object('delay_value',(p_payload->>'escalation_delay_value')::int,'delay_unit',p_payload->>'escalation_delay_unit','severity',p_payload->>'escalation_severity'));
 EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');END;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||c::text||p_rule_id::text,5));
 SELECT payload INTO prior FROM private.c03_automation_rule_overrides WHERE tenant_id=p_tenant_id AND company_id=c AND rule_id=p_rule_id;
 INSERT INTO private.c03_automation_rule_overrides(tenant_id,company_id,rule_id,payload,updated_by) VALUES(p_tenant_id,c,p_rule_id,v,(SELECT auth.uid()))
 ON CONFLICT(tenant_id,company_id,rule_id) DO UPDATE SET payload=EXCLUDED.payload,updated_by=EXCLUDED.updated_by,updated_at=now();
 PERFORM public.rpc_write_audit(p_tenant_id,'c03_company_automation_configured','automation_rule',p_rule_id,jsonb_build_object('company_id',c,'before',prior,'after',v));
 RETURN jsonb_build_object('success',true);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_update_automation(uuid,uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_update_automation(uuid,uuid,jsonb) TO authenticated;
CREATE FUNCTION public.rpc_delivery_automation_status(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;rules jsonb;scopes jsonb;runs jsonb;
BEGIN
 c:=(private.delivery_company_ids())[1];
 IF cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1 OR NOT private.delivery_cap(p_tenant_id,'automations.manage')
  OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'name',r.name,'module',r.module,'is_enabled',r.is_enabled,
  'target_role',r.target_role,'severity',r.severity,'threshold_value',r.threshold_value,'threshold_unit',r.threshold_unit,
  'escalation_delay_value',(r.escalation_config->>'delay_value')::int,'escalation_delay_unit',r.escalation_config->>'delay_unit',
  'escalation_severity',r.escalation_config->>'severity','digest_enabled',r.digest_enabled,'updated_at',r.updated_at) ORDER BY r.code),'[]') INTO rules
 FROM private.c03_operational_rules(p_tenant_id,c)r;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'valid_until',valid_until,'enabled',enabled,'recipient_count',cardinality(recipient_ids)) ORDER BY created_at DESC),'[]') INTO scopes
 FROM private.c03_automation_scopes WHERE tenant_id=p_tenant_id AND company_id=c AND approved_by=(SELECT auth.uid());
 SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.evaluated_at DESC),'[]') INTO runs FROM(
  SELECT r.id,r.scope_id,r.evaluated_at,r.outcome FROM private.c03_automation_runs r JOIN private.c03_automation_scopes s ON s.id=r.scope_id
  WHERE s.tenant_id=p_tenant_id AND s.company_id=c AND s.approved_by=(SELECT auth.uid()) ORDER BY r.evaluated_at DESC,r.id LIMIT 20)q;
 RETURN jsonb_build_object('rules',rules,'scopes',scopes,'runs',runs,'scheduled',false);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_automation_status(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_automation_status(uuid) TO authenticated;

CREATE FUNCTION private.c03_operational_candidates(p_tenant_id uuid,p_company_id uuid,p_now timestamptz,p_timezone text)
RETURNS TABLE(rule_id uuid,code text,module text,target_role text,severity text,escalation_config jsonb,
entity_type text,entity_id uuid,title text,body text,route text,occurred_at timestamptz,due_at timestamptz,metadata jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Despacho bloqueado',
           'La operación '||o.reference_code||' conserva requisitos de despacho pendientes.',
           '/operations?operation_id='||o.id||'&tab=overview',
           COALESCE(o.updated_at,o.created_at),NULL::timestamptz,
           jsonb_build_object('reference',o.reference_code,'blocking_reasons',ready->'blocking_reasons')
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('planned','assigned')
    CROSS JOIN LATERAL private.f7_operation_dispatch_readiness(o.id) ready
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_dispatch_blocked' AND r.is_enabled
      AND jsonb_typeof(ready->'blocking_reasons')='array'
      AND jsonb_array_length(ready->'blocking_reasons')>0
      AND p_now>=COALESCE(o.updated_at,o.created_at)+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation_incident',i.id,i.title,
           'Incidencia bloqueante abierta en '||o.reference_code||'.',
           '/operations?operation_id='||o.id||'&tab=incidents',
           i.created_at,NULL::timestamptz,jsonb_build_object('operation_id',o.id,'reference',o.reference_code)
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operation_incidents i ON i.tenant_id=r.tenant_id
    JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_blocking_incident' AND r.is_enabled
      AND i.status='open' AND i.is_blocking
      AND p_now>=i.created_at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation_document',d.id,'Documento requerido faltante',
           replace(d.document_type,'_',' ')||' · '||o.reference_code,
           '/operations?operation_id='||o.id||'&tab=documents&document='||d.document_type,
           d.updated_at,NULL::timestamptz,
           jsonb_build_object('operation_id',o.id,'reference',o.reference_code,'document_type',d.document_type)
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operation_documents d ON d.tenant_id=r.tenant_id
    JOIN public.operations o ON o.id=d.operation_id AND o.tenant_id=d.tenant_id
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_missing_document' AND r.is_enabled
      AND d.requirement_level='required' AND d.status='missing'
      AND d.document_type<>'proof_of_delivery'
      AND p_now>=d.updated_at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'POD pendiente',
           'La operación '||o.reference_code||' fue entregada y aún no tiene prueba de entrega.',
           '/operations?operation_id='||o.id||'&tab=documents&document=proof_of_delivery',
           delivered.at,NULL::timestamptz,jsonb_build_object('reference',o.reference_code,'document_type','proof_of_delivery')
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('delivered','closed')
    CROSS JOIN LATERAL (
        SELECT COALESCE(
            (SELECT max(e.server_timestamp) FROM public.tracking_events e
             WHERE e.operation_id=o.id AND e.event_type='delivered'),
            o.updated_at,o.created_at
        ) AS at
    ) delivered
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_pod_missing' AND r.is_enabled
      AND NOT EXISTS (
          SELECT 1 FROM public.operation_documents d
          WHERE d.operation_id=o.id AND d.document_type='proof_of_delivery' AND d.status='present'
      )
      AND p_now>=delivered.at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Facturación operativa bloqueada',
           'La operación '||o.reference_code||' conserva bloqueadores reales: '||
           array_to_string(blockers.items,', '),
           '/operations?operation_id='||o.id||'&tab=economics',
           COALESCE(o.updated_at,o.created_at),NULL::timestamptz,
           jsonb_build_object('reference',o.reference_code,'blocking_reasons',to_jsonb(blockers.items))
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('delivered','closed')
    CROSS JOIN LATERAL (
        SELECT array_remove(ARRAY[
            CASE WHEN EXISTS (SELECT 1 FROM public.operation_incidents i WHERE i.operation_id=o.id AND i.status='open' AND i.is_blocking) THEN 'incidencia bloqueante' END,
            CASE WHEN EXISTS (SELECT 1 FROM public.operation_documents d WHERE d.operation_id=o.id AND d.requirement_level='required' AND d.status='missing' AND d.document_type<>'proof_of_delivery') THEN 'documento requerido' END,
            CASE WHEN NOT EXISTS (SELECT 1 FROM public.operation_documents d WHERE d.operation_id=o.id AND d.document_type='proof_of_delivery' AND d.status='present') THEN 'POD pendiente' END,
            CASE WHEN NULLIF(btrim(COALESCE(o.client_display_name,'')),'') IS NULL THEN 'cliente faltante' END,
            CASE WHEN EXISTS (SELECT 1 FROM public.operation_billing b WHERE b.operation_id=o.id AND b.status='voided') THEN 'registro de facturación anulado' END
        ]::text[],NULL) AS items
    ) blockers
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_billing_blocked' AND r.is_enabled
      AND cardinality(blockers.items)>0
      AND p_now>=COALESCE(o.updated_at,o.created_at)+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Operación sin progreso',
           'La operación '||o.reference_code||' no registra actividad operativa significativa desde '||
           to_char(activity.last_at AT TIME ZONE p_timezone,'DD/MM/YYYY HH24:MI')||'.',
           '/operations?operation_id='||o.id||'&tab=overview',
           activity.last_at,NULL::timestamptz,jsonb_build_object('reference',o.reference_code,'last_meaningful_at',activity.last_at)
    FROM private.c03_operational_rules(p_tenant_id,p_company_id) r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('planned','assigned','in_transit')
    CROSS JOIN LATERAL (
        SELECT GREATEST(
            COALESCE(o.updated_at,o.created_at),
            COALESCE((SELECT max(h.changed_at) FROM public.operation_assignment_history h WHERE h.operation_id=o.id),'-infinity'::timestamptz),
            COALESCE((SELECT max(e.server_timestamp) FROM public.tracking_events e WHERE e.operation_id=o.id),'-infinity'::timestamptz),
            COALESCE((SELECT max(i.updated_at) FROM public.operation_incidents i WHERE i.operation_id=o.id),'-infinity'::timestamptz),
            COALESCE((SELECT max(e.created_at) FROM public.operation_evidence e WHERE e.operation_id=o.id),'-infinity'::timestamptz),
            COALESCE((SELECT max(c.updated_at) FROM public.operation_crossings c WHERE c.operation_id=o.id),'-infinity'::timestamptz),
            COALESCE((SELECT max(d.updated_at) FROM public.operation_documents d WHERE d.operation_id=o.id),'-infinity'::timestamptz)
        ) AS last_at
    ) activity
    WHERE r.tenant_id=p_tenant_id AND o.company_id=p_company_id AND o.company_classification_status='resolved' AND r.code='operation_stale' AND r.is_enabled
      AND COALESCE(o.operational_window_start,o.planned_departure,o.created_at)<=p_now
      AND activity.last_at+private.f7_interval(r.threshold_value,r.threshold_unit)<=p_now


$$;
REVOKE ALL ON FUNCTION private.c03_operational_candidates(uuid,uuid,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.c03_run_operational_scope(p_scope_id uuid,p_request_id uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s private.c03_automation_scopes%ROWTYPE;prior private.c03_automation_runs%ROWTYPE;c record;m record;n public.internal_notifications%ROWTYPE;
 nid uuid;e uuid;run_id uuid:=gen_random_uuid();v_fingerprint text;active_keys text[]:=ARRAY[]::text[];created int:=0;updated int:=0;resolved int:=0;escalated int:=0;
 level smallint;v_priority text;result jsonb;candidate_count int:=0;v_timezone text;rule_count int;
BEGIN
 IF p_scope_id IS NULL OR p_request_id IS NULL OR p_now IS NULL THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 SELECT * INTO s FROM private.c03_automation_scopes WHERE id=p_scope_id;
 IF NOT FOUND OR NOT s.enabled OR s.valid_until<=statement_timestamp() OR NOT private.delivery_required(s.tenant_id)
  OR NOT private.c03_operational_grant(s.tenant_id,s.company_id,s.approved_by,'automations.manage')
  OR NOT private.c03_operational_grant(s.tenant_id,s.company_id,s.approved_by,'operations.read')
  OR NOT EXISTS(SELECT FROM public.memberships WHERE tenant_id=s.tenant_id AND user_id=s.approved_by AND role='admin')
  OR EXISTS(SELECT FROM private.fiscal01_lab_actors WHERE tenant_id=s.tenant_id)
 THEN RETURN jsonb_build_object('error','scope_unavailable');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(s.tenant_id::text||s.company_id::text,4));
 SELECT * INTO prior FROM private.c03_automation_runs WHERE scope_id=s.id AND request_id=p_request_id;
 IF FOUND THEN RETURN prior.outcome;END IF;
 IF (SELECT count(*) FROM public.operations WHERE tenant_id=s.tenant_id AND company_id=s.company_id AND company_classification_status='resolved')>500
 THEN RETURN jsonb_build_object('error','scope_too_large');END IF;
 SELECT COALESCE(NULLIF(timezone,''),'America/Mexico_City') INTO v_timezone FROM public.tenant_settings WHERE tenant_id=s.tenant_id;
 v_timezone:=COALESCE(v_timezone,'America/Mexico_City');
 IF NOT EXISTS(SELECT FROM pg_timezone_names WHERE name=v_timezone) THEN v_timezone:='America/Mexico_City';END IF;
 SELECT count(*) INTO rule_count FROM private.c03_operational_rules(s.tenant_id,s.company_id) WHERE is_enabled;
 FOR c IN SELECT * FROM private.c03_operational_candidates(s.tenant_id,s.company_id,p_now,v_timezone) LOOP
  FOR m IN SELECT user_id,role FROM public.memberships WHERE tenant_id=s.tenant_id AND user_id=ANY(s.recipient_ids)
   AND private.f7_target_allows_role(c.target_role,role) AND private.c03_operational_grant(s.tenant_id,s.company_id,user_id,'operations.read') LOOP
   candidate_count:=candidate_count+1;
   v_fingerprint:='c03:'||s.company_id::text||':'||c.code||':'||c.entity_type||':'||c.entity_id::text;
   active_keys:=array_append(active_keys,m.user_id::text||':'||v_fingerprint);
   SELECT * INTO n FROM public.internal_notifications x WHERE x.tenant_id=s.tenant_id AND x.user_id=m.user_id AND x.fingerprint=v_fingerprint FOR UPDATE;
   level:=CASE WHEN n.id IS NOT NULL AND n.resolved_at IS NULL AND p_now>=n.first_seen_at+private.f7_interval(
    COALESCE(NULLIF(c.escalation_config->>'delay_value','')::int,0),COALESCE(NULLIF(c.escalation_config->>'delay_unit',''),'hours')) THEN 1 ELSE 0 END;
   v_priority:=CASE WHEN level>0 THEN COALESCE(NULLIF(c.escalation_config->>'severity',''),c.severity) ELSE c.severity END;
   IF v_priority NOT IN('critical','high','medium','low') THEN v_priority:=c.severity;END IF;
   IF n.id IS NULL THEN
    nid:=gen_random_uuid();
    INSERT INTO public.internal_notifications(id,tenant_id,user_id,fingerprint,trigger_type,area,priority,title,body,route,
     related_entity_type,related_entity_id,first_seen_at,last_seen_at,due_at,automation_rule_id,automation_rule_code,is_automated,metadata)
    VALUES(nid,s.tenant_id,m.user_id,v_fingerprint,c.code,c.module,v_priority,c.title,c.body,c.route,c.entity_type,c.entity_id::text,p_now,p_now,c.due_at,c.rule_id,c.code,true,
     jsonb_build_object('c03_scope_id',s.id,'operation_id',COALESCE(c.metadata->>'operation_id',CASE WHEN c.entity_type='operation' THEN c.entity_id::text END)));
    INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,access_class,evidence_reference,recorded_by)
    VALUES(s.tenant_id,'internal_notifications',nid,s.company_id,NULL,'c03-job:'||s.id::text,s.approved_by) RETURNING id INTO e;
    UPDATE public.internal_notifications SET company_id=s.company_id,company_classification_event_id=e,company_classification_status='resolved' WHERE id=nid;
    created:=created+1;
   ELSE
    IF n.company_id IS DISTINCT FROM s.company_id OR n.company_classification_status<>'resolved' THEN RAISE EXCEPTION 'c03_notification_provenance_conflict';END IF;
    UPDATE public.internal_notifications SET title=c.title,body=c.body,route=c.route,priority=v_priority,last_seen_at=p_now,
     resolved_at=NULL,escalation_level=level,escalated_at=CASE WHEN level>n.escalation_level THEN p_now ELSE n.escalated_at END,
     status=CASE WHEN n.resolved_at IS NOT NULL OR level>n.escalation_level THEN 'unread' ELSE n.status END,
     read_at=CASE WHEN n.resolved_at IS NOT NULL OR level>n.escalation_level THEN NULL ELSE n.read_at END,
     first_seen_at=CASE WHEN n.resolved_at IS NOT NULL THEN p_now ELSE n.first_seen_at END WHERE id=n.id;
    updated:=updated+1;IF level>n.escalation_level THEN escalated:=escalated+1;END IF;
   END IF;
  END LOOP;
 END LOOP;
 UPDATE public.internal_notifications x SET resolved_at=p_now,last_seen_at=p_now,status='read',read_at=COALESCE(x.read_at,p_now)
 WHERE x.tenant_id=s.tenant_id AND x.company_id=s.company_id AND x.user_id=ANY(s.recipient_ids) AND x.is_automated AND x.resolved_at IS NULL
  AND x.fingerprint LIKE 'c03:'||s.company_id::text||':%' AND NOT(x.user_id::text||':'||x.fingerprint=ANY(active_keys))
  AND private.c03_operational_grant(s.tenant_id,s.company_id,x.user_id,'operations.read');
 GET DIAGNOSTICS resolved=ROW_COUNT;
 result:=jsonb_build_object('success',true,'id',run_id,'created',created,'updated',updated,'resolved',resolved,'escalated',escalated,'candidates',candidate_count,'company_id',s.company_id,'rules_evaluated',rule_count,'timezone',v_timezone,'business_date',(p_now AT TIME ZONE v_timezone)::date);
 INSERT INTO private.c03_automation_runs(id,scope_id,request_id,evaluated_at,outcome) VALUES(run_id,s.id,p_request_id,p_now,result);
 PERFORM public.rpc_write_audit(s.tenant_id,'c03_operational_job_completed','automation_run',run_id,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION private.c03_run_operational_scope(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.rpc_delivery_run_automation(p_tenant_id uuid,p_scope_id uuid,p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'automations.manage') OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin'])
  OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1 OR NOT EXISTS(SELECT FROM private.c03_automation_scopes s
   WHERE s.id=p_scope_id AND s.tenant_id=p_tenant_id AND s.approved_by=(SELECT auth.uid()) AND s.company_id=(private.delivery_company_ids())[1])
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN private.c03_run_operational_scope(p_scope_id,p_request_id,statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_run_automation(uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_run_automation(uuid,uuid,uuid) TO authenticated;
CREATE FUNCTION private.c03_notification_allowed(nid uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE n public.internal_notifications%ROWTYPE;op uuid;
BEGIN
 SELECT * INTO n FROM public.internal_notifications WHERE id=nid AND user_id=(SELECT auth.uid());
 IF NOT FOUND OR n.company_classification_status<>'resolved' OR NOT(n.company_id=ANY(private.delivery_company_ids()))
  OR NOT private.delivery_cap(n.tenant_id,'operations.read') OR NOT(n.metadata ? 'c03_scope_id')
  OR NOT EXISTS(SELECT FROM private.c03_automation_scopes s WHERE s.id::text=n.metadata->>'c03_scope_id' AND s.tenant_id=n.tenant_id AND s.company_id=n.company_id)
 THEN RETURN false;END IF;
 BEGIN op:=(n.metadata->>'operation_id')::uuid;EXCEPTION WHEN invalid_text_representation THEN RETURN false;END;
 RETURN op IS NOT NULL AND private.delivery_entity_allowed(n.tenant_id,'operation',op);
END $$;
REVOKE ALL ON FUNCTION private.c03_notification_allowed(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.rpc_delivery_notifications(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;
BEGIN
 IF NOT private.delivery_scope_allowed(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',n.id,'module',n.area,'kind',n.trigger_type,'priority',n.priority,
  'title',n.title,'body',n.body,'route',n.route,'entity_type',n.related_entity_type,'entity_id',n.related_entity_id,
  'occurred_at',n.first_seen_at,'read_at',n.read_at,'created_at',n.first_seen_at) ORDER BY n.first_seen_at DESC,n.id),'[]') INTO items
 FROM public.internal_notifications n WHERE n.tenant_id=p_tenant_id AND n.user_id=(SELECT auth.uid())
  AND n.company_classification_status='resolved' AND n.company_id=ANY(private.delivery_company_ids()) AND n.status<>'dismissed' AND n.resolved_at IS NULL
  AND(private.delivery_cap(n.tenant_id,'financial.full.read') OR private.c03_notification_allowed(n.id));
 RETURN jsonb_build_object('items',items,'unread_count',(SELECT count(*) FROM jsonb_array_elements(items)e WHERE e->>'read_at' IS NULL),'has_more',false,'next_cursor',NULL);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_notifications(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_notifications(uuid) TO authenticated;
CREATE FUNCTION public.rpc_delivery_notification_action(p_tenant_id uuid,p_action text,p_ids uuid[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE ids uuid[];affected int;
BEGIN
 IF p_action NOT IN('read','dismiss') OR NOT private.delivery_scope_allowed(p_tenant_id) OR cardinality(p_ids)>100
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT array_agg(n.id) INTO ids FROM public.internal_notifications n WHERE n.tenant_id=p_tenant_id AND n.user_id=(SELECT auth.uid())
 AND n.company_classification_status='resolved' AND n.company_id=ANY(private.delivery_company_ids())
 AND (private.delivery_cap(p_tenant_id,'financial.full.read') OR private.c03_notification_allowed(n.id)) AND(p_ids IS NULL OR n.id=ANY(p_ids));
 IF p_ids IS NOT NULL AND EXISTS(SELECT FROM unnest(p_ids)x WHERE x IS NULL OR NOT COALESCE(x=ANY(ids),false)) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 UPDATE public.internal_notifications SET status=CASE p_action WHEN 'read' THEN 'read' ELSE 'dismissed' END,
  read_at=COALESCE(read_at,now()),dismissed_at=CASE p_action WHEN 'dismiss' THEN COALESCE(dismissed_at,now()) ELSE dismissed_at END
 WHERE id=ANY(ids);
 GET DIAGNOSTICS affected=ROW_COUNT;
 RETURN jsonb_build_object('success',true,'affected',affected);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_notification_action(uuid,text,uuid[]) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_notification_action(uuid,text,uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
