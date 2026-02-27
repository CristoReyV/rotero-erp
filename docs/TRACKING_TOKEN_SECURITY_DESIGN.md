# Diseño de Seguridad de Tokens — Módulo Tracking
> **Versión:** 1.0-FINAL · **Fecha:** 2026-02-24
> **Módulo:** OPS_TRACK · **Estado:** APROBADO
> **Reemplaza o complementa:** TRACKING_TOKEN_SCHEMA.md, TRACKING_SECURITY.md

---

## 0. Alcance de este Documento

Este documento define la arquitectura de seguridad completa para los dos tipos de links del módulo Tracking:

| Link | Ruta | Propósito |
|------|------|-----------|
| **Público** | `/t/:publicToken` | El cliente ve el estado y posición aproximada de su envío |
| **Chofer** | `/driver/:driverToken` | El operador (chofer) reporta eventos de ubicación y estado |
| **Interno** | `/tracking` (autenticado) | Gestión total: ver, revocar, regenerar, ver datos sensibles |

---

## 1. Decisión de Modelo: Tokens Completamente Independientes

### Opciones evaluadas

| Opción | Descripción | Veredicto |
|--------|-------------|-----------|
| **A — Derivados** | `driverToken = HMAC(publicToken, secret)` | ❌ Rechazada |
| **B — Independientes** | Cada token es un `uuid_v4` generado por separado, sin relación matemática | ✅ **ADOPTADA** |
| **C — JWT con scope** | Token firmado con claims `{ orderId, scope, exp }` | ⚠️ Reservada para v2 |

### Por qué **NO** tokens derivados (Opción A)

- Si el `secret` del servidor se compromete, **todos** los tokens derivados expiran simultáneamente con un solo leak.
- Si un atacante observa el `publicToken`, puede intentar derivar el `driverToken` conociendo el algoritmo.
- Aumenta la superficie criptográfica sin beneficio operativo real en v1.

### Por qué **NO** JWT (Opción C, por ahora)

- Los JWTs son **stateless por diseño**: revocarlos antes de que expiren exige una blocklist en DB, cancelando su ventaja principal.
- Para el caso de uso de revocación **inmediata y urgente** (chofer comprometido, orden robada), necesitamos revocación síncrona garantizada. Un UUID en DB es O(1) lookup con chequeo de estado incluyendo `revoked_at`.
- JWT es válido en v2 si se combina con una blocklist Redis. No en v1 mock-first.

### Por qué **SÍ** tokens independientes (Opción B)

| Propiedad | Beneficio |
|-----------|-----------|
| **Blast radius acotado** | Revocación del `publicToken` (link filtrado) no afecta al chofer ni viceversa |
| **Revocación granular** | Se puede desactivar solo el `driverToken` sin invalidar el link del cliente |
| **Rotación limpia** | El `driverToken` se rota al cambiar de chofer; el `publicToken` permanece igual para el cliente |
| **Simplicidad del hot path** | Lookup O(1) por UUID indexado. Sin criptografía en cada request |
| **Auditabilidad** | Estado explícito almacenado en DB, no inferido de claims firmados |

---

## 2. Scopes y Tabla de Permisos

### 2.1 Definición de Scopes

| Scope | Portador | Ruta de uso | Tipo de acceso |
|-------|----------|-------------|----------------|
| `public:read` | `publicToken` | `/t/:token` | Solo lectura de `PublicTrackingView` |
| `driver:write` | `driverToken` | `/driver/:token` | Crear eventos de estado/ubicación/incidencia. Sin acceso a datos sensibles |
| `internal` | Sesión autenticada (Supabase Auth + JWT de app) | `/tracking` | Acceso total: gestión, datos fiscales, coordenadas exactas, audit log |

### 2.2 Tabla de Permisos por Scope

