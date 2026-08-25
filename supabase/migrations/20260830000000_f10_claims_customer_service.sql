-- F10 — ROTERO Claims & Customer Service 360
-- Additive only. Operational service-case control; no legal fault engine,
-- accounting mutation, Auth/Edge/Tracking change or additional scheduler.

CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE private.claim_number_sequences (
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    calendar_year integer NOT NULL CHECK (calendar_year BETWEEN 2020 AND 9999),
    last_value bigint NOT NULL CHECK (last_value > 0),
    PRIMARY KEY (tenant_id, calendar_year)
);

CREATE TABLE public.claim_service_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_type text NOT NULL DEFAULT 'all',
    priority text NOT NULL,
    first_response_hours integer NOT NULL CHECK (first_response_hours BETWEEN 1 AND 8760),
    resolution_hours integer NOT NULL CHECK (resolution_hours BETWEEN 1 AND 17520),
    is_active boolean NOT NULL DEFAULT true,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT claim_service_policies_type_check CHECK (claim_type IN ('all','delay','damage','shortage','loss','documentation','billing','service_quality','provider_performance','compliance','other')),
    CONSTRAINT claim_service_policies_priority_check CHECK (priority IN ('critical','high','medium','low')),
    CONSTRAINT claim_service_policies_resolution_after_response_check CHECK (resolution_hours >= first_response_hours),
    CONSTRAINT claim_service_policies_tenant_type_priority_key UNIQUE (tenant_id,claim_type,priority)
);

CREATE TABLE public.service_claims (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_number text NOT NULL,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    source_incident_id uuid REFERENCES public.operation_incidents(id) ON DELETE SET NULL,
    compliance_requirement_id uuid REFERENCES public.partner_compliance_requirements(id) ON DELETE SET NULL,
    partner_contract_id uuid REFERENCES public.partner_contracts(id) ON DELETE SET NULL,
    claim_type text NOT NULL,
    priority text NOT NULL DEFAULT 'medium',
    status text NOT NULL DEFAULT 'open',
    subject text NOT NULL,
    description text NOT NULL,
    reported_at timestamptz NOT NULL DEFAULT now(),
    reported_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    responsible_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    customer_contact_id uuid REFERENCES public.business_contacts(id) ON DELETE SET NULL,
    provider_contact_id uuid REFERENCES public.business_contacts(id) ON DELETE SET NULL,
    response_due_at timestamptz,
    resolution_due_at timestamptz,
    first_responded_at timestamptz,
    resolved_at timestamptz,
    closed_at timestamptz,
    cancelled_at timestamptz,
    resolution_summary text,
    responsibility text NOT NULL DEFAULT 'undetermined',
    responsibility_note text,
    root_cause text NOT NULL DEFAULT 'unknown',
    root_cause_note text,
    settlement_amount numeric(18,2),
    settlement_currency text,
    settlement_type text,
    settlement_date date,
    settlement_notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT service_claims_number_key UNIQUE (tenant_id,claim_number),
    CONSTRAINT service_claims_context_check CHECK (num_nonnulls(operation_id,customer_id,provider_id) > 0),
    CONSTRAINT service_claims_type_check CHECK (claim_type IN ('delay','damage','shortage','loss','documentation','billing','service_quality','provider_performance','compliance','other')),
    CONSTRAINT service_claims_priority_check CHECK (priority IN ('critical','high','medium','low')),
    CONSTRAINT service_claims_status_check CHECK (status IN ('open','triage','investigating','awaiting_customer','awaiting_provider','action_in_progress','resolved','closed','cancelled')),
    CONSTRAINT service_claims_subject_check CHECK (char_length(btrim(subject)) BETWEEN 3 AND 180),
    CONSTRAINT service_claims_description_check CHECK (char_length(btrim(description)) BETWEEN 3 AND 10000),
    CONSTRAINT service_claims_responsibility_check CHECK (responsibility IN ('undetermined','internal','provider','customer','shared','external_other','no_fault')),
    CONSTRAINT service_claims_root_cause_check CHECK (root_cause IN ('carrier_delay','planning','documentation','communication','handling','customs','customer_instruction','provider_execution','weather_external','force_majeure_external','billing_process','unknown','other')),
    CONSTRAINT service_claims_settlement_check CHECK ((settlement_amount IS NULL AND settlement_currency IS NULL) OR (settlement_amount >= 0 AND settlement_currency IN ('MXN','USD'))),
    CONSTRAINT service_claims_resolved_check CHECK (status <> 'resolved' OR (resolved_at IS NOT NULL AND NULLIF(btrim(resolution_summary),'') IS NOT NULL)),
    CONSTRAINT service_claims_closed_check CHECK (status <> 'closed' OR (closed_at IS NOT NULL AND NULLIF(btrim(resolution_summary),'') IS NOT NULL)),
    CONSTRAINT service_claims_cancelled_check CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

CREATE TABLE public.service_claim_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_id uuid NOT NULL REFERENCES public.service_claims(id) ON DELETE CASCADE,
    event_type text NOT NULL,
    summary text NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata)='object'),
    actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT service_claim_events_type_check CHECK (event_type IN ('created','status_changed','assigned','note','customer_contact','provider_contact','evidence_added','exposure_changed','responsibility_changed','root_cause_changed','resolution','reopened','closed','cancelled','action_created','action_completed','settlement')),
    CONSTRAINT service_claim_events_summary_check CHECK (char_length(btrim(summary)) BETWEEN 1 AND 2000)
);

CREATE TABLE public.service_claim_actions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_id uuid NOT NULL REFERENCES public.service_claims(id) ON DELETE CASCADE,
    title text NOT NULL,
    owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at timestamptz,
    status text NOT NULL DEFAULT 'open',
    completed_at timestamptz,
    completion_note text,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT service_claim_actions_title_check CHECK (char_length(btrim(title)) BETWEEN 3 AND 240),
    CONSTRAINT service_claim_actions_status_check CHECK (status IN ('open','in_progress','done','cancelled')),
    CONSTRAINT service_claim_actions_completion_check CHECK (status <> 'done' OR completed_at IS NOT NULL)
);

CREATE TABLE public.service_claim_financials (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_id uuid NOT NULL REFERENCES public.service_claims(id) ON DELETE CASCADE,
    exposure_type text NOT NULL,
    amount numeric(18,2) NOT NULL CHECK (amount >= 0),
    currency text NOT NULL CHECK (currency IN ('MXN','USD')),
    status text NOT NULL DEFAULT 'estimated',
    note text,
    finance_reference text,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT service_claim_financials_type_check CHECK (exposure_type IN ('customer_claim','provider_recovery','internal_cost','credit_expected','deductible','other')),
    CONSTRAINT service_claim_financials_status_check CHECK (status IN ('estimated','approved_internal','settled','cancelled'))
);

CREATE TABLE public.service_claim_contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    claim_id uuid NOT NULL REFERENCES public.service_claims(id) ON DELETE CASCADE,
    party text NOT NULL CHECK (party IN ('customer','provider')),
    business_contact_id uuid NOT NULL REFERENCES public.business_contacts(id) ON DELETE RESTRICT,
    channel text NOT NULL CHECK (channel IN ('email','phone','meeting','whatsapp','other')),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    summary text NOT NULL CHECK (char_length(btrim(summary)) BETWEEN 1 AND 2000),
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX service_claims_tenant_status_updated_idx ON public.service_claims(tenant_id,status,updated_at DESC,id DESC);
CREATE INDEX service_claims_tenant_priority_open_idx ON public.service_claims(tenant_id,priority,response_due_at,resolution_due_at) WHERE status NOT IN ('resolved','closed','cancelled');
CREATE INDEX service_claims_operation_idx ON public.service_claims(operation_id) WHERE operation_id IS NOT NULL;
CREATE INDEX service_claims_customer_idx ON public.service_claims(tenant_id,customer_id,updated_at DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX service_claims_provider_idx ON public.service_claims(tenant_id,provider_id,updated_at DESC) WHERE provider_id IS NOT NULL;
CREATE INDEX service_claims_incident_idx ON public.service_claims(source_incident_id) WHERE source_incident_id IS NOT NULL;
CREATE INDEX service_claims_responsible_idx ON public.service_claims(tenant_id,responsible_user_id,status) WHERE responsible_user_id IS NOT NULL;
CREATE INDEX service_claim_events_claim_time_idx ON public.service_claim_events(claim_id,occurred_at DESC,id DESC);
CREATE INDEX service_claim_actions_claim_status_due_idx ON public.service_claim_actions(claim_id,status,due_at);
CREATE INDEX service_claim_actions_owner_due_idx ON public.service_claim_actions(tenant_id,owner_user_id,due_at) WHERE status IN ('open','in_progress');
CREATE INDEX service_claim_financials_claim_currency_idx ON public.service_claim_financials(claim_id,currency,status);
CREATE INDEX service_claim_contacts_claim_time_idx ON public.service_claim_contacts(claim_id,occurred_at DESC);
CREATE INDEX claim_service_policies_tenant_active_idx ON public.claim_service_policies(tenant_id,is_active,claim_type,priority);

ALTER TABLE public.claim_service_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_claim_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_claim_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_claim_financials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_claim_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY claim_service_policies_admin_f10 ON public.claim_service_policies FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY service_claims_admin_f10 ON public.service_claims FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY service_claim_events_admin_f10 ON public.service_claim_events FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY service_claim_actions_admin_f10 ON public.service_claim_actions FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY service_claim_financials_admin_f10 ON public.service_claim_financials FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
CREATE POLICY service_claim_contacts_admin_f10 ON public.service_claim_contacts FOR ALL TO authenticated
USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));

