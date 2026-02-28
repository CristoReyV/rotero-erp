-- Migration: Operations Workflow V2 (Strict Transitions & Override)

-- 1. Add missing fields
ALTER TABLE operations
ADD COLUMN IF NOT EXISTS driver_name TEXT,
ADD COLUMN IF NOT EXISTS vehicle_ref TEXT,
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Indices requested
CREATE INDEX IF NOT EXISTS operations_tenant_status_idx ON operations(tenant_id, status);
CREATE INDEX IF NOT EXISTS operations_tenant_created_at_idx ON operations(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS operations_tenant_driver_idx ON operations(tenant_id, driver_name);

-- 2. New RPC: rpc_assign_operation (updated to include driver_name and vehicle_ref)
CREATE OR REPLACE FUNCTION public.rpc_assign_operation(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_driver_id uuid,
    p_vehicle_id uuid,
    p_planned_departure timestamptz,
    p_priority text DEFAULT 'normal',
    p_driver_name text DEFAULT NULL,
    p_vehicle_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    op_tenant_id uuid;
    op_status text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT tenant_id, status INTO op_tenant_id, op_status 
    FROM operations 
    WHERE id = p_operation_id;

    IF op_tenant_id IS NULL OR op_tenant_id != p_tenant_id THEN
        RETURN jsonb_build_object('error', 'not_found_or_unauthorized');
    END IF;

    IF op_status NOT IN ('draft', 'planned', 'assigned') THEN
        RETURN jsonb_build_object('error', 'invalid_status_for_assignment');
    END IF;

    UPDATE operations SET 
        driver_id = p_driver_id,
        vehicle_id = p_vehicle_id,
        driver_name = p_driver_name,
        vehicle_ref = p_vehicle_ref,
        planned_departure = p_planned_departure,
        priority = p_priority,
        status = 'assigned',
        assigned_at = NOW(),
        updated_at = NOW()
    WHERE id = p_operation_id;

    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        p_tenant_id,
        'operation',
        p_operation_id::text,
        'status_changed',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object(
            'old_status', op_status,
            'new_status', 'assigned',
            'driver_name', p_driver_name,
            'vehicle_ref', p_vehicle_ref
        )
    );

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 2.1 New RPC: rpc_update_operation_details
CREATE OR REPLACE FUNCTION public.rpc_update_operation_details(
    p_operation_id uuid,
    p_patch jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_old_data jsonb;
BEGIN
    -- Verify existence
    SELECT tenant_id INTO v_tenant_id FROM operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    -- Verify authorization (tenant + role admin/operator)
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Get old data for audit
    SELECT row_to_json(o)::jsonb INTO v_old_data FROM operations o WHERE id = p_operation_id;

    -- Apply patch
    IF p_patch ? 'driver_name' THEN
        UPDATE operations SET driver_name = p_patch->>'driver_name' WHERE id = p_operation_id;
    END IF;
    IF p_patch ? 'vehicle_ref' THEN
        UPDATE operations SET vehicle_ref = p_patch->>'vehicle_ref' WHERE id = p_operation_id;
    END IF;
    IF p_patch ? 'eta' THEN
        UPDATE operations SET eta = p_patch->>'eta' WHERE id = p_operation_id;
    END IF;
    IF p_patch ? 'eta_display' THEN
        UPDATE operations SET eta_display = p_patch->>'eta_display' WHERE id = p_operation_id;
    END IF;
    IF p_patch ? 'origin_place' THEN
        UPDATE operations SET origin_place = (p_patch->'origin_place') WHERE id = p_operation_id;
    END IF;
    IF p_patch ? 'destination_place' THEN
        UPDATE operations SET destination_place = (p_patch->'destination_place') WHERE id = p_operation_id;
    END IF;
    
    UPDATE operations SET updated_at = NOW() WHERE id = p_operation_id;

    -- Audit log
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        v_tenant_id,
        'operation',
        p_operation_id::text,
        'operation_updated',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object(
            'patch', p_patch
        )
    );

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 3. New RPC: rpc_get_operation_requirements
CREATE OR REPLACE FUNCTION public.rpc_get_operation_requirements(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_has_driver_assigned boolean := false;
    v_has_driver_token boolean := false;
    v_has_delivered_event boolean := false;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Check driver assignment
    SELECT EXISTS (
        SELECT 1 FROM operations 
        WHERE id = p_operation_id 
          AND driver_name IS NOT NULL 
          AND driver_name != ''
          AND vehicle_ref IS NOT NULL
          AND vehicle_ref != ''
    ) INTO v_has_driver_assigned;

    -- Check driver token
    SELECT EXISTS (
        SELECT 1 FROM tracking_tokens
        WHERE operation_id = p_operation_id
          AND scope = 'driver:write'
          AND state = 'active'
          AND expires_at > NOW()
          AND revoked_at IS NULL
    ) INTO v_has_driver_token;

    -- Check delivered event
    SELECT EXISTS (
        SELECT 1 FROM tracking_events
        WHERE operation_id = p_operation_id
          AND event_type = 'delivered'
    ) INTO v_has_delivered_event;

    RETURN jsonb_build_object(
        'has_driver_assigned', v_has_driver_assigned,
        'has_driver_token', v_has_driver_token,
        'has_delivered_event', v_has_delivered_event
    );
END;
$$;

-- 4. New RPC: rpc_transition_operation_status
CREATE OR REPLACE FUNCTION public.rpc_transition_operation_status(
    p_operation_id uuid,
    p_to_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_current_status text;
    v_reqs jsonb;
    v_origin jsonb;
    v_dest jsonb;
BEGIN
    SELECT tenant_id, status, origin_place, destination_place 
    INTO v_tenant_id, v_current_status, v_origin, v_dest 
    FROM operations 
    WHERE id = p_operation_id;
    
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Matriz STRICT
    IF p_to_status = 'planned' THEN
        IF v_current_status != 'draft' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to planned from draft');
        END IF;
        IF v_origin IS NULL OR v_dest IS NULL THEN
            RETURN jsonb_build_object('error', 'missing_places');
        END IF;

    ELSIF p_to_status = 'assigned' THEN
        IF v_current_status != 'planned' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to assigned from planned');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_driver_assigned')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_driver');
        END IF;

    ELSIF p_to_status = 'in_transit' THEN
        IF v_current_status != 'assigned' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to in_transit from assigned');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_driver_token')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_driver_token');
        END IF;

    ELSIF p_to_status = 'delivered' THEN
        IF v_current_status != 'in_transit' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to delivered from in_transit');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_delivered_event')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_delivered_event');
        END IF;

    ELSIF p_to_status = 'closed' THEN
        IF v_current_status != 'delivered' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to closed from delivered');
        END IF;

    ELSIF p_to_status = 'cancelled' THEN
        IF v_current_status NOT IN ('draft', 'planned', 'assigned') THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Use override to cancel in_transit or delivered');
        END IF;

    ELSE
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;

    -- Apply transition
    UPDATE operations SET 
        status = p_to_status,
        assigned_at = CASE WHEN p_to_status = 'assigned' THEN NOW() ELSE assigned_at END,
        closed_at = CASE WHEN p_to_status = 'closed' THEN NOW() ELSE closed_at END,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN NOW() ELSE cancelled_at END,
        updated_at = NOW()
    WHERE id = p_operation_id;

    -- Audit log
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        v_tenant_id,
        'operation',
        p_operation_id::text,
        'operation_status_changed',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object(
            'from_status', v_current_status,
            'to_status', p_to_status
        )
    );

    RETURN jsonb_build_object('success', true);
