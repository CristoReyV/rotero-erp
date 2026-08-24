-- F7 — ROTERO Automations + Escalations + Daily Digest
-- Observes canonical F1-F6 business truth. It never mutates business state,
-- invokes external services, or depends on auth.uid() for scheduled execution.

CREATE EXTENSION IF NOT EXISTS pg_cron;

ALTER TABLE public.internal_notifications
    ADD COLUMN IF NOT EXISTS automation_rule_id uuid,
    ADD COLUMN IF NOT EXISTS automation_rule_code text,
    ADD COLUMN IF NOT EXISTS is_automated boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS first_seen_at timestamptz,
    ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz,
    ADD COLUMN IF NOT EXISTS escalation_level smallint NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS escalated_at timestamptz,
    ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

-- F7 extends the canonical Tanda8/F5 discriminator; it does not add a parallel
-- kind column.
ALTER TABLE public.internal_notifications DROP CONSTRAINT IF EXISTS internal_notifications_trigger_check;
ALTER TABLE public.internal_notifications
    ADD CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN (
        'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending',
        'blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked',
        'ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion',
        'operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing',
        'operation_billing_blocked','operation_stale','quote_review_stale','quote_approved_not_converted',
        'finance_due_today'
    ));

DO $constraints$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.internal_notifications'::regclass
          AND conname = 'internal_notifications_escalation_level_check'
    ) THEN
        ALTER TABLE public.internal_notifications
            ADD CONSTRAINT internal_notifications_escalation_level_check
            CHECK (escalation_level BETWEEN 0 AND 3);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.internal_notifications'::regclass
          AND conname = 'internal_notifications_metadata_object_check'
    ) THEN
        ALTER TABLE public.internal_notifications
            ADD CONSTRAINT internal_notifications_metadata_object_check
            CHECK (jsonb_typeof(metadata) = 'object');
    END IF;
END;
$constraints$;

CREATE TABLE public.automation_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    code text NOT NULL,
    name text NOT NULL,
    module text NOT NULL,
    is_enabled boolean NOT NULL DEFAULT true,
    target_role text NOT NULL,
    severity text NOT NULL,
    threshold_value integer NOT NULL DEFAULT 0,
    threshold_unit text NOT NULL DEFAULT 'hours',
    escalation_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    digest_enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_rules_tenant_code_unique UNIQUE (tenant_id, code),
    CONSTRAINT automation_rules_code_check CHECK (code IN (
        'operation_dispatch_blocked','operation_blocking_incident',
        'operation_missing_document','operation_pod_missing',
        'operation_billing_blocked','operation_stale',
        'quote_review_stale','quote_approved_not_converted',
        'ar_overdue','ap_overdue','finance_due_today','finance_due_soon'
    )),
    CONSTRAINT automation_rules_module_check CHECK (module IN ('operations','commercial','documents','finance')),
    CONSTRAINT automation_rules_target_role_check CHECK (target_role IN ('admin','finance','admin_finance')),
    CONSTRAINT automation_rules_severity_check CHECK (severity IN ('critical','high','medium','low')),
    CONSTRAINT automation_rules_threshold_check CHECK (threshold_value BETWEEN 0 AND 3650),
    CONSTRAINT automation_rules_threshold_unit_check CHECK (threshold_unit IN ('hours','days')),
    CONSTRAINT automation_rules_escalation_object_check CHECK (jsonb_typeof(escalation_config) = 'object')
);

ALTER TABLE public.internal_notifications
    ADD CONSTRAINT internal_notifications_automation_rule_fkey
    FOREIGN KEY (automation_rule_id) REFERENCES public.automation_rules(id) ON DELETE SET NULL;

CREATE TABLE public.automation_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    run_type text NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    status text NOT NULL DEFAULT 'running',
    rule_count integer NOT NULL DEFAULT 0,
    candidate_count integer NOT NULL DEFAULT 0,
    created_count integer NOT NULL DEFAULT 0,
    updated_count integer NOT NULL DEFAULT 0,
    resolved_count integer NOT NULL DEFAULT 0,
    escalated_count integer NOT NULL DEFAULT 0,
    safe_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_code text,
    requested_by uuid,
    CONSTRAINT automation_runs_type_check CHECK (run_type IN ('manual','scheduled','digest')),
    CONSTRAINT automation_runs_status_check CHECK (status IN ('running','completed','failed')),
    CONSTRAINT automation_runs_counts_check CHECK (
        rule_count >= 0 AND candidate_count >= 0 AND created_count >= 0
        AND updated_count >= 0 AND resolved_count >= 0 AND escalated_count >= 0
    ),
    CONSTRAINT automation_runs_summary_object_check CHECK (jsonb_typeof(safe_summary) = 'object')
);

CREATE TABLE public.automation_daily_digests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    business_date date NOT NULL,
    timezone text NOT NULL,
    role text NOT NULL,
    summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    items jsonb NOT NULL DEFAULT '[]'::jsonb,
    generated_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT automation_daily_digests_unique UNIQUE (tenant_id, user_id, business_date),
    CONSTRAINT automation_daily_digests_role_check CHECK (role IN ('admin','finance')),
    CONSTRAINT automation_daily_digests_summary_object_check CHECK (jsonb_typeof(summary) = 'object'),
    CONSTRAINT automation_daily_digests_items_array_check CHECK (jsonb_typeof(items) = 'array')
);

CREATE TABLE private.f7_source_candidates (
    evaluation_id uuid NOT NULL,
    rule_id uuid NOT NULL,
    code text NOT NULL,
    module text NOT NULL,
    target_role text NOT NULL,
    severity text NOT NULL,
    escalation_config jsonb NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    route text NOT NULL,
    occurred_at timestamptz NOT NULL,
    due_at timestamptz,
    metadata jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (evaluation_id, rule_id, entity_type, entity_id)
);

CREATE TABLE private.f7_recipient_candidates (
    evaluation_id uuid NOT NULL,
    rule_id uuid NOT NULL,
    code text NOT NULL,
    module text NOT NULL,
    target_role text NOT NULL,
    severity text NOT NULL,
    escalation_config jsonb NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    route text NOT NULL,
    occurred_at timestamptz NOT NULL,
    due_at timestamptz,
    metadata jsonb NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    fingerprint text NOT NULL,
    existing_id uuid,
    prior_resolved_at timestamptz,
    prior_escalation_level smallint NOT NULL,
    next_escalation_level smallint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (evaluation_id, user_id, fingerprint)
);

