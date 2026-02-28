-- Migration: Operations Workflow Hardening

-- Add new fields
ALTER TABLE operations 
ADD COLUMN IF NOT EXISTS driver_id UUID,
ADD COLUMN IF NOT EXISTS vehicle_id UUID,
ADD COLUMN IF NOT EXISTS planned_departure TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'normal',
ADD COLUMN IF NOT EXISTS required_documents JSONB DEFAULT '[]'::jsonb;

-- Update constraint
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'operations_status_check'
    ) THEN
        ALTER TABLE operations DROP CONSTRAINT operations_status_check;
    END IF;
END $$;

ALTER TABLE operations ADD CONSTRAINT operations_status_check 
    CHECK (status IN ('draft', 'planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed'));

-- RPC to assign operation
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
    op_tenant_id uuid;
    op_status text;
BEGIN
    -- Verify authorization
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Verify operation exists and belongs to tenant
    SELECT tenant_id, status INTO op_tenant_id, op_status 
    FROM operations 
    WHERE id = p_operation_id;

    IF op_tenant_id IS NULL OR op_tenant_id != p_tenant_id THEN
        RETURN jsonb_build_object('error', 'not_found_or_unauthorized');
    END IF;

    -- Update operation
    UPDATE operations SET 
        driver_id = p_driver_id,
        vehicle_id = p_vehicle_id,
        planned_departure = p_planned_departure,
        priority = p_priority,
        status = 'assigned',
        updated_at = NOW()
    WHERE id = p_operation_id;

    -- Insert audit log
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
            'changed_fields', jsonb_build_array('driver_id', 'vehicle_id', 'planned_departure', 'priority')
        )
    );

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- Update list RPC
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
                'planned_departure', planned_departure,
                'priority', priority
            ) ORDER BY created_at DESC
        ), '[]'::jsonb)
        FROM operations
        WHERE tenant_id = p_tenant_id
    );
END;
$$;

-- Update get RPC
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
        'planned_departure', planned_departure,
        'priority', priority,
        'required_documents', required_documents
    ) INTO res
    FROM operations
    WHERE id = p_operation_id;
    
    RETURN res;
END;
$$;
