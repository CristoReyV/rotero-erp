-- ============================================================
-- Tracking Route v1: GPS route points, throttling, public route
-- ============================================================

-- 1) Haversine helper: returns distance in meters between two GPS points
CREATE OR REPLACE FUNCTION public.haversine_m(
    lat1 double precision, lng1 double precision,
    lat2 double precision, lng2 double precision
) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT 6371000.0 * 2 * asin(sqrt(
        sin(radians(lat2 - lat1) / 2) ^ 2 +
        cos(radians(lat1)) * cos(radians(lat2)) *
        sin(radians(lng2 - lng1) / 2) ^ 2
    ));
$$;

-- 2) Table: tracking_route_points (append-only GPS breadcrumbs)
CREATE TABLE IF NOT EXISTS public.tracking_route_points (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     uuid NOT NULL,
    operation_id  uuid NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
    token_id      uuid NOT NULL REFERENCES tracking_tokens(id) ON DELETE CASCADE,
    recorded_at   timestamptz NOT NULL DEFAULT now(),
    lat           double precision NOT NULL,
    lng           double precision NOT NULL,
    accuracy_m    double precision,
    source        text NOT NULL CHECK (source IN ('gps','network'))
);

-- 3) Indexes
CREATE INDEX IF NOT EXISTS idx_route_points_op_time
    ON tracking_route_points (tenant_id, operation_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_route_points_token_time
    ON tracking_route_points (token_id, recorded_at DESC);

-- 4) RLS
ALTER TABLE tracking_route_points ENABLE ROW LEVEL SECURITY;

CREATE POLICY route_points_select_members ON tracking_route_points
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM memberships m
            WHERE m.user_id = auth.uid()
              AND m.tenant_id = tracking_route_points.tenant_id
        )
    );

