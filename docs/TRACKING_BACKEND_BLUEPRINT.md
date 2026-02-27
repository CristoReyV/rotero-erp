# TRACKING BACKEND BLUEPRINT
> Versión: 1.0 · Fecha: 2026-02-22 · Estado: **BORRADOR APROBADO**
> Proyecto: ROTERO ERP · Módulo: Tracking Público `/t/:token`

---

## 1. Contrato del Endpoint

### `GET /api/track/:token`

> Devuelve la vista pública sanitizada de una operación logística identificada por un token UUID v4.

#### Parámetros

| Param   | Tipo   | Requerido | Descripción                      |
|---------|--------|-----------|----------------------------------|
| `token` | `uuid` | ✅         | Token público del link de rastreo |

#### Respuestas

| Código HTTP | Condición                          | Cuerpo                              |
|-------------|-------------------------------------|--------------------------------------|
| `200 OK`    | Token válido y activo               | `PublicTrackingView`                 |
| `200 OK`    | Token `soft_expired` (< 48h vencido)| `PublicTrackingView` + header `X-Link-Status: soft_expired` |
| `404 Not Found` | Token no existe en BD          | `{ error: "not_found" }`            |
| `410 Gone`  | Token `hard_expired` o `revoked`   | `{ error: "expired" \| "revoked" }` |
| `429 Too Many Requests` | Rate limit excedido    | `{ error: "rate_limited", retryAfter: number }` |

#### Response body: `PublicTrackingView`

```typescript
interface PublicTrackingView {
  orderRef: string;           // "ROT-24-001"  ← NOT the internal UUID
  route: string;              // "Laredo → Monterrey"
  currentStatus: string;      // "En Tránsito"
  eta?: string;               // "Hoy, 14:00"  ← omitted when delivered
  currentLocation?: {         // GEO-01: rounded to 2 decimal places (~1.1 km)
    lat: number;              // GEO-03: omitted when status = 'delivered'
    lng: number;              // GEO-04: omitted when geocoding failed
  };
  events: PublicTimelineEvent[];
}

interface PublicTimelineEvent {
  id: string;                 // "evt-1"  ← ordinal, NOT db UUID
  title: string;              // "En camino"
  subtitle: string;           // "Sabinas Hidalgo, N.L. · 11:18 AM"
  timestamp: string;          // ISO 8601
  status: 'done' | 'current' | 'future';
  icon: string;               // "truck" | "map-pin" | "flag"
}
```

#### Campos explícitamente **PROHIBIDOS** en la respuesta (NO-LEAK)

| Campo prohibido           | Razón                     |
|---------------------------|---------------------------|
| `tracking_links.id`       | UUID interno de la relación |
| `orders.id`               | UUID interno de la orden  |
| `orders.tenant_id`        | Fuga de tenant            |
| `orders.operator_id`      | PII del operador          |
| `clients.name / rfc / phone` | PII del cliente        |
| `tracking_events.id`      | UUID interno del evento   |
| `tracking_events.location` | Coordenadas exactas       |
| Dirección de entrega completa | Ubicación privada      |
| Datos fiscales (RFC, CFDI) | Confidencialidad fiscal  |

#### Headers de respuesta relevantes

```
Cache-Control: public, max-age=60, stale-while-revalidate=30
X-Link-Status: active | soft_expired          ← solo en 200s
X-RateLimit-Limit: 120
X-RateLimit-Remaining: 119
X-RateLimit-Reset: <unix-timestamp>
```

---

## 2. Tablas Mínimas

### 2.1 `tracking_links`

Almacena los tokens públicos y su ciclo de vida. **Una row por link.**

| Columna         | Tipo           | Restricciones                    | Descripción                                |
|-----------------|----------------|----------------------------------|--------------------------------------------|
| `id`            | `uuid`         | PK, default `gen_random_uuid()`  | Identificador interno                      |
| `tenant_id`     | `uuid`         | NOT NULL, FK → `tenants.id`      | Aislamiento multi-tenant                   |
| `order_id`      | `uuid`         | NOT NULL, FK → `orders.id`       | Orden asociada                             |
| `token`         | `uuid`         | NOT NULL, UNIQUE, default `gen_random_uuid()` | Token público                  |
| `state`         | `text`         | CHECK IN ('active','soft_expired','hard_expired','revoked') | Estado de ciclo de vida |
| `expires_at`    | `timestamptz`  | NOT NULL                         | Límite de expiración dura (default +7 días)|
| `revoked_at`    | `timestamptz`  | NULLABLE                         | Fecha de revocación manual                 |
| `revoked_by`    | `uuid`         | NULLABLE, FK → `profiles.id`     | Actor que revocó                           |
| `created_at`    | `timestamptz`  | NOT NULL, default `now()`        |                                            |
| `last_accessed_at` | `timestamptz` | NULLABLE                       | Última vez leído (para analítica)          |

**Índices propuestos:**
- `UNIQUE INDEX` en `(token)` — lookup O(1) sin escaneo.
- `INDEX` en `(order_id)` — revocación por orden.
- `INDEX` en `(tenant_id, state)` — listar activos por tenant.

