-- Historical free text has no operational classification. Keep counts/rules,
-- but do not echo incident titles or arbitrary document labels in summaries.
BEGIN;
DO $guard$ DECLARE f record;BEGIN SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.oid='private.c03_attention_items(uuid, text)'::regprocedure;IF f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public'] OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>'67d8fa66f3b47ee48d19b56647078c6d' OR has_function_privilege('anon',f.oid,'EXECUTE') OR has_function_privilege('authenticated',f.oid,'EXECUTE') OR has_function_privilege('service_role',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'c03_projection_source_drift';END IF;END $guard$;
CREATE OR REPLACE FUNCTION private.c03_attention_items(p_tenant_id uuid, p_role text)
 RETURNS TABLE(kind text, severity text, title text, subtitle text, reference text, entity_type text, entity_id uuid, module text, route text, occurred_at timestamp with time zone, due_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT 'blocking_incident', 'critical', 'Incidencia bloqueante',
           'Incidencia bloqueante abierta'::text, o.reference_code,
           'operation_incident', i.id, 'operations',
           '/operations?operation_id=' || o.id || '&tab=incidents', i.created_at, NULL::timestamptz
    FROM private.delivery_operation_incidents i
    JOIN private.delivery_operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND i.is_blocking

    UNION ALL
    SELECT 'delivered_without_pod', 'critical', 'Entrega sin POD',
           'La ejecución contratada fue entregada y falta prueba de entrega', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operation_id=' || o.id || '&tab=documents&document=proof_of_delivery',
           COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM private.delivery_operations o
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('delivered','closed')
      AND NOT EXISTS (
          SELECT 1 FROM private.delivery_operation_documents d
          WHERE d.operation_id=o.id AND d.document_type='proof_of_delivery' AND d.status='present'
      )

    UNION ALL
    SELECT 'dispatch_blocker', 'high', 'Despacho bloqueado',
           'Faltan datos o capacidades requeridas para iniciar el despacho', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operation_id=' || o.id || '&tab=overview', COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM private.delivery_operations o
    CROSS JOIN LATERAL public.rpc_get_operation_dispatch_readiness(o.id) readiness
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('planned','assigned')
      AND jsonb_typeof(readiness->'blocking_reasons')='array'
      AND jsonb_array_length(readiness->'blocking_reasons')>0

    UNION ALL
    SELECT 'required_document_missing', 'high', 'Documento requerido faltante',
           'Requisito documental pendiente', o.reference_code,
           'operation_document', d.id, 'documents',
           '/operations?operation_id=' || o.id || '&tab=documents',
           d.updated_at, NULL::timestamptz
    FROM private.delivery_operation_documents d
    JOIN private.delivery_operations o ON o.id=d.operation_id AND o.tenant_id=d.tenant_id
    WHERE d.tenant_id=p_tenant_id AND d.requirement_level='required' AND d.status='missing'

    UNION ALL
    SELECT 'billing_blocked', 'high', 'Facturación operativa bloqueada',
           'La operación entregada conserva bloqueadores de cierre documental u operativo', o.reference_code,
           'operation', o.id, 'operations',
           '/operations?operation_id=' || o.id || '&tab=economics', COALESCE(o.updated_at,o.created_at), NULL::timestamptz
    FROM private.delivery_operations o
    CROSS JOIN LATERAL private.c03_operational_billing(o.id) billing
    WHERE o.tenant_id=p_tenant_id AND o.status IN ('delivered','closed')
      AND COALESCE((billing->>'is_billing_ready')::boolean,false)=false

    UNION ALL
    SELECT CASE WHEN i.direction='ar' THEN 'ar_overdue' ELSE 'ap_overdue' END,
           'critical', CASE WHEN i.direction='ar' THEN 'Cuenta por cobrar vencida' ELSE 'Cuenta por pagar vencida' END,
           i.counterparty_name, COALESCE(i.reference,o.reference_code,'Sin referencia'),
           'finance_invoice', i.id, 'finance',
           '/finance?view=' || i.direction || '&invoiceId=' || i.id,
           i.created_at, i.due_date::timestamptz
    FROM private.delivery_finance_invoices i
    LEFT JOIN private.delivery_operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    CROSS JOIN LATERAL private.c03_invoice_totals(i.id) totals
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND totals.balance_amount>0
      AND i.due_date<current_date

    UNION ALL
    SELECT 'finance_due_soon', 'medium',
           CASE WHEN i.direction='ar' THEN 'Cobro próximo' ELSE 'Pago a proveedor próximo' END,
           i.counterparty_name, COALESCE(i.reference,o.reference_code,'Sin referencia'),
           'finance_invoice', i.id, 'finance',
           '/finance?view=' || i.direction || '&invoiceId=' || i.id,
           i.created_at, i.due_date::timestamptz
    FROM private.delivery_finance_invoices i
    LEFT JOIN private.delivery_operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
    CROSS JOIN LATERAL private.c03_invoice_totals(i.id) totals
    WHERE i.tenant_id=p_tenant_id AND i.status='open' AND totals.balance_amount>0
      AND i.due_date BETWEEN current_date AND current_date+7

    UNION ALL
    SELECT 'quote_in_review', 'medium', 'Cotización en revisión', d.title,
           COALESCE(d.quote_reference,d.title), 'quote', d.id, 'commercial',
           '/commercial?view=quotes&quoteId=' || d.id, d.updated_at, NULL::timestamptz
    FROM private.delivery_crm_deals d
    WHERE p_role='admin' AND d.tenant_id=p_tenant_id AND d.quote_status='in_review'

    UNION ALL
    SELECT 'quote_pending_conversion', 'medium', 'Cotización aprobada pendiente de conversión', d.title,
           COALESCE(d.quote_reference,d.title), 'quote', d.id, 'commercial',
           '/commercial?view=quotes&quoteId=' || d.id, COALESCE(d.approved_at,d.updated_at), NULL::timestamptz
    FROM private.delivery_crm_deals d
    WHERE p_role='admin' AND d.tenant_id=p_tenant_id AND d.quote_status='approved'
      AND d.converted_operation_id IS NULL;
$function$
;

DO $guard$ DECLARE f record;BEGIN SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.oid='private.c03_operational_candidates(uuid, uuid, timestamp with time zone, text)'::regprocedure;IF f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.proconfig IS DISTINCT FROM ARRAY['search_path=""'] OR md5(replace(f.prosrc,E'\r\n',E'\n'))<>'9f123456e258360d4b1b7b2cb38864c6' OR has_function_privilege('anon',f.oid,'EXECUTE') OR has_function_privilege('authenticated',f.oid,'EXECUTE') OR has_function_privilege('service_role',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'c03_projection_source_drift';END IF;END $guard$;
CREATE OR REPLACE FUNCTION private.c03_operational_candidates(p_tenant_id uuid, p_company_id uuid, p_now timestamp with time zone, p_timezone text)
 RETURNS TABLE(rule_id uuid, code text, module text, target_role text, severity text, escalation_config jsonb, entity_type text, entity_id uuid, title text, body text, route text, occurred_at timestamp with time zone, due_at timestamp with time zone, metadata jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
           'operation_incident',i.id,'Incidencia bloqueante',
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
           'La operación '||o.reference_code||' conserva un documento requerido pendiente.',
           '/operations?operation_id='||o.id||'&tab=documents',
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


$function$
;

NOTIFY pgrst, 'reload schema';
COMMIT;
