-- F2 Operation 360: reproducible broker-first operational workspace contracts.
-- Forward-only DDL/RPC reconciliation. No business-row backfill or timeline table.

CREATE TABLE IF NOT EXISTS public.operation_assignment_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    old_driver_id uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
    old_driver_name_snapshot text,
    old_vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
    old_vehicle_ref_snapshot text,
    new_driver_id uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
    new_driver_name_snapshot text,
    new_vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
    new_vehicle_ref_snapshot text,
    reason text,
    changed_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    changed_at timestamptz NOT NULL DEFAULT now(),
    old_execution_type text,
    new_execution_type text,
    old_provider_id uuid,
    new_provider_id uuid,
    old_provider_name_snapshot text,
    new_provider_name_snapshot text,
    old_external_driver_snapshot jsonb,
    new_external_driver_snapshot jsonb,
    old_external_vehicle_snapshot jsonb,
    new_external_vehicle_snapshot jsonb,
    CONSTRAINT operation_assignment_history_change_type_check
        CHECK (change_type IN ('initial_assignment', 'reassignment', 'unassignment'))
);

CREATE TABLE IF NOT EXISTS public.operation_incidents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    tracking_event_id uuid REFERENCES public.tracking_events(id) ON DELETE SET NULL,
    category text NOT NULL,
    title text NOT NULL,
    description text,
    status text NOT NULL DEFAULT 'open',
    is_blocking boolean NOT NULL DEFAULT false,
    reported_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reported_at timestamptz NOT NULL DEFAULT now(),
    resolved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    resolved_at timestamptz,
    resolution_note text,
    dismissed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    dismissed_at timestamptz,
    dismiss_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_incidents_category_check CHECK (
        category IN ('delay', 'loading_unloading', 'vehicle_issue', 'driver_issue', 'documents_issue', 'general')
    ),
    CONSTRAINT operation_incidents_status_check CHECK (status IN ('open', 'resolved', 'dismissed')),
    CONSTRAINT operation_incidents_title_check CHECK (char_length(btrim(title)) > 0),
    CONSTRAINT operation_incidents_resolution_state_check CHECK (NOT (resolved_at IS NOT NULL AND dismissed_at IS NOT NULL)),
    CONSTRAINT operation_incidents_resolved_fields_check CHECK (status <> 'resolved' OR (resolved_at IS NOT NULL AND resolved_by IS NOT NULL)),
    CONSTRAINT operation_incidents_dismissed_fields_check CHECK (status <> 'dismissed' OR (dismissed_at IS NOT NULL AND dismissed_by IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS public.operation_evidence (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    incident_id uuid REFERENCES public.operation_incidents(id) ON DELETE SET NULL,
    kind text NOT NULL,
    note text,
    file_ref text,
    external_url text,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_evidence_kind_check CHECK (kind IN ('operational_note', 'file_reference', 'image_link', 'external_link')),
    CONSTRAINT operation_evidence_content_check CHECK (
        COALESCE(NULLIF(btrim(note), ''), NULLIF(btrim(file_ref), ''), NULLIF(btrim(external_url), '')) IS NOT NULL
    ),
    CONSTRAINT operation_evidence_external_url_check CHECK (external_url IS NULL OR external_url ~* '^https?://')
);

CREATE TABLE IF NOT EXISTS public.operation_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    document_type text NOT NULL,
    requirement_level text NOT NULL DEFAULT 'optional',
    status text NOT NULL DEFAULT 'missing',
    document_reference text,
    file_ref text,
    external_url text,
    note text,
    updated_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_documents_operation_type_key UNIQUE (operation_id, document_type),
    CONSTRAINT operation_documents_document_type_check CHECK (
        document_type IN ('carta_porte_reference', 'loading_order', 'delivery_order', 'proof_of_delivery', 'administrative_reference', 'supporting_reference')
    ),
    CONSTRAINT operation_documents_requirement_level_check CHECK (requirement_level IN ('required', 'optional', 'not_required')),
    CONSTRAINT operation_documents_status_check CHECK (status IN ('missing', 'present')),
    CONSTRAINT operation_documents_present_requires_content_check CHECK (
        status <> 'present' OR COALESCE(document_reference, file_ref, external_url) IS NOT NULL
    ),
    CONSTRAINT operation_documents_not_required_is_clean_check CHECK (
        requirement_level <> 'not_required'
        OR (status = 'missing' AND document_reference IS NULL AND file_ref IS NULL AND external_url IS NULL AND note IS NULL)
    ),
    CONSTRAINT operation_documents_external_url_check CHECK (external_url IS NULL OR external_url ~* '^https?://')
);

CREATE TABLE IF NOT EXISTS public.operation_crossings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    crossed_at timestamptz NOT NULL DEFAULT now(),
    crossing_point text NOT NULL,
    crossing_type text NOT NULL DEFAULT 'other',
    note text,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_crossings_type_check CHECK (crossing_type IN ('entry', 'exit', 'other'))
);

ALTER TABLE public.operation_billing ADD COLUMN IF NOT EXISTS admin_close_note text;

