-- Fix: auto-provision driver token when transitioning assigned → in_transit
-- instead of blocking with 'missing_driver_token'
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
        -- AUTO-PROVISION: if no active driver token, create one silently
        IF NOT (v_reqs->>'has_driver_token')::boolean THEN
            v_auto_token := public.rpc_create_tracking_token(
                v_tenant_id, p_operation_id, 'driver:write', 48
            );
            IF v_auto_token ? 'error' THEN
                RETURN jsonb_build_object('error', 'token_auto_create_failed', 'detail', v_auto_token->>'error');
            END IF;
            -- Also create public:read token
            PERFORM public.rpc_create_tracking_token(
                v_tenant_id, p_operation_id, 'public:read', NULL
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
                    'trigger', 'transition_to_in_transit'
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
            'auto_token_created', (v_auto_token IS NOT NULL)
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'auto_token_created', (v_auto_token IS NOT NULL)
    );
END;
$$;

NOTIFY pgrst, 'reload schema';
