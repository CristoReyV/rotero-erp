-- F5 — ROTERO Executive Control + Productivity
-- Daily command center backed by canonical F1-F4 sources. No Auth, Edge,
-- Tracking capability or external-service contract is changed here.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.f5_current_role(p_tenant_id uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT m.role
    FROM public.memberships AS m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = (SELECT auth.uid())
    LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION private.f5_module_allowed(p_tenant_id uuid, p_module text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT CASE private.f5_current_role(p_tenant_id)
        WHEN 'admin' THEN p_module IN ('operations','commercial','documents','finance')
        WHEN 'finance' THEN p_module IN ('operations','documents','finance')
        ELSE false
    END;
$function$;

REVOKE EXECUTE ON FUNCTION private.f5_current_role(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION private.f5_module_allowed(uuid,text) FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.internal_notification_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    trigger_type text NOT NULL,
    target_role text NOT NULL,
    area text,
    lead_days integer NOT NULL DEFAULT 0,
    is_enabled boolean NOT NULL DEFAULT true,
    priority text NOT NULL DEFAULT 'medium',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT internal_notification_rules_role_check CHECK (target_role IN ('admin','operator','finance','viewer')),
    CONSTRAINT internal_notification_rules_area_check CHECK (area IS NULL OR area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin')),
    CONSTRAINT internal_notification_rules_trigger_check CHECK (trigger_type IN (
        'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending',
        'blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked',
        'ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion'
    )),
    CONSTRAINT internal_notification_rules_lead_days_check CHECK (lead_days BETWEEN 0 AND 30),
    CONSTRAINT internal_notification_rules_priority_check CHECK (priority IN ('critical','high','medium','low')),
    CONSTRAINT internal_notification_rules_unique UNIQUE NULLS NOT DISTINCT (tenant_id, trigger_type, target_role, area)
);

ALTER TABLE public.internal_notification_rules
    ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'medium';

ALTER TABLE public.internal_notification_rules DROP CONSTRAINT IF EXISTS internal_notification_rules_role_check;
ALTER TABLE public.internal_notification_rules DROP CONSTRAINT IF EXISTS internal_notification_rules_area_check;
ALTER TABLE public.internal_notification_rules DROP CONSTRAINT IF EXISTS internal_notification_rules_trigger_check;
ALTER TABLE public.internal_notification_rules DROP CONSTRAINT IF EXISTS internal_notification_rules_lead_days_check;
ALTER TABLE public.internal_notification_rules DROP CONSTRAINT IF EXISTS internal_notification_rules_priority_check;
ALTER TABLE public.internal_notification_rules
    ADD CONSTRAINT internal_notification_rules_role_check CHECK (target_role IN ('admin','operator','finance','viewer')),
    ADD CONSTRAINT internal_notification_rules_area_check CHECK (area IS NULL OR area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin')),
    ADD CONSTRAINT internal_notification_rules_trigger_check CHECK (trigger_type IN (
        'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending',
        'blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked',
        'ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion'
    )),
    ADD CONSTRAINT internal_notification_rules_lead_days_check CHECK (lead_days BETWEEN 0 AND 30),
    ADD CONSTRAINT internal_notification_rules_priority_check CHECK (priority IN ('critical','high','medium','low'));

CREATE TABLE IF NOT EXISTS public.internal_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    fingerprint text NOT NULL,
    trigger_type text NOT NULL,
    area text NOT NULL,
    priority text NOT NULL,
    icon text NOT NULL DEFAULT 'info',
    title text NOT NULL,
    body text NOT NULL DEFAULT '',
    route text,
    related_entity_type text,
    related_entity_id text,
    status text NOT NULL DEFAULT 'unread',
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    read_at timestamptz,
    dismissed_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT internal_notifications_area_check CHECK (area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin')),
    CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN (
        'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending',
        'blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked',
        'ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion'
    )),
    CONSTRAINT internal_notifications_priority_check CHECK (priority IN ('critical','high','medium','low')),
    CONSTRAINT internal_notifications_icon_check CHECK (icon IN ('info','warning','success','truck')),
    CONSTRAINT internal_notifications_status_check CHECK (status IN ('unread','read','dismissed')),
    CONSTRAINT internal_notifications_user_fingerprint_unique UNIQUE (tenant_id, user_id, fingerprint)
);

ALTER TABLE public.internal_notifications ADD COLUMN IF NOT EXISTS due_at timestamptz;
ALTER TABLE public.internal_notifications DROP CONSTRAINT IF EXISTS internal_notifications_trigger_check;
ALTER TABLE public.internal_notifications
    ADD CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN (
        'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending',
        'blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked',
        'ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion'
    ));

CREATE TABLE IF NOT EXISTS public.user_saved_views (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    module text NOT NULL,
    name text NOT NULL,
    filters jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_saved_views_module_check CHECK (module IN ('operations','commercial','documents','finance')),
    CONSTRAINT user_saved_views_name_check CHECK (char_length(trim(name)) BETWEEN 1 AND 80),
    CONSTRAINT user_saved_views_filters_object_check CHECK (jsonb_typeof(filters) = 'object'),
    CONSTRAINT user_saved_views_sort_object_check CHECK (jsonb_typeof(sort) = 'object')
);

CREATE INDEX IF NOT EXISTS internal_notification_rules_tenant_role_idx
    ON public.internal_notification_rules (tenant_id, target_role, is_enabled);
CREATE INDEX IF NOT EXISTS internal_notifications_user_feed_idx
    ON public.internal_notifications (tenant_id, user_id, status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS internal_notifications_user_unread_idx
    ON public.internal_notifications (tenant_id, user_id, priority, last_seen_at DESC)
    WHERE status = 'unread';
CREATE INDEX IF NOT EXISTS user_saved_views_owner_module_idx
    ON public.user_saved_views (tenant_id, user_id, module, is_default DESC, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS user_saved_views_owner_name_uidx
    ON public.user_saved_views (tenant_id, user_id, module, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS user_saved_views_one_default_uidx
    ON public.user_saved_views (tenant_id, user_id, module) WHERE is_default;

DROP TRIGGER IF EXISTS trg_internal_notification_rules_touch_updated_at ON public.internal_notification_rules;
CREATE TRIGGER trg_internal_notification_rules_touch_updated_at
BEFORE UPDATE ON public.internal_notification_rules
FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

DROP TRIGGER IF EXISTS trg_user_saved_views_touch_updated_at ON public.user_saved_views;
CREATE TRIGGER trg_user_saved_views_touch_updated_at
BEFORE UPDATE ON public.user_saved_views
FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

ALTER TABLE public.internal_notification_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internal_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_saved_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS internal_notification_rules_admin_f5 ON public.internal_notification_rules;
CREATE POLICY internal_notification_rules_admin_f5 ON public.internal_notification_rules
FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id, ARRAY['admin'])));

DROP POLICY IF EXISTS internal_notifications_owner_f5 ON public.internal_notifications;
CREATE POLICY internal_notifications_owner_f5 ON public.internal_notifications
FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()) AND (SELECT public.tanda1_user_is_member(tenant_id)))
WITH CHECK (user_id = (SELECT auth.uid()) AND (SELECT public.tanda1_user_is_member(tenant_id)));

