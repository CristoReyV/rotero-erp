-- ============================================================================
-- TRACKING MODULE — BACKEND MIGRATION
-- ============================================================================
-- Versión : 1.0
-- Fecha   : 2026-02-24
-- Ref     : TRACKING_TOKEN_SECURITY_DESIGN.md
-- Precondición: Existen las tablas `tenants`, `operations`, `auth.users`
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 0. Extension: pgcrypto (para gen_random_uuid y digest)
-- ────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. TABLA: tracking_tokens
-- ────────────────────────────────────────────────────────────────────────────
-- El token literal NUNCA se almacena. Solo su hash SHA-256.
-- El token circula SOLO en la URL del chofer/cliente.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tracking_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    operation_id    UUID NOT NULL REFERENCES operations(id) ON DELETE CASCADE,

    -- Scope del token: 'public:read' = link cliente, 'driver:write' = link chofer
    scope           TEXT NOT NULL
                    CHECK (scope IN ('public:read', 'driver:write')),

    -- SHA-256 hex del token literal. Indexado para lookup O(1).
    -- Generación: encode(digest(token_literal, 'sha256'), 'hex')
    token_hash      TEXT NOT NULL,

    -- Estado del token (máquina de estados irreversible)
    state           TEXT NOT NULL DEFAULT 'active'
                    CHECK (state IN ('active', 'soft_expired', 'hard_expired', 'revoked', 'rotated')),

    -- Metadatos temporales
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      UUID NOT NULL,  -- FK a auth.users si se desea, omitido para flexibilidad
    expires_at      TIMESTAMPTZ NOT NULL,
    delivered_at    TIMESTAMPTZ,    -- Se llena cuando llega evento 'delivered'

    -- Revocación
    revoked_at      TIMESTAMPTZ,
    revoked_by      UUID,           -- Usuario ERP que revocó

    -- Rotación: apunta al sucesor
    rotated_into    UUID REFERENCES tracking_tokens(id),

    -- Último uso (actualizado async, fuera del hot path)
    last_used_at    TIMESTAMPTZ,

    -- Contador de eventos emitidos vía este token (anti-abuso, solo driver:write)
    event_count     INTEGER NOT NULL DEFAULT 0,

    -- Metadata auxiliar para auditoría
    ip_hash_last    TEXT,           -- SHA-256(IP + salt_diario), nunca IP en plano
    user_agent_last TEXT            -- Truncado a 200 chars
);

-- ── Índices ──

-- Lookup principal por hash (hot path de validación)
CREATE UNIQUE INDEX tracking_tokens_hash_uq
    ON tracking_tokens (token_hash);

-- Garantiza máximo 1 token activo por (operación + scope)
-- Evita conflictos de doble-link simultáneo
CREATE UNIQUE INDEX tracking_tokens_active_uq
    ON tracking_tokens (operation_id, scope)
    WHERE state = 'active';

-- Búsqueda para la UI interna: "ver tokens de esta operación"
CREATE INDEX tracking_tokens_operation_idx
    ON tracking_tokens (operation_id);

-- Limpieza periódica: encontrar tokens vencidos para cron de expiración
CREATE INDEX tracking_tokens_expires_idx
    ON tracking_tokens (expires_at)
    WHERE state = 'active';


-- ────────────────────────────────────────────────────────────────────────────
-- 2. TABLA: tracking_events
-- ────────────────────────────────────────────────────────────────────────────
-- Cada fila = un evento de tracking generado por el chofer o por el sistema.
-- Las coordenadas EXACTAS se almacenan aquí. Nunca se exponen al público tal cual.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tracking_events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id          UUID NOT NULL REFERENCES tracking_tokens(id) ON DELETE CASCADE,
    tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    operation_id      UUID NOT NULL REFERENCES operations(id) ON DELETE CASCADE,

    -- Tipo de evento
    event_type        TEXT NOT NULL
                      CHECK (event_type IN ('departure', 'in_transit', 'arrival', 'delivered', 'incident')),

    -- Fuente de la ubicación
    source            TEXT NOT NULL
                      CHECK (source IN ('gps', 'manual', 'none')),

    -- Timestamps: cliente vs servidor
    client_timestamp  TIMESTAMPTZ NOT NULL,  -- Del dispositivo del chofer (para idempotency)
    server_timestamp  TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Timestamp confiable del servidor

    -- Coordenadas exactas (NULL si source = 'none' o 'manual')
    lat               NUMERIC(9,6),
    lng               NUMERIC(9,6),
    accuracy_m        NUMERIC(7,2),   -- Precisión GPS en metros

    -- Lugar resuelto (reverse geocoded o manual)
    municipality      TEXT,
    state_name        TEXT,
    country_code      CHAR(2) DEFAULT 'MX',

    -- Incidencia (solo si event_type = 'incident')
    incident_type     TEXT,
    incident_note     TEXT,           -- Máx 280 chars

    -- Flags de calidad
    is_suspicious     BOOLEAN NOT NULL DEFAULT false,  -- Anomalía geográfica detectada
    offline_queued    BOOLEAN NOT NULL DEFAULT false,   -- Llegó desde cola offline

    -- Constraints de integridad
    CONSTRAINT incident_fields_check CHECK (
        (event_type = 'incident' AND incident_type IS NOT NULL)
        OR (event_type != 'incident' AND incident_type IS NULL AND incident_note IS NULL)
    ),
    CONSTRAINT incident_note_length CHECK (
        incident_note IS NULL OR length(incident_note) <= 280
    ),
    CONSTRAINT coords_consistency CHECK (
        (source = 'gps' AND lat IS NOT NULL AND lng IS NOT NULL)
        OR (source IN ('manual', 'none'))
    )
);

