-- F9 — ROTERO Contracts, Compliance & Renewals 360
-- Configurable ROTERO business controls. A stored document is evidence only;
-- this module does not assert legal or regulatory compliance.

CREATE TABLE public.partner_compliance_requirements (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    partner_type text NOT NULL,
    category text NOT NULL,
    is_required boolean NOT NULL DEFAULT false,
    has_expiration boolean NOT NULL DEFAULT false,
    warning_days integer NOT NULL DEFAULT 30,
    is_blocking boolean NOT NULL DEFAULT false,
    blocks_operation_assignment boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT partner_compliance_requirements_tenant_code_key UNIQUE (tenant_id, code),
    CONSTRAINT partner_compliance_requirements_code_check CHECK (code ~ '^[a-z][a-z0-9_]{1,63}$'),
    CONSTRAINT partner_compliance_requirements_partner_type_check CHECK (partner_type IN ('customer','provider','both')),
    CONSTRAINT partner_compliance_requirements_category_check CHECK (category IN ('tax','contract','insurance','operational','banking','identity','other')),
    CONSTRAINT partner_compliance_requirements_warning_check CHECK (warning_days BETWEEN 0 AND 3650),
    CONSTRAINT partner_compliance_requirements_assignment_check CHECK (NOT blocks_operation_assignment OR (partner_type IN ('provider','both') AND is_required AND is_blocking))
);

CREATE TABLE public.partner_compliance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    requirement_id uuid NOT NULL REFERENCES public.partner_compliance_requirements(id),
    customer_id uuid REFERENCES public.customers(id),
    provider_id uuid REFERENCES public.logistics_providers(id),
    document_file_id uuid REFERENCES public.document_files(id),
    responsible_contact_id uuid REFERENCES public.business_contacts(id) ON DELETE SET NULL,
    review_status text NOT NULL DEFAULT 'pending',
    valid_from date,
    valid_to date,
    reviewed_at timestamptz,
    reviewed_by uuid,
    review_note text,
    waiver_until date,
    waiver_reason text,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT partner_compliance_records_partner_check CHECK ((customer_id IS NOT NULL)::integer + (provider_id IS NOT NULL)::integer = 1),
    CONSTRAINT partner_compliance_records_review_check CHECK (review_status IN ('pending','accepted','rejected','waived')),
    CONSTRAINT partner_compliance_records_dates_check CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT partner_compliance_records_waiver_check CHECK (
        (review_status = 'waived' AND waiver_until IS NOT NULL AND NULLIF(btrim(waiver_reason),'') IS NOT NULL AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)
        OR (review_status <> 'waived' AND waiver_until IS NULL AND waiver_reason IS NULL)
    ),
    CONSTRAINT partner_compliance_records_review_actor_check CHECK (
        (review_status = 'pending' AND reviewed_at IS NULL AND reviewed_by IS NULL)
        OR (review_status <> 'pending' AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)
    )
);

CREATE TABLE public.partner_contracts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id),
    provider_id uuid REFERENCES public.logistics_providers(id),
    contract_type text NOT NULL,
    title text NOT NULL,
    reference text,
    document_file_id uuid REFERENCES public.document_files(id),
    responsible_contact_id uuid REFERENCES public.business_contacts(id) ON DELETE SET NULL,
    starts_on date,
    ends_on date,
    notice_days integer NOT NULL DEFAULT 30,
    status text NOT NULL DEFAULT 'draft',
    notes text,
    renewed_from_id uuid REFERENCES public.partner_contracts(id) ON DELETE SET NULL,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT partner_contracts_partner_check CHECK ((customer_id IS NOT NULL)::integer + (provider_id IS NOT NULL)::integer = 1),
    CONSTRAINT partner_contracts_status_check CHECK (status IN ('draft','active','terminated','archived')),
    CONSTRAINT partner_contracts_dates_check CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on),
    CONSTRAINT partner_contracts_notice_check CHECK (notice_days BETWEEN 0 AND 3650)
);

CREATE TABLE public.provider_compliance_overrides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    provider_id uuid NOT NULL REFERENCES public.logistics_providers(id),
    reason text NOT NULL,
    blocker_snapshot jsonb NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT provider_compliance_overrides_reason_check CHECK (char_length(btrim(reason)) BETWEEN 5 AND 1000),
    CONSTRAINT provider_compliance_overrides_snapshot_check CHECK (jsonb_typeof(blocker_snapshot) = 'object'),
    CONSTRAINT provider_compliance_overrides_operation_provider_key UNIQUE (operation_id, provider_id)
);

CREATE INDEX partner_compliance_requirements_scope_idx ON public.partner_compliance_requirements (tenant_id, partner_type, is_active, sort_order);
CREATE INDEX partner_compliance_records_customer_idx ON public.partner_compliance_records (tenant_id, customer_id, requirement_id, created_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX partner_compliance_records_provider_idx ON public.partner_compliance_records (tenant_id, provider_id, requirement_id, created_at DESC) WHERE provider_id IS NOT NULL;
CREATE INDEX partner_compliance_records_expiry_idx ON public.partner_compliance_records (tenant_id, valid_to) WHERE valid_to IS NOT NULL;
CREATE INDEX partner_contracts_customer_idx ON public.partner_contracts (tenant_id, customer_id, status, ends_on) WHERE customer_id IS NOT NULL;
CREATE INDEX partner_contracts_provider_idx ON public.partner_contracts (tenant_id, provider_id, status, ends_on) WHERE provider_id IS NOT NULL;
CREATE INDEX provider_compliance_overrides_lookup_idx ON public.provider_compliance_overrides (tenant_id, operation_id, provider_id);

CREATE TRIGGER trg_partner_compliance_requirements_touch BEFORE UPDATE ON public.partner_compliance_requirements FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
CREATE TRIGGER trg_partner_compliance_records_touch BEFORE UPDATE ON public.partner_compliance_records FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
CREATE TRIGGER trg_partner_contracts_touch BEFORE UPDATE ON public.partner_contracts FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

ALTER TABLE public.partner_compliance_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_compliance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_compliance_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY partner_compliance_requirements_admin ON public.partner_compliance_requirements FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin']))) WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY partner_compliance_records_admin ON public.partner_compliance_records FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin']))) WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY partner_contracts_admin ON public.partner_contracts FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin']))) WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY provider_compliance_overrides_admin ON public.provider_compliance_overrides FOR SELECT TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));

REVOKE ALL ON TABLE public.partner_compliance_requirements, public.partner_compliance_records,
    public.partner_contracts, public.provider_compliance_overrides FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.f9_admin(p_tenant_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ SELECT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) $function$;

CREATE FUNCTION private.f9_record_status(
    p_review_status text, p_valid_to date, p_warning_days integer,
    p_waiver_until date, p_as_of date
)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog
AS $function$
SELECT CASE
    WHEN p_review_status IS NULL THEN 'missing'
    WHEN p_review_status='pending' THEN 'pending_review'
    WHEN p_review_status='rejected' THEN 'rejected'
    WHEN p_review_status='waived' AND p_waiver_until>=p_as_of THEN 'waived'
    WHEN p_review_status='waived' THEN 'expired'
    WHEN p_review_status='accepted' AND p_valid_to<p_as_of THEN 'expired'
    WHEN p_review_status='accepted' AND p_valid_to IS NOT NULL AND p_valid_to<=p_as_of+greatest(p_warning_days,0) THEN 'expiring'
    WHEN p_review_status='accepted' THEN 'valid'
    ELSE 'missing' END
$function$;