DROP POLICY IF EXISTS user_saved_views_owner_f5 ON public.user_saved_views;
CREATE POLICY user_saved_views_owner_f5 ON public.user_saved_views
FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()) AND (SELECT public.tanda1_user_is_member(tenant_id)))
WITH CHECK (user_id = (SELECT auth.uid()) AND (SELECT public.tanda1_user_is_member(tenant_id)));

REVOKE ALL ON TABLE public.internal_notification_rules, public.internal_notifications, public.user_saved_views
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.f5_attention_items(p_tenant_id uuid, p_role text)
RETURNS TABLE (
    kind text, severity text, title text, subtitle text, reference text,
    entity_type text, entity_id uuid, module text, route text,
    occurred_at timestamptz, due_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT 'blocking_incident', 'critical', i.title,
           COALESCE(NULLIF(i.description,''),'Incidencia bloqueante abierta'), o.reference_code,
           'operation_incident', i.id, 'operations',
           '/operations?operationId=' || o.id || '&tab=incidents', i.created_at, NULL::timestamptz
    FROM public.operation_incidents i
    JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND i.is_blocking

    UNION ALL
    SELECT 'delivered_without_pod', 'critical', 'Entrega sin POD',
           'La ejecución contratada fue entregada y falta prueba de entrega', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operationId=' || o.id || '&tab=documents&document=proof_of_delivery',
           COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM public.operations o
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('delivered','closed')
      AND NOT EXISTS (
          SELECT 1 FROM public.operation_documents d
          WHERE d.operation_id=o.id AND d.document_type='proof_of_delivery' AND d.status='present'
      )

    UNION ALL
    SELECT 'dispatch_blocker', 'high', 'Despacho bloqueado',
           'Faltan datos o capacidades requeridas para iniciar el despacho', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operationId=' || o.id || '&tab=overview', COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM public.operations o
    CROSS JOIN LATERAL public.rpc_get_operation_dispatch_readiness(o.id) readiness
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('planned','assigned')
      AND jsonb_typeof(readiness->'blocking_reasons')='array'
      AND jsonb_array_length(readiness->'blocking_reasons')>0

    UNION ALL
    SELECT 'required_document_missing', 'high', 'Documento requerido faltante',
           replace(d.document_type,'_',' '), o.reference_code,
           'operation_document', d.id, 'documents',
           '/operations?operationId=' || o.id || '&tab=documents&document=' || d.document_type,
           d.updated_at, NULL::timestamptz
    FROM public.operation_documents d
    JOIN public.operations o ON o.id=d.operation_id AND o.tenant_id=d.tenant_id
    WHERE d.tenant_id=p_tenant_id AND d.requirement_level='required' AND d.status='missing'

    UNION ALL
    SELECT 'billing_blocked', 'high', 'Facturación operativa bloqueada',
           'La operación entregada conserva bloqueadores de cierre documental u operativo', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operationId=' || o.id || '&tab=economics', COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM public.operations o
    CROSS JOIN LATERAL public.rpc_get_operation_billing_summary(o.id) billing
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('delivered','closed')
      AND COALESCE((billing->>'is_billing_ready')::boolean,false)=false

    UNION ALL
    SELECT CASE WHEN i.direction='ar' THEN 'ar_overdue' ELSE 'ap_overdue' END,
           'critical', CASE WHEN i.direction='ar' THEN 'Cuenta por cobrar vencida' ELSE 'Cuenta por pagar vencida' END,
           i.counterparty_name, COALESCE(i.reference,o.reference_code,'Sin referencia'),
           'finance_invoice', i.id, 'finance',
           '/finance?view=' || i.direction || '&invoiceId=' || i.id,
           i.created_at, i.due_date::timestamptz
    FROM public.finance_invoices i
    LEFT JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    CROSS JOIN LATERAL private.f4_invoice_totals(i.id) totals
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND totals.balance_amount>0
      AND i.due_date<current_date

    UNION ALL
    SELECT 'finance_due_soon', 'medium',
           CASE WHEN i.direction='ar' THEN 'Cobro próximo' ELSE 'Pago a proveedor próximo' END,
           i.counterparty_name, COALESCE(i.reference,o.reference_code,'Sin referencia'),
           'finance_invoice', i.id, 'finance',
           '/finance?view=' || i.direction || '&invoiceId=' || i.id,
           i.created_at, i.due_date::timestamptz
    FROM public.finance_invoices i
    LEFT JOIN public.operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    CROSS JOIN LATERAL private.f4_invoice_totals(i.id) totals
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND totals.balance_amount>0
      AND i.due_date BETWEEN current_date AND current_date+7

    UNION ALL
    SELECT 'quote_in_review', 'medium', 'Cotización en revisión', d.title,
           COALESCE(d.quote_reference,d.title), 'quote', d.id, 'commercial',
           '/commercial?view=quotes&quoteId=' || d.id, d.updated_at, NULL::timestamptz
    FROM public.crm_deals d
    WHERE p_role='admin' AND d.tenant_id=p_tenant_id AND d.quote_status='in_review'

    UNION ALL
    SELECT 'quote_pending_conversion', 'medium', 'Cotización aprobada pendiente de conversión', d.title,
           COALESCE(d.quote_reference,d.title), 'quote', d.id, 'commercial',
           '/commercial?view=quotes&quoteId=' || d.id, COALESCE(d.approved_at,d.updated_at), NULL::timestamptz
    FROM public.crm_deals d
    WHERE p_role='admin' AND d.tenant_id=p_tenant_id AND d.quote_status='approved'
      AND d.converted_operation_id IS NULL;
$function$;

CREATE OR REPLACE FUNCTION private.f5_recent_activity(
    p_tenant_id uuid, p_role text, p_start_date timestamptz, p_end_date timestamptz
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    WITH normalized AS (
        SELECT a.id, a.entity_id, a.created_at,
               CASE
                   WHEN a.entity_type LIKE 'finance%' OR a.entity_type LIKE 'billing%' THEN 'finance'
                   WHEN a.entity_type LIKE 'operation%' THEN 'operations'
                   WHEN a.entity_type LIKE 'document%' THEN 'documents'
                   WHEN a.entity_type IN ('deal','quote','customer','provider') OR a.entity_type LIKE 'crm%' THEN 'commercial'
                   ELSE 'security'
               END AS module,
               CASE
                   WHEN a.action LIKE '%payment%' THEN 'Pago registrado'
                   WHEN a.action LIKE '%invoice%' THEN 'Cuenta financiera actualizada'
                   WHEN a.action LIKE '%document%' THEN 'Documento actualizado'
                   WHEN a.action LIKE '%incident%' THEN 'Incidencia operativa actualizada'
                   WHEN a.action LIKE '%operation%' THEN 'Operación actualizada'
                   WHEN a.action LIKE '%quote%' OR a.action LIKE '%deal%' THEN 'Actividad comercial actualizada'
                   ELSE 'Actividad registrada'
               END AS title,
               replace(a.action,'_',' ') AS subtitle,
               a.entity_type
        FROM public.audit_log a
        WHERE a.tenant_id=p_tenant_id
          AND (p_start_date IS NULL OR a.created_at>=p_start_date)
          AND (p_end_date IS NULL OR a.created_at<=p_end_date)
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',n.id,'module',n.module,'title',n.title,'subtitle',n.subtitle,
        'entity_type',n.entity_type,'entity_id',n.entity_id,'occurred_at',n.created_at,
        'route',CASE
            WHEN n.module='operations' AND n.entity_id IS NOT NULL THEN '/operations?operationId='||n.entity_id
            WHEN n.module='finance' AND n.entity_type='finance_invoice' AND n.entity_id IS NOT NULL THEN '/finance?invoiceId='||n.entity_id
            WHEN n.module='documents' AND n.entity_id IS NOT NULL THEN '/documents?fileId='||n.entity_id
            WHEN n.module='commercial' AND n.entity_id IS NOT NULL THEN '/commercial?dealId='||n.entity_id
            ELSE '/dashboard'
        END
    ) ORDER BY n.created_at DESC),'[]'::jsonb)
    FROM (SELECT * FROM normalized
          WHERE p_role='admin' OR module IN ('finance','operations','documents')
          ORDER BY created_at DESC LIMIT 25) n;