REVOKE ALL ON TABLE private.claim_number_sequences FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.claim_service_policies,public.service_claims,public.service_claim_events,public.service_claim_actions,public.service_claim_financials,public.service_claim_contacts FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER trg_claim_service_policies_touch BEFORE UPDATE ON public.claim_service_policies FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
CREATE TRIGGER trg_service_claims_touch BEFORE UPDATE ON public.service_claims FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
CREATE TRIGGER trg_service_claim_actions_touch BEFORE UPDATE ON public.service_claim_actions FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();
CREATE TRIGGER trg_service_claim_financials_touch BEFORE UPDATE ON public.service_claim_financials FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

-- Extend existing F3/F5/F7 constrained catalogs without replacing their RPCs.
ALTER TABLE public.document_files DROP CONSTRAINT document_files_source_type_check;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_type_check CHECK (source_entity_type IN ('operation','quote','customer','provider','billing_document','generated_document','finance_invoice','claim'));
ALTER TABLE public.document_files DROP CONSTRAINT document_files_source_module_check;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_module_check CHECK (source_module IN ('operations','commercial','billing','finance','documents','claims'));
ALTER TABLE public.user_saved_views DROP CONSTRAINT user_saved_views_module_check;
ALTER TABLE public.user_saved_views ADD CONSTRAINT user_saved_views_module_check CHECK (module IN ('operations','commercial','documents','finance','claims'));
ALTER TABLE public.automation_rules DROP CONSTRAINT automation_rules_code_check;
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_code_check CHECK (code IN (
 'operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale','quote_review_stale','quote_approved_not_converted','ar_overdue','ap_overdue','finance_due_today','finance_due_soon','partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring',
 'claim_first_response_overdue','claim_resolution_overdue','claim_action_overdue','critical_claim_open'
));
ALTER TABLE public.automation_rules DROP CONSTRAINT automation_rules_module_check;
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_module_check CHECK (module IN ('operations','commercial','documents','finance','claims'));
ALTER TABLE public.automation_rules ADD CONSTRAINT automation_rules_claims_admin_only_check CHECK (module<>'claims' OR target_role='admin');
ALTER TABLE public.internal_notifications DROP CONSTRAINT internal_notifications_area_check;
ALTER TABLE public.internal_notifications ADD CONSTRAINT internal_notifications_area_check CHECK (area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin','claims'));
ALTER TABLE public.internal_notifications DROP CONSTRAINT internal_notifications_trigger_check;
ALTER TABLE public.internal_notifications ADD CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN (
 'daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending','blocking_incident','delivered_without_pod','dispatch_blocker','required_document_missing','billing_blocked','ar_overdue','ap_overdue','finance_due_soon','quote_in_review','quote_pending_conversion','operation_dispatch_blocked','operation_blocking_incident','operation_missing_document','operation_pod_missing','operation_billing_blocked','operation_stale','quote_review_stale','quote_approved_not_converted','finance_due_today','partner_document_expiring','partner_document_expired','partner_contract_expiring','rate_expiring',
 'claim_first_response_overdue','claim_resolution_overdue','claim_action_overdue','critical_claim_open'
));

-- Additional Storage policies are OR-composed with F3 and only authorize Admin
-- paths shaped tenant/claims/claim/<claim-id>/<uuid.ext>.
CREATE POLICY tenant_documents_select_f10_claims ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='tenant-documents' AND split_part(name,'/',2)='claims' AND (SELECT public.tanda1_user_has_role(private.f3_storage_tenant_from_path(name),ARRAY['admin'])));
CREATE POLICY tenant_documents_insert_f10_claims ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='tenant-documents' AND owner_id=(SELECT auth.uid())::text AND split_part(name,'/',2)='claims' AND (SELECT public.tanda1_user_has_role(private.f3_storage_tenant_from_path(name),ARRAY['admin'])));
CREATE POLICY tenant_documents_update_f10_claims ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id='tenant-documents' AND owner_id=(SELECT auth.uid())::text AND split_part(name,'/',2)='claims' AND (SELECT public.tanda1_user_has_role(private.f3_storage_tenant_from_path(name),ARRAY['admin'])))
WITH CHECK (bucket_id='tenant-documents' AND owner_id=(SELECT auth.uid())::text AND split_part(name,'/',2)='claims' AND (SELECT public.tanda1_user_has_role(private.f3_storage_tenant_from_path(name),ARRAY['admin'])));
CREATE POLICY tenant_documents_delete_orphan_f10_claims ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='tenant-documents' AND owner_id=(SELECT auth.uid())::text AND split_part(name,'/',2)='claims' AND (SELECT public.tanda1_user_has_role(private.f3_storage_tenant_from_path(name),ARRAY['admin'])) AND NOT EXISTS(SELECT 1 FROM public.document_files f WHERE f.storage_bucket='tenant-documents' AND f.storage_path=name));

CREATE FUNCTION private.f10_admin(p_tenant_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ SELECT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) $function$;

CREATE FUNCTION private.f10_business_year(p_tenant_id uuid,p_at timestamptz)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_timezone text;
BEGIN
 SELECT COALESCE(NULLIF(s.timezone,''),'America/Mexico_City') INTO v_timezone FROM public.tenant_settings s WHERE s.tenant_id=p_tenant_id;
 v_timezone:=COALESCE(v_timezone,'America/Mexico_City');
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN v_timezone:='America/Mexico_City';END IF;
 RETURN extract(year FROM p_at AT TIME ZONE v_timezone)::integer;
END $function$;

CREATE FUNCTION private.f10_next_claim_number(p_tenant_id uuid,p_year integer)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_value bigint;
BEGIN
 INSERT INTO private.claim_number_sequences(tenant_id,calendar_year,last_value) VALUES(p_tenant_id,p_year,1)
 ON CONFLICT(tenant_id,calendar_year) DO UPDATE SET last_value=private.claim_number_sequences.last_value+1
 RETURNING last_value INTO v_value;
 RETURN 'CLM-'||p_year||'-'||lpad(v_value::text,6,'0');
END $function$;