CREATE FUNCTION private.f9_partner_status(
    p_tenant_id uuid, p_partner_type text, p_partner_id uuid, p_as_of date DEFAULT current_date
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_exists boolean; v_requirements jsonb; v_result jsonb;
BEGIN
    IF p_partner_type='customer' THEN
        SELECT EXISTS(SELECT 1 FROM public.customers WHERE id=p_partner_id AND tenant_id=p_tenant_id) INTO v_exists;
    ELSIF p_partner_type='provider' THEN
        SELECT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=p_partner_id AND tenant_id=p_tenant_id) INTO v_exists;
    ELSE
        RETURN jsonb_build_object('error','invalid_partner_type');
    END IF;
    IF NOT v_exists THEN RETURN jsonb_build_object('error','not_found'); END IF;

    WITH evaluated AS (
        SELECT r.id,r.code,r.name,r.category,r.is_required,r.has_expiration,r.warning_days,
               r.is_blocking,r.blocks_operation_assignment,
               x.id record_id,x.document_file_id,x.review_status,x.valid_from,x.valid_to,
               x.waiver_until,x.review_note,
               private.f9_record_status(x.review_status,x.valid_to,r.warning_days,x.waiver_until,p_as_of) derived_status
        FROM public.partner_compliance_requirements r
        LEFT JOIN LATERAL (
            SELECT c.* FROM public.partner_compliance_records c
            WHERE c.tenant_id=p_tenant_id AND c.requirement_id=r.id
              AND ((p_partner_type='customer' AND c.customer_id=p_partner_id)
                OR (p_partner_type='provider' AND c.provider_id=p_partner_id))
            ORDER BY c.created_at DESC,c.id DESC LIMIT 1
        ) x ON true
        WHERE r.tenant_id=p_tenant_id AND r.is_active AND r.partner_type IN (p_partner_type,'both')
    ), summarized AS (
        SELECT *, (is_required AND is_blocking AND blocks_operation_assignment
                    AND derived_status IN ('missing','pending_review','expired','rejected')) AS assignment_blocker
        FROM evaluated
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.is_required DESC,s.name),'[]'::jsonb),
           jsonb_build_object(
             'total_required',count(*) FILTER(WHERE is_required),
             'valid',count(*) FILTER(WHERE is_required AND derived_status='valid'),
             'missing',count(*) FILTER(WHERE is_required AND derived_status='missing'),
             'pending',count(*) FILTER(WHERE is_required AND derived_status='pending_review'),
             'expiring',count(*) FILTER(WHERE is_required AND derived_status='expiring'),
             'expired',count(*) FILTER(WHERE is_required AND derived_status='expired'),
             'rejected',count(*) FILTER(WHERE is_required AND derived_status='rejected'),
             'waived',count(*) FILTER(WHERE is_required AND derived_status='waived'),
             'blocking',count(*) FILTER(WHERE assignment_blocker),
             'provider_compliance_ready',count(*) FILTER(WHERE assignment_blocker)=0,
             'badge',CASE WHEN count(*) FILTER(WHERE assignment_blocker)>0 THEN 'blocked'
                          WHEN count(*) FILTER(WHERE is_required AND derived_status IN ('missing','pending_review','expiring','expired','rejected'))>0 THEN 'attention'
                          ELSE 'current' END
           )
    INTO v_requirements,v_result FROM summarized s;
    RETURN v_result||jsonb_build_object('partner_type',p_partner_type,'partner_id',p_partner_id,'as_of',p_as_of,'requirements',v_requirements);
END;
$function$;

CREATE FUNCTION private.f9_seed_defaults(p_tenant_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_count integer;
BEGIN
    INSERT INTO public.partner_compliance_requirements(
        tenant_id,code,name,description,partner_type,category,is_required,has_expiration,
        warning_days,is_blocking,blocks_operation_assignment,sort_order
    ) VALUES
      (p_tenant_id,'generic_tax_document','Documento fiscal','Plantilla genérica configurable por ROTERO; no acredita cumplimiento legal.','both','tax',false,false,30,false,false,10),
      (p_tenant_id,'generic_commercial_contract','Contrato comercial','Control interno de evidencia contractual.','both','contract',false,true,30,false,false,20),
      (p_tenant_id,'generic_insurance_evidence','Evidencia de seguro','Evidencia configurable; requiere revisión humana.','provider','insurance',false,true,30,false,false,30),
      (p_tenant_id,'generic_banking_information','Información bancaria','Evidencia interna de información bancaria.','both','banking',false,false,30,false,false,40)
    ON CONFLICT (tenant_id,code) DO NOTHING;
    GET DIAGNOSTICS v_count=ROW_COUNT; RETURN v_count;
END;
$function$;

CREATE FUNCTION private.f9_seed_defaults_for_tenant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN PERFORM private.f9_seed_defaults(NEW.id); RETURN NEW; END $function$;

CREATE TRIGGER trg_f9_seed_defaults_tenant AFTER INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION private.f9_seed_defaults_for_tenant();
SELECT private.f9_seed_defaults(t.id) FROM public.tenants t;

CREATE FUNCTION public.rpc_list_compliance_requirements(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
 IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.sort_order,r.name) FROM public.partner_compliance_requirements r
   WHERE r.tenant_id=p_tenant_id
     AND (NOT(p_filters?'partner_type') OR r.partner_type IN (p_filters->>'partner_type','both'))
     AND (NOT(p_filters?'active_only') OR NOT COALESCE((p_filters->>'active_only')::boolean,false) OR r.is_active)),'[]'::jsonb);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END $function$;

ALTER TABLE public.automation_rules DROP CONSTRAINT automation_rules_code_check;
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_code_check CHECK (code IN (
 'operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale','quote_review_stale','quote_approved_not_converted','ar_overdue','ap_overdue','finance_due_today','finance_due_soon',
 'partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring'
));
ALTER TABLE public.internal_notifications DROP CONSTRAINT internal_notifications_trigger_check;
ALTER TABLE public.internal_notifications ADD CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN (
 'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending','blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked','ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion','operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale','quote_review_stale','quote_approved_not_converted','finance_due_today',
 'partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring'
));