**Constraint de unicidad de link activo por orden:**
- Solo un registro con `state = 'active'` o `'soft_expired'` debe existir por `order_id`.
- Implementar vía trigger o función de revocación automática al crear uno nuevo.

---

### 2.2 `tracking_events`

Almacena el historial de posiciones GPS y eventos de la operación. Append-only.

| Columna         | Tipo           | Restricciones                    | Descripción                                |
|-----------------|----------------|----------------------------------|--------------------------------------------|
| `id`            | `uuid`         | PK, default `gen_random_uuid()`  |                                            |
| `tenant_id`     | `uuid`         | NOT NULL, FK → `tenants.id`      |                                            |
| `order_id`      | `uuid`         | NOT NULL, FK → `orders.id`       |                                            |
| `event_type`    | `text`         | NOT NULL                         | `departure`, `in_transit`, `delivered`, `checkpoint`, `delay` |
| `location_lat`  | `numeric(9,6)` | NULLABLE                         | Latitud exacta (precisión completa internamente) |
| `location_lng`  | `numeric(9,6)` | NULLABLE                         | Longitud exacta                            |
| `municipality`  | `text`         | NULLABLE                         | Resultado de geocodificación inversa       |
| `state_name`    | `text`         | NULLABLE                         | Estado/provincia                           |
| `country_code`  | `char(2)`      | NULLABLE, default `'MX'`         |                                            |
| `source`        | `text`         | CHECK IN ('gps','system','manual') |                                          |
| `recorded_at`   | `timestamptz`  | NOT NULL, default `now()`        |                                            |

**Índices propuestos:**
- `INDEX` en `(order_id, recorded_at DESC)` — consulta de historial paginado.
- `INDEX` en `(tenant_id, order_id)` — aislamiento multi-tenant.

> **Nota de privacidad:** Las coordenadas exactas se almacenan internamente con 6 decimales. El redondeo a 2 decimales se aplica **en el endpoint**, no en la tabla.

---

## 3. Lógica del Endpoint

Flujo de ejecución en **pseudocódigo** preciso. Implementable como función RPC en Supabase o como handler de Edge Function / API Route.

```
GET /api/track/:token

[1] LOOKUP
  SELECT tl.*, o.ref, o.current_status, o.eta, o.delivered_at
  FROM tracking_links tl
  JOIN orders o ON o.id = tl.order_id
  WHERE tl.token = :token
  LIMIT 1

  → if NOT FOUND: return 404 { error: "not_found" }

[2] GATE: REVOCADO
  if tl.state = 'revoked':
    return 410 { error: "revoked" }

[3] GATE: EXPIRACIÓN DURA
  is_hard_expired = (tl.expires_at < NOW() - INTERVAL '48 hours')
  OR (tl.state = 'hard_expired')

  if is_hard_expired:
    UPDATE tracking_links SET state='hard_expired' WHERE id=tl.id  ← lazy update
    return 410 { error: "expired" }

[4] DETECTAR SOFT EXPIRY
  is_soft_expired = (tl.expires_at < NOW()) AND NOT is_hard_expired
  → set response header: X-Link-Status: soft_expired (or active)

[5] FETCH EVENTS (para timeline público)
  SELECT municipality, state_name, event_type, recorded_at
  FROM tracking_events
  WHERE order_id = tl.order_id
    AND event_type IN ('departure','in_transit','checkpoint','delivered')
  ORDER BY recorded_at ASC
  LIMIT 50  ← hard cap anti-scraping

[6] FETCH LAST LOCATION (para mapa)
  SELECT location_lat, location_lng
  FROM tracking_events
  WHERE order_id = tl.order_id
    AND location_lat IS NOT NULL
    AND location_lng IS NOT NULL
  ORDER BY recorded_at DESC
  LIMIT 1

[7] SANITIZAR RESPUESTA (GEO-01..GEO-04)
  current_location = null

  if last_event EXISTS:
    if o.delivered_at IS NULL:  ← GEO-03: omitir en entregados
      current_location = {
        lat: ROUND(last_event.location_lat, 2),   ← GEO-01: 2 decimales
        lng: ROUND(last_event.location_lng, 2)
      }

[8] CONSTRUIR PublicTrackingView
  → mapear events a PublicTimelineEvent[]
      id: 'evt-' || rownum  ← NO la UUID interna
      title: derivado de event_type
      subtitle: municipality + ', ' + state_name + ' · ' + hora_local
      icon: derivado de event_type

  → ensamblar PublicTrackingView
      orderRef: o.ref          ← NOT o.id
      route: o.route_label
      currentStatus: o.current_status
      eta: o.eta (omitir si delivered)
      currentLocation: calculated above
      events: mapped events

[9] ACTUALIZAR last_accessed_at (fire-and-forget, no bloquear respuesta)
  UPDATE tracking_links SET last_accessed_at = NOW() WHERE id = tl.id

[10] RETURN 200 con PublicTrackingView
```

---

## 4. Rate Limiting

Implementar en el layer de middleware (Edge Function, API Gateway, o Netlify Edge Middleware).

