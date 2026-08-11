-- Migration: Create rpc_post_driver_event + rpc_list_tracking_tokens
-- Completes the tracking pipeline: Driver → Edge → RPC → DB
-- Created: 2026-02-27 18:15

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. rpc_post_driver_event
-- Called by track-driver Edge Function when a driver submits a location/action.
-- Validates driver token, inserts into tracking_events, updates operation status.
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rpc_post_driver_event(
    p_token TEXT,
    p_action TEXT,
    p_source TEXT DEFAULT 'gps',
    p_lat NUMERIC DEFAULT NULL,
    p_lng NUMERIC DEFAULT NULL,
    p_accuracy NUMERIC DEFAULT NULL,
    p_municipality TEXT DEFAULT NULL,
    p_state_name TEXT DEFAULT NULL,
    p_country_code CHAR(2) DEFAULT 'MX',
    p_incident_type TEXT DEFAULT NULL,
    p_incident_note TEXT DEFAULT NULL,
    p_client_timestamp TIMESTAMPTZ DEFAULT now(),
    p_offline_queued BOOLEAN DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_token          RECORD;
    v_event_id       UUID;
    v_operation_id   UUID;
    v_new_status     TEXT;
    v_valid_actions  TEXT[] := ARRAY['departure','in_transit','arrival','delivered','incident'];
BEGIN
    -- 1) Validate action
    IF p_action IS NULL OR NOT (p_action = ANY(v_valid_actions)) THEN
        RETURN jsonb_build_object('http', 400, 'accepted', false, 'reason', 'invalid_action');
    END IF;

    -- 2) Validate token via helper
    SELECT * INTO v_token FROM tracking_validate_token(p_token, 'driver:write');

    IF v_token IS NULL OR v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('http', 404, 'accepted', false, 'reason', 'not_found');
    END IF;

    IF v_token.token_state = 'revoked' THEN
        RETURN jsonb_build_object('http', 403, 'accepted', false, 'reason', 'revoked');
    END IF;

    IF v_token.token_state IN ('hard_expired', 'soft_expired', 'rotated') THEN
        RETURN jsonb_build_object('http', 403, 'accepted', false, 'reason', 'expired');
    END IF;

    IF v_token.expires_at < now() THEN
        RETURN jsonb_build_object('http', 403, 'accepted', false, 'reason', 'expired');
    END IF;

    v_operation_id := v_token.operation_id;

    -- 3) Anti-noise: check cooldown for in_transit events (30-min cooldown)
    IF p_action = 'in_transit' THEN
        IF EXISTS (
            SELECT 1 FROM tracking_events
            WHERE operation_id = v_operation_id
              AND event_type = 'in_transit'
              AND server_timestamp > now() - interval '30 minutes'
        ) THEN
            RETURN jsonb_build_object('http', 200, 'accepted', false, 'reason', 'cooldown');
        END IF;
    END IF;

    -- 4) Anti-noise: check incident cooldown (10-min cooldown)
    IF p_action = 'incident' THEN
        IF EXISTS (
            SELECT 1 FROM tracking_events
            WHERE operation_id = v_operation_id
              AND event_type = 'incident'
              AND server_timestamp > now() - interval '10 minutes'
        ) THEN
            RETURN jsonb_build_object('http', 200, 'accepted', false, 'reason', 'cooldown');
        END IF;
    END IF;

    -- 5) Detect suspicious: accuracy > 5000m or implausible jump
    -- For now, just flag if accuracy is > 5000m
    DECLARE
        v_suspicious BOOLEAN := false;
    BEGIN
        IF p_accuracy IS NOT NULL AND p_accuracy > 5000 THEN
            v_suspicious := true;
        END IF;

        -- 6) Insert event
        INSERT INTO tracking_events (
            token_id,
            tenant_id,
            operation_id,
            event_type,
            source,
            client_timestamp,
            server_timestamp,
            lat, lng, accuracy_m,
            municipality, state_name, country_code,
            incident_type, incident_note,
            is_suspicious,
            offline_queued
        )
        VALUES (
            v_token.token_id,
            v_token.tenant_id,
            v_operation_id,
            p_action,
            COALESCE(p_source, 'gps'),
            p_client_timestamp,
            now(),
            p_lat, p_lng, p_accuracy,
            p_municipality, p_state_name, p_country_code,
            p_incident_type, p_incident_note,
            v_suspicious,
            COALESCE(p_offline_queued, false)
        )
        RETURNING id INTO v_event_id;
    END;

    -- 7) Update operation status based on action
    v_new_status := CASE p_action
        WHEN 'departure'  THEN 'in_transit'
        WHEN 'in_transit' THEN 'in_transit'
        WHEN 'arrival'    THEN 'at_destination'
        WHEN 'delivered'  THEN 'delivered'
        ELSE NULL  -- incident doesn't change status
    END;

    IF v_new_status IS NOT NULL THEN
        UPDATE operations
        SET status = v_new_status
        WHERE id = v_operation_id
          -- Only advance status, never go backwards
          AND CASE status
            WHEN 'planned' THEN true
            WHEN 'assigned' THEN true
            WHEN 'in_transit' THEN v_new_status IN ('at_destination', 'delivered')
            WHEN 'at_destination' THEN v_new_status = 'delivered'
            ELSE false
          END;
    END IF;

    -- 8) Update token last_used_at
    UPDATE tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;

    -- 9) Return success
    RETURN jsonb_build_object(
        'http', 200,
        'accepted', true,
        'eventId', v_event_id
    );
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. rpc_list_tracking_tokens
-- Internal dashboard: list tracking tokens for the tenant with enriched data.
-- ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rpc_list_tracking_tokens(p_tenant_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- RBAC: must be member
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
                'id', t.id,
                'operation_id', t.operation_id,
                'token_hash', left(t.token_hash, 12) || '...',
                'scope', t.scope,
                'state', t.state,
                'created_at', t.created_at,
                'expires_at', t.expires_at,
                'last_used_at', t.last_used_at,
                -- Enriched from operation
                'reference_code', o.reference_code,
                'route_summary', o.route_summary,
                'client_display_name', o.client_display_name,
                'operation_status', o.status,
                -- Last known location
                'last_municipality', (
                    SELECT e.municipality || ', ' || e.state_name
                    FROM tracking_events e
                    WHERE e.operation_id = t.operation_id
                      AND e.municipality IS NOT NULL
                      AND e.event_type != 'incident'
                    ORDER BY e.server_timestamp DESC
                    LIMIT 1
                ),
                'last_event_at', (
                    SELECT to_char(e.server_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                    FROM tracking_events e
                    WHERE e.operation_id = t.operation_id
                    ORDER BY e.server_timestamp DESC
                    LIMIT 1
                )
            ) ORDER BY t.created_at DESC
        ), '[]'::jsonb)
        FROM tracking_tokens t
        LEFT JOIN operations o ON o.id = t.operation_id
        WHERE t.tenant_id = p_tenant_id
    );
END;
$$;


NOTIFY pgrst, 'reload schema';