CREATE FUNCTION private.f9_seed_automation_rules(p_tenant_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_count integer;
BEGIN
 INSERT INTO public.automation_rules(tenant_id,code,name,module,is_enabled,target_role,severity,threshold_value,threshold_unit,escalation_config,digest_enabled)
 VALUES
 (p_tenant_id,'partner_document_expiring','Evidencia de partner por vencer','documents',true,'admin','high',30,'days','{"delay_value":7,"delay_unit":"days","severity":"critical"}'::jsonb,true),
 (p_tenant_id,'partner_document_expired','Evidencia de partner vencida','documents',true,'admin','critical',0,'days','{"delay_value":1,"delay_unit":"days","severity":"critical"}'::jsonb,true),
 (p_tenant_id,'partner_contract_expiring','Contrato de partner por vencer','commercial',true,'admin','high',30,'days','{"delay_value":7,"delay_unit":"days","severity":"critical"}'::jsonb,true),
 (p_tenant_id,'rate_expiring','Tarifa comercial por vencer','commercial',true,'admin','medium',30,'days','{"delay_value":7,"delay_unit":"days","severity":"high"}'::jsonb,true)
 ON CONFLICT(tenant_id,code) DO NOTHING;GET DIAGNOSTICS v_count=ROW_COUNT;RETURN v_count;
END $function$;
SELECT private.f9_seed_automation_rules(t.id) FROM public.tenants t;

CREATE FUNCTION private.f9_materialize_notifications(p_tenant_id uuid,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_evaluation uuid:=gen_random_uuid();v_created integer:=0;v_resolved integer:=0;
BEGIN
 PERFORM private.f9_seed_automation_rules(p_tenant_id);
 INSERT INTO private.f7_source_candidates(evaluation_id,rule_id,code,module,target_role,severity,escalation_config,entity_type,entity_id,title,body,route,occurred_at,due_at,metadata)
 SELECT v_evaluation,a.id,a.code,a.module,a.target_role,a.severity,a.escalation_config,'partner_compliance_record',r.id,
   CASE a.code WHEN 'partner_document_expired' THEN 'Evidencia de partner vencida' ELSE 'Evidencia de partner por vencer' END,
   q.name||' · '||COALESCE(c.display_name,p.display_name),'/commercial?view=compliance&partnerType='||CASE WHEN r.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END||'&partnerId='||COALESCE(r.customer_id,r.provider_id),r.created_at,r.valid_to::timestamptz,
   jsonb_build_object('requirement_id',q.id,'requirement',q.name,'partner_type',CASE WHEN r.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END,'partner_id',COALESCE(r.customer_id,r.provider_id),'valid_to',r.valid_to)
 FROM public.automation_rules a JOIN public.partner_compliance_records r ON r.tenant_id=a.tenant_id JOIN public.partner_compliance_requirements q ON q.id=r.requirement_id LEFT JOIN public.customers c ON c.id=r.customer_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id
 WHERE a.tenant_id=p_tenant_id AND a.is_enabled AND a.code IN ('partner_document_expiring','partner_document_expired') AND r.review_status='accepted' AND r.valid_to IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.partner_compliance_records newer WHERE newer.requirement_id=r.requirement_id AND newer.tenant_id=r.tenant_id AND newer.customer_id IS NOT DISTINCT FROM r.customer_id AND newer.provider_id IS NOT DISTINCT FROM r.provider_id AND (newer.created_at,newer.id)>(r.created_at,r.id))
   AND ((a.code='partner_document_expired' AND r.valid_to<(p_now AT TIME ZONE 'America/Mexico_City')::date) OR (a.code='partner_document_expiring' AND r.valid_to BETWEEN (p_now AT TIME ZONE 'America/Mexico_City')::date AND (p_now AT TIME ZONE 'America/Mexico_City')::date+a.threshold_value))
 UNION ALL
 SELECT v_evaluation,a.id,a.code,a.module,a.target_role,a.severity,a.escalation_config,'partner_contract',k.id,'Contrato de partner por vencer',k.title||' · '||COALESCE(c.display_name,p.display_name),'/commercial?view=compliance&tab=contracts&partnerType='||CASE WHEN k.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END||'&partnerId='||COALESCE(k.customer_id,k.provider_id)||'&contractId='||k.id,k.created_at,k.ends_on::timestamptz,jsonb_build_object('reference',k.reference,'ends_on',k.ends_on)
 FROM public.automation_rules a JOIN public.partner_contracts k ON k.tenant_id=a.tenant_id LEFT JOIN public.customers c ON c.id=k.customer_id LEFT JOIN public.logistics_providers p ON p.id=k.provider_id WHERE a.tenant_id=p_tenant_id AND a.code='partner_contract_expiring' AND a.is_enabled AND k.status='active' AND k.ends_on BETWEEN (p_now AT TIME ZONE 'America/Mexico_City')::date AND (p_now AT TIME ZONE 'America/Mexico_City')::date+a.threshold_value
 UNION ALL
 SELECT v_evaluation,a.id,a.code,a.module,a.target_role,a.severity,a.escalation_config,'commercial_rate',r.id,'Tarifa por vencer',r.reference||' · '||COALESCE(p.display_name,c.display_name),'/commercial?view=rates&rateId='||r.id,r.created_at,v.valid_to::timestamptz,jsonb_build_object('rate_type',r.rate_type,'valid_to',v.valid_to)
 FROM public.automation_rules a JOIN public.commercial_rate_cards r ON r.tenant_id=a.tenant_id JOIN public.commercial_rate_versions v ON v.id=r.current_version_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id LEFT JOIN public.customers c ON c.id=r.customer_id WHERE a.tenant_id=p_tenant_id AND a.code='rate_expiring' AND a.is_enabled AND r.status='active' AND v.valid_to BETWEEN (p_now AT TIME ZONE 'America/Mexico_City')::date AND (p_now AT TIME ZONE 'America/Mexico_City')::date+a.threshold_value;

 INSERT INTO public.internal_notifications(tenant_id,user_id,fingerprint,area,trigger_type,priority,icon,title,body,route,related_entity_type,related_entity_id,status,due_at,automation_rule_id,automation_rule_code,is_automated,first_seen_at,last_seen_at,resolved_at,metadata)
 SELECT p_tenant_id,m.user_id,'automation:'||c.code||':'||c.entity_type||':'||c.entity_id,c.module,c.code,c.severity,CASE WHEN c.severity IN ('critical','high') THEN 'warning' ELSE 'info' END,c.title,c.body,c.route,c.entity_type,c.entity_id::text,'unread',c.due_at,c.rule_id,c.code,true,p_now,p_now,NULL,c.metadata||jsonb_build_object('automated',true,'target_role','admin','occurred_at',c.occurred_at)
 FROM private.f7_source_candidates c JOIN public.memberships m ON m.tenant_id=p_tenant_id AND m.role='admin' WHERE c.evaluation_id=v_evaluation
 ON CONFLICT(tenant_id,user_id,fingerprint) DO UPDATE SET title=EXCLUDED.title,body=EXCLUDED.body,route=EXCLUDED.route,due_at=EXCLUDED.due_at,last_seen_at=EXCLUDED.last_seen_at,resolved_at=NULL,automation_rule_id=EXCLUDED.automation_rule_id,automation_rule_code=EXCLUDED.automation_rule_code,metadata=EXCLUDED.metadata,status=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN 'unread' ELSE public.internal_notifications.status END,read_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN NULL ELSE public.internal_notifications.read_at END,dismissed_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN NULL ELSE public.internal_notifications.dismissed_at END;
 GET DIAGNOSTICS v_created=ROW_COUNT;
 UPDATE public.internal_notifications n SET resolved_at=p_now,last_seen_at=p_now,status='read',read_at=COALESCE(n.read_at,p_now) WHERE n.tenant_id=p_tenant_id AND n.is_automated AND n.automation_rule_code IN ('partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring') AND n.resolved_at IS NULL AND NOT EXISTS(SELECT 1 FROM private.f7_source_candidates c WHERE c.evaluation_id=v_evaluation AND n.fingerprint='automation:'||c.code||':'||c.entity_type||':'||c.entity_id);
 GET DIAGNOSTICS v_resolved=ROW_COUNT;DELETE FROM private.f7_source_candidates WHERE evaluation_id=v_evaluation;RETURN jsonb_build_object('success',true,'upserted',v_created,'resolved',v_resolved);
END $function$;

CREATE FUNCTION private.f9_after_f7_run()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NEW.status='completed' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.run_type IN ('manual','scheduled') THEN PERFORM private.f9_materialize_notifications(NEW.tenant_id,COALESCE(NEW.completed_at,now()));END IF;RETURN NEW;END $function$;
CREATE TRIGGER trg_f9_extend_f7_materialization AFTER UPDATE OF status ON public.automation_runs FOR EACH ROW EXECUTE FUNCTION private.f9_after_f7_run();

CREATE FUNCTION public.rpc_refresh_compliance_notifications(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN private.f9_materialize_notifications(p_tenant_id,now());EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error','evaluation_failed');END $function$;

CREATE FUNCTION public.rpc_upsert_compliance_requirement(p_tenant_id uuid,p_requirement_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid; v_partner_type text:=p_payload->>'partner_type'; v_required boolean:=COALESCE((p_payload->>'is_required')::boolean,false);
 v_blocking boolean:=COALESCE((p_payload->>'is_blocking')::boolean,false); v_assignment boolean:=COALESCE((p_payload->>'blocks_operation_assignment')::boolean,false);
BEGIN
 IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF NULLIF(btrim(p_payload->>'code'),'') IS NULL OR NULLIF(btrim(p_payload->>'name'),'') IS NULL
    OR v_partner_type NOT IN ('customer','provider','both') OR (p_payload->>'category') NOT IN ('tax','contract','insurance','operational','banking','identity','other')
    OR (v_assignment AND (v_partner_type='customer' OR NOT v_required OR NOT v_blocking)) THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 IF p_requirement_id IS NULL THEN
  INSERT INTO public.partner_compliance_requirements(tenant_id,code,name,description,partner_type,category,is_required,has_expiration,warning_days,is_blocking,blocks_operation_assignment,is_active,sort_order)
  VALUES(p_tenant_id,lower(btrim(p_payload->>'code')),btrim(p_payload->>'name'),nullif(btrim(p_payload->>'description'),''),v_partner_type,p_payload->>'category',v_required,COALESCE((p_payload->>'has_expiration')::boolean,false),COALESCE((p_payload->>'warning_days')::integer,30),v_blocking,v_assignment,COALESCE((p_payload->>'is_active')::boolean,true),COALESCE((p_payload->>'sort_order')::integer,0)) RETURNING id INTO v_id;
 ELSE
  UPDATE public.partner_compliance_requirements SET code=lower(btrim(p_payload->>'code')),name=btrim(p_payload->>'name'),description=nullif(btrim(p_payload->>'description'),''),partner_type=v_partner_type,category=p_payload->>'category',is_required=v_required,has_expiration=COALESCE((p_payload->>'has_expiration')::boolean,false),warning_days=COALESCE((p_payload->>'warning_days')::integer,30),is_blocking=v_blocking,blocks_operation_assignment=v_assignment,is_active=COALESCE((p_payload->>'is_active')::boolean,true),sort_order=COALESCE((p_payload->>'sort_order')::integer,0)
  WHERE id=p_requirement_id AND tenant_id=p_tenant_id RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
 END IF;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'compliance_requirement_upserted','compliance_requirement',v_id,jsonb_build_object('is_required',v_required,'is_blocking',v_blocking,'blocks_operation_assignment',v_assignment));
 RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN unique_violation OR check_violation OR invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');
END $function$;

CREATE FUNCTION public.rpc_archive_compliance_requirement(p_requirement_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_tenant uuid;
BEGIN SELECT tenant_id INTO v_tenant FROM public.partner_compliance_requirements WHERE id=p_requirement_id;
 IF v_tenant IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f9_admin(v_tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 UPDATE public.partner_compliance_requirements SET is_active=false WHERE id=p_requirement_id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES(v_tenant,auth.uid(),'compliance_requirement_archived','compliance_requirement',p_requirement_id);
 RETURN jsonb_build_object('success',true); END $function$;

CREATE FUNCTION private.f9_contact_matches_partner(p_tenant_id uuid,p_contact_id uuid,p_partner_type text,p_partner_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ SELECT p_contact_id IS NULL OR EXISTS(SELECT 1 FROM public.business_contacts c WHERE c.id=p_contact_id AND c.tenant_id=p_tenant_id AND ((p_partner_type='customer' AND c.customer_id=p_partner_id) OR (p_partner_type='provider' AND c.provider_id=p_partner_id))) $function$;

CREATE FUNCTION private.f9_document_matches_partner(p_tenant_id uuid,p_file_id uuid,p_partner_type text,p_partner_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ SELECT p_file_id IS NULL OR EXISTS(
 SELECT 1 FROM public.document_files f WHERE f.id=p_file_id AND f.tenant_id=p_tenant_id AND f.status='active' AND (
   (f.source_entity_type=p_partner_type AND f.source_entity_id=p_partner_id) OR EXISTS(SELECT 1 FROM public.document_relations r WHERE r.document_file_id=f.id AND r.tenant_id=p_tenant_id AND r.target_entity_type=p_partner_type AND r.target_entity_id=p_partner_id)
 )) $function$;

CREATE FUNCTION public.rpc_submit_partner_compliance_record(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_req public.partner_compliance_requirements%ROWTYPE; v_customer uuid; v_provider uuid; v_file uuid; v_contact uuid; v_type text; v_partner uuid; v_id uuid;
BEGIN
 IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN v_customer=nullif(p_payload->>'customer_id','')::uuid;v_provider=nullif(p_payload->>'provider_id','')::uuid;v_file=nullif(p_payload->>'document_file_id','')::uuid;v_contact=nullif(p_payload->>'responsible_contact_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
 IF (v_customer IS NOT NULL)::integer+(v_provider IS NOT NULL)::integer<>1 THEN RETURN jsonb_build_object('error','invalid_partner'); END IF;
 v_type:=CASE WHEN v_customer IS NOT NULL THEN 'customer' ELSE 'provider' END;v_partner:=COALESCE(v_customer,v_provider);
 SELECT * INTO v_req FROM public.partner_compliance_requirements WHERE id=(p_payload->>'requirement_id')::uuid AND tenant_id=p_tenant_id AND is_active;
 IF NOT FOUND OR v_req.partner_type NOT IN (v_type,'both') THEN RETURN jsonb_build_object('error','invalid_requirement'); END IF;
 IF (v_type='customer' AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_partner AND tenant_id=p_tenant_id)) OR (v_type='provider' AND NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_partner AND tenant_id=p_tenant_id)) THEN RETURN jsonb_build_object('error','invalid_partner'); END IF;
 IF NOT private.f9_document_matches_partner(p_tenant_id,v_file,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_document'); END IF;
 IF NOT private.f9_contact_matches_partner(p_tenant_id,v_contact,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_contact'); END IF;
 INSERT INTO public.partner_compliance_records(tenant_id,requirement_id,customer_id,provider_id,document_file_id,responsible_contact_id,review_status,valid_from,valid_to,created_by,created_at,updated_at)
 VALUES(p_tenant_id,v_req.id,v_customer,v_provider,v_file,v_contact,'pending',nullif(p_payload->>'valid_from','')::date,nullif(p_payload->>'valid_to','')::date,auth.uid(),clock_timestamp(),clock_timestamp()) RETURNING id INTO v_id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'compliance_evidence_submitted','partner_compliance_record',v_id,jsonb_build_object('requirement_id',v_req.id,'partner_type',v_type,'partner_id',v_partner,'document_file_id',v_file));
 RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN check_violation OR invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload');
END $function$;

CREATE FUNCTION public.rpc_review_partner_compliance_record(p_record_id uuid,p_decision text,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_record public.partner_compliance_records%ROWTYPE;
BEGIN SELECT * INTO v_record FROM public.partner_compliance_records WHERE id=p_record_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f9_admin(v_record.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_decision NOT IN ('accepted','rejected') OR (p_decision='rejected' AND NULLIF(btrim(COALESCE(p_note,'')),'') IS NULL) THEN RETURN jsonb_build_object('error','invalid_review'); END IF;
 UPDATE public.partner_compliance_records SET review_status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=nullif(btrim(COALESCE(p_note,'')),'') WHERE id=p_record_id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(v_record.tenant_id,auth.uid(),'compliance_evidence_'||p_decision,'partner_compliance_record',p_record_id,jsonb_build_object('requirement_id',v_record.requirement_id));
 RETURN jsonb_build_object('success',true,'status',p_decision); END $function$;

CREATE FUNCTION public.rpc_waive_partner_requirement(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_req public.partner_compliance_requirements%ROWTYPE;v_customer uuid;v_provider uuid;v_partner uuid;v_type text;v_until date;v_reason text;v_id uuid;
BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN v_customer=nullif(p_payload->>'customer_id','')::uuid;v_provider=nullif(p_payload->>'provider_id','')::uuid;v_until=(p_payload->>'waiver_until')::date; EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload'); END;
 v_reason:=nullif(btrim(p_payload->>'reason'),''); IF (v_customer IS NOT NULL)::integer+(v_provider IS NOT NULL)::integer<>1 OR v_reason IS NULL OR v_until<=current_date THEN RETURN jsonb_build_object('error','invalid_waiver'); END IF;
 v_type:=CASE WHEN v_customer IS NOT NULL THEN 'customer' ELSE 'provider' END;v_partner:=COALESCE(v_customer,v_provider);
 SELECT * INTO v_req FROM public.partner_compliance_requirements WHERE id=(p_payload->>'requirement_id')::uuid AND tenant_id=p_tenant_id AND is_active; IF NOT FOUND OR v_req.partner_type NOT IN (v_type,'both') THEN RETURN jsonb_build_object('error','invalid_requirement'); END IF;
 IF (v_type='customer' AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_partner AND tenant_id=p_tenant_id)) OR (v_type='provider' AND NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_partner AND tenant_id=p_tenant_id)) THEN RETURN jsonb_build_object('error','invalid_partner'); END IF;
 INSERT INTO public.partner_compliance_records(tenant_id,requirement_id,customer_id,provider_id,review_status,reviewed_at,reviewed_by,review_note,waiver_until,waiver_reason,created_by,created_at,updated_at)
 VALUES(p_tenant_id,v_req.id,v_customer,v_provider,'waived',clock_timestamp(),auth.uid(),v_reason,v_until,v_reason,auth.uid(),clock_timestamp(),clock_timestamp()) RETURNING id INTO v_id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'compliance_requirement_waived','partner_compliance_record',v_id,jsonb_build_object('requirement_id',v_req.id,'waiver_until',v_until,'reason',v_reason));
 RETURN jsonb_build_object('id',v_id,'waiver_until',v_until); END $function$;

CREATE FUNCTION public.rpc_get_partner_compliance_status(p_tenant_id uuid,p_partner_type text,p_partner_id uuid,p_as_of date DEFAULT current_date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; RETURN private.f9_partner_status(p_tenant_id,p_partner_type,p_partner_id,p_as_of); END $function$;

CREATE FUNCTION public.rpc_get_provider_operational_eligibility(p_tenant_id uuid,p_provider_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_status jsonb;
BEGIN IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 v_status:=private.f9_partner_status(p_tenant_id,'provider',p_provider_id,current_date);
 RETURN jsonb_build_object('provider_id',p_provider_id,'eligible',COALESCE((v_status->>'provider_compliance_ready')::boolean,false),'badge',v_status->>'badge','blocking',COALESCE((v_status->>'blocking')::integer,0),'reasons',COALESCE((SELECT jsonb_agg(jsonb_build_object('requirement_id',x->>'id','code',x->>'code','name',x->>'name','status',x->>'derived_status')) FROM jsonb_array_elements(v_status->'requirements') x WHERE COALESCE((x->>'assignment_blocker')::boolean,false)),'[]'::jsonb));
END $function$;

CREATE FUNCTION private.f9_contract_status(p_status text,p_ends_on date,p_notice_days integer,p_as_of date)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog
AS $function$ SELECT CASE WHEN p_status='terminated' THEN 'terminated' WHEN p_status IN ('draft','archived') THEN p_status WHEN p_ends_on<p_as_of THEN 'expired' WHEN p_ends_on IS NOT NULL AND p_ends_on<=p_as_of+greatest(p_notice_days,0) THEN 'expiring' ELSE 'active' END $function$;

CREATE FUNCTION public.rpc_upsert_partner_contract(p_tenant_id uuid,p_contract_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_customer uuid;v_provider uuid;v_file uuid;v_contact uuid;v_type text;v_partner uuid;v_id uuid;v_existing public.partner_contracts%ROWTYPE;
BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN v_customer=nullif(p_payload->>'customer_id','')::uuid;v_provider=nullif(p_payload->>'provider_id','')::uuid;v_file=nullif(p_payload->>'document_file_id','')::uuid;v_contact=nullif(p_payload->>'responsible_contact_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
 IF (v_customer IS NOT NULL)::integer+(v_provider IS NOT NULL)::integer<>1 OR nullif(btrim(p_payload->>'title'),'') IS NULL OR nullif(btrim(p_payload->>'contract_type'),'') IS NULL THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 v_type:=CASE WHEN v_customer IS NOT NULL THEN 'customer' ELSE 'provider' END;v_partner:=COALESCE(v_customer,v_provider);
 IF (v_type='customer' AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_partner AND tenant_id=p_tenant_id)) OR (v_type='provider' AND NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_partner AND tenant_id=p_tenant_id)) THEN RETURN jsonb_build_object('error','invalid_partner'); END IF;
 IF NOT private.f9_document_matches_partner(p_tenant_id,v_file,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_document'); END IF;
 IF NOT private.f9_contact_matches_partner(p_tenant_id,v_contact,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_contact'); END IF;
 IF p_contract_id IS NULL THEN
  INSERT INTO public.partner_contracts(tenant_id,customer_id,provider_id,contract_type,title,reference,document_file_id,responsible_contact_id,starts_on,ends_on,notice_days,status,notes,created_by)
  VALUES(p_tenant_id,v_customer,v_provider,btrim(p_payload->>'contract_type'),btrim(p_payload->>'title'),nullif(btrim(p_payload->>'reference'),''),v_file,v_contact,nullif(p_payload->>'starts_on','')::date,nullif(p_payload->>'ends_on','')::date,COALESCE((p_payload->>'notice_days')::integer,30),'draft',nullif(btrim(p_payload->>'notes'),''),auth.uid()) RETURNING id INTO v_id;
 ELSE
  SELECT * INTO v_existing FROM public.partner_contracts WHERE id=p_contract_id AND tenant_id=p_tenant_id FOR UPDATE; IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF v_existing.status<>'draft' THEN RETURN jsonb_build_object('error','contract_immutable'); END IF;
  UPDATE public.partner_contracts SET customer_id=v_customer,provider_id=v_provider,contract_type=btrim(p_payload->>'contract_type'),title=btrim(p_payload->>'title'),reference=nullif(btrim(p_payload->>'reference'),''),document_file_id=v_file,responsible_contact_id=v_contact,starts_on=nullif(p_payload->>'starts_on','')::date,ends_on=nullif(p_payload->>'ends_on','')::date,notice_days=COALESCE((p_payload->>'notice_days')::integer,30),notes=nullif(btrim(p_payload->>'notes'),'') WHERE id=p_contract_id RETURNING id INTO v_id;
 END IF;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'partner_contract_upserted','partner_contract',v_id,jsonb_build_object('partner_type',v_type,'partner_id',v_partner)); RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN check_violation OR invalid_text_representation OR datetime_field_overflow OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload'); END $function$;

CREATE FUNCTION public.rpc_activate_partner_contract(p_contract_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v public.partner_contracts%ROWTYPE;
BEGIN SELECT * INTO v FROM public.partner_contracts WHERE id=p_contract_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f9_admin(v.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v.status<>'draft' OR v.starts_on IS NULL THEN RETURN jsonb_build_object('error','invalid_contract_state');END IF;UPDATE public.partner_contracts SET status='active' WHERE id=p_contract_id;INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES(v.tenant_id,auth.uid(),'partner_contract_activated','partner_contract',v.id);RETURN jsonb_build_object('success',true);END $function$;

CREATE FUNCTION public.rpc_renew_partner_contract(p_contract_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v public.partner_contracts%ROWTYPE;v_file uuid;v_contact uuid;v_id uuid;v_type text;v_partner uuid;
BEGIN SELECT * INTO v FROM public.partner_contracts WHERE id=p_contract_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f9_admin(v.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v.status<>'active' THEN RETURN jsonb_build_object('error','invalid_contract_state');END IF;
 BEGIN v_file=nullif(p_payload->>'document_file_id','')::uuid;v_contact=COALESCE(nullif(p_payload->>'responsible_contact_id','')::uuid,v.responsible_contact_id);EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');END;
 v_type:=CASE WHEN v.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END;v_partner:=COALESCE(v.customer_id,v.provider_id);
 IF NOT private.f9_document_matches_partner(v.tenant_id,v_file,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_document');END IF;
 IF NOT private.f9_contact_matches_partner(v.tenant_id,v_contact,v_type,v_partner) THEN RETURN jsonb_build_object('error','invalid_contact');END IF;
 INSERT INTO public.partner_contracts(tenant_id,customer_id,provider_id,contract_type,title,reference,document_file_id,responsible_contact_id,starts_on,ends_on,notice_days,status,notes,renewed_from_id,created_by)
 VALUES(v.tenant_id,v.customer_id,v.provider_id,COALESCE(nullif(btrim(p_payload->>'contract_type'),''),v.contract_type),COALESCE(nullif(btrim(p_payload->>'title'),''),v.title),COALESCE(nullif(btrim(p_payload->>'reference'),''),v.reference),v_file,v_contact,(p_payload->>'starts_on')::date,nullif(p_payload->>'ends_on','')::date,COALESCE((p_payload->>'notice_days')::integer,v.notice_days),'active',nullif(btrim(p_payload->>'notes'),''),v.id,auth.uid()) RETURNING id INTO v_id;
 UPDATE public.partner_contracts SET status='archived' WHERE id=v.id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(v.tenant_id,auth.uid(),'partner_contract_renewed','partner_contract',v_id,jsonb_build_object('renewed_from_id',v.id));RETURN jsonb_build_object('id',v_id,'renewed_from_id',v.id);
EXCEPTION WHEN check_violation OR invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload');END $function$;

CREATE FUNCTION public.rpc_terminate_partner_contract(p_contract_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v public.partner_contracts%ROWTYPE;
BEGIN SELECT * INTO v FROM public.partner_contracts WHERE id=p_contract_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f9_admin(v.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v.status<>'active' OR nullif(btrim(COALESCE(p_reason,'')),'') IS NULL THEN RETURN jsonb_build_object('error','invalid_contract_state');END IF;UPDATE public.partner_contracts SET status='terminated',notes=concat_ws(E'\n',notes,'Terminación: '||btrim(p_reason)) WHERE id=v.id;INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(v.tenant_id,auth.uid(),'partner_contract_terminated','partner_contract',v.id,jsonb_build_object('reason',btrim(p_reason)));RETURN jsonb_build_object('success',true);END $function$;

CREATE FUNCTION public.rpc_get_partner_compliance_bundle(p_tenant_id uuid,p_partner_type text,p_partner_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN private.f9_partner_status(p_tenant_id,p_partner_type,p_partner_id,current_date)||jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object('requirement_name',q.name,'derived_status',private.f9_record_status(r.review_status,r.valid_to,q.warning_days,r.waiver_until,current_date),'file_name',f.file_name) ORDER BY r.created_at DESC) FROM public.partner_compliance_records r JOIN public.partner_compliance_requirements q ON q.id=r.requirement_id LEFT JOIN public.document_files f ON f.id=r.document_file_id WHERE r.tenant_id=p_tenant_id AND ((p_partner_type='customer' AND r.customer_id=p_partner_id) OR (p_partner_type='provider' AND r.provider_id=p_partner_id))),'[]'::jsonb),'contracts',COALESCE((SELECT jsonb_agg(to_jsonb(c)||jsonb_build_object('derived_status',private.f9_contract_status(c.status,c.ends_on,c.notice_days,current_date),'file_name',f.file_name) ORDER BY c.created_at DESC) FROM public.partner_contracts c LEFT JOIN public.document_files f ON f.id=c.document_file_id WHERE c.tenant_id=p_tenant_id AND ((p_partner_type='customer' AND c.customer_id=p_partner_id) OR (p_partner_type='provider' AND c.provider_id=p_partner_id))),'[]'::jsonb)); END $function$;

CREATE FUNCTION public.rpc_list_compliance_matrix(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY x->>'partner_name') FROM (
  SELECT jsonb_build_object('partner_id',p.id,'partner_name',p.display_name,'partner_type','provider','is_active',p.is_active)||private.f9_partner_status(p_tenant_id,'provider',p.id,current_date) x FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id AND (NOT(p_filters?'partner_type') OR p_filters->>'partner_type' IN ('provider','both'))
  UNION ALL SELECT jsonb_build_object('partner_id',c.id,'partner_name',c.display_name,'partner_type','customer','is_active',c.is_active)||private.f9_partner_status(p_tenant_id,'customer',c.id,current_date) FROM public.customers c WHERE c.tenant_id=p_tenant_id AND (NOT(p_filters?'partner_type') OR p_filters->>'partner_type' IN ('customer','both'))
 ) q WHERE (NOT COALESCE((p_filters->>'active_only')::boolean,false) OR (x->>'is_active')::boolean) AND (NOT COALESCE((p_filters->>'blocking_only')::boolean,false) OR (x->>'blocking')::integer>0)),'[]'::jsonb);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');END $function$;

CREATE FUNCTION public.rpc_list_compliance_expirations(p_tenant_id uuid,p_days integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF p_days NOT IN (7,15,30,60,90) THEN RETURN jsonb_build_object('error','invalid_window');END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'expires_on')::date,x->>'source') FROM (
  SELECT jsonb_build_object('source','Documento','id',r.id,'partner_type',CASE WHEN r.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END,'partner_id',COALESCE(r.customer_id,r.provider_id),'partner_name',COALESCE(c.display_name,p.display_name),'title',q.name,'expires_on',r.valid_to,'route','/commercial?view=compliance&partnerType='||CASE WHEN r.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END||'&partnerId='||COALESCE(r.customer_id,r.provider_id)) x FROM public.partner_compliance_records r JOIN public.partner_compliance_requirements q ON q.id=r.requirement_id LEFT JOIN public.customers c ON c.id=r.customer_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id WHERE r.tenant_id=p_tenant_id AND r.review_status='accepted' AND r.valid_to BETWEEN current_date AND current_date+p_days AND NOT EXISTS(SELECT 1 FROM public.partner_compliance_records newer WHERE newer.requirement_id=r.requirement_id AND COALESCE(newer.customer_id,newer.provider_id)=COALESCE(r.customer_id,r.provider_id) AND (newer.created_at,newer.id)>(r.created_at,r.id))
  UNION ALL SELECT jsonb_build_object('source','Contrato','id',k.id,'partner_type',CASE WHEN k.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END,'partner_id',COALESCE(k.customer_id,k.provider_id),'partner_name',COALESCE(c.display_name,p.display_name),'title',k.title,'reference',k.reference,'expires_on',k.ends_on,'route','/commercial?view=compliance&partnerType='||CASE WHEN k.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END||'&partnerId='||COALESCE(k.customer_id,k.provider_id)) FROM public.partner_contracts k LEFT JOIN public.customers c ON c.id=k.customer_id LEFT JOIN public.logistics_providers p ON p.id=k.provider_id WHERE k.tenant_id=p_tenant_id AND k.status='active' AND k.ends_on BETWEEN current_date AND current_date+p_days
  UNION ALL SELECT jsonb_build_object('source',CASE r.rate_type WHEN 'BUY' THEN 'Tarifa BUY' ELSE 'Tarifa SELL' END,'id',r.id,'partner_type',CASE r.rate_type WHEN 'BUY' THEN 'provider' ELSE 'customer' END,'partner_id',COALESCE(r.provider_id,r.customer_id),'partner_name',COALESCE(p.display_name,c.display_name),'title',r.reference,'expires_on',v.valid_to,'route','/commercial?view=rates&rateId='||r.id) FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id LEFT JOIN public.customers c ON c.id=r.customer_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id WHERE r.tenant_id=p_tenant_id AND r.status='active' AND v.valid_to BETWEEN current_date AND current_date+p_days
 ) q),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_get_provider_compliance_badges(p_tenant_id uuid,p_provider_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('provider_id',p.id,'badge',s->>'badge','blocking',(s->>'blocking')::integer,'reasons',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x->>'code','name',x->>'name','status',x->>'derived_status')) FROM jsonb_array_elements(s->'requirements') x WHERE COALESCE((x->>'assignment_blocker')::boolean,false)),'[]'::jsonb))) FROM public.logistics_providers p CROSS JOIN LATERAL private.f9_partner_status(p_tenant_id,'provider',p.id,current_date) s WHERE p.tenant_id=p_tenant_id AND p.id=ANY(COALESCE(p_provider_ids,ARRAY[]::uuid[]))),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_get_compliance_dashboard(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN jsonb_build_object(
  'blocked_providers',(SELECT count(*) FROM public.logistics_providers p CROSS JOIN LATERAL private.f9_partner_status(p_tenant_id,'provider',p.id,current_date) s WHERE p.tenant_id=p_tenant_id AND p.is_active AND (s->>'blocking')::integer>0),
  'missing_required_docs',(SELECT COALESCE(sum((s->>'missing')::integer),0) FROM (SELECT private.f9_partner_status(p_tenant_id,'provider',p.id,current_date) s FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id UNION ALL SELECT private.f9_partner_status(p_tenant_id,'customer',c.id,current_date) FROM public.customers c WHERE c.tenant_id=p_tenant_id) q),
  'documents_expiring_30d',(SELECT count(*) FROM public.partner_compliance_records r WHERE r.tenant_id=p_tenant_id AND r.review_status='accepted' AND r.valid_to BETWEEN current_date AND current_date+30 AND NOT EXISTS(SELECT 1 FROM public.partner_compliance_records newer WHERE newer.requirement_id=r.requirement_id AND COALESCE(newer.customer_id,newer.provider_id)=COALESCE(r.customer_id,r.provider_id) AND (newer.created_at,newer.id)>(r.created_at,r.id))),
  'contracts_expiring_30d',(SELECT count(*) FROM public.partner_contracts c WHERE c.tenant_id=p_tenant_id AND c.status='active' AND c.ends_on BETWEEN current_date AND current_date+30),
  'rates_expiring_30d',(SELECT count(*) FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id WHERE r.tenant_id=p_tenant_id AND r.status='active' AND v.valid_to BETWEEN current_date AND current_date+30));
END $function$;

CREATE FUNCTION public.rpc_search_compliance(p_tenant_id uuid,p_query text,p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_q text:=btrim(COALESCE(p_query,''));v_limit integer:=least(greatest(COALESCE(p_limit,10),1),25);
BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF char_length(v_q)<2 THEN RETURN '[]'::jsonb;END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY x->>'primary_label') FROM (
  SELECT jsonb_build_object('type','compliance_requirement','id',r.id,'primary_label',r.name,'secondary_label',r.code,'route','/commercial?view=compliance&tab=requirements&requirementId='||r.id) x FROM public.partner_compliance_requirements r WHERE r.tenant_id=p_tenant_id AND r.is_active AND (r.name ILIKE '%'||v_q||'%' OR r.code ILIKE '%'||v_q||'%') LIMIT v_limit
 ) q),'[]'::jsonb)||COALESCE((SELECT jsonb_agg(x ORDER BY x->>'primary_label') FROM (
  SELECT jsonb_build_object('type','partner_contract','id',c.id,'primary_label',c.title,'secondary_label',COALESCE(c.reference,COALESCE(cu.display_name,p.display_name)),'route','/commercial?view=compliance&tab=contracts&partnerType='||CASE WHEN c.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END||'&partnerId='||COALESCE(c.customer_id,c.provider_id)||'&contractId='||c.id) x FROM public.partner_contracts c LEFT JOIN public.customers cu ON cu.id=c.customer_id LEFT JOIN public.logistics_providers p ON p.id=c.provider_id WHERE c.tenant_id=p_tenant_id AND (c.title ILIKE '%'||v_q||'%' OR c.reference ILIKE '%'||v_q||'%') LIMIT v_limit
 ) q),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_export_partner_compliance(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ BEGIN IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('partner',q.partner_name,'type',q.partner_type,'requirement',q.requirement_name,'review_status',q.review_status,'derived_status',q.derived_status,'valid_to',q.valid_to,'warning_window',q.warning_days,'blocking',q.assignment_blocker,'contract_reference',q.contract_reference,'document_filename',q.file_name) ORDER BY q.partner_name,q.requirement_name) FROM (
  SELECT p.display_name partner_name,'provider' partner_type,rq.name requirement_name,x.review_status,private.f9_record_status(x.review_status,x.valid_to,rq.warning_days,x.waiver_until,current_date) derived_status,x.valid_to,rq.warning_days,(rq.is_required AND rq.is_blocking AND rq.blocks_operation_assignment AND private.f9_record_status(x.review_status,x.valid_to,rq.warning_days,x.waiver_until,current_date) IN ('missing','pending_review','expired','rejected')) assignment_blocker,(SELECT string_agg(COALESCE(k.reference,k.title),' | ' ORDER BY k.created_at DESC) FROM public.partner_contracts k WHERE k.provider_id=p.id AND k.status IN ('active','draft')) contract_reference,f.file_name
  FROM public.logistics_providers p JOIN public.partner_compliance_requirements rq ON rq.tenant_id=p.tenant_id AND rq.is_active AND rq.partner_type IN ('provider','both') LEFT JOIN LATERAL(SELECT r.* FROM public.partner_compliance_records r WHERE r.requirement_id=rq.id AND r.provider_id=p.id ORDER BY r.created_at DESC LIMIT 1)x ON true LEFT JOIN public.document_files f ON f.id=x.document_file_id WHERE p.tenant_id=p_tenant_id
  UNION ALL SELECT c.display_name,'customer',rq.name,x.review_status,private.f9_record_status(x.review_status,x.valid_to,rq.warning_days,x.waiver_until,current_date),x.valid_to,rq.warning_days,false,(SELECT string_agg(COALESCE(k.reference,k.title),' | ' ORDER BY k.created_at DESC) FROM public.partner_contracts k WHERE k.customer_id=c.id AND k.status IN ('active','draft')),f.file_name
  FROM public.customers c JOIN public.partner_compliance_requirements rq ON rq.tenant_id=c.tenant_id AND rq.is_active AND rq.partner_type IN ('customer','both') LEFT JOIN LATERAL(SELECT r.* FROM public.partner_compliance_records r WHERE r.requirement_id=rq.id AND r.customer_id=c.id ORDER BY r.created_at DESC LIMIT 1)x ON true LEFT JOIN public.document_files f ON f.id=x.document_file_id WHERE c.tenant_id=p_tenant_id
 ) q WHERE (NOT(p_filters?'partner_type') OR q.partner_type=p_filters->>'partner_type')),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_create_provider_compliance_override(p_operation_id uuid,p_provider_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_tenant uuid;v_status jsonb;v_id uuid;
BEGIN SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;IF v_tenant IS NULL OR NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=p_provider_id AND tenant_id=v_tenant) THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f9_admin(v_tenant) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF char_length(btrim(COALESCE(p_reason,'')))<5 THEN RETURN jsonb_build_object('error','missing_override_reason');END IF;
 v_status:=private.f9_partner_status(v_tenant,'provider',p_provider_id,current_date);IF COALESCE((v_status->>'blocking')::integer,0)=0 THEN RETURN jsonb_build_object('error','provider_not_blocked');END IF;
 INSERT INTO public.provider_compliance_overrides(tenant_id,operation_id,provider_id,reason,blocker_snapshot,created_by) VALUES(v_tenant,p_operation_id,p_provider_id,btrim(p_reason),v_status,auth.uid()) ON CONFLICT(operation_id,provider_id) DO UPDATE SET reason=EXCLUDED.reason,blocker_snapshot=EXCLUDED.blocker_snapshot,created_by=EXCLUDED.created_by,created_at=now() RETURNING id INTO v_id;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(v_tenant,auth.uid(),'operation_compliance_override','operation',p_operation_id,jsonb_build_object('provider_id',p_provider_id,'reason',btrim(p_reason),'blocker_snapshot',v_status));RETURN jsonb_build_object('id',v_id,'success',true);END $function$;

CREATE FUNCTION private.f9_guard_provider_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_status jsonb;
BEGIN
 IF NEW.execution_type='third_party' AND NEW.provider_id IS NOT NULL
    AND (OLD.provider_id IS DISTINCT FROM NEW.provider_id OR OLD.assigned_at IS DISTINCT FROM NEW.assigned_at OR (OLD.status='planned' AND NEW.status='assigned')) THEN
  v_status:=private.f9_partner_status(NEW.tenant_id,'provider',NEW.provider_id,current_date);
  IF COALESCE((v_status->>'blocking')::integer,0)>0 AND NOT EXISTS(SELECT 1 FROM public.provider_compliance_overrides o WHERE o.tenant_id=NEW.tenant_id AND o.operation_id=NEW.id AND o.provider_id=NEW.provider_id) THEN
   RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='provider_compliance_blocked',DETAIL=jsonb_build_object('code','provider_compliance_blocked','blocking',v_status->'blocking','reasons',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x->>'code','name',x->>'name','status',x->>'derived_status')) FROM jsonb_array_elements(v_status->'requirements') x WHERE COALESCE((x->>'assignment_blocker')::boolean,false)),'[]'::jsonb))::text;
  END IF;
 END IF; RETURN NEW;
