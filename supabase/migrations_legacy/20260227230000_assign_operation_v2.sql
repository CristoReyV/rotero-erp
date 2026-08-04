-- Migration: rpc_assign_operation_v2
-- Description: Enhanced assignment function for Operations Workflow V2

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v2(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_driver_id uuid,
    p_driver_name text,
    p_vehicle_id uuid,
    p_vehicle_ref text,
    p_planned_departure timestamptz,
    p_priority text DEFAULT 'normal'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id uuid;
    v_caller_role text;
    v_old_status text;
    v_audit_id uuid;
BEGIN
    -- 1. Get caller info
    v_caller_id := auth.uid();
    
    SELECT role INTO v_caller_role
    FROM memberships
    WHERE user_id = v_caller_id AND tenant_id = p_tenant_id;

    -- 2. Validate Membership & Role
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'operator') THEN
        RETURN jsonb_build_object('error', 'unauthorized_access');
    END IF;

    -- 3. Get current state and verify ownership
    SELECT status INTO v_old_status
    FROM operations
    WHERE db_id = p_operation_id AND tenant_id = p_tenant_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'operation_not_found');
    END IF;

    -- 4. Execute Update
    UPDATE operations
    SET 
        driver_id = p_driver_id,
        driver_name = p_driver_name,
        vehicle_id = p_vehicle_id,
        vehicle_ref = p_vehicle_ref,
        planned_departure = p_planned_departure,
        priority = p_priority,
        status = 'planned', -- Per V2 workflow, assignment usually happens in planned but stays in 'planned' until transit
        assigned_at = now(),
        updated_at = now()
    WHERE db_id = p_operation_id 
      AND tenant_id = p_tenant_id;

    -- 5. Audit Log
    INSERT INTO audit_log (
        tenant_id,
        user_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        p_tenant_id,
        v_caller_id,
        'status_changed',
        'operation',
        p_operation_id,
        jsonb_build_object(
            'old_status', v_old_status,
            'new_status', 'planned',
            'assigned_to_driver', p_driver_name,
            'assigned_vehicle', p_vehicle_ref,
            'assignment_version', 'v2'
        )
    ) RETURNING id INTO v_audit_id;

    RETURN jsonb_build_object(
        'success', true,
        'audit_id', v_audit_id
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- Reload schema for PostgREST
NOTIFY pgrst, 'reload schema';
