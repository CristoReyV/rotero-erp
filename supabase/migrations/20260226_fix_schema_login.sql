/* Fix Schema Login and Dashboard RPCs */

-- Grants to ensure Authenticated can execute everything properly
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_context() TO authenticated;

-- Fix rpc_get_my_context
CREATE OR REPLACE FUNCTION public.rpc_get_my_context()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- Fix rpc_create_invitation hash
CREATE OR REPLACE FUNCTION public.rpc_create_invitation(
    p_tenant_id uuid,
    p_email text,
    p_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
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

    IF EXISTS (SELECT 1 FROM memberships m JOIN auth.users u ON m.user_id = u.id WHERE u.email = p_email AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'already_member');
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');
    -- FIX: Use crypt instead of md5
    v_token_hash := crypt(v_token, gen_salt('bf'));

    INSERT INTO invitations (tenant_id, email, role, token_hash, expires_at, created_by)
    VALUES (p_tenant_id, p_email, p_role, v_token_hash, now() + interval '7 days', auth.uid())
    RETURNING id INTO new_id;

    PERFORM rpc_write_audit(p_tenant_id, 'create_invitation', 'invitation', new_id, jsonb_build_object('email', p_email, 'role', p_role));
    
    RETURN jsonb_build_object('success', true, 'id', new_id, 'token', v_token);
END;
$$;

-- Fix rpc_accept_invitation search_path and null contraints
CREATE OR REPLACE FUNCTION public.rpc_accept_invitation(
    p_token text,
    p_password text,
    p_full_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_invitation record;
    v_user_id uuid;
BEGIN
    SELECT * INTO v_invitation 
    FROM invitations 
    WHERE accepted_at IS NULL AND expires_at > now() 
    AND token_hash = crypt(p_token, token_hash)
    LIMIT 1;

    IF v_invitation IS NULL OR v_invitation.id IS NULL THEN
        RETURN jsonb_build_object('error', 'invalid_or_expired');
    END IF;

    SELECT id INTO v_user_id FROM auth.users WHERE email = v_invitation.email;

    IF v_user_id IS NULL THEN
        v_user_id := gen_random_uuid();
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
            confirmation_token, recovery_token, email_change_token_new, email_change
        ) VALUES (
            '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated', v_invitation.email, crypt(p_password, gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', p_full_name), now(), now(),
            '', '', '', ''
        );

        INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
        VALUES (
            gen_random_uuid(), v_user_id, format('{"sub":"%s","email":"%s"}', v_user_id::text, v_invitation.email)::jsonb, 'email', v_user_id::text, now(), now(), now()
        );
    ELSE
        UPDATE auth.users 
        SET encrypted_password = crypt(p_password, gen_salt('bf')),
            raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{full_name}', to_jsonb(p_full_name))
        WHERE id = v_user_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM memberships WHERE user_id = v_user_id AND tenant_id = v_invitation.tenant_id) THEN
        INSERT INTO memberships (tenant_id, user_id, role)
        VALUES (v_invitation.tenant_id, v_user_id, v_invitation.role);
    ELSE
        UPDATE memberships SET role = v_invitation.role WHERE user_id = v_user_id AND tenant_id = v_invitation.tenant_id;
    END IF;

    UPDATE invitations SET accepted_at = now() WHERE id = v_invitation.id;

    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (v_invitation.tenant_id, v_user_id, 'invitation_accepted', 'membership', v_user_id, jsonb_build_object('invitation_id', v_invitation.id));

    RETURN jsonb_build_object('success', true);
END;
$$;

-- Fix rpc_dashboard_overview missing columns
CREATE OR REPLACE FUNCTION public.rpc_dashboard_overview(
    p_tenant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ops_total int;
    v_ops_in_transit int;
    v_billing_total numeric;
    v_inventory_value numeric;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m 
        WHERE m.user_id = auth.uid() 
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT count(*) INTO v_ops_total FROM operations WHERE tenant_id = p_tenant_id;
    SELECT count(*) INTO v_ops_in_transit FROM operations WHERE tenant_id = p_tenant_id AND status = 'in_transit';
    
    SELECT COALESCE(SUM(total), 0) INTO v_billing_total 
    FROM billing_cfdis 
    WHERE tenant_id = p_tenant_id AND status = 'Timbrado';

    SELECT COALESCE(SUM(qty_on_hand * unit_cost), 0) INTO v_inventory_value 
    FROM inventory_lots 
    WHERE tenant_id = p_tenant_id AND status = 'available';

    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'ops_total', v_ops_total,
            'ops_in_transit', v_ops_in_transit,
            'billing_total', v_billing_total,
            'inventory_value', v_inventory_value
        ),
        'chart', jsonb_build_object(
            'data', jsonb_build_array(40, 65, 45, 90, 55, 75, 50, 80, 60, 95, 70, 85),
            'labels', jsonb_build_array('Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic')
        )
    );
END;
$$;

-- Fix rpc_dashboard_recent_activity missing columns
CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(
    p_tenant_id uuid,
    p_limit int DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
                'id', reference_code,
                'client', client_display_name,
                'status', status,
                'route', route_summary,
                'eta', eta_display
            )
        ), '[]'::jsonb)
        FROM (
            SELECT reference_code, tenant_id, status, route_summary, client_display_name, eta_display
            FROM operations
            WHERE tenant_id = p_tenant_id
            ORDER BY created_at DESC
            LIMIT p_limit
        ) sub
    );
END;
$$;

-- Notify PostgREST to reload schema cache properly
NOTIFY pgrst, 'reload schema';