-- ── Índices ──

-- Timeline público: eventos de una operación ordenados por tiempo
CREATE INDEX tracking_events_timeline_idx
    ON tracking_events (operation_id, server_timestamp DESC);

-- Idempotency check: buscar duplicados por token + acción + timestamp
CREATE INDEX tracking_events_idempotency_idx
    ON tracking_events (token_id, event_type, client_timestamp);

-- Anti-ruido: último evento de un tipo para un token
CREATE INDEX tracking_events_last_type_idx
    ON tracking_events (token_id, event_type, server_timestamp DESC);

-- Buscar eventos por operación y tipo (para validar singletones como departure/delivered)
CREATE INDEX tracking_events_singleton_idx
    ON tracking_events (operation_id, event_type);


-- ────────────────────────────────────────────────────────────────────────────
-- 3. TABLA: tracking_access_log  (auditoría de accesos públicos)
-- ────────────────────────────────────────────────────────────────────────────
-- Registra cada acceso al link público. No almacena PII en texto plano.
-- Solo para analytics y detección de scraping.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tracking_access_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash      TEXT NOT NULL,      -- Mismo hash que tracking_tokens.token_hash
    accessed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_hash         TEXT,               -- SHA-256(IP + salt_diario)
    user_agent      TEXT,               -- Truncado a 200 chars
    country_code    CHAR(2)             -- Del header CF-IPCountry si disponible
);

CREATE INDEX tracking_access_log_hash_idx
    ON tracking_access_log (token_hash, accessed_at DESC);


-- ────────────────────────────────────────────────────────────────────────────
-- 4. RLS (Row Level Security)
-- ────────────────────────────────────────────────────────────────────────────

-- ── 4.1 tracking_tokens: SOLO service_role puede leer/escribir ──
-- Los Edge Functions usan service_role key para bypass RLS.
-- No hay policy para anon ni authenticated directo → tabla invisible para todos.

ALTER TABLE tracking_tokens ENABLE ROW LEVEL SECURITY;

-- Usuarios internos autenticados pueden VER tokens de su tenant (solo lectura)
CREATE POLICY "internal_read_own_tenant_tokens"
    ON tracking_tokens FOR SELECT
    TO authenticated
    USING (
        tenant_id IN (
            SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
        )
    );

-- INSERT/UPDATE/DELETE: solo service_role (Edge Functions). No policy = denegado para todos.


-- ── 4.2 tracking_events: lectura interna por tenant, inserción solo service_role ──

ALTER TABLE tracking_events ENABLE ROW LEVEL SECURITY;

-- Lectura: usuarios internos del mismo tenant
CREATE POLICY "internal_read_own_tenant_events"
    ON tracking_events FOR SELECT
    TO authenticated
    USING (
        tenant_id IN (
            SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
        )
    );

-- INSERT/UPDATE: solo service_role. El frontend nunca inserta directamente.


-- ── 4.3 tracking_access_log: solo service_role ──

ALTER TABLE tracking_access_log ENABLE ROW LEVEL SECURITY;

-- Sin policies → invisible para anon y authenticated. Solo service_role lee/escribe.


-- ────────────────────────────────────────────────────────────────────────────
-- 5. FUNCIONES HELPER (SECURITY DEFINER)
-- ────────────────────────────────────────────────────────────────────────────

