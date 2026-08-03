# Tracking Backend — Especificación Técnica Definitiva

> **Versión:** 1.1 · **Fecha de reconciliación:** 2026-08-03 · **Estado:** LEGACY + M4.1A LOCAL PENDIENTE
> **Proyecto Supabase:** `<SUPABASE_PROJECT_REF>` · **URL:** `https://<SUPABASE_PROJECT_REF>.supabase.co`
> **Región:** us-east-1 · **Costo:** $0/mes
> **Referencia:** TRACKING_TOKEN_SECURITY_DESIGN.md

> **Nota de reconciliación (SEC.4B):** Las Edge Functions vigentes son
> `track-public`, `driver-view` y `track-driver`. Se autentican mediante tokens
> funcionales, requieren `verify_jwt=false` y todavía usan
> `SUPABASE_SERVICE_ROLE_KEY` como estado legacy. La configuración explícita,
> CORS staging y migración de credenciales quedan pendientes de SEC.4C–SEC.4H.
> `track-admin` no está implementada en el árbol actual y queda fuera de SEC.4.

> **Reconciliación local M4.1A (2026-08-03; no aplicada):** La migración
> `20260803142928_reconcile_tracking_rpc_contracts_m4_1.sql` propone corregir
> los RPC internos contra el esquema real (`state`, `revoked_at`,
> `revoked_by`), cerrar sus grants a `authenticated` y conservar el overload
> legacy de creación como wrapper. Esta nota describe código local pendiente de
> rollout; M4 y SEC.4 continúan abiertos. El fallback de credencial legacy sigue
> activo y no está autorizada todavía ninguna revocación de credenciales.

---

## A. Esquema Postgres — Desplegado

### A.1 Tablas base de soporte

```sql
-- Migración: create_base_tables (20260224204746)

CREATE TABLE tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    slug        TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL,
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    role        TEXT NOT NULL DEFAULT 'member',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, tenant_id)
);

CREATE TABLE operations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    reference_code      TEXT NOT NULL,          -- 'ROT-26-001'
    route_summary       TEXT,                   -- 'Nuevo Laredo → Monterrey'
    client_display_name TEXT,                   -- Truncated for driver view
    destination_city    TEXT,                   -- 'Monterrey, N.L.'
    eta_display         TEXT,                   -- 'Hoy, 18:00'
    status              TEXT NOT NULL DEFAULT 'active',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### A.2 Tabla `tracking_tokens`

**Decisión de diseño:** Una fila por token (no una fila por operación con dos hashes).

**Justificación:**
- Materializa la independencia de tokens en el esquema físico
- Cada token tiene su propio ciclo de vida (state, expires_at, revoked_at)
- La rotación crea una nueva fila y marca la anterior como `rotated` (audit trail perfecto)
- El índice parcial `UNIQUE (operation_id, scope) WHERE state = 'active'` garantiza máximo 1 token activo por tipo

```sql
-- Migración: create_tracking_tables (20260224204805)

CREATE TABLE tracking_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    operation_id    UUID NOT NULL REFERENCES operations(id) ON DELETE CASCADE,

    -- 'public:read' = link del cliente, 'driver:write' = link del chofer
    scope           TEXT NOT NULL
                    CHECK (scope IN ('public:read', 'driver:write')),

    -- SHA-256 hex del token literal. El token en texto plano NUNCA se almacena.
    token_hash      TEXT NOT NULL,

    -- Máquina de estados irreversible
    state           TEXT NOT NULL DEFAULT 'active'
                    CHECK (state IN (
                        'active',        -- Token válido y funcional
                        'soft_expired',  -- TTL vencido pero <48h (solo public: serve con banner)
                        'hard_expired',  -- TTL vencido >48h (bloqueo total)
                        'revoked',       -- Revocado manualmente (irreversible)
                        'rotated'        -- Reemplazado por un sucesor (irreversible)
                    )),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      UUID NOT NULL,          -- UID del usuario ERP que lo creó
    expires_at      TIMESTAMPTZ NOT NULL,   -- TTL absoluto
    delivered_at    TIMESTAMPTZ,            -- Se llena al recibir evento 'delivered'
    revoked_at      TIMESTAMPTZ,
    revoked_by      UUID,
    rotated_into    UUID REFERENCES tracking_tokens(id), -- FK al sucesor
    last_used_at    TIMESTAMPTZ,            -- Actualizado en cada request válido
    event_count     INTEGER NOT NULL DEFAULT 0,          -- Solo útil para driver:write
    ip_hash_last    TEXT,                   -- SHA-256(IP + salt), nunca IP en plano
    user_agent_last TEXT                    -- Truncado a 200 chars
);
```

**Índices:**

```sql
-- Hot path: lookup por hash (O(1))
CREATE UNIQUE INDEX tracking_tokens_hash_uq
    ON tracking_tokens (token_hash);