| Capacidad / Dato | `public:read` | `driver:write` | `internal` |
|------------------|:---:|:---:|:---:|
| Ver estado del envío (humanizado) | ✅ | ✅ | ✅ |
| Ver timeline de municipios | ✅ | ✅ | ✅ |
| Ver ETA estimada | ✅ | ✅ | ✅ |
| Ver nombre de cliente (truncado) | ❌ | ✅ | ✅ |
| Ver ciudad de destino (solo nombre) | ❌ | ✅ | ✅ |
| Ver dirección exacta de entrega | ❌ | ❌ | ✅ |
| Ver coordenadas aproximadas (~1.1 km) | ✅ | ❌ | ✅ |
| Ver coordenadas exactas (6 dec.) | ❌ | ❌ | ✅ |
| Ver nombre / teléfono del chofer | ❌ | ❌ | ✅ |
| Ver placa / unidad | ❌ | ❌ | ✅ |
| Ver datos fiscales (RFC, razón social) | ❌ | ❌ | ✅ |
| Ver montos / valor declarado | ❌ | ❌ | ✅ |
| Ver notas internas del operador | ❌ | ❌ | ✅ |
| Ver IDs internos (orderId, tenantId) | ❌ | ❌ | ✅ |
| Crear evento `departure` | ❌ | ✅ | ✅ |
| Crear evento `in_transit` | ❌ | ✅ | ✅ |
| Crear evento `arrival` | ❌ | ✅ | ✅ |
| Crear evento `delivered` | ❌ | ✅ | ✅ |
| Crear evento `incident` | ❌ | ✅ | ✅ |
| Revocar token | ❌ | ❌ | ✅ |
| Regenerar / rotar token | ❌ | ❌ | ✅ |
| Ver audit log | ❌ | ❌ | ✅ |

> **REGLA CRÍTICA:** El scope de un token se valida **solo en el servidor** (Edge Function / RPC con SECURITY DEFINER). El frontend nunca debe asumir permisos basándose en el tipo de ruta; siempre los determina la respuesta del backend.

---

## 3. Expiración y Revocación

### 3.1 TTL por tipo de token

| Token | TTL por defecto | TTL máximo | Lógica post-entrega |
|-------|:--------------:|:----------:|---------------------|
| `publicToken` | 7 días | 30 días | `delivered_at + 48h` soft-expired → `+ 48h` hard-expired |
| `driverToken` | 48 horas | 72 horas | Expira automáticamente al confirmar `delivered`. Si no confirma: TTL fijo |

**Justificación de TTL más corto para `driverToken`:**
- Un token de escritura vivo por más tiempo es superficie de ataque innecesaria.
- Un viaje terrestre MX (Laredo→CDMX) raramente supera 24h. 48h incluye margen operativo holgado.
- Si el viaje se extiende por fuerza mayor, el operador interno puede rotar el token y mandar uno fresco.

### 3.2 Estados de un token

```
CREATED ──→ ACTIVE ──→ SOFT_EXPIRED ──→ HARD_EXPIRED (irreversible)
                  └──→ REVOKED (irreversible)
                  └──→ ROTATED (pasa a inactivo, se crea sucesor)
```

> Un token `SOFT_EXPIRED` del publicToken sigue sirviendo datos en modo read-only con banner de aviso.
> Un token `SOFT_EXPIRED` del driverToken recibe HTTP 403. No se acepta ningún evento de escritura.

### 3.3 Rotación de tokens

| Escenario | Token afectado | Comportamiento |
|-----------|---------------|----------------|
| Cambio de chofer | `driverToken` | Se invalida el anterior → se genera uno nuevo. El `publicToken` **no cambia**. El cliente no percibe nada. |
| Link del cliente compartido con persona equivocada | `publicToken` | Se revoca el anterior → se genera uno nuevo. El operador reenvía el nuevo link. El `driverToken` **no cambia**. |
| Compromiso de seguridad total | Ambos | Revocar ambos en una transacción. Emitir ambos nuevos. Notificar al operador por canal interno. |
| Rotación preventiva (política empresa) | Ambos o sólo `driverToken` | Configurable por tenant. Recomendado: rotar `driverToken` cada 24h en operaciones de alto valor. |

**Regla ROT-01:** Solo puede existir un `driverToken` activo por operación simultáneamente.

### 3.4 Eventos offline cuando el token expira

| Situación | Comportamiento |
|-----------|----------------|
| El evento se encoló offline y el token expiró antes de sincronizar | El servidor rechaza con `403 token_expired`. El cliente muestra aviso al chofer. El evento se descarta (no se reinintenta). |
| El evento se encoló offline y el token sigue activo | Se procesa normalmente al reconectar. |
| El `driverToken` se revoca mientras el chofer está offline | Al reconectar, el primer sync devuelve `403 token_revoked`. Se vacía la cola local. El chofer ve pantalla "Acceso Desactivado". |