END $function$;

CREATE TRIGGER trg_f9_provider_assignment_gate BEFORE UPDATE OF provider_id,assigned_at,status ON public.operations FOR EACH ROW EXECUTE FUNCTION private.f9_guard_provider_assignment();

-- Exact collision: staging OID 22358, identical input name/type/result/default
-- contract. CREATE OR REPLACE preserves the OID and only augments F7 readiness.
CREATE OR REPLACE FUNCTION public.rpc_get_operation_dispatch_readiness(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$ DECLARE v_operation public.operations%ROWTYPE;v_role text;v_result jsonb;v_status jsonb;v_ready boolean:=true;v_reasons jsonb:='[]'::jsonb;
BEGIN SELECT * INTO v_operation FROM public.operations WHERE id=p_operation_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;SELECT role INTO v_role FROM public.memberships WHERE tenant_id=v_operation.tenant_id AND user_id=auth.uid();IF v_role NOT IN ('admin','operator','finance','viewer') THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 v_result:=private.f7_operation_dispatch_readiness(p_operation_id);
 IF v_operation.execution_type='third_party' AND v_operation.provider_id IS NOT NULL THEN v_status:=private.f9_partner_status(v_operation.tenant_id,'provider',v_operation.provider_id,current_date);v_ready:=COALESCE((v_status->>'provider_compliance_ready')::boolean,false) OR EXISTS(SELECT 1 FROM public.provider_compliance_overrides o WHERE o.operation_id=p_operation_id AND o.provider_id=v_operation.provider_id);IF NOT v_ready THEN v_reasons:=jsonb_build_array('provider_compliance_blocked');END IF;END IF;
 RETURN v_result||jsonb_build_object('provider_compliance_ready',v_ready,'provider_compliance_blocker_reasons',CASE WHEN v_role IN ('admin','operator') THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x->>'code','name',x->>'name','status',x->>'derived_status')) FROM jsonb_array_elements(COALESCE(v_status->'requirements','[]'::jsonb)) x WHERE COALESCE((x->>'assignment_blocker')::boolean,false)),'[]'::jsonb) ELSE v_reasons END,'can_transition_to_assigned',COALESCE((v_result->>'can_transition_to_assigned')::boolean,false) AND v_ready,'can_transition_to_in_transit',COALESCE((v_result->>'can_transition_to_in_transit')::boolean,false) AND v_ready,'blocking_reasons',COALESCE(v_result->'blocking_reasons','[]'::jsonb)||v_reasons);