-- 5) Patch rpc_post_driver_event to insert route points with throttling
CREATE OR REPLACE FUNCTION public.rpc_post_driver_event(
    p_token text,
    p_action text,
    p_source text DEFAULT 'gps',
    p_lat numeric DEFAULT NULL,
    p_lng numeric DEFAULT NULL,
    p_accuracy numeric DEFAULT NULL,
    p_municipality text DEFAULT NULL,
    p_state_name text DEFAULT NULL,
    p_country_code char DEFAULT 'MX',
    p_incident_type text DEFAULT NULL,
    p_incident_note text DEFAULT NULL,
    p_client_timestamp timestamptz DEFAULT now(),
    p_offline_queued boolean DEFAULT false
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
    v_suspicious     BOOLEAN := false;
    v_last_point     RECORD;
    v_dist_m         DOUBLE PRECISION;
BEGIN
    IF p_action IS NULL OR NOT (p_action = ANY(v_valid_actions)) THEN
        RETURN jsonb_build_object('http', 400, 'accepted', false, 'reason', 'invalid_action');
    END IF;

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

    -- Anti-noise: in_transit cooldown 30 min
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

    -- Anti-noise: incident cooldown 10 min
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

    -- Suspicious detection
    IF p_accuracy IS NOT NULL AND p_accuracy > 5000 THEN
        v_suspicious := true;
    END IF;

    -- Insert event
    INSERT INTO tracking_events (
        token_id, tenant_id, operation_id, event_type, source,
        client_timestamp, server_timestamp,
        lat, lng, accuracy_m,
        municipality, state_name, country_code,
        incident_type, incident_note,
        is_suspicious, offline_queued
    )
    VALUES (
        v_token.token_id, v_token.tenant_id, v_operation_id, p_action,
        COALESCE(p_source, 'gps'),
        p_client_timestamp, now(),
        p_lat, p_lng, p_accuracy,
        p_municipality, p_state_name, p_country_code,
        p_incident_type, p_incident_note,
        v_suspicious, COALESCE(p_offline_queued, false)
    )
    RETURNING id INTO v_event_id;

    -- ═══════════════════════════════════════════════════════════════
    -- ROUTE v1: Insert GPS route point with throttling
    -- ═══════════════════════════════════════════════════════════════
    IF p_source = 'gps' AND p_lat IS NOT NULL AND p_lng IS NOT NULL AND NOT v_suspicious THEN
        SELECT lat, lng, recorded_at INTO v_last_point
        FROM tracking_route_points
        WHERE operation_id = v_operation_id
        ORDER BY recorded_at DESC
        LIMIT 1;

        IF v_last_point.recorded_at IS NULL
           OR (now() - v_last_point.recorded_at) > interval '10 seconds' THEN
            IF v_last_point.lat IS NOT NULL THEN
                v_dist_m := haversine_m(v_last_point.lat, v_last_point.lng, p_lat::float8, p_lng::float8);
            END IF;

            IF v_last_point.lat IS NULL OR v_dist_m IS NULL OR v_dist_m >= 15 THEN
                INSERT INTO tracking_route_points (
                    tenant_id, operation_id, token_id,
                    lat, lng, accuracy_m, source, recorded_at
                ) VALUES (
                    v_token.tenant_id, v_operation_id, v_token.token_id,
                    p_lat::float8, p_lng::float8, p_accuracy::float8,
                    COALESCE(p_source, 'gps'), COALESCE(p_client_timestamp, now())
                );
            END IF;
        END IF;
    END IF;

    -- Update operation status (forward-only)
    v_new_status := CASE p_action
        WHEN 'departure'  THEN 'in_transit'
        WHEN 'in_transit' THEN 'in_transit'
        WHEN 'arrival'    THEN 'at_destination'
        WHEN 'delivered'  THEN 'delivered'
        ELSE NULL
    END;

    IF v_new_status IS NOT NULL THEN
        UPDATE operations
        SET status = v_new_status
        WHERE id = v_operation_id
          AND CASE status
            WHEN 'planned' THEN true
            WHEN 'assigned' THEN true
            WHEN 'in_transit' THEN v_new_status IN ('at_destination', 'delivered')
            WHEN 'at_destination' THEN v_new_status = 'delivered'
            ELSE false
          END;
    END IF;

    UPDATE tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;

    RETURN jsonb_build_object('http', 200, 'accepted', true, 'eventId', v_event_id);
END;
$$;

-- 6) RPC: list route points for ERP
CREATE OR REPLACE FUNCTION public.rpc_list_route_points(
    p_operation_id uuid,
    p_start timestamptz DEFAULT NULL,
    p_end timestamptz DEFAULT NULL,
    p_limit int DEFAULT 2000
)
RETURNS TABLE (
    lat double precision,
    lng double precision,
    recorded_at timestamptz,
    accuracy_m double precision,
    source text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM operations WHERE id = p_operation_id;

    IF v_tenant_id IS NULL THEN RETURN; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid() AND m.tenant_id = v_tenant_id
    ) THEN RETURN; END IF;

    RETURN QUERY
    SELECT rp.lat, rp.lng, rp.recorded_at, rp.accuracy_m, rp.source
    FROM tracking_route_points rp
    WHERE rp.operation_id = p_operation_id
      AND (p_start IS NULL OR rp.recorded_at >= p_start)
      AND (p_end IS NULL OR rp.recorded_at <= p_end)
    ORDER BY rp.recorded_at ASC
    LIMIT LEAST(p_limit, 2000);
END;
$$;