-- ── 5.1 Hash helper: convierte token literal → SHA-256 hex ──

CREATE OR REPLACE FUNCTION tracking_hash_token(p_token TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT encode(digest(p_token, 'sha256'), 'hex');
$$;

COMMENT ON FUNCTION tracking_hash_token IS
    'Genera el SHA-256 hex de un token literal. Usado en validación y creación. '
    'El token literal NUNCA debe persistir en columna alguna — solo este hash.';


-- ── 5.2 Validar token: retorna fila del token si es válido, NULL si no ──

CREATE OR REPLACE FUNCTION tracking_validate_token(
    p_token       TEXT,
    p_scope       TEXT    -- 'public:read' | 'driver:write'
)
RETURNS TABLE (
    token_id       UUID,
    tenant_id      UUID,
    operation_id   UUID,
    token_state    TEXT,
    expires_at     TIMESTAMPTZ,
    delivered_at   TIMESTAMPTZ,
    event_count    INTEGER
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
    v_hash TEXT;
    v_now  TIMESTAMPTZ := now();
BEGIN
    v_hash := tracking_hash_token(p_token);

    RETURN QUERY
    SELECT
        t.id,
        t.tenant_id,
        t.operation_id,
        -- Calcular estado efectivo en runtime (incluyendo soft/hard expiry)
        CASE
            WHEN t.state = 'revoked' THEN 'revoked'
            WHEN t.state = 'rotated' THEN 'rotated'
            WHEN t.state = 'hard_expired' THEN 'hard_expired'
            -- Expiración dinámica: si pasaron >48h del expires_at → hard_expired
            WHEN t.expires_at + INTERVAL '48 hours' < v_now THEN 'hard_expired'
            -- Si ya pasó expires_at pero aún no 48h → soft_expired
            WHEN t.expires_at < v_now THEN 'soft_expired'
            -- Post-entrega: delivered_at + 48h → soft_expired; +96h → hard_expired
            WHEN t.delivered_at IS NOT NULL
                 AND t.delivered_at + INTERVAL '96 hours' < v_now THEN 'hard_expired'
            WHEN t.delivered_at IS NOT NULL
                 AND t.delivered_at + INTERVAL '48 hours' < v_now THEN 'soft_expired'
            ELSE t.state
        END AS token_state,
        t.expires_at,
        t.delivered_at,
        t.event_count
    FROM tracking_tokens t
    WHERE t.token_hash = v_hash
      AND t.scope = p_scope
    LIMIT 1;

    -- NOTA: Si scope no coincide, no retorna filas → respuesta scope-blind (NL-16)
END;
$$;

COMMENT ON FUNCTION tracking_validate_token IS
    'Valida un token literal contra su hash en DB. '
    'Calcula estado efectivo (incluyendo expiración dinámica). '
    'Retorna vacío si el token no existe O si el scope no coincide (scope-blind, NL-16).';


-- ────────────────────────────────────────────────────────────────────────────
-- 6. RPC: rpc_get_public_tracking (PublicTrackingView)
-- ────────────────────────────────────────────────────────────────────────────
-- Endpoint llamado por Edge Function para GET /api/track/:publicToken
-- Retorna PublicTrackingView sanitizado. NO-LEAK garantizado.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_get_public_tracking(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token     RECORD;
    v_operation RECORD;
    v_events    JSONB;
    v_location  JSONB;
    v_status    TEXT;
    v_last_evt  RECORD;
BEGIN
    -- 1. Validar token con scope 'public:read'
    SELECT * INTO v_token
    FROM tracking_validate_token(p_token, 'public:read');

    IF v_token IS NULL OR v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    -- 2. Chequear estados terminales
    IF v_token.token_state = 'revoked' THEN
        RETURN jsonb_build_object('status', 'revoked');
    END IF;

    IF v_token.token_state IN ('hard_expired', 'rotated') THEN
        RETURN jsonb_build_object('status', 'hard_expired');
    END IF;

    -- 3. Obtener info de la operación (solo campos públicos)
    SELECT
        o.reference_code,   -- orderRef (externo, no el ID de DB)
        o.route_summary,    -- "Laredo → Monterrey"
        o.eta_display        -- "Hoy, 14:00"
    INTO v_operation
    FROM operations o
    WHERE o.id = v_token.operation_id;

    IF v_operation IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    -- 4. Construir timeline sanitizado (máximo 20 eventos, sin IDs de DB)
    SELECT jsonb_agg(evt ORDER BY evt.rank) INTO v_events
    FROM (
        SELECT
            'evt-' || row_number() OVER (ORDER BY e.server_timestamp ASC) AS id,
            CASE e.event_type
                WHEN 'departure'  THEN 'Salida de Almacén'
                WHEN 'in_transit' THEN 'En camino'
                WHEN 'arrival'    THEN 'En punto de entrega'
                WHEN 'delivered'  THEN 'Entregado'
                WHEN 'incident'   THEN 'Retraso reportado'
            END AS title,
            -- Subtitle: "Municipio, Estado · HH:MM"
            CASE
                WHEN e.municipality IS NOT NULL AND e.state_name IS NOT NULL
                    THEN e.municipality || ', ' || e.state_name || ' · '
                         || to_char(e.server_timestamp AT TIME ZONE 'America/Mexico_City', 'HH24:MI')
                ELSE 'Reportado a las '
                     || to_char(e.server_timestamp AT TIME ZONE 'America/Mexico_City', 'HH24:MI')
            END AS subtitle,
            to_char(e.server_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "timestamp",
            CASE e.event_type
                WHEN 'departure'  THEN 'truck'
                WHEN 'in_transit' THEN 'map-pin'
                WHEN 'arrival'    THEN 'map-pin'
                WHEN 'delivered'  THEN 'check-circle'
                WHEN 'incident'   THEN 'alert-triangle'
            END AS icon,
            row_number() OVER (ORDER BY e.server_timestamp ASC) AS rank
        FROM tracking_events e
        WHERE e.operation_id = v_token.operation_id
          AND e.is_suspicious = false  -- No mostrar eventos sospechosos
        ORDER BY e.server_timestamp ASC
        LIMIT 20
    ) evt;

    -- 5. Determinar current status humanizado
    SELECT * INTO v_last_evt
    FROM tracking_events
    WHERE operation_id = v_token.operation_id
      AND event_type != 'incident'
      AND is_suspicious = false
    ORDER BY server_timestamp DESC
    LIMIT 1;

    v_status := CASE
        WHEN v_last_evt IS NULL THEN 'En Espera'
        WHEN v_last_evt.event_type = 'departure' THEN 'En Tránsito'
        WHEN v_last_evt.event_type = 'in_transit' THEN 'En Tránsito'
        WHEN v_last_evt.event_type = 'arrival' THEN 'En Destino'
        WHEN v_last_evt.event_type = 'delivered' THEN 'Entregado'
        ELSE 'En Tránsito'
    END;

    -- 6. Coordenadas para el mapa público
    -- GEO-01: Redondear a 2 decimales (~1.1 km)
    -- GEO-03: Omitir si status = delivered
    -- GEO-04: Omitir si lat/lng es NULL
    v_location := NULL;

    IF v_last_evt IS NOT NULL
       AND v_last_evt.event_type != 'delivered'
       AND v_last_evt.lat IS NOT NULL
       AND v_last_evt.lng IS NOT NULL THEN
        v_location := jsonb_build_object(
            'lat', round(v_last_evt.lat::numeric, 2),
            'lng', round(v_last_evt.lng::numeric, 2)
        );
    END IF;

    -- 7. Marcar status en timeline (done / current / future)
    IF v_events IS NOT NULL THEN
        v_events := (
            SELECT jsonb_agg(
                CASE
                    WHEN (elem->>'rank')::int < (SELECT count(*) FROM jsonb_array_elements(v_events))
                        THEN elem || '{"status": "done"}'::jsonb
                    ELSE elem || '{"status": "current"}'::jsonb
                END
            )
            FROM jsonb_array_elements(v_events) AS elem
        );
    END IF;

    -- 8. Actualizar last_used_at (fire-and-forget, no bloquea respuesta)
    UPDATE tracking_tokens
    SET last_used_at = now()
    WHERE id = v_token.token_id;

    -- 9. Respuesta final
    RETURN jsonb_build_object(
        'status', CASE WHEN v_token.token_state = 'soft_expired' THEN 'soft_expired' ELSE 'success' END,
        'expired', v_token.token_state = 'soft_expired',
        'data', jsonb_build_object(
            'orderRef',        v_operation.reference_code,
            'route',           v_operation.route_summary,
            'currentStatus',   v_status,
            'eta',             v_operation.eta_display,
            'currentLocation', v_location,
            'events',          COALESCE(v_events, '[]'::jsonb)
        )
    );
END;
$$;

COMMENT ON FUNCTION rpc_get_public_tracking IS
    'Retorna PublicTrackingView sanitizado para el link público. '
    'Aplica validación de token, estado, expiración, redondeo GEO-01, omisión GEO-03/04. '
    'NO-LEAK garantizado: no expone IDs internos, datos fiscales ni coordenadas exactas.';


-- ────────────────────────────────────────────────────────────────────────────
-- 7. RPC: rpc_post_driver_event
-- ────────────────────────────────────────────────────────────────────────────
-- Endpoint llamado por Edge Function para POST /api/driver/:driverToken/events
-- Inserta un evento con todas las validaciones de seguridad y anti-ruido.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_post_driver_event(
    p_token            TEXT,
    p_action           TEXT,       -- 'departure' | 'in_transit' | 'arrival' | 'delivered' | 'incident'
    p_source           TEXT,       -- 'gps' | 'manual' | 'none'
    p_lat              NUMERIC DEFAULT NULL,
    p_lng              NUMERIC DEFAULT NULL,
    p_accuracy         NUMERIC DEFAULT NULL,
    p_municipality     TEXT DEFAULT NULL,
    p_state_name       TEXT DEFAULT NULL,
    p_country_code     CHAR(2) DEFAULT 'MX',
    p_incident_type    TEXT DEFAULT NULL,
    p_incident_note    TEXT DEFAULT NULL,
    p_client_timestamp TIMESTAMPTZ DEFAULT now(),
    p_offline_queued   BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token       RECORD;
    v_last_evt    RECORD;
    v_last_transit RECORD;
    v_existing    INTEGER;
    v_new_id      UUID;
    v_minutes     NUMERIC;
    v_distance_km NUMERIC;

    -- Anti-noise constants (mirror of DRIVER_ANTI_NOISE in frontend)
    C_COOLDOWN_MINUTES      CONSTANT INTEGER := 30;
    C_MAX_IN_TRANSIT        CONSTANT INTEGER := 15;
    C_INCIDENT_COOLDOWN_MIN CONSTANT INTEGER := 10;
    C_IDEMPOTENCY_WINDOW    CONSTANT INTERVAL := '5 seconds';
    C_SUSPICIOUS_KM         CONSTANT NUMERIC := 300;
    C_SUSPICIOUS_MINUTES    CONSTANT NUMERIC := 30;
BEGIN
    -- ── 1. Validar token ──
    SELECT * INTO v_token
    FROM tracking_validate_token(p_token, 'driver:write');

    IF v_token IS NULL OR v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('http', 403, 'reason', 'token_not_found');
    END IF;

    -- driver:write no acepta soft_expired (a diferencia de public:read)
    IF v_token.token_state != 'active' THEN
        RETURN jsonb_build_object('http', 403, 'reason', 'token_' || v_token.token_state);
    END IF;

    -- TTL check explícito
    IF v_token.expires_at < now() THEN
        RETURN jsonb_build_object('http', 403, 'reason', 'token_expired');
    END IF;

    -- ── 2. Idempotency check ──
    SELECT count(*) INTO v_existing
    FROM tracking_events
    WHERE token_id = v_token.token_id
      AND event_type = p_action
      AND client_timestamp BETWEEN p_client_timestamp - C_IDEMPOTENCY_WINDOW
                                AND p_client_timestamp + C_IDEMPOTENCY_WINDOW;

    IF v_existing > 0 THEN
        RETURN jsonb_build_object('http', 200, 'accepted', false, 'reason', 'duplicate');
    END IF;

    -- ── 3. Singleton actions (departure, delivered) ──
    IF p_action IN ('departure', 'delivered') THEN
        SELECT count(*) INTO v_existing
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = p_action;

        IF v_existing > 0 THEN
            RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'action_already_done');
        END IF;
    END IF;

    -- arrival requires departure
    IF p_action = 'arrival' THEN
        SELECT count(*) INTO v_existing
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = 'departure';

        IF v_existing = 0 THEN
            RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'departure_required_first');
        END IF;

        -- arrival is also singleton
        SELECT count(*) INTO v_existing
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = 'arrival';

        IF v_existing > 0 THEN
            RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'action_already_done');
        END IF;
    END IF;

    -- ── 4. in_transit specific validations ──
    IF p_action = 'in_transit' THEN
        -- 4a. Max events per trip
        SELECT count(*) INTO v_existing
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = 'in_transit';

        IF v_existing >= C_MAX_IN_TRANSIT THEN
            RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'max_events_reached');
        END IF;

        -- 4b. Cooldown (30 minutes between in_transit)
        SELECT * INTO v_last_transit
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = 'in_transit'
        ORDER BY server_timestamp DESC
        LIMIT 1;

        IF v_last_transit IS NOT NULL THEN
            v_minutes := EXTRACT(EPOCH FROM (now() - v_last_transit.server_timestamp)) / 60;

            IF v_minutes < C_COOLDOWN_MINUTES THEN
                RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'cooldown_active',
                    'retry_after_minutes', ceil(C_COOLDOWN_MINUTES - v_minutes));
            END IF;
        END IF;

        -- 4c. Municipality dedup (only if source is gps and municipality resolved)
        IF p_source = 'gps' AND p_municipality IS NOT NULL AND v_last_transit IS NOT NULL THEN
            IF v_last_transit.municipality = p_municipality
               AND v_last_transit.state_name = p_state_name THEN
                RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'same_municipality');
            END IF;
        END IF;
    END IF;

    -- ── 5. incident cooldown ──
    IF p_action = 'incident' THEN
        SELECT * INTO v_last_evt
        FROM tracking_events
        WHERE operation_id = v_token.operation_id
          AND event_type = 'incident'
        ORDER BY server_timestamp DESC
        LIMIT 1;

        IF v_last_evt IS NOT NULL THEN
            v_minutes := EXTRACT(EPOCH FROM (now() - v_last_evt.server_timestamp)) / 60;

            IF v_minutes < C_INCIDENT_COOLDOWN_MIN THEN
                RETURN jsonb_build_object('http', 422, 'accepted', false, 'reason', 'cooldown_active',
                    'retry_after_minutes', ceil(C_INCIDENT_COOLDOWN_MIN - v_minutes));
            END IF;
        END IF;
    END IF;

    -- ── 6. Anomaly detection (geographic impossibility) ──
    DECLARE v_is_suspicious BOOLEAN := false;
    BEGIN
        IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
            SELECT * INTO v_last_evt
            FROM tracking_events
            WHERE operation_id = v_token.operation_id
              AND lat IS NOT NULL AND lng IS NOT NULL
              AND event_type != 'incident'
            ORDER BY server_timestamp DESC
            LIMIT 1;

            IF v_last_evt IS NOT NULL THEN
                -- Haversine distance approximation
                v_distance_km := 6371 * 2 * asin(sqrt(
                    power(sin(radians((p_lat - v_last_evt.lat) / 2)), 2) +
                    cos(radians(v_last_evt.lat)) * cos(radians(p_lat)) *
                    power(sin(radians((p_lng - v_last_evt.lng) / 2)), 2)
                ));

                v_minutes := EXTRACT(EPOCH FROM (now() - v_last_evt.server_timestamp)) / 60;

                IF v_distance_km > C_SUSPICIOUS_KM AND v_minutes < C_SUSPICIOUS_MINUTES THEN
                    v_is_suspicious := true;
                    -- No rechazamos: podría ser un chofer real con GPS corrupto
                    -- Solo marcamos para revisión interna
                END IF;
            END IF;
        END IF;

        -- ── 7. INSERT the event ──
        INSERT INTO tracking_events (
            token_id, tenant_id, operation_id,
            event_type, source,
            client_timestamp, server_timestamp,
            lat, lng, accuracy_m,
            municipality, state_name, country_code,
            incident_type, incident_note,
            is_suspicious, offline_queued
        ) VALUES (
            v_token.token_id, v_token.tenant_id, v_token.operation_id,
            p_action, p_source,
            p_client_timestamp, now(),
            p_lat, p_lng, p_accuracy,
            p_municipality, p_state_name, p_country_code,
            p_incident_type, LEFT(p_incident_note, 280),
            v_is_suspicious, p_offline_queued
        )
        RETURNING id INTO v_new_id;
    END;

    -- ── 8. Update token counters ──
    UPDATE tracking_tokens
    SET event_count = event_count + 1,
        last_used_at = now(),
        -- Si es delivered, marcar delivered_at
        delivered_at = CASE WHEN p_action = 'delivered' THEN now() ELSE delivered_at END
    WHERE id = v_token.token_id;

    -- ── 9. Return success ──
    RETURN jsonb_build_object(
        'http', 201,
        'accepted', true,
        'eventId', 'evt-' || (
            SELECT count(*) FROM tracking_events
            WHERE operation_id = v_token.operation_id
        ),
        'serverTimestamp', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    );