$function$;

REVOKE EXECUTE ON FUNCTION private.f5_attention_items(uuid,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION private.f5_recent_activity(uuid,text,timestamptz,timestamptz) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_attention_items(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_items jsonb;
BEGIN
    v_role := private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY
        CASE x.severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 ELSE 3 END,
        COALESCE(x.due_at,x.occurred_at),x.reference),'[]'::jsonb)
    INTO v_items FROM private.f5_attention_items(p_tenant_id,v_role) x
    WHERE v_role='admin' OR x.module IN ('finance','operations','documents');
    RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_executive_dashboard(
    p_tenant_id uuid, p_start_date timestamptz DEFAULT NULL, p_end_date timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_role text; v_attention jsonb; v_operations jsonb; v_commercial jsonb;
    v_finance jsonb; v_documents jsonb; v_activity jsonb;
BEGIN
    v_role := private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date>p_end_date THEN
        RETURN jsonb_build_object('error','invalid_date_range');
    END IF;

    SELECT jsonb_build_object(
        'active',count(*) FILTER (WHERE o.status IN ('planned','assigned','in_transit')),
        'in_transit',count(*) FILTER (WHERE o.status='in_transit'),
        'delivered',count(*) FILTER (WHERE o.status='delivered'),
        'closed',count(*) FILTER (WHERE o.status='closed'),
        'blocking_incidents',(SELECT count(*) FROM public.operation_incidents i WHERE i.tenant_id=p_tenant_id AND i.status='open' AND i.is_blocking),
        'dispatch_blockers',(SELECT count(*) FROM private.f5_attention_items(p_tenant_id,v_role) a WHERE a.kind='dispatch_blocker'),
        'billing_ready',(SELECT count(*) FROM public.operations x CROSS JOIN LATERAL public.rpc_get_operation_billing_summary(x.id) b WHERE x.tenant_id=p_tenant_id AND x.status IN ('delivered','closed') AND COALESCE((b->>'is_billing_ready')::boolean,false)),
        'billing_blocked',(SELECT count(*) FROM private.f5_attention_items(p_tenant_id,v_role) a WHERE a.kind='billing_blocked')
    ) INTO v_operations
    FROM public.operations o
    WHERE o.tenant_id=p_tenant_id
      AND (p_start_date IS NULL OR o.created_at>=p_start_date)
      AND (p_end_date IS NULL OR o.created_at<=p_end_date);

    IF v_role='admin' THEN
        SELECT jsonb_build_object(
            'draft',count(*) FILTER (WHERE d.quote_status='draft'),
            'in_review',count(*) FILTER (WHERE d.quote_status='in_review'),
            'approved',count(*) FILTER (WHERE d.quote_status='approved'),
            'pending_conversion',count(*) FILTER (WHERE d.quote_status='approved' AND d.converted_operation_id IS NULL),
            'converted',count(*) FILTER (WHERE d.quote_status='converted'),
            'conversion_rate',CASE WHEN count(*) FILTER (WHERE d.quote_status IN ('approved','converted','rejected'))=0 THEN 0
                ELSE round(100.0*count(*) FILTER (WHERE d.quote_status='converted')/
                    count(*) FILTER (WHERE d.quote_status IN ('approved','converted','rejected')),1) END
        ) INTO v_commercial
        FROM public.crm_deals d
        WHERE d.tenant_id=p_tenant_id
          AND (p_start_date IS NULL OR d.created_at>=p_start_date)
          AND (p_end_date IS NULL OR d.created_at<=p_end_date);
    END IF;

    WITH invoice_balances AS (
        SELECT i.direction,i.status,i.due_date,i.currency,i.exchange_rate,t.balance_amount
        FROM public.finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        WHERE i.tenant_id=p_tenant_id AND i.status<>'void'
    )
    SELECT jsonb_build_object(
        'ar_outstanding',COALESCE(sum(CASE WHEN direction='ar' THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ar_overdue',COALESCE(sum(CASE WHEN direction='ar' AND status='open' AND due_date<current_date THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ap_outstanding',COALESCE(sum(CASE WHEN direction='ap' THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ap_overdue',COALESCE(sum(CASE WHEN direction='ap' AND status='open' AND due_date<current_date THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'due_soon',count(*) FILTER (WHERE status='open' AND balance_amount>0 AND due_date BETWEEN current_date AND current_date+7),
        'collections_month',COALESCE((SELECT sum(COALESCE(p.amount_mxn,p.amount*CASE WHEN p.currency='USD' THEN p.exchange_rate ELSE 1 END)) FROM public.finance_payments p JOIN public.finance_invoices i ON i.id=p.invoice_id WHERE p.tenant_id=p_tenant_id AND i.direction='ar' AND p.paid_at>=date_trunc('month',now())),0),
        'provider_payments_month',COALESCE((SELECT sum(COALESCE(p.amount_mxn,p.amount*CASE WHEN p.currency='USD' THEN p.exchange_rate ELSE 1 END)) FROM public.finance_payments p JOIN public.finance_invoices i ON i.id=p.invoice_id WHERE p.tenant_id=p_tenant_id AND i.direction='ap' AND p.paid_at>=date_trunc('month',now())),0)
    ) INTO v_finance FROM invoice_balances;

    SELECT jsonb_build_object(
        'required_missing',(SELECT count(*) FROM public.operation_documents d WHERE d.tenant_id=p_tenant_id AND d.requirement_level='required' AND d.status='missing'),
        'pod_pending',(SELECT count(*) FROM private.f5_attention_items(p_tenant_id,v_role) a WHERE a.kind='delivered_without_pod')
    ) INTO v_documents;

    v_attention := public.rpc_list_attention_items(p_tenant_id)->'items';
    v_activity := private.f5_recent_activity(p_tenant_id,v_role,p_start_date,p_end_date);

    RETURN jsonb_strip_nulls(jsonb_build_object(
        'role',v_role,'range',jsonb_build_object('start',p_start_date,'end',p_end_date),
        'operations',v_operations,'commercial',v_commercial,'finance',v_finance,
        'documents',v_documents,'attention',v_attention,'recent_activity',v_activity
    ));
END;
$function$;

-- Seed the F5 rule set once for every existing tenant while retaining all Tanda8
-- rules.  The coalesced-area identity mirrors the canonical legacy index.
INSERT INTO public.internal_notification_rules(
    tenant_id,trigger_type,target_role,area,priority,is_enabled
)
SELECT t.id,x.kind,r.target_role,x.module,x.priority,true
FROM public.tenants t
CROSS JOIN (VALUES ('admin'::text),('finance'::text)) r(target_role)
CROSS JOIN (VALUES
    ('operations','blocking_incident','critical'),('operations','delivered_without_pod','critical'),
    ('operations','dispatch_blocker','high'),('documents','required_document_missing','high'),
    ('operations','billing_blocked','high'),('finance','ar_overdue','critical'),
    ('finance','ap_overdue','critical'),('finance','finance_due_soon','medium'),
    ('commercial','quote_in_review','medium'),('commercial','quote_pending_conversion','medium')
) AS x(module,kind,priority)
WHERE (r.target_role='admin' OR x.module<>'commercial')
  AND NOT EXISTS (
      SELECT 1 FROM public.internal_notification_rules current_rule
      WHERE current_rule.tenant_id=t.id
        AND current_rule.trigger_type=x.kind
        AND current_rule.target_role=r.target_role
        AND COALESCE(current_rule.area,'*')=COALESCE(x.module,'*')
  );

CREATE OR REPLACE FUNCTION public.rpc_refresh_internal_notifications(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_user uuid := (SELECT auth.uid()); v_count integer;
BEGIN
    v_role := private.f5_current_role(p_tenant_id);
    IF v_user IS NULL OR v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;

    INSERT INTO public.internal_notification_rules(tenant_id,target_role,area,trigger_type,priority,is_enabled)
    SELECT p_tenant_id,v_role,x.module,x.kind,x.priority,true
    FROM (VALUES
        ('operations','blocking_incident','critical'),('operations','delivered_without_pod','critical'),
        ('operations','dispatch_blocker','high'),('documents','required_document_missing','high'),
        ('operations','billing_blocked','high'),('finance','ar_overdue','critical'),
        ('finance','ap_overdue','critical'),('finance','finance_due_soon','medium'),
        ('commercial','quote_in_review','medium'),('commercial','quote_pending_conversion','medium')
    ) AS x(module,kind,priority)
    WHERE (v_role='admin' OR x.module<>'commercial')
      AND NOT EXISTS (
          SELECT 1 FROM public.internal_notification_rules current_rule
          WHERE current_rule.tenant_id=p_tenant_id
            AND current_rule.trigger_type=x.kind
            AND current_rule.target_role=v_role
            AND COALESCE(current_rule.area,'*')=COALESCE(x.module,'*')
      );

    DELETE FROM public.internal_notifications n
    WHERE n.tenant_id=p_tenant_id AND n.user_id=v_user
      AND n.dismissed_at IS NULL AND n.fingerprint LIKE 'f5:%'
      AND NOT EXISTS (
          SELECT 1 FROM private.f5_attention_items(p_tenant_id,v_role) a
          JOIN public.internal_notification_rules r ON r.tenant_id=p_tenant_id AND r.target_role=v_role
              AND r.area=a.module AND r.trigger_type=a.kind AND r.is_enabled
          WHERE (v_role='admin' OR a.module IN ('operations','documents','finance'))
            AND n.fingerprint='f5:'||a.kind||':'||a.entity_type||':'||a.entity_id||':'||COALESCE(a.due_at::date::text,'current')
      );

    INSERT INTO public.internal_notifications(
        tenant_id,user_id,fingerprint,area,trigger_type,priority,icon,title,body,route,
        related_entity_type,related_entity_id,status,first_seen_at,last_seen_at,due_at,metadata
    )
    SELECT p_tenant_id,v_user,
           'f5:'||a.kind||':'||a.entity_type||':'||a.entity_id||':'||COALESCE(a.due_at::date::text,'current'),
           a.module,a.kind,r.priority,
           CASE WHEN r.priority IN ('critical','high') THEN 'warning' ELSE 'info' END,
           a.title,a.subtitle,a.route,a.entity_type,a.entity_id::text,'unread',a.occurred_at,now(),a.due_at,
           jsonb_build_object('occurred_at',a.occurred_at)
    FROM private.f5_attention_items(p_tenant_id,v_role) a
    JOIN public.internal_notification_rules r ON r.tenant_id=p_tenant_id AND r.target_role=v_role
        AND r.area=a.module AND r.trigger_type=a.kind AND r.is_enabled
    WHERE v_role='admin' OR a.module IN ('operations','documents','finance')
    ON CONFLICT (tenant_id,user_id,fingerprint) DO UPDATE SET
        area=EXCLUDED.area,trigger_type=EXCLUDED.trigger_type,priority=EXCLUDED.priority,
        icon=EXCLUDED.icon,title=EXCLUDED.title,body=EXCLUDED.body,route=EXCLUDED.route,
        related_entity_type=EXCLUDED.related_entity_type,related_entity_id=EXCLUDED.related_entity_id,
        last_seen_at=EXCLUDED.last_seen_at,due_at=EXCLUDED.due_at,metadata=EXCLUDED.metadata;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN jsonb_build_object('success',true,'refreshed',v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications(
    p_tenant_id uuid, p_limit integer DEFAULT 50, p_unread_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_items jsonb; v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,50),1),100);
BEGIN
    v_role := private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(n) ORDER BY n.created_at DESC),'[]'::jsonb) INTO v_items
    FROM (SELECT id,area AS module,trigger_type AS kind,priority,title,body,route,
                 related_entity_type AS entity_type,related_entity_id AS entity_id,
                 COALESCE(NULLIF(metadata->>'occurred_at','')::timestamptz,first_seen_at) AS occurred_at,
                 due_at,read_at,first_seen_at AS created_at
          FROM public.internal_notifications
          WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND status<>'dismissed'
            AND (NOT COALESCE(p_unread_only,false) OR status='unread')
          ORDER BY first_seen_at DESC LIMIT v_limit) n;
    RETURN jsonb_build_object('items',v_items,'unread_count',(
        SELECT count(*) FROM public.internal_notifications
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND status='unread'
    ));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_internal_notification_unread_count(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF private.f5_current_role(p_tenant_id) NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object('count',(SELECT count(*) FROM public.internal_notifications
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND status='unread'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_mark_internal_notifications_read(p_tenant_id uuid, p_ids uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_count integer;
BEGIN
    IF private.f5_current_role(p_tenant_id) NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.internal_notifications SET status='read',read_at=COALESCE(read_at,now())
    WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND status<>'dismissed'
      AND (p_ids IS NULL OR id=ANY(p_ids));
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN jsonb_build_object('success',true,'updated',v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_internal_notification(p_tenant_id uuid, p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_count integer;
BEGIN
    IF private.f5_current_role(p_tenant_id) NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.internal_notifications SET status='dismissed',dismissed_at=COALESCE(dismissed_at,now())
    WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND id=p_notification_id;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count=0 THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('success',true);
END;
$function$;

-- Preserve the canonical Tanda8 one-argument signature for existing consumers.
CREATE OR REPLACE FUNCTION public.rpc_dismiss_internal_notification(p_notification_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_count integer;
BEGIN
    UPDATE public.internal_notifications
    SET status='dismissed',dismissed_at=COALESCE(dismissed_at,now())
    WHERE id=p_notification_id AND user_id=(SELECT auth.uid());
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count=0 THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_global_search(p_tenant_id uuid, p_query text, p_limit integer DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_role text; v_query text:=lower(trim(COALESCE(p_query,''))); v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,5),1),10); v_items jsonb;
BEGIN
    v_role:=private.f5_current_role(p_tenant_id);
    IF v_role NOT IN ('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF char_length(v_query)<2 THEN RETURN jsonb_build_object('items','[]'::jsonb,'query_too_short',true); END IF;

    WITH candidates AS (
        SELECT 'operation'::text type,o.id,o.reference_code primary_label,
               concat_ws(' · ',NULLIF(o.client_display_name,''),NULLIF(o.destination_city,'')) secondary_label,
               o.status,'operations'::text module,'/operations?operationId='||o.id||'&tab=overview' route,
               CASE WHEN lower(o.reference_code)=v_query THEN 1.0 ELSE 0.85 END::numeric rank
        FROM public.operations o WHERE o.tenant_id=p_tenant_id
          AND position(v_query IN lower(concat_ws(' ',o.reference_code,o.client_display_name,o.destination_city,o.route_summary)))>0
        UNION ALL
        SELECT 'customer',c.id,c.display_name,concat_ws(' · ',c.legal_name,c.tax_id),CASE WHEN c.is_active THEN 'active' ELSE 'inactive' END,
               'commercial','/commercial?view=clients&customerId='||c.id,0.75
        FROM public.customers c WHERE v_role='admin' AND c.tenant_id=p_tenant_id
          AND position(v_query IN lower(concat_ws(' ',c.display_name,c.legal_name,c.tax_id)))>0
        UNION ALL
        SELECT 'provider',p.id,p.display_name,concat_ws(' · ',p.legal_name,p.tax_id),CASE WHEN p.is_active THEN 'active' ELSE 'inactive' END,
               'commercial','/commercial?view=providers&providerId='||p.id,0.75
        FROM public.logistics_providers p WHERE v_role='admin' AND p.tenant_id=p_tenant_id
          AND position(v_query IN lower(concat_ws(' ',p.display_name,p.legal_name,p.tax_id)))>0
        UNION ALL
        SELECT 'quote',d.id,COALESCE(d.quote_reference,d.title),d.title,d.quote_status,'commercial',
               '/commercial?view=quotes&quoteId='||d.id,0.8
        FROM public.crm_deals d WHERE v_role='admin' AND d.tenant_id=p_tenant_id AND d.quote_reference IS NOT NULL
          AND position(v_query IN lower(concat_ws(' ',d.quote_reference,d.title,d.company)))>0
        UNION ALL
        SELECT 'document',df.id,df.file_name,private.f3_entity_reference(df.tenant_id,df.source_entity_type,df.source_entity_id),
               df.status,'documents','/documents?fileId='||df.id||'&view='||CASE WHEN df.source_module='operations' THEN 'operations' WHEN df.source_module='commercial' THEN 'commercial' WHEN df.source_module IN ('finance','billing') THEN 'billing' ELSE 'all' END,0.7
        FROM public.document_files df WHERE df.tenant_id=p_tenant_id
          AND private.f3_user_can_access_module(df.tenant_id,df.source_module,false)
          AND position(v_query IN lower(concat_ws(' ',df.file_name,df.notes,private.f3_entity_reference(df.tenant_id,df.source_entity_type,df.source_entity_id))))>0
        UNION ALL
        SELECT 'finance_invoice',i.id,COALESCE(i.reference,o.reference_code,i.counterparty_name),
               concat_ws(' · ',i.counterparty_name,o.reference_code),CASE WHEN i.status='open' AND i.due_date<current_date THEN 'overdue' ELSE i.status END,
               'finance','/finance?view='||i.direction||'&invoiceId='||i.id,0.8
        FROM public.finance_invoices i LEFT JOIN public.operations o ON o.id=i.operation_id
        WHERE i.tenant_id=p_tenant_id AND position(v_query IN lower(concat_ws(' ',i.reference,i.counterparty_name,o.reference_code)))>0
    ), grouped AS (
        SELECT c.*,row_number() OVER(PARTITION BY c.type ORDER BY c.rank DESC,c.primary_label) rn FROM candidates c
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type,'id',id,'primary_label',primary_label,
        'secondary_label',secondary_label,'status',status,'module',module,'route',route,'rank',rank)
        ORDER BY rank DESC,primary_label),'[]'::jsonb) INTO v_items
    FROM grouped WHERE rn<=v_limit;
    RETURN jsonb_build_object('items',v_items);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_saved_views(p_tenant_id uuid, p_module text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb;
BEGIN
    IF NOT private.f5_module_allowed(p_tenant_id,p_module) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.is_default DESC,v.name),'[]'::jsonb) INTO v_items
    FROM (SELECT id,module,name,filters,sort,is_default,created_at,updated_at FROM public.user_saved_views
          WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND module=p_module) v;
    RETURN jsonb_build_object('items',v_items);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_save_view(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid; v_module text:=lower(trim(COALESCE(p_payload->>'module',''))); v_name text:=trim(COALESCE(p_payload->>'name',''));
    v_filters jsonb:=COALESCE(p_payload->'filters','{}'::jsonb); v_sort jsonb:=COALESCE(p_payload->'sort','{}'::jsonb); v_default boolean:=COALESCE((p_payload->>'is_default')::boolean,false); v_result jsonb;
BEGIN
    BEGIN v_id:=NULLIF(p_payload->>'id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_id'); END;
    IF NOT private.f5_module_allowed(p_tenant_id,v_module) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF char_length(v_name) NOT BETWEEN 1 AND 80 OR jsonb_typeof(v_filters)<>'object' OR jsonb_typeof(v_sort)<>'object' THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    IF v_default THEN UPDATE public.user_saved_views SET is_default=false WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND module=v_module AND (v_id IS NULL OR id<>v_id); END IF;
    IF v_id IS NULL THEN
        INSERT INTO public.user_saved_views(tenant_id,user_id,module,name,filters,sort,is_default)
        VALUES(p_tenant_id,(SELECT auth.uid()),v_module,v_name,v_filters,v_sort,v_default) RETURNING id INTO v_id;
    ELSE
        UPDATE public.user_saved_views SET name=v_name,filters=v_filters,sort=v_sort,is_default=v_default
        WHERE id=v_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND module=v_module;
        IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    END IF;
    SELECT to_jsonb(v) INTO v_result FROM (SELECT id,module,name,filters,sort,is_default,created_at,updated_at FROM public.user_saved_views WHERE id=v_id) v;
    RETURN v_result;
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','view_name_conflict');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_delete_saved_view(p_tenant_id uuid, p_view_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_module text; v_count integer;
BEGIN
    SELECT module INTO v_module FROM public.user_saved_views WHERE id=p_view_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid());
    IF v_module IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT private.f5_module_allowed(p_tenant_id,v_module) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    DELETE FROM public.user_saved_views WHERE id=p_view_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid());
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN jsonb_build_object('success',v_count=1);
END;
$function$;

-- F5 normal ERP RPC ACL: authenticated only, explicit safe search path above.
REVOKE EXECUTE ON FUNCTION public.rpc_list_attention_items(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_refresh_internal_notifications(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid,integer,boolean) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_internal_notification_unread_count(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_mark_internal_notifications_read(uuid,uuid[]) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid,uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_global_search(uuid,text,integer) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_saved_views(uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_save_view(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_delete_saved_view(uuid,uuid) FROM PUBLIC,anon,service_role;

GRANT EXECUTE ON FUNCTION public.rpc_list_attention_items(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid,timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_refresh_internal_notifications(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid,integer,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_internal_notification_unread_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_internal_notifications_read(uuid,uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_global_search(uuid,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_saved_views(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_save_view(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_delete_saved_view(uuid,uuid) TO authenticated;