> **Diseño intencional:** No reintentamos eventos con token vencido. Aceptar eventos tardíos con token expirado crearía una ventana de ataque post-revocación. La consistencia del timeline pesa más que la completitud de eventos edge-case.

---

## 4. Anti-Abuso

### 4.1 Rate Limiting por scope

| Scope / Endpoint | Límite | Ventana | Acción al exceder |
|-----------------|:------:|:-------:|-------------------|
| `GET /api/track/:publicToken` | 120 req | 1 min | HTTP 429, `Retry-After: 60` |
| `GET /api/track/:publicToken` (por IP) | 60 req | 1 min | HTTP 429, `Retry-After: 60` |
| `POST /api/driver/:driverToken/events` | **20 req** | 1 hora | HTTP 429. Más restrictivo: escritura |
| `POST /api/driver/:driverToken/events` in_transit | **15 por viaje** (cumulative) | Duración del viaje | HTTP 422 `max_events_reached` |
| Audit endpoints (internos) | 200 req | 1 min | Solo para sesiones autenticadas |

### 4.2 Límite de eventos por tipo (scope `driver:write`)

| Tipo de evento | Máximo por viaje | Cooldown mínimo entre eventos |
|----------------|:----------------:|:-----------------------------:|
| `departure` | **1** (irrepetible) | — |
| `in_transit` | **15** | **30 minutos** |
| `arrival` | **1** (irrepetible una vez `departure` confirmado) | — |
| `delivered` | **1** (irrepetible, finaliza el token) | — |
| `incident` | Sin límite duro | **10 minutos** |

> Estos valores corresponden a `DRIVER_ANTI_NOISE` en `src/types/tracking.ts`. El backend debe validarlos independientemente del frontend (defensa en profundidad).

### 4.3 Detección de comportamiento sospechoso

| Señal | Umbral | Acción |
|-------|--------|--------|
| Eventos `in_transit` desde coordenadas geográficamente imposibles (>300 km en <30 min) | 1 evento anómalo | Marcar evento como `source: suspicious`. Notificar a `ops_director`. No rechazar (no bloquear al chofer real). |
| Más de 3 tokens distintos accedidos desde misma IP en <10 min | >3 tokens/IP | Progressive delay +1s por token adicional. Log de alerta. |
| Eventos `in_transit` con `location.source = 'none'` en >80% de los eventos del viaje | >80% sin GPS | Alerta interna. Sin penalización al chofer. |
| Intentos a tokens inexistentes desde misma IP | >10 en 5 min | IP en cooling-down de 15 min. |
| Misma secuencia de acciones en <3 segundos | acción duplicada | Idempotency check por `clientTimestamp` ± 5s. Rechazar duplicado silencioso (HTTP 200 con `accepted: false, reason: duplicate`). |

### 4.4 Idempotencia de eventos del chofer

Cada `POST /api/driver/:driverToken/events` debe incluir:
- `clientTimestamp` (ISO 8601, generado en cliente)
- El backend rechaza silenciosamente cualquier evento con mismo `(driverToken, action, clientTimestamp ± 5s)` como duplicado.
- Esto protege contra doble-submit por reintento de cola offline.

---

## 5. Esquema de Datos Mínimo (Backend Futuro)

### 5.1 Tabla `tracking_tokens`