CREATE FUNCTION private.f10_seed_policies(p_tenant_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_count integer;
BEGIN
 INSERT INTO public.claim_service_policies(tenant_id,claim_type,priority,first_response_hours,resolution_hours)
 VALUES (p_tenant_id,'all','critical',2,24),(p_tenant_id,'all','high',4,48),(p_tenant_id,'all','medium',8,96),(p_tenant_id,'all','low',24,168)
 ON CONFLICT(tenant_id,claim_type,priority) DO NOTHING;
 GET DIAGNOSTICS v_count=ROW_COUNT;RETURN v_count;
END $function$;
SELECT private.f10_seed_policies(t.id) FROM public.tenants t;

CREATE FUNCTION private.f10_seed_policies_for_tenant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN PERFORM private.f10_seed_policies(NEW.id);RETURN NEW;END $function$;
CREATE TRIGGER trg_f10_seed_claim_policies AFTER INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION private.f10_seed_policies_for_tenant();

CREATE FUNCTION private.f10_policy(p_tenant_id uuid,p_claim_type text,p_priority text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
 SELECT COALESCE((SELECT jsonb_build_object('id',p.id,'first_response_hours',p.first_response_hours,'resolution_hours',p.resolution_hours,'claim_type',p.claim_type)
 FROM public.claim_service_policies p WHERE p.tenant_id=p_tenant_id AND p.is_active AND p.priority=p_priority AND p.claim_type IN (p_claim_type,'all')
 ORDER BY (p.claim_type=p_claim_type) DESC LIMIT 1),'{}'::jsonb)
$function$;

CREATE FUNCTION private.f10_sla(p_claim public.service_claims,p_as_of timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
 SELECT jsonb_build_object(
  'first_response_due_at',p_claim.response_due_at,'resolution_due_at',p_claim.resolution_due_at,
  'first_responded_at',p_claim.first_responded_at,
  'first_response_overdue',p_claim.first_responded_at IS NULL AND p_claim.status NOT IN ('resolved','closed','cancelled') AND p_claim.response_due_at IS NOT NULL AND p_claim.response_due_at<p_as_of,
  'resolution_overdue',p_claim.status NOT IN ('resolved','closed','cancelled') AND p_claim.resolution_due_at IS NOT NULL AND p_claim.resolution_due_at<p_as_of
 )
$function$;

CREATE FUNCTION private.f10_add_event(p_claim public.service_claims,p_type text,p_summary text,p_metadata jsonb DEFAULT '{}'::jsonb,p_occurred_at timestamptz DEFAULT now())
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_id uuid;
BEGIN INSERT INTO public.service_claim_events(tenant_id,claim_id,event_type,summary,metadata,actor_user_id,occurred_at)
 VALUES(p_claim.tenant_id,p_claim.id,p_type,btrim(p_summary),COALESCE(p_metadata,'{}'::jsonb),auth.uid(),p_occurred_at) RETURNING id INTO v_id;RETURN v_id;END $function$;

CREATE FUNCTION private.f10_transition_allowed(p_from text,p_to text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog
AS $function$
 SELECT CASE p_from
  WHEN 'open' THEN p_to IN ('triage','cancelled')
  WHEN 'triage' THEN p_to IN ('investigating','awaiting_customer','awaiting_provider','action_in_progress','resolved','cancelled')
  WHEN 'investigating' THEN p_to IN ('awaiting_customer','awaiting_provider','action_in_progress','resolved','cancelled')
  WHEN 'awaiting_customer' THEN p_to IN ('investigating','action_in_progress','resolved','cancelled')
  WHEN 'awaiting_provider' THEN p_to IN ('investigating','action_in_progress','resolved','cancelled')
  WHEN 'action_in_progress' THEN p_to IN ('investigating','awaiting_customer','awaiting_provider','resolved','cancelled')
  WHEN 'resolved' THEN p_to='closed'
  ELSE false END
$function$;

CREATE FUNCTION public.rpc_upsert_claim_service_policy(p_tenant_id uuid,p_policy_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_id uuid;v_type text:=COALESCE(NULLIF(p_payload->>'claim_type',''),'all');v_priority text:=p_payload->>'priority';v_response integer;v_resolution integer;
BEGIN
 IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 BEGIN v_response:=(p_payload->>'first_response_hours')::integer;v_resolution:=(p_payload->>'resolution_hours')::integer;EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF p_policy_id IS NULL THEN INSERT INTO public.claim_service_policies(tenant_id,claim_type,priority,first_response_hours,resolution_hours,is_active,created_by)
 VALUES(p_tenant_id,v_type,v_priority,v_response,v_resolution,COALESCE((p_payload->>'is_active')::boolean,true),auth.uid()) RETURNING id INTO v_id;
 ELSE UPDATE public.claim_service_policies SET claim_type=v_type,priority=v_priority,first_response_hours=v_response,resolution_hours=v_resolution,is_active=COALESCE((p_payload->>'is_active')::boolean,true)
 WHERE id=p_policy_id AND tenant_id=p_tenant_id RETURNING id INTO v_id;IF v_id IS NULL THEN RETURN jsonb_build_object('error','not_found');END IF;END IF;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'claim_service_policy_upserted','claim_service_policy',v_id,jsonb_build_object('claim_type',v_type,'priority',v_priority));
 RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN check_violation OR unique_violation THEN RETURN jsonb_build_object('error','invalid_policy');END $function$;

CREATE FUNCTION public.rpc_create_service_claim(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_operation public.operations%ROWTYPE;v_incident public.operation_incidents%ROWTYPE;v_operation_id uuid;v_customer uuid;v_provider uuid;v_incident_id uuid;v_responsible uuid;v_customer_contact uuid;v_provider_contact uuid;v_requirement uuid;v_contract uuid;v_type text:=p_payload->>'claim_type';v_priority text:=COALESCE(NULLIF(p_payload->>'priority',''),'medium');v_subject text:=NULLIF(btrim(p_payload->>'subject'),'');v_description text:=NULLIF(btrim(p_payload->>'description'),'');v_reported timestamptz;v_policy jsonb;v_id uuid;v_number text;v_response integer;v_resolution integer;v_claim public.service_claims%ROWTYPE;
BEGIN
 IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 BEGIN
  v_operation_id:=NULLIF(p_payload->>'operation_id','')::uuid;v_customer:=NULLIF(p_payload->>'customer_id','')::uuid;v_provider:=NULLIF(p_payload->>'provider_id','')::uuid;v_incident_id:=NULLIF(p_payload->>'source_incident_id','')::uuid;v_responsible:=NULLIF(p_payload->>'responsible_user_id','')::uuid;v_customer_contact:=NULLIF(p_payload->>'customer_contact_id','')::uuid;v_provider_contact:=NULLIF(p_payload->>'provider_contact_id','')::uuid;v_requirement:=NULLIF(p_payload->>'compliance_requirement_id','')::uuid;v_contract:=NULLIF(p_payload->>'partner_contract_id','')::uuid;v_reported:=COALESCE(NULLIF(p_payload->>'reported_at','')::timestamptz,now());
 EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF v_incident_id IS NOT NULL THEN
  SELECT * INTO v_incident FROM public.operation_incidents WHERE id=v_incident_id AND tenant_id=p_tenant_id;
  IF NOT FOUND OR (v_operation_id IS NOT NULL AND v_operation_id<>v_incident.operation_id) THEN RETURN jsonb_build_object('error','invalid_incident');END IF;
  v_operation_id:=v_incident.operation_id;v_subject:=COALESCE(v_subject,v_incident.title);v_description:=COALESCE(v_description,v_incident.description,v_incident.title);
 END IF;
 IF v_operation_id IS NOT NULL THEN
  SELECT * INTO v_operation FROM public.operations WHERE id=v_operation_id AND tenant_id=p_tenant_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_operation');END IF;
  v_customer:=COALESCE(v_customer,v_operation.customer_id);v_provider:=COALESCE(v_provider,v_operation.provider_id);
 END IF;
 IF v_operation_id IS NULL AND v_customer IS NULL AND v_provider IS NULL THEN RETURN jsonb_build_object('error','missing_context');END IF;
 IF v_customer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_customer AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_customer');END IF;
 IF v_provider IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_provider AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_provider');END IF;
 IF v_responsible IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.memberships WHERE tenant_id=p_tenant_id AND user_id=v_responsible AND role='admin') THEN RETURN jsonb_build_object('error','invalid_responsible');END IF;
 IF v_customer_contact IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.business_contacts WHERE id=v_customer_contact AND tenant_id=p_tenant_id AND customer_id=v_customer) THEN RETURN jsonb_build_object('error','invalid_contact');END IF;
 IF v_provider_contact IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.business_contacts WHERE id=v_provider_contact AND tenant_id=p_tenant_id AND provider_id=v_provider) THEN RETURN jsonb_build_object('error','invalid_contact');END IF;
 IF v_requirement IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.partner_compliance_requirements WHERE id=v_requirement AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_compliance_link');END IF;
 IF v_contract IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.partner_contracts WHERE id=v_contract AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_contract_link');END IF;
 IF v_subject IS NULL OR v_description IS NULL THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 v_policy:=private.f10_policy(p_tenant_id,v_type,v_priority);v_response:=NULLIF(v_policy->>'first_response_hours','')::integer;v_resolution:=NULLIF(v_policy->>'resolution_hours','')::integer;
 v_number:=private.f10_next_claim_number(p_tenant_id,private.f10_business_year(p_tenant_id,v_reported));
 INSERT INTO public.service_claims(tenant_id,claim_number,operation_id,customer_id,provider_id,source_incident_id,compliance_requirement_id,partner_contract_id,claim_type,priority,subject,description,reported_at,reported_by,responsible_user_id,customer_contact_id,provider_contact_id,response_due_at,resolution_due_at)
 VALUES(p_tenant_id,v_number,v_operation_id,v_customer,v_provider,v_incident_id,v_requirement,v_contract,v_type,v_priority,v_subject,v_description,v_reported,auth.uid(),v_responsible,v_customer_contact,v_provider_contact,CASE WHEN v_response IS NULL THEN NULL ELSE v_reported+make_interval(hours=>v_response) END,CASE WHEN v_resolution IS NULL THEN NULL ELSE v_reported+make_interval(hours=>v_resolution) END)
 RETURNING * INTO v_claim;v_id:=v_claim.id;
 PERFORM private.f10_add_event(v_claim,'created','Reclamación creada',jsonb_build_object('claim_number',v_number,'operation_id',v_operation_id,'incident_id',v_incident_id,'incident_title',v_incident.title,'incident_description',v_incident.description,'sla_policy_id',v_policy->>'id'));
 IF v_responsible IS NOT NULL THEN PERFORM private.f10_add_event(v_claim,'assigned','Responsable asignado',jsonb_build_object('responsible_user_id',v_responsible));END IF;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'service_claim_created','service_claim',v_id,jsonb_build_object('claim_number',v_number,'operation_id',v_operation_id,'customer_id',v_customer,'provider_id',v_provider,'source_incident_id',v_incident_id));
 RETURN jsonb_build_object('id',v_id,'claim_number',v_number);
EXCEPTION WHEN check_violation OR not_null_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');END $function$;

CREATE FUNCTION public.rpc_create_service_claim_from_incident(p_incident_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_tenant uuid;
BEGIN SELECT tenant_id INTO v_tenant FROM public.operation_incidents WHERE id=p_incident_id;IF v_tenant IS NULL THEN RETURN jsonb_build_object('error','not_found');END IF;
 RETURN public.rpc_create_service_claim(v_tenant,COALESCE(p_payload,'{}'::jsonb)||jsonb_build_object('source_incident_id',p_incident_id));END $function$;

CREATE FUNCTION public.rpc_get_claim_reference_data(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN
 IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN jsonb_build_object(
  'operations',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'reference_code',o.reference_code,'status',o.status,'customer_id',o.customer_id,'provider_id',o.provider_id) ORDER BY o.created_at DESC) FROM (SELECT * FROM public.operations WHERE tenant_id=p_tenant_id ORDER BY created_at DESC LIMIT 200)o),'[]'::jsonb),
  'customers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'display_name',c.display_name) ORDER BY c.display_name) FROM public.customers c WHERE c.tenant_id=p_tenant_id AND c.is_active),'[]'::jsonb),
  'providers',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) ORDER BY p.display_name) FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id AND p.is_active),'[]'::jsonb),
  'members',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_id',m.user_id,'email',COALESCE(u.email,m.user_id::text)) ORDER BY COALESCE(u.email,m.user_id::text)) FROM public.memberships m LEFT JOIN auth.users u ON u.id=m.user_id WHERE m.tenant_id=p_tenant_id AND m.role='admin'),'[]'::jsonb),
  'policies',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.claim_type,p.priority) FROM public.claim_service_policies p WHERE p.tenant_id=p_tenant_id),'[]'::jsonb));
END $function$;

