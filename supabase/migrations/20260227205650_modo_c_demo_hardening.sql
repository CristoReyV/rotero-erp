-- Migration: Modo C Demo Hardening

-- Paso 1: Agregar campo allow_demo_mode a tenant_settings
ALTER TABLE public.tenant_settings ADD COLUMN IF NOT EXISTS allow_demo_mode boolean DEFAULT false;

-- Paso 2: Crear el RPC rpc_demo_configure_module
CREATE OR REPLACE FUNCTION public.rpc_demo_configure_module(p_tenant_id uuid, p_module_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_allow_demo_mode boolean;
    v_config_data jsonb;
BEGIN
    -- 1. Validar que el caller es Admin del tenant
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role = 'admin'
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized', 'message', 'Only actual administrators can enable demo setups');
    END IF;

    -- 2. Validar que mode demo is authorized a nivel de settings
    SELECT allow_demo_mode INTO v_allow_demo_mode
    FROM tenant_settings
    WHERE id = p_tenant_id;

    IF v_allow_demo_mode IS NOT TRUE THEN
        RETURN jsonb_build_object('error', 'unauthorized', 'message', 'Demo mode is locked in this tenant environment');
    END IF;

    -- 3. Set the simulated demo data per module
    IF p_module_name = 'inventory' THEN
        v_config_data := '{"units": ["Piezas", "Cajas", "Kg", "Litros"]}';
    ELSIF p_module_name = 'billing' THEN
        v_config_data := '{"rfc": "EKU9003173C9", "csd_loaded": true}';
    ELSIF p_module_name = 'customs' THEN
        v_config_data := '{"patente": "9999", "api_key": "simulated"}';
    ELSE
        v_config_data := '{}';
    END IF;

    -- 4. Upsert the setup status mimicking rpc_configure_module
    INSERT INTO public.tenant_setup_status (tenant_id, module_name, is_configured, config_data)
    VALUES (p_tenant_id, p_module_name, true, v_config_data)
    ON CONFLICT (tenant_id, module_name)
    DO UPDATE SET 
        is_configured = EXCLUDED.is_configured,
        config_data = EXCLUDED.config_data,
        updated_at = now();

    RETURN jsonb_build_object('success', true, 'message', 'Demo setup completed for ' || p_module_name);
END;
$$;