END $function$;

CREATE FUNCTION public.rpc_list_compliance_attention_items(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
 IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY CASE x->>'severity' WHEN 'critical' THEN 1 ELSE 2 END,x->>'due_at') FROM (
  SELECT jsonb_build_object('kind','provider_compliance_blocked','severity','critical','title','Proveedor bloqueado para asignación','subtitle',p.display_name||' · '||(s->>'blocking')||' requisito(s) bloqueante(s)','reference',p.display_name,'entity_type','provider','entity_id',p.id,'module','commercial','route','/commercial?view=compliance&tab=providers&partnerType=provider&partnerId='||p.id,'occurred_at',p.updated_at,'due_at',NULL::timestamptz) x
  FROM public.logistics_providers p CROSS JOIN LATERAL private.f9_partner_status(p_tenant_id,'provider',p.id,current_date) s WHERE p.tenant_id=p_tenant_id AND p.is_active AND (s->>'blocking')::integer>0
  UNION ALL
  SELECT jsonb_build_object('kind','compliance_expiring','severity','high','title',(e->>'source')||' por vencer','subtitle',(e->>'partner_name')||' · '||(e->>'title'),'reference',COALESCE(e->>'reference',e->>'title'),'entity_type',lower(replace(e->>'source',' ','_')),'entity_id',e->>'id','module',CASE WHEN e->>'source'='Documento' THEN 'documents' ELSE 'commercial' END,'route',e->>'route','occurred_at',now(),'due_at',e->>'expires_on')
  FROM jsonb_array_elements(public.rpc_list_compliance_expirations(p_tenant_id,30)) e
 ) q),'[]'::jsonb);