END;
$$;


-- 5. New RPC: rpc_override_operation_status
CREATE OR REPLACE FUNCTION public.rpc_override_operation_status(
    p_operation_id uuid,
    p_to_status text,
    p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_current_status text;
BEGIN
    SELECT tenant_id, status INTO v_tenant_id, v_current_status FROM operations WHERE id = p_operation_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    -- MUST BE ADMIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role = 'admin'
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized', 'msg', 'Override requires admin role');
    END IF;

    -- Validate reason
    IF p_reason IS NULL OR length(p_reason) < 10 THEN
        RETURN jsonb_build_object('error', 'invalid_reason', 'msg', 'Reason must be at least 10 chars');
    END IF;
    IF length(p_reason) > 280 THEN
        RETURN jsonb_build_object('error', 'invalid_reason', 'msg', 'Reason max 280 chars');
    END IF;

    IF p_to_status NOT IN ('draft', 'planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed') THEN
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;

    -- Apply transition
    UPDATE operations SET 
        status = p_to_status,
        closed_at = CASE WHEN p_to_status = 'closed' THEN NOW() ELSE closed_at END,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN NOW() ELSE cancelled_at END,
        updated_at = NOW()
    WHERE id = p_operation_id;

    -- Audit log overriding
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        v_tenant_id,
        'operation',
        p_operation_id::text,
        'operation_override_used',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object(
            'from_status', v_current_status,
            'to_status', p_to_status,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 6. Update lists and get
CREATE OR REPLACE FUNCTION public.rpc_list_operations(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', id,
                'reference_code', reference_code,
                'route_summary', route_summary,
                'client_display_name', client_display_name,
                'destination_city', destination_city,
                'eta_display', eta_display,
                'status', status,
                'created_at', created_at,
                'eta', eta,
                'origin_place', origin_place,
                'destination_place', destination_place,
                'driver_id', driver_id,
                'vehicle_id', vehicle_id,
                'driver_name', driver_name,
                'vehicle_ref', vehicle_ref,
                'planned_departure', planned_departure,
                'priority', priority
            ) ORDER BY created_at DESC
        ), '[]'::jsonb)
        FROM operations
        WHERE tenant_id = p_tenant_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_get_operation(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    op_tenant_id uuid;
    res jsonb;
BEGIN
    SELECT tenant_id INTO op_tenant_id FROM operations WHERE id = p_operation_id;
    IF op_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = op_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT jsonb_build_object(
        'id', id,
        'tenant_id', tenant_id,
        'reference_code', reference_code,
        'route_summary', route_summary,
        'client_display_name', client_display_name,
        'destination_city', destination_city,
        'eta_display', eta_display,
        'status', status,
        'created_at', created_at,
        'eta', eta,
        'origin_place', origin_place,
        'destination_place', destination_place,
        'driver_id', driver_id,
        'vehicle_id', vehicle_id,
        'driver_name', driver_name,
        'vehicle_ref', vehicle_ref,
        'planned_departure', planned_departure,
        'priority', priority,
        'required_documents', required_documents
    ) INTO res
    FROM operations
    WHERE id = p_operation_id;
    
    RETURN res;
END;
$$;
