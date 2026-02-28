-- Migration: Fix legacy rpc_assign_operation schema mismatch
-- Created: 2026-02-27 16:35

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
  op_status text;
BEGIN
  -- 1. Get current status and verify operation ownership
  SELECT status INTO op_status
  FROM public.operations
  WHERE id = p_operation_id AND tenant_id = p_tenant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'operation_not_found');
  END IF;

  -- 2. Update operation
  -- Note: updated_at is handled by the set_updated_at trigger
  UPDATE public.operations
  SET
    driver_id = p_driver_id,
    vehicle_id = p_vehicle_id,
    planned_departure = p_planned_departure,
    priority = p_priority,
    status = 'assigned',
    assigned_at = now()
  WHERE id = p_operation_id AND tenant_id = p_tenant_id;

  -- 3. Audit Log with latest schema (metadata + actor_user_id)
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
    auth.uid(),
    'status_changed',
    'operation',
    p_operation_id,
    jsonb_build_object(
      'old_status', op_status,
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