CREATE FUNCTION public.rpc_list_service_claims(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_limit integer:=least(greatest(COALESCE(NULLIF(p_filters->>'limit','')::integer,100),1),200);v_query text:=NULLIF(lower(btrim(p_filters->>'query')),'');v_customer uuid:=NULLIF(p_filters->>'customer_id','')::uuid;v_provider uuid:=NULLIF(p_filters->>'provider_id','')::uuid;v_operation uuid:=NULLIF(p_filters->>'operation_id','')::uuid;v_responsible uuid:=NULLIF(p_filters->>'responsible_user_id','')::uuid;v_breached boolean:=COALESCE((p_filters->>'sla_breached')::boolean,false);
BEGIN
 IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'updated_at')::timestamptz DESC) FROM (
  SELECT jsonb_build_object('id',c.id,'claim_number',c.claim_number,'subject',c.subject,'claim_type',c.claim_type,'priority',c.priority,'status',c.status,'operation_id',c.operation_id,'operation_reference',o.reference_code,'customer_id',c.customer_id,'customer_name',cu.display_name,'provider_id',c.provider_id,'provider_name',p.display_name,'responsible_user_id',c.responsible_user_id,'responsible_label',COALESCE(u.email,c.responsible_user_id::text),'responsibility',c.responsibility,'root_cause',c.root_cause,'reported_at',c.reported_at,'resolved_at',c.resolved_at,'closed_at',c.closed_at,'updated_at',c.updated_at,'sla',private.f10_sla(c,now()),'exposure_by_currency',COALESCE(exposure.items,'[]'::jsonb)) x
  FROM public.service_claims c
  LEFT JOIN public.operations o ON o.id=c.operation_id LEFT JOIN public.customers cu ON cu.id=c.customer_id LEFT JOIN public.logistics_providers p ON p.id=c.provider_id LEFT JOIN auth.users u ON u.id=c.responsible_user_id
  LEFT JOIN LATERAL(SELECT jsonb_agg(jsonb_build_object('currency',f.currency,'amount',f.amount) ORDER BY f.currency) items FROM (SELECT currency,sum(amount) amount FROM public.service_claim_financials WHERE claim_id=c.id AND status<>'cancelled' GROUP BY currency)f)exposure ON true
  WHERE c.tenant_id=p_tenant_id
    AND (NOT(p_filters?'status') OR c.status=ANY(string_to_array(p_filters->>'status',',')))
    AND (NOT(p_filters?'priority') OR c.priority=p_filters->>'priority')
    AND (NOT(p_filters?'claim_type') OR c.claim_type=p_filters->>'claim_type')
    AND (v_customer IS NULL OR c.customer_id=v_customer) AND (v_provider IS NULL OR c.provider_id=v_provider) AND (v_operation IS NULL OR c.operation_id=v_operation) AND (v_responsible IS NULL OR c.responsible_user_id=v_responsible)
    AND (NOT v_breached OR COALESCE((private.f10_sla(c,now())->>'first_response_overdue')::boolean,false) OR COALESCE((private.f10_sla(c,now())->>'resolution_overdue')::boolean,false))
    AND (NOT(p_filters?'date_from') OR c.reported_at>=(p_filters->>'date_from')::date) AND (NOT(p_filters?'date_to') OR c.reported_at<(p_filters->>'date_to')::date+1)
    AND (v_query IS NULL OR position(v_query IN lower(concat_ws(' ',c.claim_number,c.subject,o.reference_code,cu.display_name,p.display_name)))>0)
  ORDER BY c.updated_at DESC LIMIT v_limit
 )q),'[]'::jsonb);
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_filters');END $function$;

CREATE FUNCTION public.rpc_get_service_claim(p_claim_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_operation jsonb;v_quote jsonb;v_rate jsonb;
BEGIN
 SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT jsonb_build_object('id',o.id,'reference',o.reference_code,'status',o.status,'route','/operations?operationId='||o.id,'service_type',o.service_type,'service_catalog_snapshot',o.service_catalog_snapshot,'origin_place',o.origin_place,'destination_place',o.destination_place,'planned_departure',o.planned_departure,'operational_window_start',o.operational_window_start,'operational_window_end',o.operational_window_end,'eta',o.eta,'pricing_currency',o.pricing_currency,'sell_amount',o.customer_price_amount,'provider_cost',o.provider_cost_amount,'source_deal_id',o.source_deal_id,
 'pod_present',EXISTS(SELECT 1 FROM public.operation_documents od WHERE od.operation_id=o.id AND od.document_type='proof_of_delivery' AND od.status='present'),
 'incidents',COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.reported_at DESC) FROM public.operation_incidents i WHERE i.operation_id=o.id),'[]'::jsonb),
 'operation_documents',COALESCE((SELECT jsonb_agg(to_jsonb(od) ORDER BY od.updated_at DESC) FROM public.operation_documents od WHERE od.operation_id=o.id),'[]'::jsonb),
 'private_documents',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',f.id,'file_name',f.file_name,'file_kind',f.file_kind,'status',f.status,'created_at',f.created_at) ORDER BY f.created_at DESC) FROM public.document_files f WHERE f.tenant_id=o.tenant_id AND f.status='active' AND ((f.source_entity_type='operation' AND f.source_entity_id=o.id) OR EXISTS(SELECT 1 FROM public.document_relations dr WHERE dr.document_file_id=f.id AND dr.target_entity_type='operation' AND dr.target_entity_id=o.id))),'[]'::jsonb)) INTO v_operation FROM public.operations o WHERE o.id=c.operation_id;
 SELECT jsonb_build_object('id',d.id,'reference',d.quote_reference,'status',d.quote_status,'currency',d.currency,'sell_amount',COALESCE(NULLIF(d.quote_payload->>'customer_price_amount','')::numeric,d.value),'provider_cost',NULLIF(d.quote_payload->>'provider_cost_amount','')::numeric,'route','/commercial?view=quotes&quoteId='||d.id) INTO v_quote FROM public.crm_deals d WHERE d.id=(SELECT source_deal_id FROM public.operations WHERE id=c.operation_id);
 SELECT jsonb_build_object('rate_card_id',s.rate_card_id,'rate_version_id',s.rate_version_id,'rate_type',s.rate_type,'currency',s.currency,'total_amount',s.total_amount,'selected_at',s.selected_at) INTO v_rate FROM public.crm_quote_rate_snapshots s WHERE s.deal_id=(SELECT source_deal_id FROM public.operations WHERE id=c.operation_id) ORDER BY s.selected_at DESC LIMIT 1;
 RETURN to_jsonb(c)||jsonb_build_object(
  'sla',private.f10_sla(c,now()),'customer',(SELECT to_jsonb(x) FROM (SELECT id,display_name FROM public.customers WHERE id=c.customer_id)x),'provider',(SELECT to_jsonb(x) FROM (SELECT id,display_name FROM public.logistics_providers WHERE id=c.provider_id)x),'operation',v_operation,'quote',v_quote,'rate_snapshot',v_rate,
  'source_incident',(SELECT to_jsonb(x) FROM (SELECT id,category,title,description,status,is_blocking,reported_at,resolved_at FROM public.operation_incidents WHERE id=c.source_incident_id)x),
  'compliance_requirement',(SELECT to_jsonb(x) FROM (SELECT id,code,name,category,is_required,is_blocking FROM public.partner_compliance_requirements WHERE id=c.compliance_requirement_id)x),
  'partner_contract',(SELECT to_jsonb(x) FROM (SELECT id,title,reference,status,starts_on,ends_on FROM public.partner_contracts WHERE id=c.partner_contract_id)x),
  'events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.occurred_at DESC,e.id DESC) FROM public.service_claim_events e WHERE e.claim_id=c.id),'[]'::jsonb),
  'actions',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY (a.status='done'),a.due_at NULLS LAST,a.created_at) FROM public.service_claim_actions a WHERE a.claim_id=c.id),'[]'::jsonb),
  'financials',COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC) FROM public.service_claim_financials f WHERE f.claim_id=c.id),'[]'::jsonb),
  'exposure_by_currency',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',x.currency,'amount',x.amount) ORDER BY x.currency) FROM (SELECT currency,sum(amount) amount FROM public.service_claim_financials WHERE claim_id=c.id AND status<>'cancelled' GROUP BY currency)x),'[]'::jsonb),
  'contacts',COALESCE((SELECT jsonb_agg(to_jsonb(l)||jsonb_build_object('contact_name',b.name,'email',b.email,'phone',b.phone) ORDER BY l.occurred_at DESC) FROM public.service_claim_contacts l JOIN public.business_contacts b ON b.id=l.business_contact_id WHERE l.claim_id=c.id),'[]'::jsonb),
  'available_contacts',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',b.id,'party',CASE WHEN b.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END,'name',b.name,'email',b.email,'phone',b.phone) ORDER BY b.name) FROM public.business_contacts b WHERE b.tenant_id=c.tenant_id AND b.is_active AND ((b.customer_id IS NOT NULL AND b.customer_id=c.customer_id) OR (b.provider_id IS NOT NULL AND b.provider_id=c.provider_id))),'[]'::jsonb),
  'available_responsibles',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',m.user_id,'label',COALESCE(u.email,m.user_id::text)) ORDER BY COALESCE(u.email,m.user_id::text)) FROM public.memberships m LEFT JOIN auth.users u ON u.id=m.user_id WHERE m.tenant_id=c.tenant_id AND m.role='admin'),'[]'::jsonb),
  'documents',COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC) FROM public.document_relations r JOIN public.document_files f ON f.id=r.document_file_id WHERE r.tenant_id=c.tenant_id AND r.target_entity_type='claim' AND r.target_entity_id=c.id AND f.status='active'),'[]'::jsonb));
END $function$;