```sql
CREATE TABLE tracking_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    operation_id    UUID NOT NULL REFERENCES operations(id),
    scope           TEXT NOT NULL CHECK (scope IN ('public:read', 'driver:write')),
    token_hash      TEXT NOT NULL UNIQUE,  -- SHA-256 del token. El token literal NUNCA se almacena.
    state           TEXT NOT NULL DEFAULT 'active'
                    CHECK (state IN ('active', 'soft_expired', 'hard_expired', 'revoked', 'rotated')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by      UUID NOT NULL REFERENCES users(id),
    expires_at      TIMESTAMPTZ NOT NULL,
    delivered_at    TIMESTAMPTZ,           -- Se llena cuando llega evento delivered
    revoked_at      TIMESTAMPTZ,
    revoked_by      UUID REFERENCES users(id),
    rotated_into    UUID REFERENCES tracking_tokens(id),  -- apunta al sucesor
    last_used_at    TIMESTAMPTZ,           -- actualizado en cada request válido
    event_count     INTEGER NOT NULL DEFAULT 0  -- solo para scope driver:write (anti-abuso)
);

-- Garantiza solo 1 token activo por (operación + scope)
CREATE UNIQUE INDEX tracking_tokens_active_unique
    ON tracking_tokens (operation_id, scope)
    WHERE state = 'active';

-- Lookup rápido por hash
CREATE INDEX tracking_tokens_hash_idx ON tracking_tokens (token_hash);
```

> **CRÍTICO:** El `token` literal que circula en la URL **nunca se almacena en DB**. Solo se guarda `token_hash = sha256(token)`. La validación en runtime hace `sha256(request_token)` y busca en DB. Esto protege ante dump de la tabla.

### 5.2 Tabla `tracking_events`

```sql
CREATE TABLE tracking_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id        UUID NOT NULL REFERENCES tracking_tokens(id),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    operation_id    UUID NOT NULL REFERENCES operations(id),
    event_type      TEXT NOT NULL CHECK (event_type IN (
                        'departure', 'in_transit', 'arrival', 'delivered', 'incident'
                    )),
    source          TEXT NOT NULL CHECK (source IN ('gps', 'manual', 'none')),
    client_timestamp TIMESTAMPTZ NOT NULL,  -- Timestamp del cliente (para idempotency)
    server_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Timestamp confiable del servidor
    lat             NUMERIC(9,6),           -- NULL si source = 'none' o 'manual'
    lng             NUMERIC(9,6),           -- NULL si source = 'none' o 'manual'
    accuracy_m      NUMERIC(7,2),           -- Precisión GPS en metros, si disponible
    municipality    TEXT,
    state_name      TEXT,
    country_code    CHAR(2),
    incident_type   TEXT,                   -- Solo para event_type = 'incident'
    incident_note   TEXT,                   -- Máx 280 chars, solo para 'incident'
    is_suspicious   BOOLEAN NOT NULL DEFAULT false,  -- Flag de anomalía geográfica
    offline_queued  BOOLEAN NOT NULL DEFAULT false   -- Vino de cola offline
);

-- Índice para el endpoint público (timeline de un viaje)
CREATE INDEX tracking_events_operation_time_idx
    ON tracking_events (operation_id, server_timestamp DESC);
```

---

## 6. Contrato de los Endpoints Futuros

### 6.1 `GET /api/track/:publicToken`

**Propósito:** Retorna `PublicTrackingView` para el link del cliente.

**Validaciones (en orden, todas en el servidor):**

1. `sha256(publicToken)` existe en `tracking_tokens WHERE scope = 'public:read'`
2. `state ∉ { 'hard_expired', 'revoked' }` → si no, respuesta de error inmediata
3. `state = 'soft_expired'` → retornar datos con flag `expired: true` en el body
4. Actualizar `last_used_at = now()` (fuera del hot path, async)

**Response exitosa (HTTP 200):**
```json
{
    "status": "success",
    "expired": false,
    "data": {
        "orderRef": "ROT-24-001",
        "route": "Laredo → Monterrey",
        "currentStatus": "En Tránsito",
        "eta": "Hoy, 14:00",
        "currentLocation": { "lat": 25.96, "lng": -100.17 },
        "events": [
            { "id": "evt-1", "title": "Salida de Almacén", "subtitle": "Nuevo Laredo, Tam. · 10:00 AM", "timestamp": "...", "status": "done", "icon": "truck" }
        ]
    }
}
```

**Responses de error:**

| HTTP | `status` en body | Cuándo |
|------|-----------------|--------|
| `404` | `not_found` | Token no existe |
| `403` | `revoked` | Token revocado |
| `410` | `hard_expired` | Más de 48h post-expiración |
| `429` | `rate_limited` | Rate limit excedido |
| `200` | `soft_expired` | Dentro de ventana de 48h post-expiración |