END $function$;

REVOKE ALL ON FUNCTION private.f9_admin(uuid),private.f9_record_status(text,date,integer,date,date),private.f9_partner_status(uuid,text,uuid,date),private.f9_seed_defaults(uuid),private.f9_seed_defaults_for_tenant(),private.f9_contact_matches_partner(uuid,uuid,text,uuid),private.f9_document_matches_partner(uuid,uuid,text,uuid),private.f9_contract_status(text,date,integer,date),private.f9_guard_provider_assignment(),private.f9_seed_automation_rules(uuid),private.f9_materialize_notifications(uuid,timestamptz),private.f9_after_f7_run() FROM PUBLIC,anon,authenticated,service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_list_compliance_requirements(uuid,jsonb),public.rpc_upsert_compliance_requirement(uuid,uuid,jsonb),public.rpc_archive_compliance_requirement(uuid),public.rpc_submit_partner_compliance_record(uuid,jsonb),public.rpc_review_partner_compliance_record(uuid,text,text),public.rpc_waive_partner_requirement(uuid,jsonb),public.rpc_get_partner_compliance_status(uuid,text,uuid,date),public.rpc_get_provider_operational_eligibility(uuid,uuid),public.rpc_upsert_partner_contract(uuid,uuid,jsonb),public.rpc_activate_partner_contract(uuid),public.rpc_renew_partner_contract(uuid,jsonb),public.rpc_terminate_partner_contract(uuid,text),public.rpc_get_partner_compliance_bundle(uuid,text,uuid),public.rpc_list_compliance_matrix(uuid,jsonb),public.rpc_list_compliance_expirations(uuid,integer),public.rpc_get_provider_compliance_badges(uuid,uuid[]),public.rpc_get_compliance_dashboard(uuid),public.rpc_list_compliance_attention_items(uuid),public.rpc_search_compliance(uuid,text,integer),public.rpc_export_partner_compliance(uuid,jsonb),public.rpc_create_provider_compliance_override(uuid,uuid,text),public.rpc_refresh_compliance_notifications(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_compliance_requirements(uuid,jsonb),public.rpc_upsert_compliance_requirement(uuid,uuid,jsonb),public.rpc_archive_compliance_requirement(uuid),public.rpc_submit_partner_compliance_record(uuid,jsonb),public.rpc_review_partner_compliance_record(uuid,text,text),public.rpc_waive_partner_requirement(uuid,jsonb),public.rpc_get_partner_compliance_status(uuid,text,uuid,date),public.rpc_get_provider_operational_eligibility(uuid,uuid),public.rpc_upsert_partner_contract(uuid,uuid,jsonb),public.rpc_activate_partner_contract(uuid),public.rpc_renew_partner_contract(uuid,jsonb),public.rpc_terminate_partner_contract(uuid,text),public.rpc_get_partner_compliance_bundle(uuid,text,uuid),public.rpc_list_compliance_matrix(uuid,jsonb),public.rpc_list_compliance_expirations(uuid,integer),public.rpc_get_provider_compliance_badges(uuid,uuid[]),public.rpc_get_compliance_dashboard(uuid),public.rpc_list_compliance_attention_items(uuid),public.rpc_search_compliance(uuid,text,integer),public.rpc_export_partner_compliance(uuid,jsonb),public.rpc_create_provider_compliance_override(uuid,uuid,text),public.rpc_refresh_compliance_notifications(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_dispatch_readiness(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_dispatch_readiness(uuid) TO authenticated;