CREATE FUNCTION public.rpc_transition_service_claim(p_claim_id uuid,p_to_status text,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_note text:=NULLIF(btrim(COALESCE(p_note,'')),'');v_type text;v_from text;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF NOT private.f10_transition_allowed(c.status,p_to_status) THEN RETURN jsonb_build_object('error','invalid_transition');END IF;
 IF p_to_status IN ('resolved','closed','cancelled') AND v_note IS NULL THEN RETURN jsonb_build_object('error','reason_required');END IF;
 v_from:=c.status;
 UPDATE public.service_claims SET status=p_to_status,resolved_at=CASE WHEN p_to_status='resolved' THEN now() ELSE resolved_at END,closed_at=CASE WHEN p_to_status='closed' THEN now() ELSE closed_at END,cancelled_at=CASE WHEN p_to_status='cancelled' THEN now() ELSE cancelled_at END,resolution_summary=CASE WHEN p_to_status IN ('resolved','closed') THEN COALESCE(v_note,resolution_summary) ELSE resolution_summary END WHERE id=c.id RETURNING * INTO c;
 v_type:=CASE p_to_status WHEN 'resolved' THEN 'resolution' WHEN 'closed' THEN 'closed' WHEN 'cancelled' THEN 'cancelled' ELSE 'status_changed' END;
 PERFORM private.f10_add_event(c,v_type,COALESCE(v_note,'Estado actualizado a '||p_to_status),jsonb_build_object('from_status',v_from,'to_status',p_to_status));
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_status_changed','service_claim',c.id,jsonb_build_object('to_status',p_to_status,'reason',v_note));
 RETURN jsonb_build_object('success',true,'status',p_to_status);
END $function$;

CREATE FUNCTION public.rpc_reopen_service_claim(p_claim_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_reason text:=NULLIF(btrim(COALESCE(p_reason,'')),'');v_prior jsonb;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF c.status NOT IN ('resolved','closed') OR v_reason IS NULL THEN RETURN jsonb_build_object('error','invalid_reopen');END IF;
 v_prior:=jsonb_build_object('prior_status',c.status,'prior_resolution',c.resolution_summary,'prior_resolved_at',c.resolved_at,'prior_closed_at',c.closed_at);
 UPDATE public.service_claims SET status='investigating',resolved_at=NULL,closed_at=NULL WHERE id=c.id RETURNING * INTO c;
 PERFORM private.f10_add_event(c,'reopened',v_reason,v_prior);INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_reopened','service_claim',c.id,v_prior||jsonb_build_object('reason',v_reason));
 RETURN jsonb_build_object('success',true,'status','investigating');END $function$;

CREATE FUNCTION public.rpc_assign_service_claim(p_claim_id uuid,p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF p_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.memberships WHERE tenant_id=c.tenant_id AND user_id=p_user_id AND role='admin') THEN RETURN jsonb_build_object('error','invalid_responsible');END IF;
 UPDATE public.service_claims SET responsible_user_id=p_user_id WHERE id=c.id RETURNING * INTO c;PERFORM private.f10_add_event(c,'assigned',CASE WHEN p_user_id IS NULL THEN 'Responsable removido' ELSE 'Responsable asignado' END,jsonb_build_object('responsible_user_id',p_user_id));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_assigned','service_claim',c.id,jsonb_build_object('responsible_user_id',p_user_id));RETURN jsonb_build_object('success',true);END $function$;

CREATE FUNCTION public.rpc_update_claim_classification(p_claim_id uuid,p_responsibility text,p_root_cause text,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_note text:=NULLIF(btrim(COALESCE(p_note,'')),'');v_material boolean;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 v_material:=c.priority IN ('critical','high') OR EXISTS(SELECT 1 FROM public.service_claim_financials WHERE claim_id=c.id AND status<>'cancelled' AND amount>0);
 IF p_responsibility<>'undetermined' AND v_material AND v_note IS NULL THEN RETURN jsonb_build_object('error','responsibility_note_required');END IF;
 UPDATE public.service_claims SET responsibility=p_responsibility,responsibility_note=COALESCE(v_note,responsibility_note),root_cause=p_root_cause,root_cause_note=CASE WHEN p_root_cause='other' THEN v_note ELSE root_cause_note END WHERE id=c.id RETURNING * INTO c;
 PERFORM private.f10_add_event(c,'responsibility_changed','Clasificación operativa actualizada',jsonb_build_object('responsibility',p_responsibility,'root_cause',p_root_cause,'note',v_note));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_classification_changed','service_claim',c.id,jsonb_build_object('responsibility',p_responsibility,'root_cause',p_root_cause,'note',v_note));RETURN jsonb_build_object('success',true);
EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('error','invalid_classification');END $function$;

CREATE FUNCTION public.rpc_add_claim_note(p_claim_id uuid,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE c public.service_claims%ROWTYPE;v_note text:=NULLIF(btrim(COALESCE(p_note,'')),'');v_id uuid;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v_note IS NULL THEN RETURN jsonb_build_object('error','note_required');END IF;v_id:=private.f10_add_event(c,'note',v_note);RETURN jsonb_build_object('id',v_id);END $function$;

CREATE FUNCTION public.rpc_log_claim_contact(p_claim_id uuid,p_party text,p_contact_id uuid,p_channel text,p_summary text,p_occurred_at timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_id uuid;v_summary text:=NULLIF(btrim(COALESCE(p_summary,'')),'');
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v_summary IS NULL OR NOT EXISTS(SELECT 1 FROM public.business_contacts b WHERE b.id=p_contact_id AND b.tenant_id=c.tenant_id AND ((p_party='customer' AND b.customer_id=c.customer_id) OR (p_party='provider' AND b.provider_id=c.provider_id))) THEN RETURN jsonb_build_object('error','invalid_contact');END IF;
 INSERT INTO public.service_claim_contacts(tenant_id,claim_id,party,business_contact_id,channel,occurred_at,summary,created_by) VALUES(c.tenant_id,c.id,p_party,p_contact_id,p_channel,COALESCE(p_occurred_at,now()),v_summary,auth.uid()) RETURNING id INTO v_id;
 UPDATE public.service_claims SET first_responded_at=COALESCE(first_responded_at,COALESCE(p_occurred_at,now())) WHERE id=c.id RETURNING * INTO c;
 PERFORM private.f10_add_event(c,CASE p_party WHEN 'customer' THEN 'customer_contact' ELSE 'provider_contact' END,v_summary,jsonb_build_object('contact_id',p_contact_id,'channel',p_channel),COALESCE(p_occurred_at,now()));RETURN jsonb_build_object('id',v_id,'first_responded_at',c.first_responded_at);
EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('error','invalid_contact');END $function$;

CREATE FUNCTION public.rpc_upsert_claim_action(p_claim_id uuid,p_action_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_id uuid;v_owner uuid;v_due timestamptz;v_title text:=NULLIF(btrim(p_payload->>'title'),'');
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 BEGIN v_owner:=NULLIF(p_payload->>'owner_user_id','')::uuid;v_due:=NULLIF(p_payload->>'due_at','')::timestamptz;EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF v_title IS NULL OR (v_owner IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.memberships WHERE tenant_id=c.tenant_id AND user_id=v_owner AND role='admin')) THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 IF p_action_id IS NULL THEN INSERT INTO public.service_claim_actions(tenant_id,claim_id,title,owner_user_id,due_at,created_by) VALUES(c.tenant_id,c.id,v_title,v_owner,v_due,auth.uid()) RETURNING id INTO v_id;
 ELSE UPDATE public.service_claim_actions SET title=v_title,owner_user_id=v_owner,due_at=v_due WHERE id=p_action_id AND claim_id=c.id AND status NOT IN ('done','cancelled') RETURNING id INTO v_id;IF v_id IS NULL THEN RETURN jsonb_build_object('error','action_immutable');END IF;END IF;
 PERFORM private.f10_add_event(c,'action_created','Acción: '||v_title,jsonb_build_object('action_id',v_id,'owner_user_id',v_owner,'due_at',v_due));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_action_upserted','service_claim_action',v_id,jsonb_build_object('claim_id',c.id,'owner_user_id',v_owner,'due_at',v_due));RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('error','invalid_payload');END $function$;

CREATE FUNCTION public.rpc_update_claim_action_status(p_action_id uuid,p_status text,p_completion_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE a public.service_claim_actions%ROWTYPE;c public.service_claims%ROWTYPE;v_note text:=NULLIF(btrim(COALESCE(p_completion_note,'')),'');
BEGIN SELECT * INTO a FROM public.service_claim_actions WHERE id=p_action_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;SELECT * INTO c FROM public.service_claims WHERE id=a.claim_id;IF NOT private.f10_admin(a.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_status NOT IN ('open','in_progress','done','cancelled') OR (p_status='done' AND v_note IS NULL) THEN RETURN jsonb_build_object('error','invalid_action_status');END IF;
 UPDATE public.service_claim_actions SET status=p_status,completed_at=CASE WHEN p_status='done' THEN now() ELSE NULL END,completion_note=CASE WHEN p_status='done' THEN v_note ELSE completion_note END WHERE id=a.id RETURNING * INTO a;
 IF p_status='done' THEN PERFORM private.f10_add_event(c,'action_completed',a.title,jsonb_build_object('action_id',a.id,'completion_note',v_note));END IF;INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(a.tenant_id,auth.uid(),'service_claim_action_status_changed','service_claim_action',a.id,jsonb_build_object('claim_id',a.claim_id,'status',p_status));RETURN jsonb_build_object('success',true,'status',p_status);END $function$;

CREATE FUNCTION public.rpc_upsert_claim_financial(p_claim_id uuid,p_financial_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_id uuid;v_amount numeric;v_type text:=p_payload->>'exposure_type';v_currency text:=upper(p_payload->>'currency');v_status text:=COALESCE(NULLIF(p_payload->>'status',''),'estimated');v_note text:=NULLIF(btrim(p_payload->>'note'),'');
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;BEGIN v_amount:=(p_payload->>'amount')::numeric;EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF p_financial_id IS NULL THEN INSERT INTO public.service_claim_financials(tenant_id,claim_id,exposure_type,amount,currency,status,note,finance_reference,created_by) VALUES(c.tenant_id,c.id,v_type,v_amount,v_currency,v_status,v_note,NULLIF(btrim(p_payload->>'finance_reference'),''),auth.uid()) RETURNING id INTO v_id;
 ELSE UPDATE public.service_claim_financials SET exposure_type=v_type,amount=v_amount,currency=v_currency,status=v_status,note=v_note,finance_reference=NULLIF(btrim(p_payload->>'finance_reference'),'') WHERE id=p_financial_id AND claim_id=c.id RETURNING id INTO v_id;IF v_id IS NULL THEN RETURN jsonb_build_object('error','not_found');END IF;END IF;
 PERFORM private.f10_add_event(c,'exposure_changed','Exposición operativa actualizada',jsonb_build_object('financial_id',v_id,'type',v_type,'amount',v_amount,'currency',v_currency,'status',v_status));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_financial_changed','service_claim_financial',v_id,jsonb_build_object('claim_id',c.id,'type',v_type,'amount',v_amount,'currency',v_currency,'status',v_status));RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('error','invalid_financial');END $function$;

CREATE FUNCTION public.rpc_record_claim_settlement(p_claim_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_amount numeric;v_currency text:=upper(p_payload->>'currency');v_type text:=NULLIF(btrim(p_payload->>'settlement_type'),'');v_notes text:=NULLIF(btrim(p_payload->>'notes'),'');v_date date;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id FOR UPDATE;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;BEGIN v_amount:=(p_payload->>'amount')::numeric;v_date:=(p_payload->>'date')::date;EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF v_amount<0 OR v_currency NOT IN ('MXN','USD') OR v_type IS NULL OR v_notes IS NULL THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 UPDATE public.service_claims SET settlement_amount=v_amount,settlement_currency=v_currency,settlement_type=v_type,settlement_date=v_date,settlement_notes=v_notes WHERE id=c.id RETURNING * INTO c;
 PERFORM private.f10_add_event(c,'settlement','Acuerdo operativo registrado',jsonb_build_object('amount',v_amount,'currency',v_currency,'settlement_type',v_type,'date',v_date));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_settlement_recorded','service_claim',c.id,jsonb_build_object('amount',v_amount,'currency',v_currency,'settlement_type',v_type,'date',v_date));RETURN jsonb_build_object('success',true,'accounting_mutated',false);END $function$;

CREATE FUNCTION public.rpc_get_claim_finance_handoff(p_claim_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE c public.service_claims%ROWTYPE;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN jsonb_build_object('claim_id',c.id,'claim_number',c.claim_number,'accounting_mutated',false,'route','/finance?action=new-adjustment&claimId='||c.id,'message','Crear el ajuste explícitamente en Finance 360; la exposición no es contabilidad.');END $function$;

CREATE FUNCTION public.rpc_register_claim_document(p_claim_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_path text:=NULLIF(btrim(p_payload->>'storage_path'),'');v_name text:=NULLIF(btrim(p_payload->>'file_name'),'');v_mime text:=lower(NULLIF(btrim(p_payload->>'mime_type'),''));v_size bigint;v_checksum text:=lower(NULLIF(btrim(p_payload->>'checksum_sha256'),''));v_file uuid;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;BEGIN v_size:=(p_payload->>'size_bytes')::bigint;EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF v_path IS NULL OR v_name IS NULL OR v_mime IS NULL OR v_size<=0 OR v_checksum !~ '^[0-9a-f]{64}$' OR NOT private.f3_storage_path_is_valid(v_path,c.tenant_id,'claims','claim',c.id) THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 IF NOT private.f3_extension_matches_mime(v_name,v_mime) OR NOT EXISTS(SELECT 1 FROM storage.buckets b WHERE b.id='tenant-documents' AND NOT b.public AND v_size<=b.file_size_limit AND v_mime=ANY(b.allowed_mime_types)) THEN RETURN jsonb_build_object('error','file_type_not_allowed');END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='tenant-documents' AND o.name=v_path AND o.owner_id=auth.uid()::text) THEN RETURN jsonb_build_object('error','storage_object_not_found');END IF;
 INSERT INTO public.document_files(tenant_id,storage_bucket,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,source_module,source_entity_type,source_entity_id,status,notes,metadata,uploaded_by)
 VALUES(c.tenant_id,'tenant-documents',v_path,v_name,v_mime,v_size,v_checksum,'supporting_file','claims','claim',c.id,'active',NULLIF(btrim(p_payload->>'notes'),''),COALESCE(p_payload->'metadata','{}'::jsonb),auth.uid()) RETURNING id INTO v_file;
 INSERT INTO public.document_relations(tenant_id,relation_type,source_entity_type,source_entity_id,target_entity_type,target_entity_id,notes,created_by,document_file_id) VALUES(c.tenant_id,'supporting_document','document_file',v_file,'claim',c.id,NULLIF(btrim(p_payload->>'notes'),''),auth.uid(),v_file);
 PERFORM private.f10_add_event(c,'evidence_added','Evidencia privada agregada',jsonb_build_object('document_file_id',v_file,'file_name',v_name));INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(c.tenant_id,auth.uid(),'service_claim_evidence_added','service_claim',c.id,jsonb_build_object('document_file_id',v_file,'file_name',v_name));RETURN (SELECT to_jsonb(f) FROM public.document_files f WHERE f.id=v_file);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','storage_path_already_registered');END $function$;

CREATE FUNCTION public.rpc_relate_claim_document(p_claim_id uuid,p_file_id uuid,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;f public.document_files%ROWTYPE;v_id uuid;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;SELECT * INTO f FROM public.document_files WHERE id=p_file_id;IF c.id IS NULL OR f.id IS NULL OR c.tenant_id<>f.tenant_id THEN RETURN jsonb_build_object('error','invalid_document');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 INSERT INTO public.document_relations(tenant_id,relation_type,source_entity_type,source_entity_id,target_entity_type,target_entity_id,notes,created_by,document_file_id) VALUES(c.tenant_id,'supporting_document','document_file',f.id,'claim',c.id,NULLIF(btrim(p_note),''),auth.uid(),f.id)
 ON CONFLICT(document_file_id,target_entity_type,target_entity_id,relation_type) WHERE document_file_id IS NOT NULL DO UPDATE SET notes=COALESCE(EXCLUDED.notes,public.document_relations.notes) RETURNING id INTO v_id;
 PERFORM private.f10_add_event(c,'evidence_added','Documento existente relacionado',jsonb_build_object('document_file_id',f.id,'file_name',f.file_name));RETURN jsonb_build_object('id',v_id,'success',true);END $function$;

CREATE FUNCTION public.rpc_list_claim_documents(p_claim_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE c public.service_claims%ROWTYPE;
BEGIN SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC) FROM public.document_relations r JOIN public.document_files f ON f.id=r.document_file_id WHERE r.tenant_id=c.tenant_id AND r.target_entity_type='claim' AND r.target_entity_id=c.id AND f.status='active'),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_list_partner_claims(p_partner_type text,p_partner_id uuid,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE v_tenant uuid;
BEGIN IF p_partner_type='customer' THEN SELECT tenant_id INTO v_tenant FROM public.customers WHERE id=p_partner_id;ELSIF p_partner_type='provider' THEN SELECT tenant_id INTO v_tenant FROM public.logistics_providers WHERE id=p_partner_id;ELSE RETURN jsonb_build_object('error','invalid_partner');END IF;IF v_tenant IS NULL THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(v_tenant) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC) FROM (SELECT c.id,c.claim_number,c.claim_type,c.priority,c.status,c.subject,c.responsibility,c.reported_at,c.response_due_at,c.resolution_due_at,c.updated_at,private.f10_sla(c,now()) sla,o.reference_code operation_reference,COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',e.currency,'amount',e.amount) ORDER BY e.currency) FROM (SELECT f.currency,sum(f.amount) amount FROM public.service_claim_financials f WHERE f.claim_id=c.id AND f.status<>'cancelled' GROUP BY f.currency)e),'[]'::jsonb) exposure_by_currency FROM public.service_claims c LEFT JOIN public.operations o ON o.id=c.operation_id WHERE c.tenant_id=v_tenant AND ((p_partner_type='customer' AND c.customer_id=p_partner_id) OR (p_partner_type='provider' AND c.provider_id=p_partner_id)) ORDER BY c.updated_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),200))x),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_get_claims_dashboard(p_tenant_id uuid,p_from timestamptz DEFAULT NULL,p_to timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE v_from timestamptz:=COALESCE(p_from,date_trunc('month',now()));v_to timestamptz:=COALESCE(p_to,now());
BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v_to<v_from THEN RETURN jsonb_build_object('error','invalid_period');END IF;
 RETURN jsonb_build_object(
  'open_count',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled')),
  'critical_open',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.priority='critical' AND c.status NOT IN ('resolved','closed','cancelled')),
  'first_response_overdue',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.first_responded_at IS NULL AND c.status NOT IN ('resolved','closed','cancelled') AND c.response_due_at<now()),
  'resolution_overdue',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND c.resolution_due_at<now()),
  'opened_in_period',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=v_from AND c.reported_at<v_to),
  'resolved_in_period',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.resolved_at>=v_from AND c.resolved_at<v_to),
  'exposure_by_currency',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',x.currency,'amount',x.amount) ORDER BY x.currency) FROM (SELECT f.currency,sum(f.amount) amount FROM public.service_claim_financials f JOIN public.service_claims c ON c.id=f.claim_id WHERE c.tenant_id=p_tenant_id AND f.status<>'cancelled' GROUP BY f.currency)x),'[]'::jsonb),
  'by_type',COALESCE((SELECT jsonb_agg(jsonb_build_object('claim_type',x.claim_type,'count',x.total) ORDER BY x.total DESC,x.claim_type) FROM (SELECT c.claim_type,count(*) total FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=v_from AND c.reported_at<v_to GROUP BY c.claim_type)x),'[]'::jsonb));END $function$;

CREATE FUNCTION public.rpc_list_claim_attention_items(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.priority_rank,x.due_at NULLS LAST,x.title) FROM (
 SELECT c.id::text entity_id,'claim'::text entity_type,CASE WHEN c.priority='critical' THEN 'critical_claim_open' WHEN c.first_responded_at IS NULL AND c.response_due_at<now() THEN 'claim_first_response_overdue' ELSE 'claim_resolution_overdue' END kind,c.priority,c.claim_number||' · '||c.subject title,'/claims?claimId='||c.id route,LEAST(c.response_due_at,c.resolution_due_at) due_at,CASE c.priority WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END priority_rank FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND (c.priority='critical' OR (c.first_responded_at IS NULL AND c.response_due_at<now()) OR c.resolution_due_at<now())
 UNION ALL SELECT a.id::text,'claim_action','claim_action_overdue','high',c.claim_number||' · '||a.title,'/claims?claimId='||c.id,a.due_at,2 FROM public.service_claim_actions a JOIN public.service_claims c ON c.id=a.claim_id WHERE a.tenant_id=p_tenant_id AND a.status IN ('open','in_progress') AND a.due_at<now())x),'[]'::jsonb));END $function$;

CREATE FUNCTION public.rpc_search_claims(p_tenant_id uuid,p_query text,p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE v_query text:=lower(NULLIF(btrim(COALESCE(p_query,'')),''));
BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v_query IS NULL OR char_length(v_query)<2 THEN RETURN '[]'::jsonb;END IF;RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC) FROM (SELECT c.id,c.claim_number,c.subject,c.status,c.priority,c.updated_at,'/claims?claimId='||c.id route,o.reference_code operation_reference,cu.display_name customer_name,p.display_name provider_name FROM public.service_claims c LEFT JOIN public.operations o ON o.id=c.operation_id LEFT JOIN public.customers cu ON cu.id=c.customer_id LEFT JOIN public.logistics_providers p ON p.id=c.provider_id WHERE c.tenant_id=p_tenant_id AND position(v_query IN lower(concat_ws(' ',c.claim_number,c.subject,o.reference_code,cu.display_name,p.display_name)))>0 ORDER BY c.updated_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,10),1),50))x),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_get_claim_reporting(p_tenant_id uuid,p_from timestamptz,p_to timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from THEN RETURN jsonb_build_object('error','invalid_period');END IF;RETURN jsonb_build_object(
 'root_causes',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.root_cause) FROM (SELECT root_cause,count(*) total FROM public.service_claims WHERE tenant_id=p_tenant_id AND reported_at>=p_from AND reported_at<p_to GROUP BY root_cause)x),'[]'::jsonb),
 'provider_recurrence',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.provider_name) FROM (SELECT p.id provider_id,p.display_name provider_name,count(*) total FROM public.service_claims c JOIN public.logistics_providers p ON p.id=c.provider_id WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY p.id,p.display_name)x),'[]'::jsonb),
 'customer_counts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.customer_name) FROM (SELECT cu.id customer_id,cu.display_name customer_name,count(*) total FROM public.service_claims c JOIN public.customers cu ON cu.id=c.customer_id WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY cu.id,cu.display_name)x),'[]'::jsonb),
 'responsibility_counts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.responsibility) FROM (SELECT c.responsibility,count(*) total FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY c.responsibility)x),'[]'::jsonb),
 'status_counts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.status) FROM (SELECT c.status,count(*) total FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY c.status)x),'[]'::jsonb),
 'monthly_counts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.month_key) FROM (SELECT to_char(date_trunc('month',c.reported_at),'YYYY-MM') month_key,count(*) total FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY date_trunc('month',c.reported_at))x),'[]'::jsonb),
 'claim_type_recurrence',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.claim_type) FROM (SELECT c.claim_type,count(*) total FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY c.claim_type)x),'[]'::jsonb),
 'lane_recurrence',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.lane) FROM (SELECT COALESCE(NULLIF(o.route_summary,''),concat_ws(' → ',o.origin_place->>'municipality',o.destination_place->>'municipality'),'Sin carril') lane,count(*) total FROM public.service_claims c JOIN public.operations o ON o.id=c.operation_id WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY 1)x),'[]'::jsonb),
 'service_recurrence',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total DESC,x.service_type) FROM (SELECT COALESCE(o.service_type,'Sin servicio') service_type,count(*) total FROM public.service_claims c JOIN public.operations o ON o.id=c.operation_id WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to GROUP BY 1)x),'[]'::jsonb),
 'response_sla',jsonb_build_object('met',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to AND c.first_responded_at IS NOT NULL AND c.first_responded_at<=c.response_due_at),'breached',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.reported_at>=p_from AND c.reported_at<p_to AND COALESCE(c.first_responded_at,now())>c.response_due_at)),
 'resolution_sla',jsonb_build_object('met',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.resolved_at>=p_from AND c.resolved_at<p_to AND c.resolved_at<=c.resolution_due_at),'breached',(SELECT count(*) FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.resolved_at>=p_from AND c.resolved_at<p_to AND c.resolved_at>c.resolution_due_at)));