> **REGLA NO-LEAK:** La respuesta 404 debe ser **idéntica** para: token no existe, token de scope incorrecto, tenant incorrecto. Nunca revelar la razón exacta del fallo a un token desconocido.

---

### 6.2 `POST /api/driver/:driverToken/events`

**Propósito:** El chofer crea un nuevo `TrackingEvent` para la operación asociada al token.

**Request body:**
```json
{
    "action": "in_transit",
    "location": {
        "lat": 25.6866,
        "lng": -100.3161,
        "accuracy": 12.4,
        "source": "gps"
    },
    "manualPlace": null,
    "incident": null,
    "clientTimestamp": "2026-02-24T19:30:00.000Z",
    "offlineQueued": false
}
```

**Validaciones del servidor (en orden):**

1. `sha256(driverToken)` existe en `tracking_tokens WHERE scope = 'driver:write'`
2. `state = 'active'` (cualquier otro estado → 403 inmediato, **incluyendo soft_expired**)
3. `expires_at > now()` (TTL no vencida)
4. Idempotency: no existe evento con mismo `(token_id, action, clientTimestamp ± 5s)`
5. Rate limit: `event_count < limite_por_action`para el `action` recibido
6. Si `action = 'in_transit'`: verificar cooldown de 30 min desde último `in_transit`; verificar que el municipio haya cambiado (si `source != 'none'`)
7. Si `action = 'departure'` y ya existe un `departure` para este token → rechazar con `conflict`
8. Reverse geocoding (si `source = 'gps'`): llamar al servicio interno (no Nominatim directo desde cliente)
9. Anomalía geográfica: comparar coords con último evento; si delta > 300 km en < 30 min, marcar `is_suspicious = true`
10. Insertar en `tracking_events`
11. Incrementar `event_count` en `tracking_tokens`
12. Si `action = 'delivered'`: actualizar `delivered_at` en token; programar job para marcar `state = 'soft_expired'` en 48h

**Response exitosa (HTTP 201):**
```json
{
    "accepted": true,
    "eventId": "evt-ordinal-4",
    "serverTimestamp": "2026-02-24T19:30:01.123Z"
}
```

**Responses de rechazo:**

| HTTP | `accepted` | `reason` | Cuándo |
|------|:----------:|----------|--------|
| `403` | — | `token_expired` / `token_revoked` / `token_not_found` | Token inválido |
| `429` | `false` | `rate_limited` | Rate limit general |
| `422` | `false` | `max_events_reached` | Límite de `in_transit` alcanzado |
| `422` | `false` | `cooldown_active` | Menos de 30 min desde último `in_transit` |
| `422` | `false` | `same_municipality` | Municipio no cambió (anti-ruido) |
| `422` | `false` | `action_already_done` | `departure` o `delivered` repetido |
| `200` | `false` | `duplicate` | Idempotency hit (no es error, se ignora silenciosamente) |

---

## 7. Checklist NO-LEAK Confirmado