END;
$$;

COMMENT ON FUNCTION rpc_post_driver_event IS
    'Inserta un TrackingEvent del chofer con validaciones completas: '
    'token, scope, expiración, idempotency, singletones, cooldown, dedup municipio, '
    'límite de eventos, detección de anomalías geográficas. '
    'Retorna JSONB con http code, accepted flag, y eventId o reason.';


-- ────────────────────────────────────────────────────────────────────────────
-- 8. RPC: rpc_create_tracking_token (uso interno)
-- ────────────────────────────────────────────────────────────────────────────
-- Solo llamada desde el ERP interno (sesión autenticada + service_role).
-- Genera un UUID v4 como token literal, almacena su hash, retorna el literal
-- para que el operador lo comparta.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_create_tracking_token(
    p_tenant_id    UUID,
    p_operation_id UUID,
    p_scope        TEXT,        -- 'public:read' | 'driver:write'
    p_ttl_hours    INTEGER DEFAULT NULL  -- NULL = usar defaults
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token_literal TEXT;
    v_token_hash    TEXT;
    v_ttl           INTERVAL;
    v_new_id        UUID;
    v_existing      UUID;
BEGIN
    -- Validate scope
    IF p_scope NOT IN ('public:read', 'driver:write') THEN
        RETURN jsonb_build_object('error', 'invalid_scope');
    END IF;

    -- Calculate TTL
    IF p_ttl_hours IS NOT NULL THEN
        -- Enforce max TTL
        IF p_scope = 'public:read' AND p_ttl_hours > 720 THEN  -- 30 days
            p_ttl_hours := 720;
        END IF;
        IF p_scope = 'driver:write' AND p_ttl_hours > 72 THEN
            p_ttl_hours := 72;
        END IF;
        v_ttl := (p_ttl_hours || ' hours')::INTERVAL;
    ELSE
        v_ttl := CASE p_scope
            WHEN 'public:read'  THEN INTERVAL '7 days'
            WHEN 'driver:write' THEN INTERVAL '48 hours'
        END;
    END IF;

    -- Check if there's already an active token for this operation+scope
    SELECT id INTO v_existing
    FROM tracking_tokens
    WHERE operation_id = p_operation_id
      AND scope = p_scope
      AND state = 'active';

    -- If exists, rotate it (mark as 'rotated')
    IF v_existing IS NOT NULL THEN
        UPDATE tracking_tokens
        SET state = 'rotated',
            revoked_at = now(),
            revoked_by = auth.uid()
        WHERE id = v_existing;
    END IF;

    -- Generate new token
    v_token_literal := gen_random_uuid()::TEXT;
    v_token_hash    := tracking_hash_token(v_token_literal);

    INSERT INTO tracking_tokens (
        tenant_id, operation_id, scope,
        token_hash, state,
        created_by, expires_at,
        rotated_into
    ) VALUES (
        p_tenant_id, p_operation_id, p_scope,
        v_token_hash, 'active',
        auth.uid(), now() + v_ttl,
        NULL
    )
    RETURNING id INTO v_new_id;

    -- Link predecessor to successor
    IF v_existing IS NOT NULL THEN
        UPDATE tracking_tokens
        SET rotated_into = v_new_id
        WHERE id = v_existing;
    END IF;

    -- Return the literal token (ONLY time it leaves the server)
    RETURN jsonb_build_object(
        'token_id',   v_new_id,
        'token',      v_token_literal,  -- The caller shares this via URL
        'scope',      p_scope,
        'expires_at', to_char(now() + v_ttl, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'rotated_previous', v_existing IS NOT NULL
    );
END;
$$;

COMMENT ON FUNCTION rpc_create_tracking_token IS
    'Crea un nuevo token de tracking. Rota automáticamente el anterior si existe. '
    'Retorna el token literal UNA SOLA VEZ. Nunca se almacena — solo su SHA-256.';


-- ────────────────────────────────────────────────────────────────────────────
-- 9. RPC: rpc_revoke_tracking_token (uso interno)
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_revoke_tracking_token(
    p_token_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_state TEXT;
BEGIN
    SELECT state INTO v_current_state
    FROM tracking_tokens
    WHERE id = p_token_id;

    IF v_current_state IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF v_current_state != 'active' THEN
        RETURN jsonb_build_object('error', 'already_' || v_current_state);
    END IF;

    UPDATE tracking_tokens
    SET state = 'revoked',
        revoked_at = now(),
        revoked_by = auth.uid()
    WHERE id = p_token_id;

    RETURN jsonb_build_object('success', true, 'revoked_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
END;
$$;


-- ────────────────────────────────────────────────────────────────────────────
-- 10. RPC: rpc_get_driver_view (DriverView sanitizado)
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rpc_get_driver_view(
    p_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token     RECORD;
    v_operation RECORD;
    v_last_evt  RECORD;
    v_status    TEXT;
BEGIN
    -- 1. Validar token con scope 'driver:write'
    SELECT * INTO v_token
    FROM tracking_validate_token(p_token, 'driver:write');

    IF v_token IS NULL OR v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    IF v_token.token_state = 'revoked' THEN
        RETURN jsonb_build_object('status', 'revoked');
    END IF;

    IF v_token.token_state IN ('hard_expired', 'soft_expired', 'rotated') THEN
        RETURN jsonb_build_object('status', 'expired');
    END IF;

    IF v_token.expires_at < now() THEN
        RETURN jsonb_build_object('status', 'expired');
    END IF;

    -- 2. Obtener info de la operación (campos limitados para el chofer)
    SELECT
        o.reference_code,
        o.route_summary,
        -- NL-14: Solo nombre parcial del cliente, sin datos fiscales
        LEFT(o.client_display_name, 20) AS client_name,
        o.destination_city,
        o.eta_display
    INTO v_operation
    FROM operations o
    WHERE o.id = v_token.operation_id;

    IF v_operation IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;

    -- 3. Determinar status actual
    SELECT * INTO v_last_evt
    FROM tracking_events
    WHERE operation_id = v_token.operation_id
      AND event_type != 'incident'
    ORDER BY server_timestamp DESC
    LIMIT 1;

    v_status := CASE
        WHEN v_last_evt IS NULL THEN 'assigned'
        WHEN v_last_evt.event_type = 'departure' THEN 'in_transit'
        WHEN v_last_evt.event_type = 'in_transit' THEN 'in_transit'
        WHEN v_last_evt.event_type = 'arrival' THEN 'at_destination'
        WHEN v_last_evt.event_type = 'delivered' THEN 'delivered'
        ELSE 'assigned'
    END;

    -- 4. Último evento con place para mostrar
    SELECT municipality, state_name, server_timestamp INTO v_last_evt
    FROM tracking_events
    WHERE operation_id = v_token.operation_id
      AND municipality IS NOT NULL
      AND event_type != 'incident'
    ORDER BY server_timestamp DESC
    LIMIT 1;

    -- 5. Actualizar last_used_at
    UPDATE tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;

    -- 6. Respuesta
    RETURN jsonb_build_object(
        'status', 'success',
        'data', jsonb_build_object(
            'orderRef',        v_operation.reference_code,
            'route',           v_operation.route_summary,
            'currentStatus',   v_status,
            'eta',             CASE WHEN v_status != 'delivered' THEN v_operation.eta_display ELSE NULL END,
            'clientName',      v_operation.client_name,
            'destinationCity', v_operation.destination_city,
            'lastEvent',       CASE
                WHEN v_last_evt IS NOT NULL AND v_last_evt.municipality IS NOT NULL
                THEN jsonb_build_object(
                    'municipality', v_last_evt.municipality || ', ' || v_last_evt.state_name,
                    'timestamp',    to_char(v_last_evt.server_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                )
                ELSE NULL
            END
        )
    );
END;
$$;

COMMENT ON FUNCTION rpc_get_driver_view IS
    'Retorna DriverView sanitizado para el chofer. '
    'No expone IDs internos, datos fiscales, coordenadas exactas ni notas internas. '
    'Solo se acepta scope driver:write y state active.';


-- ────────────────────────────────────────────────────────────────────────────
-- 11. CRON: Expiración automática de tokens
-- ────────────────────────────────────────────────────────────────────────────
-- Se recomienda ejecutar cada hora vía pg_cron o Supabase Scheduled Functions.
-- Este bloque solo define la función; la programación es externa.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION tracking_expire_tokens()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    -- Tokens cuyo TTL pasó + 48h de gracia → hard_expired
    UPDATE tracking_tokens
    SET state = 'hard_expired'
    WHERE state = 'active'
      AND expires_at + INTERVAL '48 hours' < now();
    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Post-entrega: delivered_at + 96h → hard_expired
    UPDATE tracking_tokens
    SET state = 'hard_expired'
    WHERE state = 'active'
      AND delivered_at IS NOT NULL
      AND delivered_at + INTERVAL '96 hours' < now();
    GET DIAGNOSTICS v_count = v_count + ROW_COUNT;

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION tracking_expire_tokens IS
    'Función de limpieza para ejecutar via pg_cron cada hora. '
    'Marca tokens expirados como hard_expired para liberar el unique index.';


COMMIT;
