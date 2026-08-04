-- Migration: Settings, Users & Audit (Admin Console)

-- 1. Tablas
CREATE TABLE IF NOT EXISTS tenant_settings (
    tenant_id uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
    brand_name text NOT NULL DEFAULT 'WLS Rotero',
    primary_color text NOT NULL DEFAULT '#0F2B5B',
    logo_url text,
    timezone text NOT NULL DEFAULT 'America/Mexico_City',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email text NOT NULL,
    role text NOT NULL CHECK (role IN ('admin', 'operator', 'viewer')),
    token_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT unique_tenant_email UNIQUE (tenant_id, email, accepted_at)
);

CREATE TABLE IF NOT EXISTS audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    metadata jsonb,
    created_at timestamptz DEFAULT now()
);

-- Índices de auditoría
CREATE INDEX idx_audit_log_tenant_created ON audit_log(tenant_id, created_at DESC);
CREATE INDEX idx_audit_log_entity ON audit_log(tenant_id, entity_type, entity_id);

-- 2. RLS Policies
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Tenant Settings RLS
CREATE POLICY "Users can view their tenant settings"
ON tenant_settings FOR SELECT
USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_settings.tenant_id));

CREATE POLICY "Admins and Operators can update tenant settings"
ON tenant_settings FOR UPDATE
USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_settings.tenant_id AND m.role IN ('admin', 'operator')));

CREATE POLICY "Admins can insert tenant settings" 
ON tenant_settings FOR INSERT
WITH CHECK (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = tenant_settings.tenant_id AND m.role = 'admin'));

-- Invitations RLS
CREATE POLICY "Admins and Operators can view invitations"
ON invitations FOR SELECT
USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = invitations.tenant_id AND m.role IN ('admin', 'operator')));

CREATE POLICY "Admins can insert invitations"
ON invitations FOR INSERT
WITH CHECK (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = invitations.tenant_id AND m.role = 'admin'));

CREATE POLICY "Admins can update invitations (revoke)"
ON invitations FOR UPDATE
USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = invitations.tenant_id AND m.role = 'admin'));

-- Audit Log RLS
CREATE POLICY "Users can view audit_log"
ON audit_log FOR SELECT
USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = audit_log.tenant_id));

-- Note: Audit logs should only be inserted via RPC (rpc_write_audit), so no INSERT policy directly.

-- 3. Core RPC Helper for Audit
CREATE OR REPLACE FUNCTION public.rpc_write_audit(
    p_action text,
    p_entity_type text,
    p_entity_id uuid,
    p_metadata jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    -- We extract tenant_id from the first membership.
    -- To make this completely safe, we should ideally pass tenant_id, but we infer it for the session user.
    -- For safety in multi-tenant contexts where a user has multiple tenants, we rely on the DB transaction context or require strict tenant passing.
    -- As a fallback helper, we'll try to find the active tenant from current request context or just grab the first membership.
    -- BEST PRACTICE: pass tenant_id. Since we don't have it in signature, we look it up (Careful if user is in multiple tenants!)
    -- For this MVP architecture, passing it explicitly is much safer.
    -- WE EXPECT THE CALLER TO HANDLE IT, but we'll re-declare below.
END;
$$;
DROP FUNCTION public.rpc_write_audit; -- Recreating safely

CREATE OR REPLACE FUNCTION public.rpc_write_audit(
    p_tenant_id uuid,
    p_action text,
    p_entity_type text,
    p_entity_id uuid,
    p_metadata jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (p_tenant_id, auth.uid(), p_action, p_entity_type, p_entity_id, p_metadata);
END;
$$;

-- 4. User/Membership RPCs
CREATE OR REPLACE FUNCTION public.rpc_list_members(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'user_id', m.user_id,
                'role', m.role,
                'created_at', m.created_at,
                'email', u.email,
                'name', (u.raw_user_meta_data->>'full_name')
            ) ORDER BY m.created_at DESC
        ), '[]'::jsonb)
        FROM memberships m
        LEFT JOIN auth.users u ON u.id = m.user_id
        WHERE m.tenant_id = p_tenant_id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_update_member_role(p_tenant_id uuid, p_member_user_id uuid, p_new_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only Admins can change roles
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role = 'admin') THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_new_role NOT IN ('admin', 'operator', 'viewer') THEN
        RETURN jsonb_build_object('error', 'invalid_role');
    END IF;

    UPDATE memberships SET role = p_new_role WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    
    PERFORM rpc_write_audit(p_tenant_id, 'update_role', 'membership', p_member_user_id, jsonb_build_object('new_role', p_new_role));
    
    RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_deactivate_member(p_tenant_id uuid, p_member_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only Admins can deactivate
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role = 'admin') THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- MVP: Hard delete membership to revoke access (or soft delete if we add disabled_at later)
    DELETE FROM memberships WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    
    PERFORM rpc_write_audit(p_tenant_id, 'deactivate_member', 'membership', p_member_user_id, 'null'::jsonb);
    
    RETURN jsonb_build_object('success', true);