-- Máximo 1 activo por (operación + scope)
CREATE UNIQUE INDEX tracking_tokens_active_uq
    ON tracking_tokens (operation_id, scope)
    WHERE state = 'active';

-- UI interna: "ver tokens de esta operación"
CREATE INDEX tracking_tokens_operation_idx
    ON tracking_tokens (operation_id);

-- Cron de expiración
CREATE INDEX tracking_tokens_expires_idx
    ON tracking_tokens (expires_at)
    WHERE state = 'active';
```

### A.3 Tabla `tracking_events`

```sql
CREATE TABLE tracking_events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id          UUID NOT NULL REFERENCES tracking_tokens(id) ON DELETE CASCADE,
    tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    operation_id      UUID NOT NULL REFERENCES operations(id) ON DELETE CASCADE,

    event_type        TEXT NOT NULL
                      CHECK (event_type IN (
                          'departure',    -- 1x por viaje
                          'in_transit',   -- Max 15x por viaje, cooldown 30min
                          'arrival',      -- 1x por viaje, requiere departure previo
                          'delivered',    -- 1x por viaje, finaliza el token
                          'incident'      -- Sin límite, cooldown 10min
                      )),

    source            TEXT NOT NULL
                      CHECK (source IN ('gps', 'manual', 'none')),

    client_timestamp  TIMESTAMPTZ NOT NULL, -- Del dispositivo (para idempotency ±5s)
    server_timestamp  TIMESTAMPTZ NOT NULL DEFAULT now(),

    lat               NUMERIC(9,6),         -- NULL si source != 'gps'
    lng               NUMERIC(9,6),
    accuracy_m        NUMERIC(7,2),         -- Precisión GPS en metros

    municipality      TEXT,                 -- Reverse geocoded o manual
    state_name        TEXT,
    country_code      CHAR(2) DEFAULT 'MX',

    incident_type     TEXT,                 -- Solo para event_type = 'incident'
    incident_note     TEXT,                 -- Máx 280 chars

    is_suspicious     BOOLEAN NOT NULL DEFAULT false,  -- Anomalía geográfica
    offline_queued    BOOLEAN NOT NULL DEFAULT false,   -- Vino de cola offline

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
```

**Índices:**

```sql
-- Timeline público (ordenado por tiempo)
CREATE INDEX tracking_events_timeline_idx
    ON tracking_events (operation_id, server_timestamp DESC);

-- Idempotency: buscar duplicados por token + acción + timestamp
CREATE INDEX tracking_events_idempotency_idx
    ON tracking_events (token_id, event_type, client_timestamp);

-- Anti-ruido: último evento de un tipo
CREATE INDEX tracking_events_last_type_idx
    ON tracking_events (token_id, event_type, server_timestamp DESC);

-- Validar singletones (departure, delivered)
CREATE INDEX tracking_events_singleton_idx
    ON tracking_events (operation_id, event_type);
```

### A.4 Tabla `tracking_access_log`

```sql
CREATE TABLE tracking_access_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash      TEXT NOT NULL,
    accessed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_hash         TEXT,           -- SHA-256(IP + salt_diario), NUNCA IP en plano
    user_agent      TEXT,           -- Truncado a 200 chars
    country_code    CHAR(2)         -- CF-IPCountry header
);

CREATE INDEX tracking_access_log_hash_idx
    ON tracking_access_log (token_hash, accessed_at DESC);
