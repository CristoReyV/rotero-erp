-- Migration: Config Gating System

CREATE TABLE IF NOT EXISTS public.tenant_setup_status (
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    module_name text NOT NULL,
    is_configured boolean NOT NULL DEFAULT false,
    config_data jsonb DEFAULT '{}'::jsonb,
    updated_at timestamptz DEFAULT now(),
    updated_by uuid REFERENCES auth.users(id),
    PRIMARY KEY (tenant_id, module_name)
);

ALTER TABLE public.tenant_setup_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their tenant's setup status" ON public.tenant_setup_status
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_setup_status.tenant_id
    ));

CREATE POLICY "Admins can update their tenant's setup status" ON public.tenant_setup_status
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_setup_status.tenant_id AND m.role = 'admin'
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_setup_status.tenant_id AND m.role = 'admin'
    ));

-- RPC: rpc_validate_module_access
CREATE OR REPLACE FUNCTION public.rpc_validate_module_access(p_tenant_id uuid, p_module_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_configured boolean;
    v_config_data jsonb;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized', 'is_configured', false);
    END IF;

    SELECT is_configured, config_data INTO v_is_configured, v_config_data
    FROM tenant_setup_status
    WHERE tenant_id = p_tenant_id AND module_name = p_module_name;

    IF v_is_configured IS NULL THEN
        RETURN jsonb_build_object('is_configured', false, 'config_data', '{}'::jsonb);
    END IF;

    RETURN jsonb_build_object('is_configured', v_is_configured, 'config_data', v_config_data);
END;
$$;

-- RPC: rpc_configure_module (Added to allow frontend to setup modules)
CREATE OR REPLACE FUNCTION public.rpc_configure_module(p_tenant_id uuid, p_module_name text, p_config_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role = 'admin'
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized_admin_required');
    END IF;

    INSERT INTO tenant_setup_status (tenant_id, module_name, is_configured, config_data, updated_by)
    VALUES (p_tenant_id, p_module_name, true, p_config_data, auth.uid())
    ON CONFLICT (tenant_id, module_name) DO UPDATE 
    SET is_configured = true,
        config_data = EXCLUDED.config_data,
        updated_at = now(),
        updated_by = EXCLUDED.updated_by;

    RETURN jsonb_build_object('success', true);
END;
$$;