END $function$;

CREATE FUNCTION public.rpc_export_claims(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.reported_at DESC) FROM (SELECT c.claim_number,c.claim_type,c.priority,c.status,c.subject,c.reported_at,c.response_due_at,c.first_responded_at,c.resolution_due_at,c.resolved_at,c.closed_at,c.responsibility,c.root_cause,o.reference_code operation_reference,cu.display_name customer_name,p.display_name provider_name,COALESCE((SELECT string_agg(e.currency||' '||e.amount::text,' | ' ORDER BY e.currency) FROM (SELECT f.currency,sum(f.amount) amount FROM public.service_claim_financials f WHERE f.claim_id=c.id AND f.status<>'cancelled' GROUP BY f.currency)e),'') estimated_exposure_by_currency FROM public.service_claims c LEFT JOIN public.operations o ON o.id=c.operation_id LEFT JOIN public.customers cu ON cu.id=c.customer_id LEFT JOIN public.logistics_providers p ON p.id=c.provider_id WHERE c.tenant_id=p_tenant_id AND (NOT(p_filters?'status') OR c.status=ANY(string_to_array(p_filters->>'status',','))) AND (NOT(p_filters?'date_from') OR c.reported_at>=(p_filters->>'date_from')::date) AND (NOT(p_filters?'date_to') OR c.reported_at<(p_filters->>'date_to')::date+1))x),'[]'::jsonb);EXCEPTION WHEN invalid_datetime_format THEN RETURN jsonb_build_object('error','invalid_filters');END $function$;