```

### A.5 Enforcement de constraints: ¿Trigger vs RPC?

| Constraint | Mecanismo | Justificación |
|------------|-----------|---------------|
| Acción válida | ✅ **Edge + RPC** | `departure`, `in_transit`, `arrival`, `delivered`, `incident`; una acción inválida responde `400` |
| Cooldown `in_transit` | ✅ **RPC validation** | 30 minutos; responde `200`, `accepted:false`, `reason:cooldown` |
| Cooldown `incident` | ✅ **RPC validation** | 10 minutos; responde `200`, `accepted:false`, `reason:cooldown` |
| Idempotencia general por timestamp | ❌ **No vigente** | La última definición versionada no deduplica por `clientTimestamp`; queda para M4.1B/M4.6 |
| Singletones y secuencia de eventos | ❌ **No vigentes en la definición final** | No asumir respuestas `422` de versiones históricas |
| Anomalía por precisión | ✅ **RPC validation** | `accuracy > 5000m` marca el evento como sospechoso |
| Puntos de ruta GPS | ✅ **RPC validation** | Inserción separada con throttling de tiempo/distancia cuando aplica |

**Decisión:** Todo se valida en la RPC (`SECURITY DEFINER`), no con triggers.

**Justificación:**
- Los triggers no retornan mensajes de error descriptivos al cliente
- La RPC retorna JSONB con `{http, accepted, reason}` que la Edge Function traduce directamente a HTTP codes
- Es más fácil de depurar y evolucionar
- Defensa en profundidad: las constraints CHECK de la tabla son la segunda línea de defensa

---

## B. Hashing — Estrategia SHA-256

### B.1 Regla fundamental

> **El token literal (UUID v4) que circula en la URL NUNCA se almacena en la base de datos.**
> Solo se guarda su hash SHA-256 en formato hexadecimal (64 caracteres).

### B.2 Función de hash en Postgres

```sql
-- Desplegada como migración fix_hash_function_schema
CREATE OR REPLACE FUNCTION tracking_hash_token(p_token TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT encode(extensions.digest(p_token::bytea, 'sha256'), 'hex');
$$;
```

**Nota Supabase:** La función `digest()` de pgcrypto vive en el schema `extensions`, no en `public`. Por eso se usa `extensions.digest()`.

### B.3 Cálculo equivalente en Edge Function (Deno)

```
// Conceptual — no es código de producción aún
const token = "<PUBLIC_TOKEN>";
const data = new TextEncoder().encode(token);
const hash = await crypto.subtle.digest("SHA-256", data);
const hex = Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
// hex = "a1b2c3d4..." (64 chars)
```

### B.4 Ciclo de vida del token literal

```
1. CREACIÓN: rpc_create_tracking_token() genera UUID v4 con gen_random_uuid()
   → Almacena tracking_hash_token(uuid) en DB
   → Retorna UUID literal en la respuesta (ÚNICA VEZ)

2. DISTRIBUCIÓN: El operador ERP copia el link y lo envía por WhatsApp/email
   El token literal viaja solo en la URL: /t/<PUBLIC_TOKEN>

3. VALIDACIÓN: Cada request calcula SHA-256(token_del_request) y busca en DB
   → Si no hay match: 404 (scope-blind)
   → Si hay match: verificar state, expires_at, scope

4. ALMACENAMIENTO: La DB solo contiene el hash. Las respuestas de error no
   exponen el token. El código Edge vigente no registra el literal ni el body
   completo; los errores RPC se registran sin prefijo del token.
```

---

## C. RLS — Políticas de seguridad

### C.1 Principio: Acceso público y driver vía Edge Functions exclusivamente

```
Browser ─── Edge Function ─── Supabase DB (service_role key)
                │
                └── La Edge Function usa service_role key
                    que BYPASA RLS completamente.
                    La validación de acceso ocurre en la RPC
                    (SECURITY DEFINER), no en RLS.
```

**¿Por qué no usar RLS para el acceso público?**
- Un `anon` user con RLS necesitaría un policy que exponga hashes de tokens. Inaceptable.
- El token literal llegaría como parámetro de una query directa a la tabla. Eso lo haría visible en logs de Postgres.
- La Edge Function se interpone como gateway de seguridad. Usa `service_role` para bypasear RLS y llama RPCs `SECURITY DEFINER` que hacen toda la validación.

### C.2 Políticas desplegadas

```sql
-- tracking_tokens: RLS habilitado
ALTER TABLE tracking_tokens ENABLE ROW LEVEL SECURITY;

-- Solo usuarios autenticados del mismo tenant pueden VER tokens (UI interna)
CREATE POLICY "internal_read_own_tenant_tokens"
    ON tracking_tokens FOR SELECT
    TO authenticated
    USING (
        tenant_id IN (
            SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
        )
    );
-- Sin policy INSERT/UPDATE/DELETE → solo service_role puede escribir

-- tracking_events: RLS habilitado
ALTER TABLE tracking_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "internal_read_own_tenant_events"
    ON tracking_events FOR SELECT
    TO authenticated
    USING (
        tenant_id IN (
            SELECT tenant_id FROM memberships WHERE user_id = auth.uid()
        )
    );
-- Sin policy INSERT → solo service_role (Edge Functions) puede insertar

-- tracking_access_log: RLS habilitado, SIN policies
ALTER TABLE tracking_access_log ENABLE ROW LEVEL SECURITY;
-- → Invisible para anon y authenticated. Solo service_role lee/escribe.
```

### C.3 Resumen de acceso por rol

| Tabla | `anon` | `authenticated` | `service_role` | Edge Function RPC |
|-------|:------:|:---------------:|:--------------:|:-----------------:|
| `tracking_tokens` | ❌ Bloqueado | ✅ SELECT (su tenant) | ✅ Full | ✅ SECURITY DEFINER |
| `tracking_events` | ❌ Bloqueado | ✅ SELECT (su tenant) | ✅ Full | ✅ SECURITY DEFINER |
| `tracking_access_log` | ❌ Bloqueado | ❌ Bloqueado | ✅ Full | ✅ INSERT only |

---

## D. Contratos de Endpoints (Edge Functions)

### D.1 `GET /functions/v1/track-public?token=<PUBLIC_TOKEN>`

**Propósito:** Retorna `PublicTrackingView` sanitizado para el link del cliente.

**Request:**
```
GET /functions/v1/track-public?token=<PUBLIC_TOKEN>
Headers: (ninguno requerido — acceso público)
```

**Flujo interno:**
```
1. Rate limit check: IP (60/min) + token prefix (120/min)
2. supabase.rpc('rpc_get_public_tracking', { p_token })
   2a. SHA-256(token) → lookup en tracking_tokens WHERE scope = 'public:read'
   2b. Computar estado efectivo (active / soft / hard expired)
   2c. Query tracking_events → build timeline (max 20, IDs ordinales)
   2d. Redondear coordenadas a 2 decimales (GEO-01: ~1.1 km)
   2e. Omitir location si delivered (GEO-03) o si null (GEO-04)
   2f. Update last_used_at (async)
3. Esperar el log best-effort con Promise.allSettled; un fallo no invalida la respuesta
4. Return JSON + X-Robots-Tag: noindex + Cache-Control: 60s
```

**Response exitosa (200):**
```json
{
    "status": "success",
    "expired": false,
    "data": {
        "orderRef": "ROT-26-001",
        "route": "Nuevo Laredo → Monterrey",
        "currentStatus": "En Tránsito",
        "eta": "Hoy, 18:00",
        "currentLocation": { "lat": 26.01, "lng": -99.75 },
        "events": [
            {
                "id": "evt-1",
                "title": "Salida de Almacén",
                "subtitle": "Nuevo Laredo, Tamaulipas · 10:50",
                "timestamp": "2026-02-24T16:50:46Z",
                "icon": "truck",
                "status": "done"
            },
            {
                "id": "evt-2",
                "title": "En camino",
                "subtitle": "Sabinas Hidalgo, Nuevo León · 12:30",
                "timestamp": "2026-02-24T18:30:00Z",
                "icon": "map-pin",
                "status": "current"
            }
        ]
    }
}
```

**Responses de error:**

| HTTP | `status` | Cuándo | Mensaje UI sugerido |
|:----:|----------|--------|---------------------|
| 404 | `not_found` | Token no existe, scope incorrecto, o tenant incorrecto | "Este enlace de seguimiento no existe." |
| 200 | `soft_expired` | TTL vencido pero < 48h | Banner: "Este seguimiento ha expirado. Los datos pueden no estar actualizados." |
| 410 | `hard_expired` | TTL vencido > 48h | "Este enlace de seguimiento ya no está disponible." |
| 403 | `revoked` | Token revocado manualmente | "Este enlace fue desactivado por el operador." |
| 429 | `rate_limited` | Rate limit excedido | "Demasiadas solicitudes. Intenta de nuevo en un momento." |

**Headers de respuesta obligatorios:**
```
X-Robots-Tag: noindex, nofollow
Cache-Control: public, max-age=60, stale-while-revalidate=30
Access-Control-Allow-Origin: <ORIGEN_PERMITIDO>
```

La cabecera CORS solo se incluye para orígenes de la allowlist vigente; no se
usa wildcard. `https://rotero-erp-staging.netlify.app` sigue pendiente de
incorporación en SEC.4C.

**NO-LEAK checklist para este endpoint:**
- [x] No expone `orderId` UUID de DB → usa `orderRef` (referencia externa)
- [x] No expone `tenantId`, `userId`, `tokenId`
- [x] Coordenadas redondeadas a 2 decimales (~1.1 km)
- [x] `currentLocation` omitido si `delivered` o si `null`
- [x] Timeline IDs son ordinales (`evt-1`, `evt-2`), no UUIDs de DB
- [x] Sin nombre/teléfono/placa del chofer
- [x] Sin datos fiscales
- [x] Sin notas internas ni `incident_note`
- [x] Eventos `is_suspicious` excluidos del timeline
- [x] Error 404 = scope-blind (no revela si token existe con otro scope)

---

### D.2 `POST /functions/v1/track-driver`

**Propósito:** El chofer crea un nuevo TrackingEvent.

**Request:**
```
POST /functions/v1/track-driver
Content-Type: application/json

{
    "driverToken": "<DRIVER_TOKEN>",
    "action": "in_transit",
    "location": {
        "lat": 26.5080,
        "lng": -99.7500,
        "accuracy": 20.0,
        "source": "gps"
    },
    "manualPlace": null,
    "incident": null,
    "clientTimestamp": "2026-02-24T18:30:00.000Z",
    "offlineQueued": false
}
```

**Valores válidos por campo:**

| Campo | Valores | Requerido |
|-------|---------|:---------:|
| `driverToken` | UUID v4 string | ✅ |
| `action` | `departure` · `in_transit` · `arrival` · `delivered` · `incident` | ✅ |
| `location.source` | `gps` · `manual` · `none` | ✅ |
| `location.lat/lng` | Coordenadas decimales | Solo si source=gps |
| `location.accuracy` | Metros (float) | Solo si source=gps |
| `manualPlace.municipality` | Texto libre | Solo si source=manual |
| `manualPlace.state` | Texto libre | Solo si source=manual |
| `incident.type` | Texto libre | Solo si action=incident |
| `incident.note` | Texto, máx 280 chars | Opcional con incident |
| `clientTimestamp` | ISO 8601 UTC | ✅ |
| `offlineQueued` | boolean | Opcional (default false) |

**Flujo de validaciones (en orden, todas en el servidor):**

```
 1. Rate limit: IP ≤ 20 req/hora
 2. Input validation: campos requeridos presentes, action válido
 3. SHA-256(driverToken) → lookup WHERE scope = 'driver:write'
 4. Token state = 'active' (soft_expired → 403 para driver)
 5. Token expires_at > now()
 6. Idempotency: no existe (token_id, action, clientTimestamp ± 5s)
 7. Singleton: departure/delivered/arrival no repetidos
 8. arrival requiere departure previo
 9. in_transit: count < 15 (max_events_reached)
10. in_transit: cooldown 30 min desde último in_transit
11. in_transit + source=gps: municipality no sea igual al anterior (same_municipality)
12. incident: cooldown 10 min desde último incident
13. Anomaly: >300km en <30min → is_suspicious = true (no rechaza)
14. INSERT tracking_events
15. UPDATE tracking_tokens.event_count + last_used_at
16. Si action=delivered → SET delivered_at = now()
```

**Response exitosa (201):**
```json
{
    "http": 201,
    "accepted": true,
    "eventId": "evt-4",
    "serverTimestamp": "2026-02-24T18:30:01.123Z"
}
```

**Responses de rechazo:**

| HTTP | `accepted` | `reason` | Cuándo |
|:----:|:----------:|----------|--------|
| 403 | — | `token_not_found` | Token no existe o scope incorrecto |
| 403 | — | `token_revoked` | Token revocado |
| 403 | — | `token_expired` | TTL vencido |
| 403 | — | `token_soft_expired` | Solo para driver (soft = bloqueado) |
| 200 | `false` | `duplicate` | Idempotency hit — no es error |
| 422 | `false` | `action_already_done` | departure/delivered/arrival repetido |
| 422 | `false` | `departure_required_first` | arrival sin departure |
| 422 | `false` | `max_events_reached` | ≥ 15 in_transit en este viaje |
| 422 | `false` | `cooldown_active` | < 30min desde último in_transit (o < 10min incident) |
| 422 | `false` | `same_municipality` | Municipio no cambió (anti-ruido) |
| 429 | `false` | `rate_limited` | Rate limit IP |
| 400 | — | `missing_fields` | Campos requeridos faltantes |
| 400 | — | `invalid_action` | Action no reconocido |

---

### D.3 `GET /functions/v1/driver-view?token=<DRIVER_TOKEN>`

**Propósito:** Retorna `DriverView` sanitizado para la mini-web del chofer.

**Response exitosa (200):**
```json
{
    "status": "success",
    "data": {
        "orderRef": "ROT-26-001",
        "route": "Nuevo Laredo → Monterrey",
        "currentStatus": "in_transit",
        "eta": "Hoy, 18:00",
        "clientName": "Acme Corp",
        "destinationCity": "Monterrey, N.L.",
        "lastEvent": {
            "municipality": "Sabinas Hidalgo, Nuevo León",
            "timestamp": "2026-02-24T18:30:00Z"
        }
    }
}
```

**NO-LEAK para DriverView:**
- [x] `clientName` truncado a 20 caracteres
- [x] Sin dirección exacta de entrega
- [x] Sin datos fiscales
- [x] Sin IDs internos (orderId, tenantId, tokenId)
- [x] Sin coordenadas (el chofer no necesita verse en un mapa)
- [x] Sin notas internas de operador
- [x] No se cachea (`Cache-Control: no-store`)

---

## E. RPCs Desplegadas

| RPC | Scope | Propósito |
|-----|-------|-----------|
| `rpc_get_public_tracking(p_token)` | `public:read` | PublicTrackingView sanitizado |
| `rpc_get_driver_view(p_token)` | `driver:write` | DriverView sanitizado |
| `rpc_post_driver_event(p_token, ...)` | `driver:write` | Insertar evento; `400` acción inválida, `404` token ausente, `403` revocado/expirado, `200` aceptado/cooldown |
| `rpc_create_tracking_token(tenant, op, scope, ttl, force_rotate)` | `internal core` | Crear/rotar token; el literal solo se retorna al crear/rotar |
| `rpc_create_tracking_token(tenant, op, scope)` | `internal legacy` | Wrapper no rotante hacia el core; retiro pendiente de consumidores |
| `rpc_create_tracking_token(tenant, op, scope, ttl)` | `internal adapter` | Compatibilidad SQL histórica; delega con `force_rotate=false` |
| `rpc_create_tracking_token(tenant, op, scope, force_rotate)` | `internal adapter` | Compatibilidad con las llamadas frontend que omiten TTL |
| `rpc_list_tracking_tokens(tenant)` | `internal` | Listar metadatos sanitizados; sin hash en la propuesta M4.1A |
| `rpc_revoke_tracking_token(token_id)` | `internal` | Revocación idempotente propuesta en M4.1A; rollout pendiente |
| `tracking_validate_token(token, scope)` | helper | Validar token + computar estado efectivo |
| `tracking_hash_token(token)` | helper | SHA-256 hex de un token literal |
| `tracking_expire_tokens()` | cron | Marcar tokens expirados (ejecutar c/hora) |

---

## F. Checklist de Pruebas (14 casos)

### F.1 Token lifecycle

| # | Caso | Input | Expected | Verificado |
|---|------|-------|----------|:----------:|
| T01 | Crear publicToken | `rpc_create_tracking_token(tenant, op, 'public:read', null, false)` | Si no existe activo, retorna `{token, token_id, scope, expires_at}`; default 7 días | ⬜ M4.1A |
| T02 | Crear driverToken | `rpc_create_tracking_token(tenant, op, 'driver:write', null, false)` | Si no existe activo, retorna literal una vez; default 48h | ⬜ M4.1A |
| T03 | Revocar driverToken | `rpc_revoke_tracking_token(token_id)` | `state → revoked`; `revoked_at`/`revoked_by` establecidos | ⬜ M4.1A pendiente |
| T04 | Evento post-revocación | `rpc_post_driver_event(revoked_token, ...)` | `{http: 403, accepted:false, reason:'revoked'}` | ⬜ M4.4 |
| T05 | publicToken sigue activo post-revocación de driver | `rpc_get_public_tracking(public_token)` | `{status: 'success'}` con datos | ✅ |
| T06 | Rotación explícita de driverToken activo | `rpc_create_tracking_token(..., p_force_rotate=true)` | Anterior → `rotated`; nuevo → `active`; literal nuevo una sola vez | ⬜ M4.1A |

### F.2 Scope-blind y NO-LEAK

| # | Caso | Input | Expected | Verificado |
|---|------|-------|----------|:----------:|
| T07 | driverToken en endpoint público | `rpc_get_public_tracking(driver_token)` | `{status: 'not_found'}` (idéntico a token inexistente) | ✅ |
| T08 | Token inexistente | `rpc_get_public_tracking('<PUBLIC_TOKEN>')` | `{status: 'not_found'}` | ✅ |
| T09 | PublicView no contiene IDs de DB | Inspeccionar response | Solo `orderRef`, `evt-N`. Sin UUIDs internos | ✅ |

### F.3 Anti-ruido y validaciones

| # | Caso | Input | Expected | Verificado |
|---|------|-------|----------|:----------:|
| T10 | Acción inválida | Enviar acción fuera del allowlist | `{http: 400, accepted: false, reason: 'invalid_action'}` | ⬜ M4.4 |
| T11 | in_transit aceptado | Primer `in_transit` elegible | `{http: 200, accepted: true, eventId: <uuid>}` | ⬜ M4.4 |
| T12 | in_transit cooldown | Segundo `in_transit` inmediato (< 30 min) | `{http: 200, accepted: false, reason: 'cooldown'}` | ⬜ M4.4 |
| T13 | incident cooldown | Segundo `incident` inmediato (< 10 min) | `{http: 200, accepted: false, reason: 'cooldown'}` | ⬜ M4.4 |
| T14 | Idempotencia general | Repetir otro evento con el mismo `clientTimestamp` | No garantizada por el contrato final; deuda M4.1B/M4.6 | ⬜ |

**Leyenda:** ✅ = Verificado en smoke test · ⬜ = Verificable en test de integración (requiere delays o mock de clock)

---

## G. Migraciones Aplicadas

| # | Versión | Nombre | Contenido |
|---|---------|--------|-----------|
| 1 | 20260224204746 | `create_base_tables` | tenants, memberships, operations |
| 2 | 20260224204805 | `create_tracking_tables` | tracking_tokens, tracking_events, tracking_access_log + 8 índices + constraints + RLS |
| 3 | 20260224204822 | `create_tracking_functions_helpers` | tracking_hash_token(), tracking_validate_token() |
| 4 | 20260224204847 | `create_rpc_get_public_tracking` | PublicTrackingView con GEO-01/03/04 |
| 5 | 20260224204920 | `create_rpc_post_driver_event` | Insert con 13 validaciones |
| 6 | 20260224204955 | `create_tracking_admin_functions` | create/revoke token, driver view, expire cron |
| 7 | 20260224205026 | `fix_hash_function_schema` | Fix digest() → extensions.digest() para Supabase |

---

## H. Datos de prueba en el sistema

| Entidad | ID | Valor |
|---------|-----|-------|
| Tenant | `aaaaaaaa-0000-...-0001` | WLS Rotero Test |
| Operación | `bbbbbbbb-0000-...-0001` | ROT-26-001, Nuevo Laredo → Monterrey |
| publicToken (activo) | hash almacenado | Ejemplo: `<PUBLIC_TOKEN>` |
| driverToken (REVOCADO) | hash almacenado | Ejemplo: `<DRIVER_TOKEN>` |
| Eventos | 3 | departure + 2x in_transit |
