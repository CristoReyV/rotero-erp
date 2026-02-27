-- Migration: Operations Core

UPDATE operations SET status = 'in_transit' WHERE status = 'active';
UPDATE operations SET status = 'planned' WHERE status = 'assigned';

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'operations_status_check'
    ) THEN
        ALTER TABLE operations DROP CONSTRAINT operations_status_check;
    END IF;
END $$;

ALTER TABLE operations ADD CONSTRAINT operations_status_check 
    CHECK (status IN ('draft', 'planned', 'in_transit', 'delivered', 'cancelled'));

ALTER TABLE operations ALTER COLUMN status SET DEFAULT 'planned';

ALTER TABLE operations ADD COLUMN IF NOT EXISTS origin_place JSONB;
ALTER TABLE operations ADD COLUMN IF NOT EXISTS destination_place JSONB;
ALTER TABLE operations ADD COLUMN IF NOT EXISTS eta TIMESTAMPTZ;

-- Drop duplicates and enforce reference uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS operations_tenant_reference_idx ON operations(tenant_id, reference_code);

-- RLS
ALTER TABLE operations ENABLE ROW LEVEL SECURITY;

-- Clean existing policies for operations before recreating to be idempotent
DROP POLICY IF EXISTS "Users can create operations in their tenants" ON operations;
DROP POLICY IF EXISTS "Users can update operations in their tenants" ON operations;
DROP POLICY IF EXISTS "Users can delete operations in their tenants" ON operations;

CREATE POLICY "Users can create operations in their tenants"
ON operations FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = operations.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update operations in their tenants"
ON operations FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = operations.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can delete operations in their tenants"
ON operations FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = operations.tenant_id
          AND m.role = 'admin'
    )
);

-- RPC for list operations
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
                'destination_place', destination_place
            ) ORDER BY created_at DESC
        ), '[]'::jsonb)
        FROM operations
        WHERE tenant_id = p_tenant_id
    );
END;
$$;

-- RPC for create operation
CREATE OR REPLACE FUNCTION public.rpc_create_operation(
    p_tenant_id uuid,
    p_reference_code text,
    p_route_summary text DEFAULT NULL,
    p_client_display_name text DEFAULT NULL,
    p_destination_city text DEFAULT NULL,
    p_eta_display text DEFAULT NULL,
    p_status text DEFAULT 'planned',
    p_origin_place jsonb DEFAULT NULL,
    p_destination_place jsonb DEFAULT NULL,
    p_eta timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    
    INSERT INTO operations (
        tenant_id, reference_code, route_summary, client_display_name, 
        destination_city, eta_display, status, origin_place, destination_place, eta
    )
    VALUES (
        p_tenant_id, p_reference_code, p_route_summary, p_client_display_name,
        p_destination_city, p_eta_display, p_status, p_origin_place, p_destination_place, p_eta
    )
    RETURNING id INTO new_id;
    
    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'reference_exists');
WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC for get operation
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
        'destination_place', destination_place
    ) INTO res
    FROM operations
    WHERE id = p_operation_id;
    
    RETURN res;
END;
$$;