CREATE FUNCTION public.rpc_list_claim_saved_views(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.is_default DESC,v.updated_at DESC) FROM (SELECT id,module,name,filters,sort,is_default,created_at,updated_at FROM public.user_saved_views WHERE tenant_id=p_tenant_id AND user_id=auth.uid() AND module='claims')v),'[]'::jsonb);END $function$;

CREATE FUNCTION public.rpc_save_claim_view(p_tenant_id uuid,p_view_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE v_id uuid:=p_view_id;v_name text:=NULLIF(btrim(p_payload->>'name'),'');v_default boolean:=COALESCE((p_payload->>'is_default')::boolean,false);v_filters jsonb:=COALESCE(p_payload->'filters','{}'::jsonb);v_sort jsonb:=COALESCE(p_payload->'sort','{}'::jsonb);
BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;IF v_name IS NULL OR jsonb_typeof(v_filters)<>'object' OR jsonb_typeof(v_sort)<>'object' THEN RETURN jsonb_build_object('error','invalid_view');END IF;IF v_default THEN UPDATE public.user_saved_views SET is_default=false WHERE tenant_id=p_tenant_id AND user_id=auth.uid() AND module='claims' AND (v_id IS NULL OR id<>v_id);END IF;IF v_id IS NULL THEN INSERT INTO public.user_saved_views(tenant_id,user_id,module,name,filters,sort,is_default) VALUES(p_tenant_id,auth.uid(),'claims',v_name,v_filters,v_sort,v_default) RETURNING id INTO v_id;ELSE UPDATE public.user_saved_views SET name=v_name,filters=v_filters,sort=v_sort,is_default=v_default WHERE id=v_id AND tenant_id=p_tenant_id AND user_id=auth.uid() AND module='claims';IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;END IF;RETURN (SELECT to_jsonb(v) FROM public.user_saved_views v WHERE v.id=v_id);EXCEPTION WHEN unique_violation OR check_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_view');END $function$;

CREATE FUNCTION public.rpc_delete_claim_view(p_tenant_id uuid,p_view_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;DELETE FROM public.user_saved_views WHERE id=p_view_id AND tenant_id=p_tenant_id AND user_id=auth.uid() AND module='claims';RETURN jsonb_build_object('success',FOUND);END $function$;

CREATE FUNCTION private.f10_seed_automation_rules(p_tenant_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ INSERT INTO public.automation_rules(tenant_id,code,name,module,target_role,severity,threshold_value,threshold_unit,escalation_config,digest_enabled) VALUES
 (p_tenant_id,'claim_first_response_overdue','Primera respuesta de reclamación vencida','claims','admin','high',0,'hours','{"levels":[{"after_hours":24,"severity":"critical"}]}'::jsonb,true),
 (p_tenant_id,'claim_resolution_overdue','Resolución de reclamación vencida','claims','admin','high',0,'hours','{"levels":[{"after_hours":48,"severity":"critical"}]}'::jsonb,true),
 (p_tenant_id,'claim_action_overdue','Acción de reclamación vencida','claims','admin','high',0,'hours','{"levels":[{"after_hours":24,"severity":"critical"}]}'::jsonb,true),
 (p_tenant_id,'critical_claim_open','Reclamación crítica abierta','claims','admin','critical',0,'hours','{"levels":[]}'::jsonb,true)
 ON CONFLICT(tenant_id,code) DO NOTHING $function$;

SELECT private.f10_seed_automation_rules(id) FROM public.tenants;

CREATE FUNCTION private.f10_seed_tenant_automation_rules()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN PERFORM private.f10_seed_automation_rules(NEW.id);RETURN NEW;END $function$;
CREATE TRIGGER trg_tenants_seed_f10_automation AFTER INSERT ON public.tenants FOR EACH ROW EXECUTE FUNCTION private.f10_seed_tenant_automation_rules();

CREATE FUNCTION private.f10_materialize_claim_notifications(p_tenant_id uuid,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ DECLARE v_upserted integer:=0;v_resolved integer:=0;
BEGIN PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('rotero-f10-claims'),pg_catalog.hashtext(p_tenant_id::text));PERFORM private.f10_seed_automation_rules(p_tenant_id);
 WITH candidates AS (
  SELECT c.id entity_id,c.id claim_id,'claim_first_response_overdue' code,c.response_due_at due_at,c.priority,c.claim_number||' · primera respuesta vencida' title,c.subject body FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND c.first_responded_at IS NULL AND c.response_due_at<p_now
  UNION ALL SELECT c.id,c.id,'claim_resolution_overdue',c.resolution_due_at,c.priority,c.claim_number||' · resolución vencida',c.subject FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND c.resolution_due_at<p_now
  UNION ALL SELECT a.id,c.id,'claim_action_overdue',a.due_at,'high',c.claim_number||' · acción vencida',a.title FROM public.service_claim_actions a JOIN public.service_claims c ON c.id=a.claim_id WHERE a.tenant_id=p_tenant_id AND a.status IN ('open','in_progress') AND a.due_at<p_now
  UNION ALL SELECT c.id,c.id,'critical_claim_open',c.resolution_due_at,'critical',c.claim_number||' · reclamación crítica',c.subject FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.priority='critical' AND c.status NOT IN ('resolved','closed','cancelled')
 ), recipients AS (SELECT m.user_id FROM public.memberships m WHERE m.tenant_id=p_tenant_id AND m.role='admin'), upserted AS (
  INSERT INTO public.internal_notifications(tenant_id,user_id,fingerprint,trigger_type,area,priority,icon,title,body,route,related_entity_type,related_entity_id,status,first_seen_at,last_seen_at,due_at,automation_rule_id,automation_rule_code,is_automated,resolved_at,metadata)
  SELECT p_tenant_id,r.user_id,'automation:'||c.code||':'||c.entity_id,c.code,'claims',c.priority,'warning',c.title,c.body,'/claims?claimId='||c.claim_id,'service_claim',c.claim_id::text,'unread',p_now,p_now,c.due_at,ar.id,c.code,true,NULL,jsonb_build_object('claim_id',c.claim_id,'candidate_id',c.entity_id)
  FROM candidates c CROSS JOIN recipients r JOIN public.automation_rules ar ON ar.tenant_id=p_tenant_id AND ar.code=c.code AND ar.is_enabled
  ON CONFLICT(tenant_id,user_id,fingerprint) DO UPDATE SET priority=EXCLUDED.priority,title=EXCLUDED.title,body=EXCLUDED.body,route=EXCLUDED.route,last_seen_at=p_now,due_at=EXCLUDED.due_at,resolved_at=NULL,status=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN 'unread' ELSE public.internal_notifications.status END,read_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN NULL ELSE public.internal_notifications.read_at END,dismissed_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN NULL ELSE public.internal_notifications.dismissed_at END,first_seen_at=CASE WHEN public.internal_notifications.resolved_at IS NOT NULL THEN p_now ELSE public.internal_notifications.first_seen_at END,metadata=EXCLUDED.metadata RETURNING 1)
 SELECT count(*) INTO v_upserted FROM upserted;
 UPDATE public.internal_notifications n SET resolved_at=p_now,last_seen_at=p_now,status='read',read_at=COALESCE(n.read_at,p_now) WHERE n.tenant_id=p_tenant_id AND n.is_automated AND n.area='claims' AND n.resolved_at IS NULL AND NOT EXISTS(
  SELECT 1 FROM (SELECT c.id entity_id,'claim_first_response_overdue' code FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND c.first_responded_at IS NULL AND c.response_due_at<p_now UNION ALL SELECT c.id,'claim_resolution_overdue' FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.status NOT IN ('resolved','closed','cancelled') AND c.resolution_due_at<p_now UNION ALL SELECT a.id,'claim_action_overdue' FROM public.service_claim_actions a WHERE a.tenant_id=p_tenant_id AND a.status IN ('open','in_progress') AND a.due_at<p_now UNION ALL SELECT c.id,'critical_claim_open' FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND c.priority='critical' AND c.status NOT IN ('resolved','closed','cancelled'))c WHERE n.fingerprint='automation:'||c.code||':'||c.entity_id);GET DIAGNOSTICS v_resolved=ROW_COUNT;
 RETURN jsonb_build_object('upserted',v_upserted,'resolved',v_resolved);END $function$;

CREATE FUNCTION private.f10_after_automation_run()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NEW.status='completed' AND OLD.status IS DISTINCT FROM NEW.status THEN PERFORM private.f10_materialize_claim_notifications(NEW.tenant_id,COALESCE(NEW.completed_at,now()));END IF;RETURN NEW;END $function$;
CREATE TRIGGER trg_automation_runs_f10_claims AFTER UPDATE OF status ON public.automation_runs FOR EACH ROW EXECUTE FUNCTION private.f10_after_automation_run();

CREATE FUNCTION public.rpc_refresh_claim_notifications(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$ BEGIN IF NOT private.f10_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;RETURN private.f10_materialize_claim_notifications(p_tenant_id,now());END $function$;

-- F10 function ACL: owner execution remains available to triggers; normal ERP
-- entry points require an authenticated user and then enforce Admin membership.
REVOKE EXECUTE ON FUNCTION private.f10_admin(uuid),private.f10_business_year(uuid,timestamptz),private.f10_next_claim_number(uuid,integer),private.f10_seed_policies(uuid),private.f10_seed_policies_for_tenant(),private.f10_policy(uuid,text,text),private.f10_sla(public.service_claims,timestamptz),private.f10_add_event(public.service_claims,text,text,jsonb,timestamptz),private.f10_transition_allowed(text,text),private.f10_seed_automation_rules(uuid),private.f10_seed_tenant_automation_rules(),private.f10_materialize_claim_notifications(uuid,timestamptz),private.f10_after_automation_run() FROM PUBLIC,anon,authenticated,service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_upsert_claim_service_policy(uuid,uuid,jsonb),public.rpc_create_service_claim(uuid,jsonb),public.rpc_create_service_claim_from_incident(uuid,jsonb),public.rpc_get_claim_reference_data(uuid),public.rpc_list_service_claims(uuid,jsonb),public.rpc_get_service_claim(uuid),public.rpc_transition_service_claim(uuid,text,text),public.rpc_reopen_service_claim(uuid,text),public.rpc_assign_service_claim(uuid,uuid),public.rpc_update_claim_classification(uuid,text,text,text),public.rpc_add_claim_note(uuid,text),public.rpc_log_claim_contact(uuid,text,uuid,text,text,timestamptz),public.rpc_upsert_claim_action(uuid,uuid,jsonb),public.rpc_update_claim_action_status(uuid,text,text),public.rpc_upsert_claim_financial(uuid,uuid,jsonb),public.rpc_record_claim_settlement(uuid,jsonb),public.rpc_get_claim_finance_handoff(uuid),public.rpc_register_claim_document(uuid,jsonb),public.rpc_relate_claim_document(uuid,uuid,text),public.rpc_list_claim_documents(uuid),public.rpc_list_partner_claims(text,uuid,integer),public.rpc_get_claims_dashboard(uuid,timestamptz,timestamptz),public.rpc_list_claim_attention_items(uuid),public.rpc_search_claims(uuid,text,integer),public.rpc_get_claim_reporting(uuid,timestamptz,timestamptz),public.rpc_export_claims(uuid,jsonb),public.rpc_list_claim_saved_views(uuid),public.rpc_save_claim_view(uuid,uuid,jsonb),public.rpc_delete_claim_view(uuid,uuid),public.rpc_refresh_claim_notifications(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_claim_service_policy(uuid,uuid,jsonb),public.rpc_create_service_claim(uuid,jsonb),public.rpc_create_service_claim_from_incident(uuid,jsonb),public.rpc_get_claim_reference_data(uuid),public.rpc_list_service_claims(uuid,jsonb),public.rpc_get_service_claim(uuid),public.rpc_transition_service_claim(uuid,text,text),public.rpc_reopen_service_claim(uuid,text),public.rpc_assign_service_claim(uuid,uuid),public.rpc_update_claim_classification(uuid,text,text,text),public.rpc_add_claim_note(uuid,text),public.rpc_log_claim_contact(uuid,text,uuid,text,text,timestamptz),public.rpc_upsert_claim_action(uuid,uuid,jsonb),public.rpc_update_claim_action_status(uuid,text,text),public.rpc_upsert_claim_financial(uuid,uuid,jsonb),public.rpc_record_claim_settlement(uuid,jsonb),public.rpc_get_claim_finance_handoff(uuid),public.rpc_register_claim_document(uuid,jsonb),public.rpc_relate_claim_document(uuid,uuid,text),public.rpc_list_claim_documents(uuid),public.rpc_list_partner_claims(text,uuid,integer),public.rpc_get_claims_dashboard(uuid,timestamptz,timestamptz),public.rpc_list_claim_attention_items(uuid),public.rpc_search_claims(uuid,text,integer),public.rpc_get_claim_reporting(uuid,timestamptz,timestamptz),public.rpc_export_claims(uuid,jsonb),public.rpc_list_claim_saved_views(uuid),public.rpc_save_claim_view(uuid,uuid,jsonb),public.rpc_delete_claim_view(uuid,uuid),public.rpc_refresh_claim_notifications(uuid) TO authenticated;