REVOKE ALL ON TABLE private.f7_source_candidates, private.f7_recipient_candidates
FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX automation_rules_tenant_enabled_idx
    ON public.automation_rules (tenant_id, is_enabled, module, code);
CREATE INDEX automation_runs_tenant_started_idx
    ON public.automation_runs (tenant_id, started_at DESC);
CREATE INDEX automation_daily_digests_owner_date_idx
    ON public.automation_daily_digests (tenant_id, user_id, business_date DESC);
CREATE INDEX internal_notifications_automation_active_idx
    ON public.internal_notifications (tenant_id, user_id, automation_rule_code, last_seen_at DESC)
    WHERE is_automated AND resolved_at IS NULL;
CREATE INDEX f7_source_candidates_created_idx ON private.f7_source_candidates (created_at);
CREATE INDEX f7_recipient_candidates_created_idx ON private.f7_recipient_candidates (created_at);

CREATE TRIGGER trg_automation_rules_touch_updated_at
BEFORE UPDATE ON public.automation_rules
FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

CREATE TRIGGER trg_automation_daily_digests_touch_updated_at
BEFORE UPDATE ON public.automation_daily_digests
FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.automation_daily_digests ENABLE ROW LEVEL SECURITY;

CREATE POLICY automation_rules_admin_f7 ON public.automation_rules
FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin'])));

CREATE POLICY automation_runs_admin_f7 ON public.automation_runs
FOR SELECT TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin'])));

CREATE POLICY automation_daily_digests_owner_f7 ON public.automation_daily_digests
FOR SELECT TO authenticated
USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin','finance']))
);

REVOKE ALL ON TABLE public.automation_rules, public.automation_runs,
    public.automation_daily_digests FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.f7_interval(p_value integer, p_unit text)
RETURNS interval
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT CASE p_unit
        WHEN 'days' THEN make_interval(days => p_value)
        ELSE make_interval(hours => p_value)
    END;
$function$;

