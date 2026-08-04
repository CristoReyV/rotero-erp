-- ============================================================
-- Post-Hotfix Stabilization: idempotent token creation + enriched audit
-- ============================================================

-- 1) Make rpc_create_tracking_token idempotent (return existing active token)
CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_ttl_hours integer DEFAULT NULL,
    p_force_rotate boolean DEFAULT false
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_token_literal TEXT;
    v_token_hash    TEXT;
    v_ttl           INTERVAL;
    v_new_id        UUID;
    v_existing_id   UUID;
    v_existing_exp  TIMESTAMPTZ;
    v_creator       UUID;
BEGIN
    -- RBAC
    IF auth.uid() IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM memberships
        WHERE user_id = auth.uid()
          AND tenant_id = p_tenant_id
          AND role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_scope NOT IN ('public:read', 'driver:write') THEN
        RETURN jsonb_build_object('error', 'invalid_scope');
    END IF;

    -- Check for existing active token
    SELECT id, expires_at INTO v_existing_id, v_existing_exp
    FROM tracking_tokens
    WHERE operation_id = p_operation_id AND scope = p_scope AND state = 'active';

    -- IDEMPOTENT: if active token exists and no forced rotation, return it
    IF v_existing_id IS NOT NULL AND NOT COALESCE(p_force_rotate, false) THEN
        RETURN jsonb_build_object(
            'token_id',        v_existing_id,
            'already_existed', true,
            'scope',           p_scope,
            'expires_at',      to_char(v_existing_exp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        );
    END IF;

    -- TTL calculation
    IF p_ttl_hours IS NOT NULL THEN
        IF p_scope = 'public:read' AND p_ttl_hours > 720 THEN p_ttl_hours := 720; END IF;
        IF p_scope = 'driver:write' AND p_ttl_hours > 72 THEN p_ttl_hours := 72; END IF;
        v_ttl := (p_ttl_hours || ' hours')::INTERVAL;
    ELSE
        v_ttl := CASE p_scope
            WHEN 'public:read'  THEN INTERVAL '7 days'
            WHEN 'driver:write' THEN INTERVAL '48 hours'
        END;
    END IF;

    v_creator := COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::UUID);

    -- Rotate existing active token if force_rotate
    IF v_existing_id IS NOT NULL THEN
        UPDATE tracking_tokens
        SET state = 'rotated', revoked_at = now(), revoked_by = v_creator
        WHERE id = v_existing_id;
    END IF;

    v_token_literal := gen_random_uuid()::TEXT;
    v_token_hash    := tracking_hash_token(v_token_literal);

    INSERT INTO tracking_tokens (
        tenant_id, operation_id, scope,
        token_hash, state, created_by, expires_at
    ) VALUES (
        p_tenant_id, p_operation_id, p_scope,
        v_token_hash, 'active', v_creator, now() + v_ttl
    )
    RETURNING id INTO v_new_id;

    IF v_existing_id IS NOT NULL THEN
        UPDATE tracking_tokens SET rotated_into = v_new_id WHERE id = v_existing_id;
    END IF;

    RETURN jsonb_build_object(
        'token_id',          v_new_id,
        'token',             v_token_literal,
        'scope',             p_scope,
        'expires_at',        to_char(now() + v_ttl, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'rotated_previous',  v_existing_id IS NOT NULL,
        'already_existed',   false
    );
END;
$$;


-- 2) Enriched rpc_transition_operation_status with better audit + revoked token detection
CREATE OR REPLACE FUNCTION public.rpc_transition_operation_status(p_operation_id uuid, p_to_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
    v_tenant_id uuid;
    v_current_status text;
    v_reqs jsonb;
    v_origin jsonb;
    v_dest jsonb;
    v_auto_token jsonb;
    v_had_revoked boolean := false;
    v_actor_email text;
BEGIN
    SELECT tenant_id, status, origin_place, destination_place
    INTO v_tenant_id, v_current_status, v_origin, v_dest
    FROM operations
    WHERE id = p_operation_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    -- Resolve actor email for audit
    SELECT email INTO v_actor_email FROM auth.users WHERE id = auth.uid();

    IF p_to_status = 'planned' THEN
        IF v_current_status != 'draft' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to planned from draft');
        END IF;
        IF v_origin IS NULL OR v_dest IS NULL THEN
            RETURN jsonb_build_object('error', 'missing_places');
        END IF;
    ELSIF p_to_status = 'assigned' THEN
        IF v_current_status != 'planned' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to assigned from planned');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_driver_assigned')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_driver');
        END IF;
    ELSIF p_to_status = 'in_transit' THEN
        IF v_current_status != 'assigned' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to in_transit from assigned');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_driver_assigned')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_driver');
        END IF;

        -- Check for revoked tokens (for audit enrichment)
        SELECT EXISTS(
            SELECT 1 FROM tracking_tokens
            WHERE operation_id = p_operation_id
              AND scope = 'driver:write'
              AND state IN ('revoked', 'rotated')
        ) INTO v_had_revoked;

        -- AUTO-PROVISION: idempotent — rpc_create_tracking_token returns existing if active
        IF NOT (v_reqs->>'has_driver_token')::boolean THEN
            v_auto_token := public.rpc_create_tracking_token(
                v_tenant_id, p_operation_id, 'driver:write', 48, false
            );
            IF v_auto_token ? 'error' THEN
                RETURN jsonb_build_object('error', 'token_auto_create_failed', 'detail', v_auto_token->>'error');
            END IF;
            -- Also create public:read token (idempotent)
            PERFORM public.rpc_create_tracking_token(
                v_tenant_id, p_operation_id, 'public:read', NULL, false
            );
            -- Audit the auto-creation
            INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
            VALUES (
                v_tenant_id,
                auth.uid(),
                'tracking_token_auto_created',
                'operation',
                p_operation_id,
                jsonb_build_object(
                    'token_id', v_auto_token->>'token_id',
                    'scope', 'driver:write',
                    'trigger', 'transition_to_in_transit',
                    'had_revoked_tokens', v_had_revoked,
                    'actor_email', COALESCE(v_actor_email, 'system'),
                    'already_existed', (v_auto_token->>'already_existed')::boolean
                )
            );
        END IF;
    ELSIF p_to_status = 'delivered' THEN
        IF v_current_status != 'in_transit' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to delivered from in_transit');
        END IF;
        v_reqs := public.rpc_get_operation_requirements(p_operation_id);
        IF NOT (v_reqs->>'has_delivered_event')::boolean THEN
            RETURN jsonb_build_object('error', 'missing_delivered_event');
        END IF;
    ELSIF p_to_status = 'closed' THEN
        IF v_current_status != 'delivered' THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Can only transition to closed from delivered');
        END IF;
    ELSIF p_to_status = 'cancelled' THEN
        IF v_current_status NOT IN ('draft', 'planned', 'assigned') THEN
            RETURN jsonb_build_object('error', 'invalid_transition', 'msg', 'Use override to cancel in_transit or delivered');
        END IF;
    ELSE
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;

    UPDATE operations SET
        status = p_to_status,
        assigned_at = CASE WHEN p_to_status = 'assigned' THEN NOW() ELSE assigned_at END,
        closed_at = CASE WHEN p_to_status = 'closed' THEN NOW() ELSE closed_at END,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN NOW() ELSE cancelled_at END
    WHERE id = p_operation_id;

    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (
        v_tenant_id,
        auth.uid(),
        'status_changed',
        'operation',
        p_operation_id,
        jsonb_build_object(
            'from_status', v_current_status,
            'to_status', p_to_status,
            'auto_token_created', (v_auto_token IS NOT NULL AND NOT COALESCE((v_auto_token->>'already_existed')::boolean, false)),
            'auto_token_id', v_auto_token->>'token_id',
            'actor_email', COALESCE(v_actor_email, 'system'),
            'had_revoked_tokens', v_had_revoked
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'auto_token_created', (v_auto_token IS NOT NULL AND NOT COALESCE((v_auto_token->>'already_existed')::boolean, false))
    );
END;
$$;

NOTIFY pgrst, 'reload schema';
