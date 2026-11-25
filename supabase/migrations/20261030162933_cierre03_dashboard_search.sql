BEGIN;
DO $$DECLARE r record;f record;BEGIN FOR r IN SELECT * FROM(VALUES ('f4_invoice_totals','ed45387f5a6d43605e67b6b6e6851eea'),('f5_attention_items','65ce5d8ae42a0dd1c8d0981632d42278'),('delivery_core_d7007371b8152ebb1640','bd60a21518d3dc4a3ef5e10cdb85d019'))v(name,body_md5) LOOP SELECT p.* INTO STRICT f FROM pg_proc p WHERE p.pronamespace='private'::regnamespace AND p.proname=r.name;IF md5(replace(f.prosrc,E'\r\n',E'\n'))<>r.body_md5 OR f.proowner<>'postgres'::regrole OR NOT f.prosecdef OR f.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public'] THEN RAISE EXCEPTION 'c03_dashboard_source_drift: %',r.name;END IF;END LOOP;END $$;
CREATE FUNCTION private.c03_operational_billing(op uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE t uuid;r jsonb;
BEGIN
 SELECT tenant_id INTO t FROM public.operations WHERE id=op;
 IF NOT private.delivery_cap(t,'operations.read') OR NOT private.delivery_entity_allowed(t,'operation',op)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 r:=private.delivery_scoped_2eb544e85b693f1cdd0f(op);
 RETURN private.delivery_pick_dto(r,ARRAY['has_billing_record','is_billing_ready','billing_blockers','is_billed','can_admin_close','pod_present','documentation_complete']);
END $$;
REVOKE ALL ON FUNCTION private.c03_operational_billing(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.c03_audit_allowed(t uuid,k text,entity uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE op uuid;
BEGIN
 IF NOT private.delivery_scope_allowed(t) THEN RETURN false;END IF;
 IF k='operation' THEN op:=entity;
 ELSIF k='operation_incident' THEN SELECT operation_id INTO op FROM public.operation_incidents WHERE id=entity AND tenant_id=t;
 ELSIF k='operation_document' THEN SELECT operation_id INTO op FROM public.operation_documents WHERE id=entity AND tenant_id=t;
 ELSIF k='operation_evidence' THEN SELECT operation_id INTO op FROM public.operation_evidence WHERE id=entity AND tenant_id=t;
 ELSIF k='operation_crossing' THEN SELECT operation_id INTO op FROM private.c03_child_facts WHERE entity_kind='crossing' AND entity_id=entity AND tenant_id=t ORDER BY fact_sequence DESC LIMIT 1;
 ELSIF k='document_file' THEN RETURN private.delivery_file_allowed(entity);
 ELSIF k='finance_invoice' THEN RETURN private.delivery_cap(t,'financial.full.read') AND private.delivery_entity_allowed(t,'invoice',entity);
 ELSE RETURN false;END IF;
 RETURN op IS NOT NULL AND private.delivery_cap(t,'operations.read') AND private.delivery_entity_allowed(t,'operation',op);
END $$;
REVOKE ALL ON FUNCTION private.c03_audit_allowed(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.c03_recent_activity(p_tenant_id uuid,p_role text,p_start_date timestamptz,p_end_date timestamptz) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'entity_type',a.entity_type,'entity_id',a.entity_id,'occurred_at',a.created_at,
  'module',CASE WHEN a.entity_type='finance_invoice' THEN 'finance' WHEN a.entity_type='document_file' THEN 'documents' ELSE 'operations' END,
  'title',CASE WHEN a.entity_type='finance_invoice' THEN 'Cuenta financiera actualizada' WHEN a.entity_type='document_file' THEN 'Documento actualizado' ELSE 'Actividad operativa actualizada' END,
  'route',CASE WHEN a.entity_type='operation' THEN '/operations?operation_id='||a.entity_id ELSE '/dashboard' END)
  ORDER BY a.created_at DESC,a.id DESC),'[]')
 FROM(SELECT id,entity_type,entity_id,created_at FROM public.audit_log
 WHERE tenant_id=p_tenant_id AND (p_start_date IS NULL OR created_at>=p_start_date) AND (p_end_date IS NULL OR created_at<=p_end_date)
 AND private.c03_audit_allowed(tenant_id,entity_type,entity_id) ORDER BY created_at DESC,id DESC LIMIT 25)a;
$$;
REVOKE ALL ON FUNCTION private.c03_recent_activity(uuid,text,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.c03_invoice_totals(p_invoice_id uuid)
 RETURNS TABLE(paid_amount numeric, credit_amount numeric, balance_amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT
        COALESCE((SELECT sum(p.amount) FROM private.delivery_finance_payments p WHERE p.invoice_id = i.id), 0)::numeric,
        COALESCE((SELECT sum(c.total) FROM private.delivery_billing_credit_notes c WHERE c.finance_invoice_id = i.id AND c.status = 'applied'), 0)::numeric,
        GREATEST(i.amount
            - COALESCE((SELECT sum(p.amount) FROM private.delivery_finance_payments p WHERE p.invoice_id = i.id), 0)
            - COALESCE((SELECT sum(c.total) FROM private.delivery_billing_credit_notes c WHERE c.finance_invoice_id = i.id AND c.status = 'applied'), 0), 0)::numeric
    FROM private.delivery_finance_invoices i
    WHERE i.id = p_invoice_id;
$function$
;
REVOKE ALL ON FUNCTION private.c03_invoice_totals(p_invoice_id uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.c03_attention_items(p_tenant_id uuid, p_role text)
 RETURNS TABLE(kind text, severity text, title text, subtitle text, reference text, entity_type text, entity_id uuid, module text, route text, occurred_at timestamp with time zone, due_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
    SELECT 'blocking_incident', 'critical', i.title,
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
           replace(d.document_type,'_',' '), o.reference_code,
           'operation_document', d.id, 'documents',
           '/operations?operation_id=' || o.id || '&tab=documents&document=' || d.document_type,
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
REVOKE ALL ON FUNCTION private.c03_attention_items(p_tenant_id uuid, p_role text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.c03_dashboard_core(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_role text; v_attention jsonb; v_operations jsonb; v_commercial jsonb;
    v_finance jsonb; v_documents jsonb; v_activity jsonb;
BEGIN
    v_role := private.f5_current_role(p_tenant_id);
    IF NOT private.delivery_cap(p_tenant_id,'operations.read') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date>p_end_date THEN
        RETURN jsonb_build_object('error','invalid_date_range');
    END IF;

    SELECT jsonb_build_object(
        'total',count(*),
        'active',count(*) FILTER (WHERE o.status IN ('planned','assigned','in_transit')),
        'in_transit',count(*) FILTER (WHERE o.status='in_transit'),
        'delivered',count(*) FILTER (WHERE o.status='delivered'),
        'closed',count(*) FILTER (WHERE o.status='closed'),
        'blocking_incidents',(SELECT count(*) FROM private.delivery_operation_incidents i WHERE i.tenant_id=p_tenant_id AND i.status='open' AND i.is_blocking),
        'dispatch_blockers',(SELECT count(*) FROM private.c03_attention_items(p_tenant_id,v_role) a WHERE a.kind='dispatch_blocker'),
        'billing_ready',(SELECT count(*) FROM private.delivery_operations x CROSS JOIN LATERAL private.c03_operational_billing(x.id) b WHERE x.tenant_id=p_tenant_id AND x.status IN ('delivered','closed') AND COALESCE((b->>'is_billing_ready')::boolean,false)),
        'billing_blocked',(SELECT count(*) FROM private.c03_attention_items(p_tenant_id,v_role) a WHERE a.kind='billing_blocked')
    ) INTO v_operations
    FROM private.delivery_operations o
    WHERE o.tenant_id=p_tenant_id
      AND (p_start_date IS NULL OR o.created_at>=p_start_date)
      AND (p_end_date IS NULL OR o.created_at<=p_end_date);

    IF v_role='admin' AND private.delivery_cap(p_tenant_id,'pipeline.read') THEN
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
        FROM private.delivery_crm_deals d
        WHERE d.tenant_id=p_tenant_id
          AND (p_start_date IS NULL OR d.created_at>=p_start_date)
          AND (p_end_date IS NULL OR d.created_at<=p_end_date);
    END IF;

    IF private.delivery_cap(p_tenant_id,'financial.full.read') AND v_role IN('admin','finance') THEN
    WITH invoice_balances AS (
        SELECT i.direction,i.status,i.due_date,i.currency,i.exchange_rate,t.balance_amount
        FROM private.delivery_finance_invoices i
        CROSS JOIN LATERAL private.c03_invoice_totals(i.id) t
        WHERE i.tenant_id=p_tenant_id AND i.status<>'void'
    )
    SELECT jsonb_build_object(
        'ar_outstanding',COALESCE(sum(CASE WHEN direction='ar' THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ar_overdue',COALESCE(sum(CASE WHEN direction='ar' AND status='open' AND due_date<current_date THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ap_outstanding',COALESCE(sum(CASE WHEN direction='ap' THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'ap_overdue',COALESCE(sum(CASE WHEN direction='ap' AND status='open' AND due_date<current_date THEN balance_amount*CASE WHEN currency='USD' THEN exchange_rate ELSE 1 END ELSE 0 END),0),
        'due_soon',count(*) FILTER (WHERE status='open' AND balance_amount>0 AND due_date BETWEEN current_date AND current_date+7),
        'collections_month',COALESCE((SELECT sum(COALESCE(p.amount_mxn,p.amount*CASE WHEN p.currency='USD' THEN p.exchange_rate ELSE 1 END)) FROM private.delivery_finance_payments p JOIN private.delivery_finance_invoices i ON i.id=p.invoice_id WHERE p.tenant_id=p_tenant_id AND i.direction='ar' AND p.paid_at>=date_trunc('month',now())),0),
        'provider_payments_month',COALESCE((SELECT sum(COALESCE(p.amount_mxn,p.amount*CASE WHEN p.currency='USD' THEN p.exchange_rate ELSE 1 END)) FROM private.delivery_finance_payments p JOIN private.delivery_finance_invoices i ON i.id=p.invoice_id WHERE p.tenant_id=p_tenant_id AND i.direction='ap' AND p.paid_at>=date_trunc('month',now())),0)
    ) INTO v_finance FROM invoice_balances;
    END IF;

    SELECT jsonb_build_object(
        'required_missing',(SELECT count(*) FROM private.delivery_operation_documents d WHERE d.tenant_id=p_tenant_id AND d.requirement_level='required' AND d.status='missing'),
        'pod_pending',(SELECT count(*) FROM private.c03_attention_items(p_tenant_id,v_role) a WHERE a.kind='delivered_without_pod')
    ) INTO v_documents;

    SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.occurred_at DESC),'[]') INTO v_attention FROM private.c03_attention_items(p_tenant_id,v_role)a;
    v_activity := private.c03_recent_activity(p_tenant_id,v_role,p_start_date,p_end_date);

    RETURN jsonb_strip_nulls(jsonb_build_object(
        'role',v_role,'range',jsonb_build_object('start',p_start_date,'end',p_end_date),
        'operations',v_operations,'commercial',v_commercial,'finance',v_finance,
        'documents',v_documents,'attention',v_attention,'recent_activity',v_activity
    ));
END;
$function$
;
REVOKE ALL ON FUNCTION private.c03_dashboard_core(p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.rpc_delivery_dashboard(p_tenant_id uuid,p_start_date timestamptz DEFAULT NULL,p_end_date timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE r jsonb;
BEGIN
 IF NOT private.delivery_required(p_tenant_id) OR NOT private.delivery_cap(p_tenant_id,'operations.read') THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 r:=private.c03_dashboard_core(p_tenant_id,p_start_date,p_end_date);
 IF r ? 'error' THEN RETURN r;END IF;
 RETURN r||jsonb_build_object('financial_available',private.delivery_cap(p_tenant_id,'financial.full.read') AND public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']),
  'commercial_available',private.delivery_cap(p_tenant_id,'pipeline.read') AND public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']),
  'classification_notice','resolved authorized entities only; historical unclassified audit and fiscal laboratory excluded');
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_dashboard(uuid,timestamptz,timestamptz) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_dashboard(uuid,timestamptz,timestamptz) TO authenticated;
CREATE OR REPLACE FUNCTION public.rpc_delivery_search(p_tenant_id uuid,p_query text,p_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_scope_allowed(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_query IS NULL OR length(p_query)>160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RETURN jsonb_build_object('error','invalid_filters');END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(q)-'sort_order' ORDER BY sort_order,id) FROM(
  SELECT 'operation'::text type,o.id,o.reference_code primary_label,o.route_summary secondary_label,o.status,'operations'::text module,
   '/operations?operation_id='||o.id::text route,1 sort_order,1 rank
  FROM private.delivery_operations o WHERE o.tenant_id=p_tenant_id AND private.delivery_cap(p_tenant_id,'operations.read')
   AND position(lower(p_query) IN lower(concat_ws(' ',o.reference_code,o.route_summary,o.client_display_name)))>0
  UNION ALL SELECT 'finance_invoice',i.id,i.reference,i.counterparty_name,i.status,'finance','/finance?invoiceId='||i.id,2,1
  FROM private.delivery_finance_invoices i WHERE i.tenant_id=p_tenant_id AND private.delivery_cap(p_tenant_id,'financial.full.read')
   AND position(lower(p_query) IN lower(concat_ws(' ',i.reference,i.counterparty_name)))>0
  UNION ALL SELECT 'document',f.id,f.file_name,f.mime_type,f.status,'documents','/documents?fileId='||f.id,3,1
  FROM public.document_files f WHERE f.tenant_id=p_tenant_id AND private.delivery_file_allowed(f.id)
   AND position(lower(p_query) IN lower(f.file_name))>0
  UNION ALL SELECT 'quote',d.id,d.quote_reference,d.title,d.quote_status,'commercial','/commercial?quoteId='||d.id,4,1
  FROM private.delivery_crm_deals d WHERE d.tenant_id=p_tenant_id AND private.delivery_cap(p_tenant_id,'pipeline.read')
   AND position(lower(p_query) IN lower(concat_ws(' ',d.quote_reference,d.title)))>0
  ORDER BY sort_order,id LIMIT p_limit)q),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_search(uuid,text,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_search(uuid,text,integer) TO authenticated;
CREATE FUNCTION public.rpc_delivery_operational_billing(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN private.c03_operational_billing(p_operation_id);
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_operational_billing(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_operational_billing(uuid,uuid) TO authenticated;
COMMIT;