END;
$$;

-- 5. Invitations RPCs
CREATE OR REPLACE FUNCTION public.rpc_create_invitation(p_tenant_id uuid, p_email text, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token text;
    v_token_hash text;
    new_id uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role = 'admin') THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_role NOT IN ('admin', 'operator', 'viewer') THEN
        RETURN jsonb_build_object('error', 'invalid_role');
    END IF;

    -- Check if user is already a member
    IF EXISTS (SELECT 1 FROM memberships m JOIN auth.users u ON m.user_id = u.id WHERE u.email = p_email AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'already_member');
    END IF;

    -- Generate a simple random token (INSECURE FOR REAL PROD if not using cryptographically secure random, but good for MVP structure)
    v_token := encode(gen_random_bytes(32), 'hex');
    -- We can use pg_crypto's digest here, but for now just storing the hash
    v_token_hash := crypt(v_token, gen_salt('bf'));

    INSERT INTO invitations (tenant_id, email, role, token_hash, expires_at, created_by)
    VALUES (p_tenant_id, p_email, p_role, v_token_hash, now() + interval '7 days', auth.uid())
    RETURNING id INTO new_id;

    PERFORM rpc_write_audit(p_tenant_id, 'create_invitation', 'invitation', new_id, jsonb_build_object('email', p_email, 'role', p_role));
    
    -- IMPORTANT: Return the token ONCE so the backend service can mail it.
    RETURN jsonb_build_object('success', true, 'id', new_id, 'token', v_token);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_revoke_invitation(p_tenant_id uuid, p_invitation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role = 'admin') THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Hard delete for revocation
    DELETE FROM invitations WHERE id = p_invitation_id AND tenant_id = p_tenant_id AND accepted_at IS NULL;
    
    PERFORM rpc_write_audit(p_tenant_id, 'revoke_invitation', 'invitation', p_invitation_id, 'null'::jsonb);

    RETURN jsonb_build_object('success', true);
END;
$$;

-- Note: rpc_accept_invitation left out as it requires auth.users inserts which is highly locked down by supabase.
-- To properly accept invitations in Supabase, we invite via GoTrue admin API directly (inviteUserByEmail).
-- This custom token system is possible but harder without `security definer` executing over auth schema.
-- We will just scaffold it minimally to pretend it works for the MVP or return success if the token matches.

-- 6. Audit Log RPC
CREATE OR REPLACE FUNCTION public.rpc_list_audit_log(p_tenant_id uuid, p_limit int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', a.id,
                'action', a.action,
                'entity_type', a.entity_type,
                'entity_id', a.entity_id,
                'created_at', a.created_at,
                'metadata', a.metadata,
                'actor_id', a.actor_user_id,
                'actor_email', u.email,
                'actor_name', (u.raw_user_meta_data->>'full_name')
            ) ORDER BY a.created_at DESC
        ), '[]'::jsonb)
        FROM audit_log a
        LEFT JOIN auth.users u ON u.id = a.actor_user_id
        WHERE a.tenant_id = p_tenant_id
        LIMIT p_limit
    );
END;
$$;

-- 7. Settings RPCs
CREATE OR REPLACE FUNCTION public.rpc_get_tenant_settings(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    res jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT to_jsonb(t.*) INTO res FROM tenant_settings t WHERE t.tenant_id = p_tenant_id;
    
    IF res IS NULL THEN
        -- Auto-create defaults if none exist (lazy init)
        INSERT INTO tenant_settings (tenant_id) VALUES (p_tenant_id);
        SELECT to_jsonb(t.*) INTO res FROM tenant_settings t WHERE t.tenant_id = p_tenant_id;
    END IF;

    RETURN res;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_update_tenant_settings(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role IN ('admin', 'operator')) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    UPDATE tenant_settings SET
        brand_name = COALESCE(p_payload->>'brand_name', brand_name),
        primary_color = COALESCE(p_payload->>'primary_color', primary_color),
        timezone = COALESCE(p_payload->>'timezone', timezone),
        updated_at = now()
    WHERE tenant_id = p_tenant_id;

    PERFORM rpc_write_audit(p_tenant_id, 'update_settings', 'tenant_settings', p_tenant_id, p_payload);

    RETURN jsonb_build_object('success', true);
END;
$$;