CREATE INDEX IF NOT EXISTS operation_assignment_history_operation_idx
    ON public.operation_assignment_history (tenant_id, operation_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS operation_incidents_tenant_operation_created_idx
    ON public.operation_incidents (tenant_id, operation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS operation_incidents_tenant_status_blocking_idx
    ON public.operation_incidents (tenant_id, status, is_blocking);
CREATE INDEX IF NOT EXISTS operation_incidents_tracking_event_idx
    ON public.operation_incidents (tracking_event_id);
CREATE INDEX IF NOT EXISTS operation_evidence_tenant_operation_created_idx
    ON public.operation_evidence (tenant_id, operation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS operation_evidence_incident_created_idx
    ON public.operation_evidence (incident_id, created_at DESC);
CREATE INDEX IF NOT EXISTS operation_documents_tenant_operation_idx
    ON public.operation_documents (tenant_id, operation_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS operation_crossings_operation_idx
    ON public.operation_crossings (operation_id, crossed_at DESC);

ALTER TABLE public.operation_assignment_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_crossings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.operation_assignment_history FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.operation_incidents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.operation_evidence FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.operation_documents FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.operation_crossings FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_operation_document_catalog()
RETURNS TABLE(document_type text, display_label text, sort_order integer)
LANGUAGE sql
IMMUTABLE
SET search_path TO pg_catalog, public
AS $function$
    VALUES
        ('carta_porte_reference'::text, 'Referencia Carta Porte'::text, 10),
        ('loading_order'::text, 'Orden de carga'::text, 20),
        ('delivery_order'::text, 'Orden de entrega'::text, 30),
        ('proof_of_delivery'::text, 'Prueba de entrega (POD)'::text, 40),
        ('administrative_reference'::text, 'Referencia administrativa'::text, 50),
        ('supporting_reference'::text, 'Documento de soporte'::text, 60);
$function$;

CREATE OR REPLACE FUNCTION public.rpc_complete_operation_planning_v2(
    p_operation_id uuid,
    p_service_type text,
    p_origin_place jsonb,
    p_destination_place jsonb,
    p_operational_window_start timestamptz,
    p_operational_window_end timestamptz,
    p_notes text DEFAULT NULL,
    p_cargo_summary jsonb DEFAULT NULL,
    p_route_summary text DEFAULT NULL,
    p_destination_city text DEFAULT NULL,
    p_eta timestamptz DEFAULT NULL,
    p_eta_display text DEFAULT NULL,
    p_operation_scope text DEFAULT 'national',
    p_execution_type text DEFAULT 'third_party',
    p_provider_cost_amount numeric DEFAULT NULL,
    p_customer_price_amount numeric DEFAULT NULL,
    p_pricing_currency text DEFAULT 'MXN',
    p_service_catalog_item_id uuid DEFAULT NULL,
    p_service_catalog_snapshot jsonb DEFAULT '{}'::jsonb,
    p_boxes_placed_days integer DEFAULT NULL,
    p_documentation_received_at timestamptz DEFAULT NULL,
    p_documentation_received_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_scope text := COALESCE(NULLIF(btrim(p_operation_scope), ''), 'national');
    v_execution text := COALESCE(NULLIF(btrim(p_execution_type), ''), 'third_party');
    v_currency text := COALESCE(NULLIF(upper(btrim(p_pricing_currency)), ''), 'MXN');
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id FOR UPDATE;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_operation.status NOT IN ('draft', 'planned') THEN
        RETURN jsonb_build_object('error', 'invalid_status_for_planning');
    END IF;
    IF NULLIF(btrim(COALESCE(p_service_type, '')), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_service_type');
    END IF;
    IF p_origin_place IS NULL OR jsonb_typeof(p_origin_place) <> 'object'
       OR p_destination_place IS NULL OR jsonb_typeof(p_destination_place) <> 'object' THEN
        RETURN jsonb_build_object('error', 'missing_places');
    END IF;
    IF p_operational_window_start IS NULL OR p_operational_window_end IS NULL
       OR p_operational_window_end <= p_operational_window_start THEN
        RETURN jsonb_build_object('error', 'invalid_operational_window');
    END IF;
    IF p_eta IS NOT NULL AND p_eta < p_operational_window_start THEN
        RETURN jsonb_build_object('error', 'invalid_eta');
    END IF;
    IF v_scope NOT IN ('national', 'international') THEN RETURN jsonb_build_object('error', 'invalid_operation_scope'); END IF;
    IF v_execution NOT IN ('third_party', 'own_fleet') THEN RETURN jsonb_build_object('error', 'invalid_execution_type'); END IF;
    IF v_currency NOT IN ('MXN', 'USD') THEN RETURN jsonb_build_object('error', 'invalid_currency'); END IF;
    IF COALESCE(p_provider_cost_amount, 0) < 0 OR COALESCE(p_customer_price_amount, 0) < 0 THEN
        RETURN jsonb_build_object('error', 'invalid_pricing');
    END IF;
    IF p_boxes_placed_days IS NOT NULL AND p_boxes_placed_days < 0 THEN
        RETURN jsonb_build_object('error', 'invalid_boxes_placed_days');
    END IF;
    IF p_cargo_summary IS NOT NULL AND jsonb_typeof(p_cargo_summary) <> 'object' THEN
        RETURN jsonb_build_object('error', 'invalid_cargo_summary');
    END IF;
    IF p_service_catalog_snapshot IS NOT NULL AND jsonb_typeof(p_service_catalog_snapshot) <> 'object' THEN
        RETURN jsonb_build_object('error', 'invalid_service_snapshot');
    END IF;
    IF p_service_catalog_item_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.service_catalog_items s
        WHERE s.id = p_service_catalog_item_id AND s.tenant_id = v_operation.tenant_id
    ) THEN RETURN jsonb_build_object('error', 'invalid_service_catalog_item'); END IF;

    UPDATE public.operations SET
        service_type = btrim(p_service_type),
        origin_place = p_origin_place,
        destination_place = p_destination_place,
        operational_window_start = p_operational_window_start,
        operational_window_end = p_operational_window_end,
        notes = NULLIF(btrim(COALESCE(p_notes, '')), ''),
        cargo_summary = COALESCE(p_cargo_summary, '{}'::jsonb),
        route_summary = NULLIF(btrim(COALESCE(p_route_summary, '')), ''),
        destination_city = NULLIF(btrim(COALESCE(p_destination_city, '')), ''),
        eta = p_eta,
        eta_display = NULLIF(btrim(COALESCE(p_eta_display, '')), ''),
        operation_scope = v_scope,
        execution_type = v_execution,
        provider_cost_amount = p_provider_cost_amount,
        customer_price_amount = p_customer_price_amount,
        pricing_currency = v_currency,
        service_catalog_item_id = p_service_catalog_item_id,
        service_catalog_snapshot = COALESCE(p_service_catalog_snapshot, '{}'::jsonb),
        boxes_placed_days = p_boxes_placed_days,
        documentation_received_at = p_documentation_received_at,
        documentation_received_note = NULLIF(btrim(COALESCE(p_documentation_received_note, '')), ''),
        status = CASE WHEN status = 'draft' THEN 'planned' ELSE status END,
        updated_at = now()
    WHERE id = p_operation_id;

    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'complete_operation_planning', 'operation', p_operation_id,
        jsonb_build_object('scope', v_scope, 'execution_type', v_execution, 'currency', v_currency));
    RETURN jsonb_build_object('success', true);
EXCEPTION
    WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_incidents(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'operation_id', i.operation_id, 'tracking_event_id', i.tracking_event_id,
        'category', i.category, 'title', i.title, 'description', i.description,
        'status', i.status, 'is_blocking', i.is_blocking,
        'reported_by', i.reported_by, 'reported_at', i.reported_at,
        'resolved_by', i.resolved_by, 'resolved_at', i.resolved_at, 'resolution_note', i.resolution_note,
        'dismissed_by', i.dismissed_by, 'dismissed_at', i.dismissed_at, 'dismiss_note', i.dismiss_note,
        'created_at', i.created_at, 'updated_at', i.updated_at
    ) ORDER BY CASE WHEN i.status = 'open' THEN 0 ELSE 1 END, i.created_at DESC)
    FROM public.operation_incidents i WHERE i.operation_id = p_operation_id), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_incident_summary(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN (SELECT jsonb_build_object(
        'open_incident_count', count(*) FILTER (WHERE i.status = 'open'),
        'blocking_incident_count', count(*) FILTER (WHERE i.status = 'open' AND i.is_blocking),
        'has_open_incidents', count(*) FILTER (WHERE i.status = 'open') > 0,
        'has_blocking_incidents', count(*) FILTER (WHERE i.status = 'open' AND i.is_blocking) > 0,
        'can_close_operation', count(*) FILTER (WHERE i.status = 'open' AND i.is_blocking) = 0,
        'evidence_count', (SELECT count(*) FROM public.operation_evidence e WHERE e.operation_id = p_operation_id),
        'latest_incident_at', max(i.created_at)
    ) FROM public.operation_incidents i WHERE i.operation_id = p_operation_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_create_operation_incident(
    p_operation_id uuid, p_category text, p_title text,
    p_description text DEFAULT NULL, p_is_blocking boolean DEFAULT false,
    p_tracking_event_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_id uuid;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF p_category NOT IN ('delay', 'loading_unloading', 'vehicle_issue', 'driver_issue', 'documents_issue', 'general') THEN
        RETURN jsonb_build_object('error', 'invalid_category');
    END IF;
    IF NULLIF(btrim(COALESCE(p_title, '')), '') IS NULL THEN RETURN jsonb_build_object('error', 'missing_title'); END IF;
    IF p_tracking_event_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.tracking_events e WHERE e.id = p_tracking_event_id AND e.operation_id = p_operation_id
    ) THEN RETURN jsonb_build_object('error', 'invalid_tracking_event'); END IF;
    INSERT INTO public.operation_incidents (
        tenant_id, operation_id, tracking_event_id, category, title, description, is_blocking, reported_by
    ) VALUES (
        v_operation.tenant_id, p_operation_id, p_tracking_event_id, p_category, btrim(p_title),
        NULLIF(btrim(COALESCE(p_description, '')), ''), COALESCE(p_is_blocking, false), auth.uid()
    ) RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'create_operation_incident', 'operation_incident', v_id,
        jsonb_build_object('operation_id', p_operation_id, 'category', p_category, 'is_blocking', COALESCE(p_is_blocking, false)));
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_resolve_operation_incident(p_incident_id uuid, p_resolution_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_incident public.operation_incidents%ROWTYPE;
BEGIN
    SELECT * INTO v_incident FROM public.operation_incidents WHERE id = p_incident_id FOR UPDATE;
    IF v_incident.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_incident.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_incident.status <> 'open' THEN RETURN jsonb_build_object('error', 'invalid_status'); END IF;
    UPDATE public.operation_incidents SET status = 'resolved', resolved_by = auth.uid(), resolved_at = now(),
        resolution_note = NULLIF(btrim(COALESCE(p_resolution_note, '')), ''),
        dismissed_by = NULL, dismissed_at = NULL, dismiss_note = NULL, updated_at = now()
    WHERE id = p_incident_id;
    PERFORM public.rpc_write_audit(v_incident.tenant_id, 'resolve_operation_incident', 'operation_incident', p_incident_id,
        jsonb_build_object('operation_id', v_incident.operation_id));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_operation_incident(p_incident_id uuid, p_dismiss_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_incident public.operation_incidents%ROWTYPE;
BEGIN
    SELECT * INTO v_incident FROM public.operation_incidents WHERE id = p_incident_id FOR UPDATE;
    IF v_incident.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_incident.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_incident.status <> 'open' THEN RETURN jsonb_build_object('error', 'invalid_status'); END IF;
    UPDATE public.operation_incidents SET status = 'dismissed', dismissed_by = auth.uid(), dismissed_at = now(),
        dismiss_note = NULLIF(btrim(COALESCE(p_dismiss_note, '')), ''),
        resolved_by = NULL, resolved_at = NULL, resolution_note = NULL, updated_at = now()
    WHERE id = p_incident_id;
    PERFORM public.rpc_write_audit(v_incident.tenant_id, 'dismiss_operation_incident', 'operation_incident', p_incident_id,
        jsonb_build_object('operation_id', v_incident.operation_id));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_evidence(p_operation_id uuid, p_incident_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'operation_id', e.operation_id, 'incident_id', e.incident_id,
        'incident_title', i.title, 'kind', e.kind, 'note', e.note,
        'file_ref', e.file_ref, 'external_url', e.external_url,
        'created_by', e.created_by, 'created_at', e.created_at
    ) ORDER BY e.created_at DESC)
    FROM public.operation_evidence e LEFT JOIN public.operation_incidents i ON i.id = e.incident_id
    WHERE e.operation_id = p_operation_id AND (p_incident_id IS NULL OR e.incident_id = p_incident_id)), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_add_operation_evidence(
    p_operation_id uuid, p_incident_id uuid DEFAULT NULL,
    p_kind text DEFAULT 'operational_note', p_note text DEFAULT NULL,
    p_file_ref text DEFAULT NULL, p_external_url text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE; v_id uuid;
    v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_file text := NULLIF(btrim(COALESCE(p_file_ref, '')), '');
    v_url text := NULLIF(btrim(COALESCE(p_external_url, '')), '');
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF p_kind NOT IN ('operational_note', 'file_reference', 'image_link', 'external_link') THEN
        RETURN jsonb_build_object('error', 'invalid_kind');
    END IF;
    IF COALESCE(v_note, v_file, v_url) IS NULL THEN RETURN jsonb_build_object('error', 'missing_content'); END IF;
    IF v_url IS NOT NULL AND v_url !~* '^https?://' THEN RETURN jsonb_build_object('error', 'invalid_external_url'); END IF;
    IF p_incident_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.operation_incidents i WHERE i.id = p_incident_id AND i.operation_id = p_operation_id
    ) THEN RETURN jsonb_build_object('error', 'invalid_incident'); END IF;
    INSERT INTO public.operation_evidence (tenant_id, operation_id, incident_id, kind, note, file_ref, external_url, created_by)
    VALUES (v_operation.tenant_id, p_operation_id, p_incident_id, p_kind, v_note, v_file, v_url, auth.uid())
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'add_operation_evidence', 'operation_evidence', v_id,
        jsonb_build_object('operation_id', p_operation_id, 'incident_id', p_incident_id, 'kind', p_kind));
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v3(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_execution_type text DEFAULT 'third_party',
    p_provider_id uuid DEFAULT NULL,
    p_provider_name text DEFAULT NULL,
    p_external_driver jsonb DEFAULT '{}'::jsonb,
    p_external_vehicle jsonb DEFAULT '{}'::jsonb,
    p_driver_id uuid DEFAULT NULL,
    p_driver_name text DEFAULT NULL,
    p_vehicle_id uuid DEFAULT NULL,
    p_vehicle_ref text DEFAULT NULL,
    p_planned_departure timestamptz DEFAULT NULL,
    p_priority text DEFAULT 'normal',
    p_reason text DEFAULT NULL,
    p_force_override boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_provider public.logistics_providers%ROWTYPE;
    v_driver public.drivers%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
    v_execution text := COALESCE(NULLIF(btrim(p_execution_type), ''), 'third_party');
    v_priority text := COALESCE(NULLIF(btrim(p_priority), ''), 'normal');
    v_provider_name text;
    v_reassignment boolean;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    SELECT * INTO v_operation FROM public.operations
    WHERE id = p_operation_id AND tenant_id = p_tenant_id FOR UPDATE;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF v_operation.status NOT IN ('planned', 'assigned', 'in_transit') THEN
        RETURN jsonb_build_object('error', 'invalid_status_for_assignment');
    END IF;
    IF v_execution NOT IN ('third_party', 'own_fleet') THEN RETURN jsonb_build_object('error', 'invalid_execution_type'); END IF;
    IF v_priority NOT IN ('low', 'normal', 'high') THEN RETURN jsonb_build_object('error', 'invalid_priority'); END IF;
    IF p_planned_departure IS NULL THEN RETURN jsonb_build_object('error', 'missing_planned_departure'); END IF;
    IF jsonb_typeof(COALESCE(p_external_driver, '{}'::jsonb)) <> 'object'
       OR jsonb_typeof(COALESCE(p_external_vehicle, '{}'::jsonb)) <> 'object' THEN
        RETURN jsonb_build_object('error', 'invalid_external_snapshot');
    END IF;

    IF v_execution = 'third_party' THEN
        IF p_provider_id IS NULL THEN RETURN jsonb_build_object('error', 'missing_provider'); END IF;
        SELECT * INTO v_provider FROM public.logistics_providers
        WHERE id = p_provider_id AND tenant_id = p_tenant_id;
        IF v_provider.id IS NULL THEN RETURN jsonb_build_object('error', 'invalid_provider'); END IF;
        IF NOT v_provider.is_active AND v_operation.provider_id IS DISTINCT FROM v_provider.id THEN
            RETURN jsonb_build_object('error', 'provider_inactive');
        END IF;
        v_provider_name := COALESCE(NULLIF(btrim(p_provider_name), ''), v_provider.display_name);
    ELSE
        SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id AND tenant_id = p_tenant_id;
        SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id AND tenant_id = p_tenant_id;
        IF v_driver.id IS NULL THEN RETURN jsonb_build_object('error', 'invalid_driver'); END IF;
        IF v_vehicle.id IS NULL THEN RETURN jsonb_build_object('error', 'invalid_vehicle'); END IF;
    END IF;

    v_reassignment := v_operation.assigned_at IS NOT NULL AND (
        v_operation.execution_type IS DISTINCT FROM v_execution
        OR v_operation.provider_id IS DISTINCT FROM p_provider_id
        OR v_operation.driver_id IS DISTINCT FROM p_driver_id
        OR v_operation.vehicle_id IS DISTINCT FROM p_vehicle_id
        OR v_operation.external_driver IS DISTINCT FROM COALESCE(p_external_driver, '{}'::jsonb)
        OR v_operation.external_vehicle IS DISTINCT FROM COALESCE(p_external_vehicle, '{}'::jsonb)
    );
    IF v_reassignment AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_reassignment_reason');
    END IF;
    IF p_force_override AND (
        NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin'])
        OR NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL
    ) THEN RETURN jsonb_build_object('error', 'missing_override_reason'); END IF;

    UPDATE public.operations SET
        execution_type = v_execution,
        provider_id = CASE WHEN v_execution = 'third_party' THEN p_provider_id ELSE NULL END,
        provider_name = CASE WHEN v_execution = 'third_party' THEN v_provider_name ELSE NULL END,
        external_driver = CASE WHEN v_execution = 'third_party' THEN COALESCE(p_external_driver, '{}'::jsonb) ELSE '{}'::jsonb END,
        external_vehicle = CASE WHEN v_execution = 'third_party' THEN COALESCE(p_external_vehicle, '{}'::jsonb) ELSE '{}'::jsonb END,
        driver_id = CASE WHEN v_execution = 'own_fleet' THEN p_driver_id ELSE NULL END,
        driver_name = CASE WHEN v_execution = 'own_fleet' THEN COALESCE(NULLIF(btrim(p_driver_name), ''), v_driver.display_name) ELSE NULL END,
        vehicle_id = CASE WHEN v_execution = 'own_fleet' THEN p_vehicle_id ELSE NULL END,
        vehicle_ref = CASE WHEN v_execution = 'own_fleet' THEN COALESCE(NULLIF(btrim(p_vehicle_ref), ''), v_vehicle.unit_code) ELSE NULL END,
        planned_departure = p_planned_departure,
        priority = v_priority,
        assigned_at = COALESCE(assigned_at, now()),
        status = CASE WHEN status = 'planned' THEN 'assigned' ELSE status END,
        updated_at = now()
    WHERE id = p_operation_id;

    INSERT INTO public.operation_assignment_history (
        tenant_id, operation_id, change_type,
        old_execution_type, old_provider_id, old_provider_name_snapshot,
        old_external_driver_snapshot, old_external_vehicle_snapshot,
        old_driver_id, old_driver_name_snapshot, old_vehicle_id, old_vehicle_ref_snapshot,
        new_execution_type, new_provider_id, new_provider_name_snapshot,
        new_external_driver_snapshot, new_external_vehicle_snapshot,
        new_driver_id, new_driver_name_snapshot, new_vehicle_id, new_vehicle_ref_snapshot,
        reason, changed_by
    ) VALUES (
        p_tenant_id, p_operation_id,
        CASE WHEN v_reassignment THEN 'reassignment' ELSE 'initial_assignment' END,
        v_operation.execution_type, v_operation.provider_id, v_operation.provider_name,
        v_operation.external_driver, v_operation.external_vehicle,
        v_operation.driver_id, v_operation.driver_name, v_operation.vehicle_id, v_operation.vehicle_ref,
        v_execution,
        CASE WHEN v_execution = 'third_party' THEN p_provider_id ELSE NULL END,
        CASE WHEN v_execution = 'third_party' THEN v_provider_name ELSE NULL END,
        CASE WHEN v_execution = 'third_party' THEN COALESCE(p_external_driver, '{}'::jsonb) ELSE NULL END,
        CASE WHEN v_execution = 'third_party' THEN COALESCE(p_external_vehicle, '{}'::jsonb) ELSE NULL END,
        CASE WHEN v_execution = 'own_fleet' THEN p_driver_id ELSE NULL END,
        CASE WHEN v_execution = 'own_fleet' THEN COALESCE(NULLIF(btrim(p_driver_name), ''), v_driver.display_name) ELSE NULL END,
        CASE WHEN v_execution = 'own_fleet' THEN p_vehicle_id ELSE NULL END,
        CASE WHEN v_execution = 'own_fleet' THEN COALESCE(NULLIF(btrim(p_vehicle_ref), ''), v_vehicle.unit_code) ELSE NULL END,
        NULLIF(btrim(COALESCE(p_reason, '')), ''), auth.uid()
    );

    PERFORM public.rpc_write_audit(p_tenant_id,
        CASE WHEN v_reassignment THEN 'reassign_operation' ELSE 'assign_operation' END,
        'operation', p_operation_id,
        jsonb_build_object('execution_type', v_execution, 'provider_id', p_provider_id, 'reason', NULLIF(btrim(COALESCE(p_reason, '')), '')));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_assignment_history(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.changed_at DESC)
        FROM public.operation_assignment_history h WHERE h.operation_id = p_operation_id), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_requirements(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN jsonb_build_object(
        'has_driver_assigned', v_operation.driver_id IS NOT NULL OR COALESCE(v_operation.external_driver, '{}'::jsonb) <> '{}'::jsonb,
        'has_provider_assignment', v_operation.execution_type = 'own_fleet' OR v_operation.provider_id IS NOT NULL,
        'has_driver_token', EXISTS (SELECT 1 FROM public.tracking_tokens t WHERE t.operation_id = p_operation_id AND t.scope = 'driver:write' AND t.state = 'active' AND t.revoked_at IS NULL AND t.expires_at > now()),
        'has_public_token', EXISTS (SELECT 1 FROM public.tracking_tokens t WHERE t.operation_id = p_operation_id AND t.scope = 'public:read' AND t.state = 'active' AND t.revoked_at IS NULL AND t.expires_at > now()),
        'has_delivered_event', EXISTS (SELECT 1 FROM public.tracking_events e WHERE e.operation_id = p_operation_id AND e.event_type = 'delivered')
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_dispatch_readiness(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_requirements jsonb;
    v_planning boolean;
    v_assignment boolean;
    v_reasons text[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    v_requirements := public.rpc_get_operation_requirements(p_operation_id);
    v_planning := NULLIF(btrim(COALESCE(v_operation.service_type, '')), '') IS NOT NULL
        AND v_operation.origin_place IS NOT NULL AND v_operation.destination_place IS NOT NULL
        AND v_operation.operational_window_start IS NOT NULL AND v_operation.operational_window_end IS NOT NULL
        AND v_operation.operational_window_end > v_operation.operational_window_start;
    v_assignment := v_operation.planned_departure IS NOT NULL AND (
        (v_operation.execution_type = 'third_party' AND v_operation.provider_id IS NOT NULL)
        OR (v_operation.execution_type = 'own_fleet' AND v_operation.driver_id IS NOT NULL AND v_operation.vehicle_id IS NOT NULL)
    );
    IF NOT v_planning THEN v_reasons := array_append(v_reasons, 'missing_planning_data'); END IF;
    IF NOT v_assignment THEN v_reasons := array_append(v_reasons, 'missing_assignment'); END IF;
    IF NOT COALESCE((v_requirements->>'has_driver_token')::boolean, false) THEN v_reasons := array_append(v_reasons, 'missing_driver_capability'); END IF;
    IF NOT COALESCE((v_requirements->>'has_public_token')::boolean, false) THEN v_reasons := array_append(v_reasons, 'missing_public_capability'); END IF;
    RETURN jsonb_build_object(
        'is_minimum_planned_complete', v_planning,
        'is_assignment_complete', v_assignment,
        'is_tracking_ready', v_assignment
            AND COALESCE((v_requirements->>'has_driver_token')::boolean, false)
            AND COALESCE((v_requirements->>'has_public_token')::boolean, false),
        'can_transition_to_assigned', v_planning AND v_assignment,
        'can_transition_to_in_transit', v_planning AND v_assignment
            AND COALESCE((v_requirements->>'has_driver_token')::boolean, false)
            AND COALESCE((v_requirements->>'has_public_token')::boolean, false),
        'has_driver_token', COALESCE((v_requirements->>'has_driver_token')::boolean, false),
        'has_public_token', COALESCE((v_requirements->>'has_public_token')::boolean, false),
        'blocking_reasons', to_jsonb(v_reasons)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_tracking_events(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', e.id, 'event_type', e.event_type, 'source', e.source,
        'server_timestamp', e.server_timestamp, 'client_timestamp', e.client_timestamp,
        'municipality', e.municipality, 'state_name', e.state_name,
        'incident_type', e.incident_type, 'incident_note', e.incident_note
    ) ORDER BY e.server_timestamp DESC) FROM public.tracking_events e WHERE e.operation_id = p_operation_id), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_documents(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', d.id, 'operation_id', p_operation_id, 'document_type', c.document_type,
        'display_label', c.display_label,
        'requirement_level', COALESCE(d.requirement_level, 'optional'),
        'status', COALESCE(d.status, 'missing'),
        'document_reference', d.document_reference, 'file_ref', d.file_ref,
        'external_url', d.external_url, 'note', d.note,
        'updated_by', d.updated_by, 'created_at', d.created_at, 'updated_at', d.updated_at
    ) ORDER BY c.sort_order)
    FROM public.fn_operation_document_catalog() c
    LEFT JOIN public.operation_documents d
      ON d.operation_id = p_operation_id AND d.document_type = c.document_type), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_document_summary(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN (WITH slots AS (
        SELECT c.document_type, COALESCE(d.requirement_level, 'optional') requirement_level,
            COALESCE(d.status, 'missing') status
        FROM public.fn_operation_document_catalog() c
        LEFT JOIN public.operation_documents d ON d.operation_id = p_operation_id AND d.document_type = c.document_type
    ) SELECT jsonb_build_object(
        'required_count', count(*) FILTER (WHERE requirement_level = 'required'),
        'present_required_count', count(*) FILTER (WHERE requirement_level = 'required' AND status = 'present'),
        'missing_required_count', count(*) FILTER (WHERE requirement_level = 'required' AND status = 'missing'),
        'has_missing_required', count(*) FILTER (WHERE requirement_level = 'required' AND status = 'missing') > 0,
        'is_documentation_complete', count(*) FILTER (WHERE requirement_level = 'required' AND status = 'missing') = 0,
        'pod_present', count(*) FILTER (WHERE document_type = 'proof_of_delivery' AND status = 'present') > 0,
        'pod_required', count(*) FILTER (WHERE document_type = 'proof_of_delivery' AND requirement_level = 'required') > 0
    ) FROM slots);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_operation_document(
    p_operation_id uuid, p_document_type text, p_requirement_level text, p_status text,
    p_document_reference text DEFAULT NULL, p_file_ref text DEFAULT NULL,
    p_external_url text DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE; v_id uuid;
    v_requirement text := btrim(COALESCE(p_requirement_level, ''));
    v_status text := btrim(COALESCE(p_status, ''));
    v_reference text := NULLIF(btrim(COALESCE(p_document_reference, '')), '');
    v_file text := NULLIF(btrim(COALESCE(p_file_ref, '')), '');
    v_url text := NULLIF(btrim(COALESCE(p_external_url, '')), '');
    v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fn_operation_document_catalog() c WHERE c.document_type = p_document_type) THEN
        RETURN jsonb_build_object('error', 'invalid_document_type');
    END IF;
    IF v_requirement NOT IN ('required', 'optional', 'not_required') THEN
        RETURN jsonb_build_object('error', 'invalid_requirement_level');
    END IF;
    IF v_status NOT IN ('missing', 'present') THEN RETURN jsonb_build_object('error', 'invalid_status'); END IF;
    IF v_url IS NOT NULL AND v_url !~* '^https?://' THEN RETURN jsonb_build_object('error', 'invalid_external_url'); END IF;
    IF v_requirement = 'not_required' THEN
        v_status := 'missing'; v_reference := NULL; v_file := NULL; v_url := NULL; v_note := NULL;
    ELSIF v_status = 'present' AND COALESCE(v_reference, v_file, v_url) IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_content');
    END IF;
    INSERT INTO public.operation_documents (
        tenant_id, operation_id, document_type, requirement_level, status,
        document_reference, file_ref, external_url, note, updated_by
    ) VALUES (
        v_operation.tenant_id, p_operation_id, p_document_type, v_requirement, v_status,
        v_reference, v_file, v_url, v_note, auth.uid()
    ) ON CONFLICT (operation_id, document_type) DO UPDATE SET
        requirement_level = EXCLUDED.requirement_level, status = EXCLUDED.status,
        document_reference = EXCLUDED.document_reference, file_ref = EXCLUDED.file_ref,
        external_url = EXCLUDED.external_url, note = EXCLUDED.note,
        updated_by = EXCLUDED.updated_by, updated_at = now()
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'upsert_operation_document', 'operation_document', v_id,
        jsonb_build_object('operation_id', p_operation_id, 'document_type', p_document_type,
            'requirement_level', v_requirement, 'status', v_status));
    RETURN jsonb_build_object('success', true, 'id', v_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_crossings(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_operation.operation_scope <> 'international' THEN RETURN '[]'::jsonb; END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.crossed_at DESC, c.created_at DESC)
        FROM public.operation_crossings c WHERE c.operation_id = p_operation_id), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_operation_crossing(p_operation_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_id uuid := NULLIF(p_payload->>'id', '')::uuid;
    v_type text := COALESCE(NULLIF(btrim(p_payload->>'crossing_type'), ''), 'other');
    v_saved public.operation_crossings%ROWTYPE;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF v_operation.operation_scope <> 'international' THEN RETURN jsonb_build_object('error', 'national_operation'); END IF;
    IF v_type NOT IN ('entry', 'exit', 'other') THEN RETURN jsonb_build_object('error', 'invalid_crossing_type'); END IF;
    IF NULLIF(btrim(COALESCE(p_payload->>'crossing_point', '')), '') IS NULL THEN
        RETURN jsonb_build_object('error', 'missing_crossing_point');
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO public.operation_crossings (tenant_id, operation_id, crossed_at, crossing_point, crossing_type, note, created_by)
        VALUES (v_operation.tenant_id, p_operation_id,
            COALESCE(NULLIF(p_payload->>'crossed_at', '')::timestamptz, now()),
            btrim(p_payload->>'crossing_point'), v_type,
            NULLIF(btrim(COALESCE(p_payload->>'note', '')), ''), auth.uid())
        RETURNING * INTO v_saved;
    ELSE
        UPDATE public.operation_crossings SET
            crossed_at = COALESCE(NULLIF(p_payload->>'crossed_at', '')::timestamptz, crossed_at),
            crossing_point = btrim(p_payload->>'crossing_point'), crossing_type = v_type,
            note = NULLIF(btrim(COALESCE(p_payload->>'note', '')), ''), updated_at = now()
        WHERE id = v_id AND operation_id = p_operation_id AND tenant_id = v_operation.tenant_id
        RETURNING * INTO v_saved;
    END IF;
    IF v_saved.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'upsert_operation_crossing', 'operation_crossing', v_saved.id,
        jsonb_build_object('operation_id', p_operation_id, 'crossing_type', v_type));
    RETURN jsonb_build_object('success', true, 'item', to_jsonb(v_saved));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_delete_operation_crossing(p_crossing_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_crossing public.operation_crossings%ROWTYPE;
BEGIN
    SELECT * INTO v_crossing FROM public.operation_crossings WHERE id = p_crossing_id;
    IF v_crossing.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_crossing.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    DELETE FROM public.operation_crossings WHERE id = p_crossing_id;
    PERFORM public.rpc_write_audit(v_crossing.tenant_id, 'delete_operation_crossing', 'operation_crossing', p_crossing_id,
        jsonb_build_object('operation_id', v_crossing.operation_id));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_billing_summary(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_billing public.operation_billing%ROWTYPE;
    v_incidents jsonb;
    v_documents jsonb;
    v_blockers text[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    SELECT * INTO v_billing FROM public.operation_billing WHERE operation_id = p_operation_id;
    v_incidents := public.rpc_get_operation_incident_summary(p_operation_id);
    v_documents := public.rpc_get_operation_document_summary(p_operation_id);
    IF v_operation.status <> 'delivered' THEN v_blockers := array_append(v_blockers, 'operation_not_delivered'); END IF;
    IF v_operation.status = 'cancelled' THEN v_blockers := array_append(v_blockers, 'operation_cancelled'); END IF;
    IF COALESCE((v_incidents->>'has_blocking_incidents')::boolean, false) THEN
        v_blockers := array_append(v_blockers, 'blocking_incidents_open');
    END IF;
    IF NULLIF(btrim(COALESCE(v_operation.client_display_name, '')), '') IS NULL THEN
        v_blockers := array_append(v_blockers, 'missing_client_name');
    END IF;
    IF NULLIF(btrim(COALESCE(v_operation.reference_code, '')), '') IS NULL THEN
        v_blockers := array_append(v_blockers, 'missing_operation_reference');
    END IF;
    IF v_billing.id IS NOT NULL AND v_billing.status = 'issued' THEN
        v_blockers := array_append(v_blockers, 'billing_already_issued');
    END IF;
    IF v_billing.id IS NOT NULL AND v_billing.status = 'voided' THEN
        v_blockers := array_append(v_blockers, 'billing_voided');
    END IF;
    RETURN jsonb_build_object(
        'id', v_billing.id, 'status', v_billing.status,
        'billing_reference', v_billing.billing_reference, 'linked_cfdi_id', v_billing.linked_cfdi_id,
        'notes', v_billing.notes, 'issued_at', v_billing.issued_at,
        'voided_at', v_billing.voided_at, 'void_reason', v_billing.void_reason,
        'admin_closed_at', v_billing.admin_closed_at, 'admin_closed_by', v_billing.admin_closed_by,
        'admin_close_note', v_billing.admin_close_note,
        'admin_close_override', COALESCE(v_billing.admin_close_override, false),
        'has_billing_record', v_billing.id IS NOT NULL,
        'is_billing_ready', COALESCE(array_length(v_blockers, 1), 0) = 0,
        'billing_blockers', to_jsonb(v_blockers),
        'is_billed', v_billing.id IS NOT NULL AND v_billing.status = 'issued',
        'is_admin_closed', v_operation.status = 'closed' OR v_billing.admin_closed_at IS NOT NULL,
        'can_admin_close', v_operation.status = 'delivered'
            AND NOT COALESCE((v_incidents->>'has_blocking_incidents')::boolean, false)
            AND v_billing.id IS NOT NULL AND v_billing.status = 'issued',
        'pod_present', COALESCE((v_documents->>'pod_present')::boolean, false),
        'documentation_complete', COALESCE((v_documents->>'is_documentation_complete')::boolean, false)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_billing(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_result jsonb;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'finance', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    SELECT to_jsonb(b) || jsonb_build_object('summary', public.rpc_get_operation_billing_summary(p_operation_id))
    INTO v_result FROM public.operation_billing b WHERE b.operation_id = p_operation_id;
    RETURN COALESCE(v_result, jsonb_build_object('summary', public.rpc_get_operation_billing_summary(p_operation_id)));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_transition_operation_status(p_operation_id uuid, p_to_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
    v_readiness jsonb;
    v_incidents jsonb;
    v_billing jsonb;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id FOR UPDATE;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    v_readiness := public.rpc_get_operation_dispatch_readiness(p_operation_id);
    v_incidents := public.rpc_get_operation_incident_summary(p_operation_id);
    v_billing := public.rpc_get_operation_billing_summary(p_operation_id);
    CASE p_to_status
        WHEN 'planned' THEN
            IF v_operation.status <> 'draft' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
            IF NOT COALESCE((v_readiness->>'is_minimum_planned_complete')::boolean, false) THEN
                RETURN jsonb_build_object('error', 'missing_planning_data');
            END IF;
        WHEN 'assigned' THEN
            IF v_operation.status <> 'planned' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
            IF NOT COALESCE((v_readiness->>'can_transition_to_assigned')::boolean, false) THEN
                RETURN jsonb_build_object('error', 'assignment_not_ready');
            END IF;
        WHEN 'in_transit' THEN
            IF v_operation.status <> 'assigned' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
            IF NOT COALESCE((v_readiness->>'can_transition_to_in_transit')::boolean, false) THEN
                RETURN jsonb_build_object('error', 'tracking_not_ready');
            END IF;
        WHEN 'delivered' THEN
            IF v_operation.status <> 'in_transit' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
            IF NOT EXISTS (SELECT 1 FROM public.tracking_events e WHERE e.operation_id = p_operation_id AND e.event_type = 'delivered') THEN
                RETURN jsonb_build_object('error', 'missing_delivered_event');
            END IF;
        WHEN 'closed' THEN
            IF v_operation.status <> 'delivered' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
            IF COALESCE((v_incidents->>'has_blocking_incidents')::boolean, false) THEN
                RETURN jsonb_build_object('error', 'blocking_incidents_open');
            END IF;
            IF NOT COALESCE((v_billing->>'is_billed')::boolean, false) THEN
                RETURN jsonb_build_object('error', 'billing_not_issued');
            END IF;
        WHEN 'cancelled' THEN
            IF v_operation.status NOT IN ('draft', 'planned', 'assigned') THEN
                RETURN jsonb_build_object('error', 'invalid_transition');
            END IF;
        ELSE RETURN jsonb_build_object('error', 'invalid_status');
    END CASE;
    UPDATE public.operations SET status = p_to_status,
        assigned_at = CASE WHEN p_to_status = 'assigned' THEN COALESCE(assigned_at, now()) ELSE assigned_at END,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN now() ELSE cancelled_at END,
        closed_at = CASE WHEN p_to_status = 'closed' THEN now() ELSE closed_at END,
        updated_at = now()
    WHERE id = p_operation_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'transition_operation_status', 'operation', p_operation_id,
        jsonb_build_object('from_status', v_operation.status, 'to_status', p_to_status));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_override_operation_status(p_operation_id uuid, p_to_status text, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id FOR UPDATE;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_to_status NOT IN ('draft', 'planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed') THEN
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;
    IF v_reason IS NULL OR char_length(v_reason) < 10 OR char_length(v_reason) > 280 THEN
        RETURN jsonb_build_object('error', 'invalid_reason');
    END IF;
    UPDATE public.operations SET status = p_to_status,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN now() ELSE cancelled_at END,
        closed_at = CASE WHEN p_to_status = 'closed' THEN now() ELSE closed_at END,
        updated_at = now() WHERE id = p_operation_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'operation_status_override', 'operation', p_operation_id,
        jsonb_build_object('from_status', v_operation.status, 'to_status', p_to_status, 'reason', v_reason));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_close_operation(p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_result jsonb;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    v_result := public.rpc_transition_operation_status(p_operation_id, 'closed');
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    UPDATE public.operation_billing
    SET admin_closed_at = COALESCE(admin_closed_at, now()),
        admin_closed_by = COALESCE(admin_closed_by, auth.uid()),
        admin_close_override = false,
        updated_at = now()
    WHERE operation_id = p_operation_id;
    PERFORM public.rpc_write_audit(v_operation.tenant_id, 'close_operation', 'operation', p_operation_id,
        jsonb_build_object('closed_with_override', false, 'billing_status', 'issued'));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_close_operation_override(p_operation_id uuid, p_override_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_result jsonb;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_operation.id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF v_operation.status <> 'delivered' THEN RETURN jsonb_build_object('error', 'invalid_transition'); END IF;
    v_result := public.rpc_override_operation_status(p_operation_id, 'closed', p_override_reason);
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    INSERT INTO public.operation_billing (tenant_id, operation_id, status, admin_closed_at, admin_closed_by, admin_close_note, admin_close_override)
    VALUES (v_operation.tenant_id, p_operation_id, 'draft', now(), auth.uid(), btrim(p_override_reason), true)
    ON CONFLICT (operation_id) DO UPDATE SET admin_closed_at = now(), admin_closed_by = auth.uid(),
        admin_close_note = btrim(p_override_reason), admin_close_override = true, updated_at = now();
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_cancel_operation(p_operation_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$ SELECT public.rpc_transition_operation_status(p_operation_id, 'cancelled') $function$;

DO $triggers$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'f2_operation_incidents_touch_updated_at') THEN
        CREATE TRIGGER f2_operation_incidents_touch_updated_at
        BEFORE UPDATE ON public.operation_incidents
        FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'f2_operation_documents_touch_updated_at') THEN
        CREATE TRIGGER f2_operation_documents_touch_updated_at
        BEFORE UPDATE ON public.operation_documents
        FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'f2_operation_crossings_touch_updated_at') THEN
        CREATE TRIGGER f2_operation_crossings_touch_updated_at
        BEFORE UPDATE ON public.operation_crossings
        FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
    END IF;
END;
$triggers$;

REVOKE EXECUTE ON FUNCTION public.fn_operation_document_catalog() FROM PUBLIC, anon, authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_list_operations(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_create_operation(uuid,text,text,text,text,text,text,jsonb,jsonb,timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_update_operation_details(uuid,jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_complete_operation_planning_v2(uuid,text,jsonb,jsonb,timestamptz,timestamptz,text,jsonb,text,text,timestamptz,text,text,text,numeric,numeric,text,uuid,jsonb,integer,timestamptz,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_assign_operation_v3(uuid,uuid,text,uuid,text,jsonb,jsonb,uuid,text,uuid,text,timestamptz,text,text,boolean) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_assignment_history(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_requirements(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_dispatch_readiness(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_tracking_events(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_incidents(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_incident_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_create_operation_incident(uuid,text,text,text,boolean,uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_resolve_operation_incident(uuid,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dismiss_operation_incident(uuid,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_evidence(uuid,uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_add_operation_evidence(uuid,uuid,text,text,text,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_documents(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_document_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_upsert_operation_document(uuid,text,text,text,text,text,text,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_operation_crossings(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_upsert_operation_crossing(uuid,jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_delete_operation_crossing(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_billing(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_operation_billing_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_transition_operation_status(uuid,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_override_operation_status(uuid,text,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_close_operation(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_close_operation_override(uuid,text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_cancel_operation(uuid) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.rpc_list_operations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation(uuid,text,text,text,text,text,text,jsonb,jsonb,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_operation_details(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_complete_operation_planning_v2(uuid,text,jsonb,jsonb,timestamptz,timestamptz,text,jsonb,text,text,timestamptz,text,text,text,numeric,numeric,text,uuid,jsonb,integer,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation_v3(uuid,uuid,text,uuid,text,jsonb,jsonb,uuid,text,uuid,text,timestamptz,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_assignment_history(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_requirements(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_dispatch_readiness(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_tracking_events(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_incidents(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_incident_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation_incident(uuid,text,text,text,boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_resolve_operation_incident(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dismiss_operation_incident(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_evidence(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_operation_evidence(uuid,uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_documents(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_document_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_operation_document(uuid,text,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operation_crossings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_operation_crossing(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_delete_operation_crossing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_billing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_billing_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_transition_operation_status(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_override_operation_status(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_close_operation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_close_operation_override(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_operation(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