CREATE OR REPLACE FUNCTION private.f7_target_allows_role(p_target text, p_role text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT p_role IN ('admin','finance')
       AND (p_target = p_role OR p_target = 'admin_finance');
$function$;

CREATE OR REPLACE FUNCTION private.f7_seed_rules(p_tenant_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_count integer;
BEGIN
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
        ('operation_stale','Operación sin progreso significativo','operations','admin_finance','high',24,'hours',12,'hours','critical'),
        ('quote_review_stale','Cotización en revisión sin avance','commercial','admin','medium',24,'hours',24,'hours','high'),
        ('quote_approved_not_converted','Cotización aprobada pendiente de conversión','commercial','admin','high',12,'hours',12,'hours','critical'),
        ('ar_overdue','Cuenta por cobrar vencida','finance','admin_finance','critical',0,'days',1,'days','critical'),
        ('ap_overdue','Cuenta por pagar vencida','finance','admin_finance','critical',0,'days',1,'days','critical'),
        ('finance_due_today','Cuenta financiera vence hoy','finance','admin_finance','high',0,'days',12,'hours','critical'),
        ('finance_due_soon','Cuenta financiera próxima a vencer','finance','admin_finance','medium',7,'days',3,'days','high')
    ) AS d(code,name,module,target_role,severity,threshold_value,threshold_unit,escalation_delay,escalation_unit,escalation_severity)
    ON CONFLICT (tenant_id, code) DO NOTHING;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$function$;

SELECT private.f7_seed_rules(t.id) FROM public.tenants AS t;

CREATE OR REPLACE FUNCTION private.f7_operation_dispatch_readiness(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_planning boolean;
    v_assignment boolean;
    v_tracking_ready boolean;
    v_driver_ok boolean := true;
    v_vehicle_ok boolean := true;
    v_has_driver_token boolean;
    v_has_public_token boolean;
    v_has_incident boolean;
    v_last_signal_at timestamptz;
    v_tracking_status text;
    v_reasons text[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;

    v_planning := NULLIF(btrim(COALESCE(v_operation.service_type,'')),'') IS NOT NULL
        AND v_operation.origin_place IS NOT NULL
        AND v_operation.destination_place IS NOT NULL
        AND v_operation.operational_window_start IS NOT NULL
        AND v_operation.operational_window_end IS NOT NULL
        AND v_operation.operational_window_end > v_operation.operational_window_start
        AND NULLIF(btrim(COALESCE(v_operation.route_summary,'')),'') IS NOT NULL
        AND NULLIF(btrim(COALESCE(v_operation.destination_city,'')),'') IS NOT NULL;
    v_assignment := v_operation.planned_departure IS NOT NULL AND (
        (v_operation.execution_type='third_party' AND v_operation.provider_id IS NOT NULL)
        OR (v_operation.execution_type='own_fleet' AND v_operation.driver_id IS NOT NULL AND v_operation.vehicle_id IS NOT NULL)
    );
    IF v_operation.execution_type='own_fleet' AND v_operation.driver_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM public.drivers d
            WHERE d.id=v_operation.driver_id AND d.tenant_id=v_operation.tenant_id
              AND d.status='available' AND COALESCE((to_jsonb(d)->>'is_active')::boolean,true)
        ) AND NOT EXISTS (
            SELECT 1 FROM public.operations o
            WHERE o.tenant_id=v_operation.tenant_id AND o.driver_id=v_operation.driver_id
              AND o.id<>p_operation_id AND o.status IN ('assigned','in_transit')
        ) INTO v_driver_ok;
    END IF;
    IF v_operation.execution_type='own_fleet' AND v_operation.vehicle_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM public.vehicles v
            WHERE v.id=v_operation.vehicle_id AND v.tenant_id=v_operation.tenant_id
              AND v.status='available' AND COALESCE((to_jsonb(v)->>'is_active')::boolean,true)
        ) AND NOT EXISTS (
            SELECT 1 FROM public.operations o
            WHERE o.tenant_id=v_operation.tenant_id AND o.vehicle_id=v_operation.vehicle_id
              AND o.id<>p_operation_id AND o.status IN ('assigned','in_transit')
        ) INTO v_vehicle_ok;
    END IF;
    SELECT EXISTS (
        SELECT 1 FROM public.tracking_tokens t
        WHERE t.operation_id=p_operation_id AND t.scope='driver:write'
          AND t.state='active' AND t.revoked_at IS NULL AND t.expires_at>now()
    ) INTO v_has_driver_token;
    SELECT EXISTS (
        SELECT 1 FROM public.tracking_tokens t
        WHERE t.operation_id=p_operation_id AND t.scope='public:read'
          AND t.state='active' AND t.revoked_at IS NULL AND t.expires_at>now()
    ) INTO v_has_public_token;
    SELECT EXISTS (
        SELECT 1 FROM public.operation_incidents i
        WHERE i.operation_id=p_operation_id AND i.status='open' AND i.is_blocking
    ) INTO v_has_incident;
    SELECT e.server_timestamp,e.event_type INTO v_last_signal_at,v_tracking_status
    FROM public.tracking_events e
    WHERE e.operation_id=p_operation_id AND e.event_type NOT IN ('incident','location_reset')
    ORDER BY e.server_timestamp DESC LIMIT 1;

    v_tracking_ready := v_assignment AND v_has_driver_token AND v_has_public_token;
    IF NOT v_planning THEN v_reasons:=array_append(v_reasons,'missing_planning_data'); END IF;
    IF NOT v_assignment THEN v_reasons:=array_append(v_reasons,'missing_assignment'); END IF;
    IF v_operation.execution_type='own_fleet' AND v_operation.driver_id IS NOT NULL AND NOT v_driver_ok THEN
        v_reasons:=array_append(v_reasons,'driver_unavailable');
    END IF;
    IF v_operation.execution_type='own_fleet' AND v_operation.vehicle_id IS NOT NULL AND NOT v_vehicle_ok THEN
        v_reasons:=array_append(v_reasons,'vehicle_unavailable');
    END IF;
    IF v_operation.status='assigned' AND NOT v_tracking_ready THEN
        v_reasons:=array_append(v_reasons,'tracking_not_ready');
    END IF;
    RETURN jsonb_build_object(
        'is_minimum_planned_complete',v_planning,
        'is_assignment_complete',v_assignment,
        'is_tracking_ready',v_tracking_ready,
        'can_transition_to_assigned',v_planning AND v_assignment AND v_driver_ok AND v_vehicle_ok,
        'can_transition_to_in_transit',v_planning AND v_assignment AND v_driver_ok AND v_vehicle_ok AND v_tracking_ready,
        'has_driver_token',v_has_driver_token,'has_public_token',v_has_public_token,
        'has_incident',v_has_incident,'last_signal_at',v_last_signal_at,
        'current_tracking_status',v_tracking_status,'blocking_reasons',to_jsonb(v_reasons)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_dispatch_readiness(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id=p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator','finance','viewer']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN private.f7_operation_dispatch_readiness(p_operation_id);
END;
$function$;

CREATE OR REPLACE FUNCTION private.f7_materialize_automation_notifications(
    p_tenant_id uuid,
    p_target_user_id uuid,
    p_run_type text,
    p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_timezone text;
    v_local_date date;
    v_rule_count integer := 0;
    v_candidate_count integer := 0;
    v_created integer := 0;
    v_updated integer := 0;
    v_resolved integer := 0;
    v_escalated integer := 0;
    v_run_id uuid;
    v_evaluation_id uuid := gen_random_uuid();
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id=p_tenant_id) THEN
        RETURN jsonb_build_object('error','tenant_not_found');
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext('rotero-f7-automation'),
        pg_catalog.hashtext(p_tenant_id::text)
    );
    PERFORM private.f7_seed_rules(p_tenant_id);
    SELECT COALESCE(NULLIF(s.timezone,''),'America/Mexico_City') INTO v_timezone
    FROM public.tenant_settings s WHERE s.tenant_id=p_tenant_id;
    v_timezone := COALESCE(v_timezone,'America/Mexico_City');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
        v_timezone := 'America/Mexico_City';
    END IF;
    v_local_date := (p_now AT TIME ZONE v_timezone)::date;
    SELECT count(*) INTO v_rule_count
    FROM public.automation_rules WHERE tenant_id=p_tenant_id AND is_enabled;

    IF p_run_type IN ('manual','scheduled') AND p_target_user_id IS NULL THEN
        INSERT INTO public.automation_runs(tenant_id,run_type,started_at,requested_by)
        VALUES (p_tenant_id,p_run_type,p_now,CASE WHEN p_run_type='manual' THEN (SELECT auth.uid()) ELSE NULL END)
        RETURNING id INTO v_run_id;
    END IF;

    DELETE FROM private.f7_recipient_candidates WHERE created_at<now()-interval '1 day';
    DELETE FROM private.f7_source_candidates WHERE created_at<now()-interval '1 day';

    INSERT INTO private.f7_source_candidates(
        evaluation_id,rule_id,code,module,target_role,severity,escalation_config,
        entity_type,entity_id,title,body,route,occurred_at,due_at,metadata
    )
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Despacho bloqueado',
           'La operación '||o.reference_code||' conserva requisitos de despacho pendientes.',
           '/operations?operationId='||o.id||'&tab=overview',
           COALESCE(o.updated_at,o.created_at),NULL::timestamptz,
           jsonb_build_object('reference',o.reference_code,'blocking_reasons',ready->'blocking_reasons')
    FROM public.automation_rules r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('planned','assigned')
    CROSS JOIN LATERAL private.f7_operation_dispatch_readiness(o.id) ready
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_dispatch_blocked' AND r.is_enabled
      AND jsonb_typeof(ready->'blocking_reasons')='array'
      AND jsonb_array_length(ready->'blocking_reasons')>0
      AND p_now>=COALESCE(o.updated_at,o.created_at)+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation_incident',i.id,i.title,
           COALESCE(NULLIF(i.description,''),'Incidencia bloqueante abierta en '||o.reference_code||'.'),
           '/operations?operationId='||o.id||'&tab=incidents',
           i.created_at,NULL::timestamptz,jsonb_build_object('operation_id',o.id,'reference',o.reference_code)
    FROM public.automation_rules r
    JOIN public.operation_incidents i ON i.tenant_id=r.tenant_id
    JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_blocking_incident' AND r.is_enabled
      AND i.status='open' AND i.is_blocking
      AND p_now>=i.created_at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation_document',d.id,'Documento requerido faltante',
           replace(d.document_type,'_',' ')||' · '||o.reference_code,
           '/operations?operationId='||o.id||'&tab=documents&document='||d.document_type,
           d.updated_at,NULL::timestamptz,
           jsonb_build_object('operation_id',o.id,'reference',o.reference_code,'document_type',d.document_type)
    FROM public.automation_rules r
    JOIN public.operation_documents d ON d.tenant_id=r.tenant_id
    JOIN public.operations o ON o.id=d.operation_id AND o.tenant_id=d.tenant_id
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_missing_document' AND r.is_enabled
      AND d.requirement_level='required' AND d.status='missing'
      AND d.document_type<>'proof_of_delivery'
      AND p_now>=d.updated_at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'POD pendiente',
           'La operación '||o.reference_code||' fue entregada y aún no tiene prueba de entrega.',
           '/operations?operationId='||o.id||'&tab=documents&document=proof_of_delivery',
           delivered.at,NULL::timestamptz,jsonb_build_object('reference',o.reference_code,'document_type','proof_of_delivery')
    FROM public.automation_rules r
    JOIN public.operations o ON o.tenant_id=r.tenant_id AND o.status IN ('delivered','closed')
    CROSS JOIN LATERAL (
        SELECT COALESCE(
            (SELECT max(e.server_timestamp) FROM public.tracking_events e
             WHERE e.operation_id=o.id AND e.event_type='delivered'),
            o.updated_at,o.created_at
        ) AS at
    ) delivered
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_pod_missing' AND r.is_enabled
      AND NOT EXISTS (
          SELECT 1 FROM public.operation_documents d
          WHERE d.operation_id=o.id AND d.document_type='proof_of_delivery' AND d.status='present'
      )
      AND p_now>=delivered.at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Facturación operativa bloqueada',
           'La operación '||o.reference_code||' conserva bloqueadores reales: '||
           array_to_string(blockers.items,', '),
           '/operations?operationId='||o.id||'&tab=economics',
           COALESCE(o.updated_at,o.created_at),NULL::timestamptz,
           jsonb_build_object('reference',o.reference_code,'blocking_reasons',to_jsonb(blockers.items))
    FROM public.automation_rules r
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
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_billing_blocked' AND r.is_enabled
      AND cardinality(blockers.items)>0
      AND p_now>=COALESCE(o.updated_at,o.created_at)+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'operation',o.id,'Operación sin progreso',
           'La operación '||o.reference_code||' no registra actividad operativa significativa desde '||
           to_char(activity.last_at AT TIME ZONE v_timezone,'DD/MM/YYYY HH24:MI')||'.',
           '/operations?operationId='||o.id||'&tab=overview',
           activity.last_at,NULL::timestamptz,jsonb_build_object('reference',o.reference_code,'last_meaningful_at',activity.last_at)
    FROM public.automation_rules r
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
    WHERE r.tenant_id=p_tenant_id AND r.code='operation_stale' AND r.is_enabled
      AND COALESCE(o.operational_window_start,o.planned_departure,o.created_at)<=p_now
      AND activity.last_at+private.f7_interval(r.threshold_value,r.threshold_unit)<=p_now

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'quote',d.id,'Cotización en revisión sin avance',
           COALESCE(d.quote_reference,d.title)||' lleva más tiempo del configurado en revisión.',
           '/commercial?view=quotes&quoteId='||d.id,
           d.updated_at,NULL::timestamptz,jsonb_build_object('reference',COALESCE(d.quote_reference,d.title))
    FROM public.automation_rules r
    JOIN public.crm_deals d ON d.tenant_id=r.tenant_id
    WHERE r.tenant_id=p_tenant_id AND r.code='quote_review_stale' AND r.is_enabled
      AND d.quote_status='in_review'
      AND p_now>=d.updated_at+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'quote',d.id,'Cotización aprobada pendiente de conversión',
           COALESCE(d.quote_reference,d.title)||' aún no se convierte en operación.',
           '/commercial?view=quotes&quoteId='||d.id,
           COALESCE(d.approved_at,d.updated_at),NULL::timestamptz,
           jsonb_build_object('reference',COALESCE(d.quote_reference,d.title))
    FROM public.automation_rules r
    JOIN public.crm_deals d ON d.tenant_id=r.tenant_id
    WHERE r.tenant_id=p_tenant_id AND r.code='quote_approved_not_converted' AND r.is_enabled
      AND d.quote_status='approved' AND d.converted_operation_id IS NULL
      AND p_now>=COALESCE(d.approved_at,d.updated_at)+private.f7_interval(r.threshold_value,r.threshold_unit)

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'finance_invoice',i.id,
           CASE i.direction WHEN 'ar' THEN 'Cuenta por cobrar vencida' ELSE 'Cuenta por pagar vencida' END,
           i.counterparty_name||' · saldo '||trim(to_char(t.balance_amount,'FM999999999990.00'))||' '||i.currency,
           '/finance?view='||i.direction||'&invoiceId='||i.id,
           i.created_at,i.due_date::timestamptz,
           jsonb_build_object('reference',i.reference,'direction',i.direction,'remaining_balance',t.balance_amount,'currency',i.currency,'due_date',i.due_date)
    FROM public.automation_rules r
    JOIN public.finance_invoices i ON i.tenant_id=r.tenant_id
    CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
    WHERE r.tenant_id=p_tenant_id AND r.code=CASE i.direction WHEN 'ar' THEN 'ar_overdue' ELSE 'ap_overdue' END
      AND r.is_enabled AND i.status='open' AND t.balance_amount>0 AND i.due_date<v_local_date

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'finance_invoice',i.id,'Cuenta financiera vence hoy',
           i.counterparty_name||' · saldo '||trim(to_char(t.balance_amount,'FM999999999990.00'))||' '||i.currency,
           '/finance?view='||i.direction||'&invoiceId='||i.id,
           i.created_at,i.due_date::timestamptz,
           jsonb_build_object('reference',i.reference,'direction',i.direction,'remaining_balance',t.balance_amount,'currency',i.currency,'due_date',i.due_date)
    FROM public.automation_rules r
    JOIN public.finance_invoices i ON i.tenant_id=r.tenant_id
    CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
    WHERE r.tenant_id=p_tenant_id AND r.code='finance_due_today' AND r.is_enabled
      AND i.status='open' AND t.balance_amount>0 AND i.due_date=v_local_date

    UNION ALL
    SELECT v_evaluation_id,r.id,r.code,r.module,r.target_role,r.severity,r.escalation_config,
           'finance_invoice',i.id,'Cuenta financiera próxima a vencer',
           i.counterparty_name||' · saldo '||trim(to_char(t.balance_amount,'FM999999999990.00'))||' '||i.currency,
           '/finance?view='||i.direction||'&invoiceId='||i.id,
           i.created_at,i.due_date::timestamptz,
           jsonb_build_object('reference',i.reference,'direction',i.direction,'remaining_balance',t.balance_amount,'currency',i.currency,'due_date',i.due_date)
    FROM public.automation_rules r
    JOIN public.finance_invoices i ON i.tenant_id=r.tenant_id
    CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
    WHERE r.tenant_id=p_tenant_id AND r.code='finance_due_soon' AND r.is_enabled
      AND i.status='open' AND t.balance_amount>0
      AND i.due_date>v_local_date
      AND i.due_date<=v_local_date+r.threshold_value;

    INSERT INTO private.f7_recipient_candidates(
        evaluation_id,rule_id,code,module,target_role,severity,escalation_config,
        entity_type,entity_id,title,body,route,occurred_at,due_at,metadata,
        user_id,role,fingerprint,existing_id,prior_resolved_at,
        prior_escalation_level,next_escalation_level
    )
    SELECT v_evaluation_id,c.rule_id,c.code,c.module,c.target_role,c.severity,c.escalation_config,
           c.entity_type,c.entity_id,c.title,c.body,c.route,c.occurred_at,c.due_at,c.metadata,
           m.user_id,m.role,
           'automation:'||c.code||':'||c.entity_type||':'||c.entity_id AS fingerprint,
           n.id AS existing_id,n.resolved_at AS prior_resolved_at,
           COALESCE(n.escalation_level,0) AS prior_escalation_level,
           CASE
             WHEN n.id IS NOT NULL AND n.resolved_at IS NULL
              AND p_now>=n.first_seen_at+private.f7_interval(
                  COALESCE(NULLIF(c.escalation_config->>'delay_value','')::integer,0),
                  COALESCE(NULLIF(c.escalation_config->>'delay_unit',''),'hours')
              )
             THEN 1 ELSE 0
           END::smallint AS next_escalation_level
    FROM private.f7_source_candidates c
    JOIN public.memberships m ON m.tenant_id=p_tenant_id
      AND private.f7_target_allows_role(c.target_role,m.role)
      AND (p_target_user_id IS NULL OR m.user_id=p_target_user_id)
    LEFT JOIN public.internal_notifications n
      ON n.tenant_id=p_tenant_id AND n.user_id=m.user_id
     AND n.fingerprint='automation:'||c.code||':'||c.entity_type||':'||c.entity_id
    WHERE c.evaluation_id=v_evaluation_id;

    SELECT count(*) INTO v_candidate_count
    FROM private.f7_recipient_candidates WHERE evaluation_id=v_evaluation_id;
    SELECT count(*) FILTER (WHERE existing_id IS NULL),
           count(*) FILTER (WHERE existing_id IS NOT NULL),
           count(*) FILTER (WHERE existing_id IS NOT NULL AND next_escalation_level>prior_escalation_level)
      INTO v_created,v_updated,v_escalated
    FROM private.f7_recipient_candidates WHERE evaluation_id=v_evaluation_id;

    INSERT INTO public.internal_notifications (
        tenant_id,user_id,fingerprint,area,trigger_type,priority,icon,title,body,route,
        related_entity_type,related_entity_id,status,due_at,automation_rule_id,
        automation_rule_code,is_automated,first_seen_at,last_seen_at,
        resolved_at,escalation_level,escalated_at,metadata
    )
    SELECT p_tenant_id,c.user_id,c.fingerprint,c.module,c.code,
           CASE WHEN c.next_escalation_level>0
                THEN COALESCE(NULLIF(c.escalation_config->>'severity',''),c.severity)
                ELSE c.severity END,
           CASE WHEN c.severity IN ('critical','high') THEN 'warning' ELSE 'info' END,
           c.title,c.body,c.route,c.entity_type,c.entity_id::text,'unread',c.due_at,
           c.rule_id,c.code,true,p_now,p_now,NULL,c.next_escalation_level,
           CASE WHEN c.next_escalation_level>0 THEN p_now END,
           c.metadata||jsonb_build_object('automated',true,'target_role',c.target_role,'occurred_at',c.occurred_at)
    FROM private.f7_recipient_candidates c
    WHERE c.evaluation_id=v_evaluation_id
    ON CONFLICT (tenant_id,user_id,fingerprint) DO UPDATE SET
        area=EXCLUDED.area,trigger_type=EXCLUDED.trigger_type,priority=EXCLUDED.priority,
        icon=EXCLUDED.icon,
        title=EXCLUDED.title,body=EXCLUDED.body,route=EXCLUDED.route,
        related_entity_type=EXCLUDED.related_entity_type,
        related_entity_id=EXCLUDED.related_entity_id,due_at=EXCLUDED.due_at,
        automation_rule_id=EXCLUDED.automation_rule_id,
        automation_rule_code=EXCLUDED.automation_rule_code,is_automated=true,
        first_seen_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL
                           THEN EXCLUDED.first_seen_at
                           ELSE COALESCE(public.internal_notifications.first_seen_at,EXCLUDED.first_seen_at) END,
        last_seen_at=EXCLUDED.last_seen_at,resolved_at=NULL,
        escalation_level=EXCLUDED.escalation_level,
        escalated_at=CASE
            WHEN EXCLUDED.escalation_level>public.internal_notifications.escalation_level THEN EXCLUDED.escalated_at
            ELSE public.internal_notifications.escalated_at END,
        read_at=CASE
            WHEN public.internal_notifications.resolved_at IS NOT NULL
              OR EXCLUDED.escalation_level>public.internal_notifications.escalation_level THEN NULL
            ELSE public.internal_notifications.read_at END,
        status=CASE
            WHEN public.internal_notifications.resolved_at IS NOT NULL
              OR EXCLUDED.escalation_level>public.internal_notifications.escalation_level THEN 'unread'
            ELSE public.internal_notifications.status END,
        dismissed_at=CASE
            WHEN public.internal_notifications.resolved_at IS NOT NULL
              OR EXCLUDED.escalation_level>public.internal_notifications.escalation_level THEN NULL
            ELSE public.internal_notifications.dismissed_at END,
        metadata=EXCLUDED.metadata;

    UPDATE public.internal_notifications n
    SET resolved_at=p_now,last_seen_at=p_now,status='read',read_at=COALESCE(n.read_at,p_now)
    WHERE n.tenant_id=p_tenant_id AND n.is_automated AND n.resolved_at IS NULL
      AND (p_target_user_id IS NULL OR n.user_id=p_target_user_id)
      AND NOT EXISTS (
          SELECT 1 FROM private.f7_recipient_candidates c
          WHERE c.evaluation_id=v_evaluation_id
            AND c.user_id=n.user_id AND c.fingerprint=n.fingerprint
      );
    GET DIAGNOSTICS v_resolved=ROW_COUNT;

    IF v_escalated>0 THEN
        INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,metadata)
        VALUES (
            p_tenant_id,CASE WHEN p_run_type='manual' THEN (SELECT auth.uid()) ELSE NULL END,
            'automation_escalation_summary','automation',
            jsonb_build_object('run_type',p_run_type,'escalated_count',v_escalated)
        );
    END IF;
    IF v_run_id IS NOT NULL THEN
        UPDATE public.automation_runs
        SET completed_at=clock_timestamp(),status='completed',rule_count=v_rule_count,
            candidate_count=v_candidate_count,created_count=v_created,
            updated_count=v_updated,resolved_count=v_resolved,escalated_count=v_escalated,
            safe_summary=jsonb_build_object('timezone',v_timezone,'business_date',v_local_date)
        WHERE id=v_run_id;
    END IF;
    DELETE FROM private.f7_recipient_candidates WHERE evaluation_id=v_evaluation_id;
    DELETE FROM private.f7_source_candidates WHERE evaluation_id=v_evaluation_id;
    RETURN jsonb_build_object(
        'success',true,'rules_evaluated',v_rule_count,'candidates',v_candidate_count,
        'created',v_created,'updated',v_updated,'resolved',v_resolved,
        'escalated',v_escalated,'business_date',v_local_date,'timezone',v_timezone
    );
END;
$function$;

CREATE OR REPLACE FUNCTION private.f7_generate_tenant_digests(
    p_tenant_id uuid,
    p_now timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_timezone text;
    v_business_date date;
    v_member record;
    v_items jsonb;
    v_summary jsonb;
    v_user_count integer := 0;
    v_item_count integer := 0;
    v_run_id uuid;
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext('rotero-f7-digest'),
        pg_catalog.hashtext(p_tenant_id::text)
    );
    PERFORM private.f7_seed_rules(p_tenant_id);
    SELECT COALESCE(NULLIF(s.timezone,''),'America/Mexico_City') INTO v_timezone
    FROM public.tenant_settings s WHERE s.tenant_id=p_tenant_id;
    v_timezone:=COALESCE(v_timezone,'America/Mexico_City');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
        v_timezone:='America/Mexico_City';
    END IF;
    v_business_date:=(p_now AT TIME ZONE v_timezone)::date;
    INSERT INTO public.automation_runs(tenant_id,run_type,started_at)
    VALUES (p_tenant_id,'digest',p_now) RETURNING id INTO v_run_id;

    FOR v_member IN
        SELECT m.user_id,m.role FROM public.memberships m
        WHERE m.tenant_id=p_tenant_id AND m.role IN ('admin','finance')
        ORDER BY m.user_id
    LOOP
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id',n.id,'module',n.area,'rule_code',n.automation_rule_code,
            'priority',n.priority,'title',n.title,'body',n.body,'route',n.route,
            'entity_type',n.related_entity_type,'entity_id',n.related_entity_id,
            'first_seen_at',n.first_seen_at,'escalation_level',n.escalation_level
        ) ORDER BY
            CASE n.priority WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
            n.first_seen_at),'[]'::jsonb)
        INTO v_items
        FROM public.internal_notifications n
        JOIN public.automation_rules r ON r.id=n.automation_rule_id
        WHERE n.tenant_id=p_tenant_id AND n.user_id=v_member.user_id
          AND n.is_automated AND n.resolved_at IS NULL AND n.status<>'dismissed'
          AND r.is_enabled AND r.digest_enabled;

        SELECT jsonb_build_object(
            'total',jsonb_array_length(v_items),
            'critical',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'priority'='critical'),
            'high',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'priority'='high'),
            'operations_blocked',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'rule_code' IN ('operation_dispatch_blocked','operation_blocking_incident','operation_billing_blocked','operation_stale')),
            'ar_overdue',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'rule_code'='ar_overdue'),
            'ap_overdue',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'rule_code'='ap_overdue'),
            'documents_missing',(SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'rule_code' IN ('operation_missing_document','operation_pod_missing')),
            'quotes_pending',CASE WHEN v_member.role='admin'
                THEN (SELECT count(*) FROM jsonb_array_elements(v_items) x WHERE x->>'module'='commercial')
                ELSE 0 END
        ) INTO v_summary;

        INSERT INTO public.automation_daily_digests(
            tenant_id,user_id,business_date,timezone,role,summary,items,generated_at
        ) VALUES (
            p_tenant_id,v_member.user_id,v_business_date,v_timezone,v_member.role,
            v_summary,v_items,p_now
        )
        ON CONFLICT (tenant_id,user_id,business_date) DO UPDATE SET
            timezone=EXCLUDED.timezone,role=EXCLUDED.role,summary=EXCLUDED.summary,
            items=EXCLUDED.items,generated_at=EXCLUDED.generated_at;
        v_user_count:=v_user_count+1;
        v_item_count:=v_item_count+jsonb_array_length(v_items);
    END LOOP;

    UPDATE public.automation_runs
    SET completed_at=clock_timestamp(),status='completed',candidate_count=v_item_count,
        updated_count=v_user_count,
        safe_summary=jsonb_build_object(
            'business_date',v_business_date,'timezone',v_timezone,
            'digest_users',v_user_count,'digest_items',v_item_count
        )
    WHERE id=v_run_id;
    INSERT INTO public.audit_log(tenant_id,action,entity_type,metadata)
    VALUES (
        p_tenant_id,'automation_digest_evaluated','automation_digest',
        jsonb_build_object('business_date',v_business_date,'users',v_user_count,'items',v_item_count)
    );
    RETURN jsonb_build_object(
        'success',true,'business_date',v_business_date,'timezone',v_timezone,
        'users',v_user_count,'items',v_item_count
    );
