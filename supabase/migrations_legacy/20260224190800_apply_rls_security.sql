-- 1. MIGRAR ROLES EXISTENTES Y AGREGAR CHECK
UPDATE memberships SET role = 'operator' WHERE role = 'member';

ALTER TABLE memberships DROP CONSTRAINT IF EXISTS memberships_role_check;
ALTER TABLE memberships ADD CONSTRAINT memberships_role_check CHECK (role IN ('admin', 'operator', 'viewer'));

-- 2. HARDEN rpc_create_tracking_token (Bloquear cross-tenant y roles insuficientes)
CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text DEFAULT 'public:read'::text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    new_token text;
    new_id uuid;
BEGIN
    -- [SECURITY GUARD] Verificar que auth.uid() es miembro del tenant con rol de 'admin' o 'operator'
    IF NOT EXISTS (
        SELECT 1 FROM memberships
        WHERE user_id = auth.uid()
          AND tenant_id = p_tenant_id
          AND role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    new_token := 'trk_' || substr(md5(random()::text), 1, 16);
    
    INSERT INTO tracking_tokens (tenant_id, operation_id, token, scope)
    VALUES (p_tenant_id, p_operation_id, new_token, p_scope)
    RETURNING id INTO new_id;

    RETURN jsonb_build_object('id', new_id, 'token', new_token);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 3. HARDEN rpc_revoke_tracking_token (Bloquear cross-tenant y roles insuficientes)
CREATE OR REPLACE FUNCTION public.rpc_revoke_tracking_token(
    p_token_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    -- [SECURITY GUARD] Verificar que el token pertenece a un tenant donde el caller es admin/operator
    IF NOT EXISTS (
        SELECT 1 FROM tracking_tokens t
        JOIN memberships m ON m.tenant_id = t.tenant_id
        WHERE t.id = p_token_id
          AND m.user_id = auth.uid()
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    UPDATE tracking_tokens
    SET status = 'revoked', updated_at = now()
    WHERE id = p_token_id;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- 4. NUEVA RPC: rpc_get_my_context (Para cargar sesión en el cliente)
CREATE OR REPLACE FUNCTION public.rpc_get_my_context()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'user_id', auth.uid(),
        'email', (SELECT email FROM auth.users WHERE id = auth.uid()),
        'memberships', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tenant_id', m.tenant_id,
                'role', m.role,
                'tenant_name', t.name
            ))
            FROM memberships m
            JOIN tenants t ON t.id = m.tenant_id
            WHERE m.user_id = auth.uid()
        ), '[]'::jsonb)
    ) INTO result;
    
    RETURN result;
END;
$$;


-- 5. ACTIVAR RLS EN MEMBERSHIPS
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own memberships" ON memberships;
CREATE POLICY "Users can view their own memberships" 
    ON memberships FOR SELECT 
    TO authenticated 
    USING (user_id = auth.uid());

-- 6. ACTIVAR RLS EN TENANTS
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view tenants they are members of" ON tenants;
CREATE POLICY "Users can view tenants they are members of" 
    ON tenants FOR SELECT 
    TO authenticated 
    USING (id IN (
        SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
    ));

-- 7. ACTIVAR RLS EN OPERATIONS
ALTER TABLE operations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view operations in their tenants" ON operations;
CREATE POLICY "Users can view operations in their tenants" 
    ON operations FOR SELECT 
    TO authenticated 
    USING (tenant_id IN (
        SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
    ));

-- (Las tablas tracking_tokens y tracking_events ya tienen policies similares y RLS encendido)