| # | Control | Estado | Referencia |
|---|---------|:------:|------------|
| **NL-01** | `publicToken` no contiene ni codifica `orderId`, `tenantId` ni ningún ID interno | ✅ UUID v4 opaco | §1 |
| **NL-02** | `driverToken` no contiene ni codifica `orderId`, `tenantId` ni ningún ID interno | ✅ UUID v4 opaco | §1 |
| **NL-03** | Token literal nunca almacenado en DB (solo su hash SHA-256) | ✅ Diseño §5.1 | §5 |
| **NL-04** | Token literal nunca aparece en logs, audit log ni respuestas de error | ✅ Solo hash en logs | §5 |
| **NL-05** | `PublicTrackingView` no expone `orderId` de DB, solo `orderRef` (referencia externa) | ✅ Spec §6.2 TRACKING_SECURITY | §2 |
| **NL-06** | Coordenadas en vista pública redondeadas a 2 decimales (~1.1 km) | ✅ GEO-01 implementado | §2 |
| **NL-07** | `currentLocation` omitido en estado `delivered` | ✅ GEO-03 implementado | §2 |
| **NL-08** | `currentLocation` omitido si `place = null` | ✅ GEO-04 implementado | §2 |
| **NL-09** | Nombre, teléfono, placa del operador ausentes de `PublicTrackingView` | ✅ Tabla §2.2 | §2 |
| **NL-10** | Datos fiscales (RFC, razón social, dirección exacta) ausentes de vista pública y chofer | ✅ Tabla §2.2 | §2 |
| **NL-11** | Error 404 idéntico para token inexistente, scope incorrecto o tenant incorrecto | ✅ Diseño §6.2 | §6 |
| **NL-12** | `PublicTimelineEvent.id` es ordinal (`evt-1`, `evt-2`), jamás el UUID de DB | ✅ Implementado en mock | §2 |
| **NL-13** | Notas internas de eventos nunca incluidas en `PublicTimelineEvent` | ✅ DTO explícito | §2 |
| **NL-14** | Vista del chofer (`DriverView`) no expone datos fiscales, montos ni ID internos | ✅ Tabla §2.2 | §2 |
| **NL-15** | Rate limiting activo antes de cualquier consulta a DB | ✅ Diseño §4.1 | §4 |
| **NL-16** | Respuesta scope-blind: mismo error 404 sin importar si el token existe pero tiene scope incorrecto | ✅ Diseño §6.1 | §6 |
| **NL-17** | IPs de acceso almacenadas como hash con salt diario (no en texto plano) | ✅ Diseño §5 / TRACKING_SECURITY §4.2 | §5 |
| **NL-18** | `<meta name="robots" content="noindex, nofollow">` en `/t/:token` y `/driver/:token` | 🔲 Pendiente implementación | §4 |
| **NL-19** | Headers CORS restrictivos en endpoints `/api/track/` (solo dominios propios) | 🔲 Pendiente — Edge Function config | §6 |
| **NL-20** | Eventos `incident.note` no expuestos en `PublicTrackingView` | ✅ DTO explícito, solo visible internamente | §2 |

**Leyenda:** ✅ = Confirmado en diseño o implementación mock · 🔲 = Pendiente de implementar en backend real

---

## 8. Consideraciones para Implementación en Supabase

### 8.1 Flujo recomendado con Edge Functions

```
Browser (chofer)
    ↓  POST /functions/v1/driver-event
Edge Function (Deno)
    ├── Valida JWT de Supabase (anon key del chofer)
    ├── sha256(driverToken) → lookup en tracking_tokens
    ├── Aplica validaciones §6.2 (rate limit, cooldown, dedup)
    ├── Llama reverse geocoding interno (si coordenadas presentes)
    ├── INSERT en tracking_events (con service_role key, bypassing RLS)
    └── Retorna response
```

### 8.2 RLS recomendada para `tracking_tokens`

```sql
-- Nadie puede leer tokens directamente vía anon
ALTER TABLE tracking_tokens ENABLE ROW LEVEL SECURITY;
-- Solo service_role (Edge Functions) puede leer/escribir
-- No hay policy permisiva para anon/authenticated
```

### 8.3 RLS recomendada para `tracking_events`

```sql
-- Solo service_role puede insertar (desde Edge Function)
-- usuarios internos (con claim is_internal = true) pueden leer los de su tenant
CREATE POLICY "ops internos pueden leer eventos de su tenant"
    ON tracking_events FOR SELECT
    TO authenticated
    USING (tenant_id = (SELECT tenant_id FROM users WHERE id = auth.uid()));
```

---

## 9. Resumen Ejecutivo

| Decisión | Valor |
|----------|-------|
| **Modelo de token** | Tokens **independientes** (UUID v4, sin derivación matemática) |
| **publicToken TTL** | 7 días (max 30), soft-expired +48h, hard-expired +48h |
| **driverToken TTL** | 48 horas, expira al confirmar `delivered` |
| **Revocación** | Inmediata y síncrona (lookup en DB por hash). Irreversible. |
| **Rotación** | Independiente por tipo. Cambiar chofer no invalida link del cliente. |
| **Anti-abuso** | Rate limit + máx 15 eventos `in_transit`, cooldown 30 min, idempotency por `clientTimestamp` |
| **Offline expirado** | El evento se descarta. No se acepta escritura con token revocado/expirado. |
| **Almacenamiento** | Solo `token_hash` (SHA-256). Token literal nunca persiste en DB ni logs. |
| **No-leak** | 20 controles verificados (18 confirmados, 2 pendientes de backend) |