END;
$function$;

CREATE OR REPLACE FUNCTION private.run_f7_automations()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant record; v_ok integer:=0; v_failed integer:=0;
BEGIN
    FOR v_tenant IN SELECT id FROM public.tenants ORDER BY id LOOP
        BEGIN
            PERFORM private.f7_materialize_automation_notifications(v_tenant.id,NULL,'scheduled',now());
            v_ok:=v_ok+1;
        EXCEPTION WHEN OTHERS THEN
            v_failed:=v_failed+1;
            INSERT INTO public.automation_runs(
                tenant_id,run_type,started_at,completed_at,status,error_code,safe_summary
            ) VALUES (
                v_tenant.id,'scheduled',now(),clock_timestamp(),'failed',
                'automation_evaluation_failed','{"source":"scheduler"}'::jsonb
            );
        END;
    END LOOP;
    RETURN jsonb_build_object('success',v_failed=0,'tenants_completed',v_ok,'tenants_failed',v_failed);
END;
$function$;

CREATE OR REPLACE FUNCTION private.run_f7_daily_digest()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant record; v_ok integer:=0; v_failed integer:=0;
BEGIN
    FOR v_tenant IN SELECT id FROM public.tenants ORDER BY id LOOP
        BEGIN
            PERFORM private.f7_generate_tenant_digests(v_tenant.id,now());
            v_ok:=v_ok+1;
        EXCEPTION WHEN OTHERS THEN
            v_failed:=v_failed+1;
            INSERT INTO public.automation_runs(
                tenant_id,run_type,started_at,completed_at,status,error_code,safe_summary
            ) VALUES (
                v_tenant.id,'digest',now(),clock_timestamp(),'failed',
                'digest_evaluation_failed','{"source":"scheduler"}'::jsonb
            );
        END;
    END LOOP;
    RETURN jsonb_build_object('success',v_failed=0,'tenants_completed',v_ok,'tenants_failed',v_failed);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_automation_rules(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    PERFORM private.f7_seed_rules(p_tenant_id);
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.module,x.name),'[]'::jsonb)
    INTO v_items
    FROM (
        SELECT id,code,name,module,is_enabled,target_role,severity,threshold_value,
               threshold_unit,
               COALESCE(NULLIF(escalation_config->>'delay_value','')::integer,0) escalation_delay_value,
               COALESCE(NULLIF(escalation_config->>'delay_unit',''),'hours') escalation_delay_unit,
               COALESCE(NULLIF(escalation_config->>'severity',''),'high') escalation_severity,
               digest_enabled,updated_at
        FROM public.automation_rules WHERE tenant_id=p_tenant_id
    ) x;
    RETURN jsonb_build_object('items',v_items);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_update_automation_rule(
    p_tenant_id uuid,
    p_rule_id uuid,
    p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_rule public.automation_rules%ROWTYPE;
    v_target text;
    v_severity text;
    v_threshold integer;
    v_unit text;
    v_delay integer;
    v_delay_unit text;
    v_escalation_severity text;
    v_enabled boolean;
    v_digest boolean;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    SELECT * INTO v_rule FROM public.automation_rules
    WHERE id=p_rule_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF v_rule.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    BEGIN
        v_target:=COALESCE(NULLIF(p_payload->>'target_role',''),v_rule.target_role);
        v_severity:=COALESCE(NULLIF(p_payload->>'severity',''),v_rule.severity);
        v_threshold:=COALESCE(NULLIF(p_payload->>'threshold_value','')::integer,v_rule.threshold_value);
        v_unit:=COALESCE(NULLIF(p_payload->>'threshold_unit',''),v_rule.threshold_unit);
        v_delay:=COALESCE(NULLIF(p_payload->>'escalation_delay_value','')::integer,
            NULLIF(v_rule.escalation_config->>'delay_value','')::integer,0);
        v_delay_unit:=COALESCE(NULLIF(p_payload->>'escalation_delay_unit',''),
            NULLIF(v_rule.escalation_config->>'delay_unit',''),'hours');
        v_escalation_severity:=COALESCE(NULLIF(p_payload->>'escalation_severity',''),
            NULLIF(v_rule.escalation_config->>'severity',''),'high');
        v_enabled:=COALESCE(NULLIF(p_payload->>'is_enabled','')::boolean,v_rule.is_enabled);
        v_digest:=COALESCE(NULLIF(p_payload->>'digest_enabled','')::boolean,v_rule.digest_enabled);
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END;
    IF v_severity NOT IN ('critical','high','medium','low')
       OR v_escalation_severity NOT IN ('critical','high','medium','low')
       OR v_unit NOT IN ('hours','days') OR v_delay_unit NOT IN ('hours','days')
       OR v_threshold NOT BETWEEN 0 AND 3650 OR v_delay NOT BETWEEN 0 AND 3650
       OR v_target NOT IN ('admin','finance','admin_finance')
       OR (CASE v_escalation_severity WHEN 'critical' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 ELSE 1 END)
          < (CASE v_severity WHEN 'critical' THEN 4 WHEN 'high' THEN 3 WHEN 'medium' THEN 2 ELSE 1 END)
       OR (v_rule.module='commercial' AND v_target<>'admin')
       OR (v_rule.module='finance' AND v_target<>'admin_finance')
       OR (v_rule.code='finance_due_soon' AND v_unit<>'days') THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    UPDATE public.automation_rules
    SET is_enabled=v_enabled,target_role=v_target,severity=v_severity,
        threshold_value=v_threshold,threshold_unit=v_unit,
        escalation_config=jsonb_build_object(
            'delay_value',v_delay,'delay_unit',v_delay_unit,'severity',v_escalation_severity
        ),
        digest_enabled=v_digest
    WHERE id=v_rule.id
    RETURNING * INTO v_rule;
    INSERT INTO public.audit_log(
        tenant_id,actor_user_id,action,entity_type,entity_id,metadata
    ) VALUES (
        p_tenant_id,(SELECT auth.uid()),'automation_rule_updated','automation_rule',v_rule.id,
        jsonb_build_object(
            'code',v_rule.code,'is_enabled',v_rule.is_enabled,
            'threshold_value',v_rule.threshold_value,'threshold_unit',v_rule.threshold_unit,
            'severity',v_rule.severity,'target_role',v_rule.target_role,
            'digest_enabled',v_rule.digest_enabled
        )
    );
    RETURN to_jsonb(v_rule)-'tenant_id'-'escalation_config'
        ||jsonb_build_object(
            'escalation_delay_value',v_delay,'escalation_delay_unit',v_delay_unit,
            'escalation_severity',v_escalation_severity
        );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_evaluate_automations(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_result jsonb;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    BEGIN
        v_result:=private.f7_materialize_automation_notifications(p_tenant_id,NULL,'manual',now());
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('error','evaluation_failed');
    END;
    INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,metadata)
    VALUES (
        p_tenant_id,(SELECT auth.uid()),'automation_manual_evaluation','automation',
        jsonb_build_object(
            'rules_evaluated',COALESCE((v_result->>'rules_evaluated')::integer,0),
            'candidates',COALESCE((v_result->>'candidates')::integer,0),
            'created',COALESCE((v_result->>'created')::integer,0),
            'updated',COALESCE((v_result->>'updated')::integer,0),
            'resolved',COALESCE((v_result->>'resolved')::integer,0),
            'escalated',COALESCE((v_result->>'escalated')::integer,0)
        )
    );
    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_refresh_internal_notifications(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_user uuid:=(SELECT auth.uid());
BEGIN
    v_role:=private.f5_current_role(p_tenant_id);
    IF v_user IS NULL OR v_role NOT IN ('admin','finance') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    BEGIN
        RETURN private.f7_materialize_automation_notifications(p_tenant_id,v_user,'refresh',now());
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('error','refresh_failed');
    END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications(
    p_tenant_id uuid,
    p_limit integer DEFAULT 50,
    p_unread_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_items jsonb; v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,50),1),100);