-- 7) Patch rpc_get_public_tracking to include route[] (GEO-01)
CREATE OR REPLACE FUNCTION public.rpc_get_public_tracking(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_token       RECORD;
    v_operation   RECORD;
    v_events      JSONB;
    v_route       JSONB;
    v_location    JSONB;
    v_status_text TEXT;
    v_route_label TEXT;
BEGIN
    SELECT * INTO v_token FROM tracking_validate_token(p_token, 'public:read');

    IF v_token IS NULL OR v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    IF v_token.token_state = 'revoked' THEN
        RETURN jsonb_build_object('status', 'revoked');
    END IF;

    IF v_token.token_state = 'hard_expired' THEN
        RETURN jsonb_build_object('status', 'hard_expired');
    END IF;

    SELECT o.* INTO v_operation
    FROM operations o WHERE o.id = v_token.operation_id;

    IF v_operation IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    v_route_label := COALESCE(
        (v_operation.origin_place->>'municipality') || ' → ' || (v_operation.destination_place->>'municipality'),
        'Ruta en curso'
    );

    v_status_text := CASE v_operation.status
        WHEN 'draft' THEN 'Preparando'
        WHEN 'planned' THEN 'Planificado'
        WHEN 'assigned' THEN 'Asignado'
        WHEN 'in_transit' THEN 'En Camino'
        WHEN 'at_destination' THEN 'En Destino'
        WHEN 'delivered' THEN 'Entregado'
        WHEN 'closed' THEN 'Cerrado'
        WHEN 'cancelled' THEN 'Cancelado'
        ELSE v_operation.status
    END;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', 'evt-' || row_number,
            'title', CASE te.event_type
                WHEN 'departure' THEN 'Salida'
                WHEN 'in_transit' THEN 'En Camino'
                WHEN 'arrival' THEN 'Llegada'
                WHEN 'delivered' THEN 'Entregado'
                WHEN 'incident' THEN 'Incidencia'
                ELSE te.event_type
            END,
            'subtitle', COALESCE(te.municipality || ', ' || te.state_name, 'Ubicación registrada'),
            'timestamp', to_char(te.server_timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'status', 'done',
            'icon', CASE te.event_type
                WHEN 'departure' THEN 'truck'
                WHEN 'in_transit' THEN 'map-pin'
                WHEN 'arrival' THEN 'flag'
                WHEN 'delivered' THEN 'check-circle'
                WHEN 'incident' THEN 'alert-triangle'
                ELSE 'clock'
            END
        ) ORDER BY te.server_timestamp ASC
    ), '[]'::jsonb)
    INTO v_events
    FROM (
        SELECT *, row_number() OVER (ORDER BY server_timestamp ASC) as row_number
        FROM tracking_events
        WHERE operation_id = v_token.operation_id AND event_type != 'incident'
        ORDER BY server_timestamp ASC LIMIT 50
    ) te;

    IF v_operation.status NOT IN ('delivered', 'closed', 'cancelled') THEN
        SELECT jsonb_build_object(
            'lat', round(te.lat::numeric, 2),
            'lng', round(te.lng::numeric, 2)
        ) INTO v_location
        FROM tracking_events te
        WHERE te.operation_id = v_token.operation_id
          AND te.lat IS NOT NULL AND te.lng IS NOT NULL AND te.source = 'gps'
        ORDER BY te.server_timestamp DESC LIMIT 1;
    END IF;

    IF v_operation.status NOT IN ('delivered', 'closed', 'cancelled') THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object('lat', round(rp.lat::numeric, 2), 'lng', round(rp.lng::numeric, 2))
            ORDER BY rp.recorded_at ASC
        ), '[]'::jsonb) INTO v_route
        FROM (
            SELECT lat, lng, recorded_at FROM tracking_route_points
            WHERE operation_id = v_token.operation_id
            ORDER BY recorded_at ASC LIMIT 200
        ) rp;
    ELSE
        v_route := '[]'::jsonb;
    END IF;

    RETURN jsonb_build_object(
        'status', CASE WHEN v_token.token_state = 'soft_expired' THEN 'soft_expired' ELSE 'success' END,
        'data', jsonb_build_object(
            'orderRef', v_operation.reference,
            'route', v_route_label,
            'currentStatus', v_status_text,
            'events', v_events,
            'currentLocation', COALESCE(v_location, 'null'::jsonb),
            'routePoints', COALESCE(v_route, '[]'::jsonb)
        )
    );
END;
$$;

NOTIFY pgrst, 'reload schema';
