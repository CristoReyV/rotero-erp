-- Migration: Secure rpc_assign_operation (V1) with RBAC and Schema Fix
-- Created: 2026-02-27 16:47

CREATE OR REPLACE FUNCTION public.rpc_assign_operation(
  p_tenant_id uuid,
  p_operation_id uuid,
  p_driver_id uuid,
  p_vehicle_id uuid,
  p_planned_departure timestamptz,
  p_priority text DEFAULT 'normal'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_op_status text;
  v_caller_id uuid;
  v_caller_role text;
BEGIN
  -- 1. Get caller and check membership/role (RBAC)
  v_caller_id := auth.uid();
  
  SELECT role INTO v_caller_role
  FROM memberships
  WHERE user_id = v_caller_id AND tenant_id = p_tenant_id;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'operator') THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- 2. Verify operation existence, tenant ownership and get current status
  SELECT status INTO v_op_status
  FROM public.operations
  WHERE id = p_operation_id AND tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'operation_not_found');
  END IF;

  -- 3. Transition Hardening: Only allow assignment if currently 'planned'
  -- (If more statuses allowed, adjust IN clause)
  IF v_op_status NOT IN ('planned') THEN
    RETURN jsonb_build_object(
      'error', 'invalid_status_transition',
      'current_status', v_op_status
    );
  END IF;

  -- 4. Update operations (updated_at handled by system trigger)
  UPDATE public.operations
  SET
    driver_id = p_driver_id,
    vehicle_id = p_vehicle_id,
    planned_departure = p_planned_departure,
    priority = p_priority,
    status = 'assigned',
    assigned_at = now()
  WHERE id = p_operation_id AND tenant_id = p_tenant_id;

  -- 5. Insert audit_log (Correct Schema)
  INSERT INTO public.audit_log (
    tenant_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  VALUES (
    p_tenant_id,
    v_caller_id,
    'status_changed',
    'operation',
    p_operation_id,
    jsonb_build_object(
      'old_status', v_op_status,
      'new_status', 'assigned',
      'changed_fields', jsonb_build_array('driver_id','vehicle_id','planned_departure','priority'),
      'driver_id', p_driver_id,
      'vehicle_id', p_vehicle_id,
      'planned_departure', p_planned_departure,
      'priority', p_priority
    )
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

NOTIFY pgrst, 'reload schema';
