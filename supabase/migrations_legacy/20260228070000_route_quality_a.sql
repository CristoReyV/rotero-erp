-- ============================================================
-- Sprint A: Route Quality — Outlier Filter + Downsampling
-- ============================================================

-- 1) Patch rpc_list_route_points: add outlier filter + downsampling
CREATE OR REPLACE FUNCTION public.rpc_list_route_points(
    p_operation_id uuid,
    p_start timestamptz DEFAULT NULL,
    p_end timestamptz DEFAULT NULL,
    p_limit int DEFAULT 2000,
    p_max_display int DEFAULT 500
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
    v_total     int;
    v_step      int;
BEGIN
    SELECT tenant_id INTO v_tenant_id
    FROM operations WHERE id = p_operation_id;

    IF v_tenant_id IS NULL THEN RETURN; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid() AND m.tenant_id = v_tenant_id
    ) THEN RETURN; END IF;

    RETURN QUERY
    WITH raw AS (
        SELECT rp.lat, rp.lng, rp.recorded_at, rp.accuracy_m, rp.source
        FROM tracking_route_points rp
        WHERE rp.operation_id = p_operation_id
          AND (p_start IS NULL OR rp.recorded_at >= p_start)
          AND (p_end IS NULL OR rp.recorded_at <= p_end)
        ORDER BY rp.recorded_at ASC
        LIMIT LEAST(p_limit, 2000)
    ),
    -- Compute speed from previous point using LAG window function
    with_speed AS (
        SELECT
            r.lat, r.lng, r.recorded_at, r.accuracy_m, r.source,
            CASE
                WHEN LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC) IS NULL THEN 0
                WHEN EXTRACT(EPOCH FROM (r.recorded_at - LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC))) < 1 THEN 0
                ELSE (
                    haversine_m(
                        LAG(r.lat) OVER (ORDER BY r.recorded_at ASC),
                        LAG(r.lng) OVER (ORDER BY r.recorded_at ASC),
                        r.lat, r.lng
                    ) / 1000.0
                ) / (
                    EXTRACT(EPOCH FROM (r.recorded_at - LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC))) / 3600.0
                )
            END AS speed_kmh,
            row_number() OVER (ORDER BY r.recorded_at ASC) AS rn,
            count(*) OVER () AS total_count
        FROM raw r
    ),
    -- Outlier filter: discard points where speed > 200 km/h
    filtered AS (
        SELECT ws.lat, ws.lng, ws.recorded_at, ws.accuracy_m, ws.source,
               row_number() OVER (ORDER BY ws.recorded_at ASC) AS rn,
               count(*) OVER () AS filtered_count
        FROM with_speed ws
        WHERE ws.speed_kmh <= 200 OR ws.rn = 1  -- always keep first point
    ),
    -- Downsampling: if too many points, pick every Nth + first + last
    sampled AS (
        SELECT f.lat, f.lng, f.recorded_at, f.accuracy_m, f.source
        FROM filtered f
        WHERE f.filtered_count <= p_max_display
           OR f.rn = 1
           OR f.rn = f.filtered_count
           OR (f.rn % GREATEST(1, (f.filtered_count / p_max_display))) = 0
        ORDER BY f.recorded_at ASC
    )
    SELECT s.lat, s.lng, s.recorded_at, s.accuracy_m, s.source
    FROM sampled s;
END;
$$;

-- 2) Patch rpc_get_public_tracking: add outlier filter to routePoints
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

    -- Route v1 + Sprint A: GEO-01 ofuscated + outlier filtered
    IF v_operation.status NOT IN ('delivered', 'closed', 'cancelled') THEN
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object('lat', round(f.lat::numeric, 2), 'lng', round(f.lng::numeric, 2))
            ORDER BY f.recorded_at ASC
        ), '[]'::jsonb) INTO v_route
        FROM (
            WITH raw_pts AS (
                SELECT rp.lat, rp.lng, rp.recorded_at,
                       row_number() OVER (ORDER BY rp.recorded_at ASC) AS rn
                FROM tracking_route_points rp
                WHERE rp.operation_id = v_token.operation_id
                ORDER BY rp.recorded_at ASC LIMIT 300
            ),
            with_speed AS (
                SELECT r.lat, r.lng, r.recorded_at, r.rn,
                    CASE
                        WHEN LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC) IS NULL THEN 0
                        WHEN EXTRACT(EPOCH FROM (r.recorded_at - LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC))) < 1 THEN 0
                        ELSE (
                            haversine_m(
                                LAG(r.lat) OVER (ORDER BY r.recorded_at ASC),
                                LAG(r.lng) OVER (ORDER BY r.recorded_at ASC),
                                r.lat, r.lng
                            ) / 1000.0
                        ) / (
                            EXTRACT(EPOCH FROM (r.recorded_at - LAG(r.recorded_at) OVER (ORDER BY r.recorded_at ASC))) / 3600.0
                        )
                    END AS speed_kmh
                FROM raw_pts r
            )
            SELECT ws.lat, ws.lng, ws.recorded_at
            FROM with_speed ws
            WHERE ws.speed_kmh <= 200 OR ws.rn = 1
            ORDER BY ws.recorded_at ASC
            LIMIT 200
        ) f;
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