BEGIN
    v_role:=private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(n) ORDER BY
        CASE n.priority WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
        n.last_seen_at DESC,n.first_seen_at DESC),'[]'::jsonb)
    INTO v_items
    FROM (
        SELECT id,area AS module,trigger_type AS kind,priority,title,body,route,
               related_entity_type AS entity_type,related_entity_id AS entity_id,
               COALESCE(NULLIF(metadata->>'occurred_at','')::timestamptz,first_seen_at) AS occurred_at,
               due_at,read_at,first_seen_at AS created_at,is_automated,
               automation_rule_code,first_seen_at,last_seen_at,
               escalation_level,escalated_at,metadata
        FROM public.internal_notifications
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid())
          AND status<>'dismissed' AND resolved_at IS NULL
          AND (NOT COALESCE(p_unread_only,false) OR status='unread')
        ORDER BY
            CASE priority WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
            last_seen_at DESC NULLS LAST,first_seen_at DESC
        LIMIT v_limit
    ) n;
    RETURN jsonb_build_object(
        'items',v_items,
        'unread_count',(SELECT count(*) FROM public.internal_notifications
            WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid())
              AND status='unread' AND resolved_at IS NULL)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_internal_notification_unread_count(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF private.f5_current_role(p_tenant_id) NOT IN ('admin','finance') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN jsonb_build_object('count',(SELECT count(*) FROM public.internal_notifications
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid())
          AND status='unread' AND resolved_at IS NULL));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_automation_health(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_last_automation jsonb; v_last_digest jsonb; v_jobs jsonb;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    SELECT to_jsonb(x) INTO v_last_automation FROM (
        SELECT id,run_type,started_at,completed_at,status,rule_count,candidate_count,
               created_count,updated_count,resolved_count,escalated_count,error_code
        FROM public.automation_runs
        WHERE tenant_id=p_tenant_id AND run_type IN ('manual','scheduled')
        ORDER BY started_at DESC LIMIT 1
    ) x;
    SELECT to_jsonb(x) INTO v_last_digest FROM (
        SELECT id,started_at,completed_at,status,candidate_count,updated_count,error_code
        FROM public.automation_runs
        WHERE tenant_id=p_tenant_id AND run_type='digest'
        ORDER BY started_at DESC LIMIT 1
    ) x;
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'jobname',jobname,'schedule',schedule,'active',active
    ) ORDER BY jobname),'[]'::jsonb) INTO v_jobs
    FROM cron.job WHERE jobname IN ('rotero-f7-automation-hourly','rotero-f7-daily-digest');
    RETURN jsonb_build_object(
        'scheduler_contract_status',CASE WHEN jsonb_array_length(v_jobs)=2 THEN 'ready' ELSE 'release_pending' END,
        'scheduler_enabled',jsonb_array_length(v_jobs)=2
            AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname IN ('rotero-f7-automation-hourly','rotero-f7-daily-digest') AND NOT active),
        'jobs',v_jobs,
        'rules_enabled',(SELECT count(*) FROM public.automation_rules WHERE tenant_id=p_tenant_id AND is_enabled),
        'last_automation_run',v_last_automation,'last_digest_run',v_last_digest
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_daily_digest(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_timezone text; v_date date; v_digest jsonb;
BEGIN
    v_role:=private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(NULLIF(s.timezone,''),'America/Mexico_City') INTO v_timezone
    FROM public.tenant_settings s WHERE s.tenant_id=p_tenant_id;
    v_timezone:=COALESCE(v_timezone,'America/Mexico_City');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
        v_timezone:='America/Mexico_City';
    END IF;
    v_date:=(now() AT TIME ZONE v_timezone)::date;
    SELECT to_jsonb(d) INTO v_digest
    FROM (
        SELECT id,business_date,timezone,role,summary,items,generated_at,updated_at
        FROM public.automation_daily_digests
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND business_date=v_date
    ) d;
    RETURN jsonb_build_object('digest',v_digest,'business_date',v_date,'timezone',v_timezone);
END;
$function$;

REVOKE EXECUTE ON FUNCTION private.f7_interval(integer,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f7_target_allows_role(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f7_seed_rules(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f7_operation_dispatch_readiness(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f7_materialize_automation_notifications(uuid,uuid,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f7_generate_tenant_digests(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.run_f7_automations() FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.run_f7_daily_digest() FROM PUBLIC,anon,authenticated,service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_list_automation_rules(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_update_automation_rule(uuid,uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_evaluate_automations(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_automation_health(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_daily_digest(uuid) FROM PUBLIC,anon,service_role;

GRANT EXECUTE ON FUNCTION public.rpc_list_automation_rules(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_automation_rule(uuid,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_evaluate_automations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_automation_health(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_daily_digest(uuid) TO authenticated;

DO $cron$
DECLARE v_job record;
BEGIN
    FOR v_job IN
        SELECT jobid FROM cron.job
        WHERE jobname IN ('rotero-f7-automation-hourly','rotero-f7-daily-digest')
    LOOP
        PERFORM cron.unschedule(v_job.jobid);
    END LOOP;
    PERFORM cron.schedule(
        'rotero-f7-automation-hourly',
        '0 * * * *',
        'SELECT private.run_f7_automations();'
    );
    PERFORM cron.schedule(
        'rotero-f7-daily-digest',
        '15 12 * * *',
        'SELECT private.run_f7_daily_digest();'
    );
END;
$cron$;
