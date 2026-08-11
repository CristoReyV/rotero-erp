/* 14. Hardening and Performance */

-- Create index on invitations token_hash
CREATE INDEX IF NOT EXISTS idx_invitations_token_hash ON invitations (token_hash);

-- Modify rpc_create_invitation to use digest
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
    IF NOT EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id AND m.role IN ('admin', 'operator')) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_role NOT IN ('admin', 'operator', 'viewer') THEN
        RETURN jsonb_build_object('error', 'invalid_role');
    END IF;

    IF EXISTS (SELECT 1 FROM memberships m JOIN auth.users u ON m.user_id = u.id WHERE u.email = p_email AND m.tenant_id = p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'already_member');
    END IF;

    v_token := encode(gen_random_bytes(32), 'hex');
    -- Use deterministic SHA256 as requested for invitations.token_hash
    v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

    INSERT INTO invitations (tenant_id, email, role, token_hash, expires_at, created_by)
    VALUES (p_tenant_id, p_email, p_role, v_token_hash, now() + interval '7 days', auth.uid())
    RETURNING id INTO new_id;

    PERFORM rpc_write_audit(p_tenant_id, 'create_invitation', 'invitation', new_id, jsonb_build_object('email', p_email, 'role', p_role));
    
    RETURN jsonb_build_object('success', true, 'id', new_id, 'token', v_token);
END;
$$;


-- Modify rpc_accept_invitation for password policy and SHA256 tokens
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
    v_token_hash text;
BEGIN
    -- Password Policy Check (Min 8 chars, 1 uppercase, 1 number)
    IF length(p_password) < 8 OR p_password !~ '[A-Z]' OR p_password !~ '[0-9]' THEN
        RETURN jsonb_build_object('error', 'password_policy_failed', 'message', 'Password must be at least 8 characters long, contain 1 uppercase letter and 1 number');
    END IF;

    -- Token hash backwards compatibility: support crypt and simple sha256. 
    v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

    SELECT * INTO v_invitation 
    FROM invitations 
    WHERE accepted_at IS NULL AND expires_at > now() 
    AND (
       token_hash = v_token_hash 
       OR token_hash = crypt(p_token, token_hash)
    )
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

NOTIFY pgrst, 'reload schema';