| Nivel              | Límite           | Ventana  | Acción al superar        |
|--------------------|------------------|----------|--------------------------|
| Por IP             | 60 req/min       | 1 minuto | `429` + Retry-After      |
| Por token          | 120 req/min      | 1 minuto | `429` + Retry-After      |
| Global (todos)     | 1 000 req/min    | 1 minuto | Circuit-breaker temporal |
| Anti-scraping      | >20 tokens/IP/día | 24h     | Progressive delay + CAPTCHA fallback |

**Algoritmo recomendado:** Sliding Window Counter sobre Redis / Upstash.

---

## 5. Caching

El endpoint es **público y sin cookies**, por lo que es seguro agregar headers de caché para CDN.

| Recurso                  | `Cache-Control`                                     | TTL efectivo |
|--------------------------|-----------------------------------------------------|--------------|
| Respuesta JSON activa    | `public, max-age=60, stale-while-revalidate=30`     | ~90s         |
| Respuesta JSON soft_expired | `public, max-age=10`                             | 10s          |
| Error 404/410            | `public, max-age=3600`                              | 1h           |
| Tiles de mapa (Carto/OSM)| `public, max-age=604800`                            | 7 días       |

**CDN propuesto:** Netlify Edge Cache o Cloudflare. Variación por header opcional:
- `Vary: Accept-Encoding`
- **Nunca** `Vary: Cookie` (rompería el caché público).

---

## 6. Reglas RLS (Supabase)

> Asumiendo que este endpoint se implementa como un Supabase Edge Function que usa el `service_role` key **solo internamente**, y el cliente público llama al Edge Function, no directamente a Supabase.

Si en algún caso se expone la tabla vía PostgREST, las políticas RLS serían:

### `tracking_links`

| Operación | Actor             | Condición                                         |
|-----------|-------------------|---------------------------------------------------|
| `SELECT`  | Anónimo (público) | `token = :token_param` · estado NO en `('revoked','hard_expired')` |
| `SELECT`  | Authenticated     | `tenant_id = auth.jwt().tenant_id`                |
| `INSERT`  | Authenticated ops | `tenant_id = auth.jwt().tenant_id` + rol `operator` |
| `UPDATE`  | Authenticated ops | Solo campos `state`, `revoked_at`, `revoked_by`, `last_accessed_at` |
| `DELETE`  | Nunca             | Revocación es lógica (state='revoked'), no borrado físico |

### `tracking_events`

| Operación | Actor             | Condición                                         |
|-----------|-------------------|---------------------------------------------------|
| `SELECT`  | Anónimo (público) | Solo columnas: `municipality`, `state_name`, `event_type`, `recorded_at` — **NUNCA** `location_lat/lng` directamente |
| `SELECT`  | Authenticated     | `tenant_id = auth.jwt().tenant_id`                |
| `INSERT`  | Authenticated ops | `tenant_id = auth.jwt().tenant_id`                |
| `UPDATE`  | Nunca             | Append-only — inmutable una vez registrado        |
| `DELETE`  | Solo admin        | Auditoría + retención de datos                    |

> **Patrón recomendado:** Implementar el endpoint como una **Edge Function** con `service_role` key en lugar de exponer las tablas a anónimos vía RLS. La Edge Function aplica toda la lógica de sanitización antes de responder. Las RLS sirven como línea de defensa secundaria.

---

## 7. Función RPC propuesta (Supabase)

```
rpc_get_public_tracking(p_token uuid) → PublicTrackingView | error_code

Privados de ejecución:
- SECURITY DEFINER
- SET search_path = public, pg_catalog
- Ejecuta como el owner de la función, no como el rol del caller

Responsabilidades:
1. Lookup + gate de estado en una sola transacción READ COMMITTED
2. Redondeo de coordenadas (ROUND(col::numeric, 2))
3. Formateo de events a PublicTimelineEvent (row_number() como id, no uuid)
4. UPDATE lazy de last_accessed_at (en la misma tx o diferida)
5. Retornar NULL en campos prohibidos
```

> **Alternativa sin RPC:** Supabase Edge Function (TypeScript/Deno) que hace las queries al service-role. Más flexible para lógica de negocio compleja como deduplicación y rate limiting.

---

## 8. Checklist de Implementación

- [ ] Crear migración para tabla `tracking_links`
- [ ] Crear migración para tabla `tracking_events`
- [ ] Crear función `rpc_get_public_tracking` o Edge Function equivalente
- [ ] Implementar lógica de redondeo GEO-01 en la capa de salida
- [ ] Establecer rate limiting en middleware (Upstash Redis sugerido)
- [ ] Configurar headers de caché en CDN
- [ ] Definir y probar políticas RLS con `supabase test`
- [ ] Migrar mocks del frontend (`getMockPublicTracking`) a llamadas reales
- [ ] Añadir registro de auditoría: `LINK_VIEWED`, `LINK_REVOKED` con IP hasheada
- [ ] Configurar alertas de monitoreo para `429` y `410` frecuentes

---

*Documento generado como especificación de diseño. Sin código SQL ni de producción implementado.*
