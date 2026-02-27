# Esquema Seguro de Tokens para Tracking
> Versión: 1.0 · Fecha: 2026-02-23 · Estado: **BORRADOR APROBADO**
> Módulo: OPS_TRACK · Dependencias: TRACKING_SECURITY.md, TRACKING_BACKEND_BLUEPRINT.md, DRIVER_MINIWEB_SPEC.md

---

## 1. Decisión Recomendada: Tokens Completamente Independientes

### ¿Tokens derivados o independientes?

| Opción | Descripción | Veredicto |
|--------|-------------|-----------|
| **A: Derivados** | `driver_token = HMAC(public_token, secret_key + scope)` | ❌ Rechazada |
| **B: Independientes** | Cada token es un `uuid_v4` generado por separado sin relación matemática | ✅ **Adoptada** |
| **C: JWT con scopes** | Un JWT firmado con claims `{ orderId, scope, exp }` | ⚠️ Reservada para v2 |

**Justificación de rechazar tokens derivados:**
- Si el `secret_key` se compromete, todos los tokens derivados quedan expuestos simultáneamente.
- Si el `public_token` se filtra, un atacante podría intentar derivar el `driver_token` si conoce el algoritmo.
- Complejidad innecesaria en v1. La separación total es más auditable.

**Justificación de tokens independientes:**
- Compromiso de uno no implica compromiso del otro. Aislamiento total.
- Revocación granular: revocar el token público no afecta al chofer y viceversa.
- Simplicidad: lookup `O(1)` por UUID indexado, sin criptografía adicional en el hot path.
- Compatible con cualquier base de datos relacional sin extensiones especiales.

---

## 2. Definición de Cada Token

### 2.1 Token Público (`public_token`) — `/t/:token`

| Propiedad | Valor |
|-----------|-------|
| **Formato** | UUID v4 — `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` |
| **Entropía** | 122 bits (CSPRNG) |
| **Generación** | Backend, `crypto.randomUUID()` al crear el link público |
| **Scope** | `public:read` |
| **Operaciones permitidas** | Solo `GET /api/track/:token` → `PublicTrackingView` |
| **TTL por defecto** | 7 días desde creación (configurable hasta 30 días) |
| **TTL post-entrega** | `delivered_at + 48h` → soft_expired → `+ 48h` → hard_expired |
| **Revocación** | Manual por `ops_coordinator` / `ops_director`. Irreversible. |
| **Compartible con** | Cliente final, cualquier persona |

### 2.2 Token Chofer (`driver_token`) — `/d/:token`

| Propiedad | Valor |
|-----------|-------|
| **Formato** | UUID v4 — `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` |
| **Entropía** | 122 bits (CSPRNG) |
| **Generación** | Backend, `crypto.randomUUID()` al asignar chofer a la operación |
| **Scope** | `driver:write` |
| **Operaciones permitidas** | `GET /api/driver/:token` (su DriverView) + `POST /api/driver/event` |
| **TTL por defecto** | ETA estimada de entrega `+ 24h` |
| **TTL máximo** | 7 días (operaciones internacionales largas) |
| **TTL post-entrega** | `delivered_at + 2h` → expirado automáticamente |
| **Revocación** | Manual por ops, O automática al rotar (nuevo chofer asignado) |
| **Compartible con** | Solo el chofer asignado, vía SMS/WhatsApp interno |

---

## 3. Permisos por Scope

### Matriz de Acceso

| Operación | `public:read` | `driver:write` | `ops:admin` (autenticado) |
|-----------|:---:|:---:|:---:|
| `GET /api/track/:token` → `PublicTrackingView` | ✅ | ❌ | ✅ |
| `GET /api/driver/:token` → `DriverView` | ❌ | ✅ | ✅ |
| `POST /api/driver/event` → crear `TrackingEvent` | ❌ | ✅ | ✅ |
| `POST /api/track/:token/revoke` | ❌ | ❌ | ✅ |
| `POST /api/driver/:token/revoke` | ❌ | ❌ | ✅ |
| `GET /api/orders/:id/tracking` (vista interna) | ❌ | ❌ | ✅ |

### Restricciones del Scope `driver:write`

El token del chofer NO puede:
- Crear eventos para una `order_id` distinta a la asociada a su `driver_token`.
- Crear más de 20 eventos de tipo `in_transit` por día (DEDUP-04).
- Leer datos de otros pedidos o choferes.
- Revocar su propio token ni el token público.
- Acceder a coordenadas exactas de otros eventos.

### Qué ve cada actor

| Dato | Público (`/t/`) | Chofer (`/d/`) | Operador (ERP) |
|------|:---:|:---:|:---:|
| `orderRef` (ej: ROT-24-001) | ✅ | ✅ | ✅ |
| `route` (origen → destino) | ✅ | ✅ | ✅ |
| `currentStatus` | ✅ | ✅ | ✅ |
| `eta` | ✅ | ✅ | ✅ |
| `events[]` (timeline) | ✅ Completo (sanitizado) | ✅ Últimos 3 | ✅ Completo + GPS exacto |
| `currentLocation` (redondeada ±1.1km) | ✅ | ❌ | ✅ Exacta |
| Primer nombre del cliente | ❌ | ✅ | ✅ |
| Ciudad de destino | ❌ | ✅ Ciudad + colonia | ✅ Dirección completa |
| Teléfono del cliente | ❌ | ❌ | ✅ |
| UUIDs internos | ❌ | ❌ | ✅ |
| Datos fiscales | ❌ | ❌ | ✅ |

---

## 4. Esquema de Datos Mínimo

### Opción: Una tabla unificada `tracking_tokens` con `scope`

En lugar de dos tablas separadas (`tracking_links` + `driver_links`), se propone una tabla única con un campo `scope` que determina los permisos. Esto simplifica el ciclo de vida, la auditoría y las consultas de revocación por orden.

```
TABLE: tracking_tokens
```

| Columna | Tipo | Restricciones | Descripción |
|---------|------|---------------|-------------|
| `id` | `uuid` | PK, `gen_random_uuid()` | ID interno. Nunca expuesto. |
| `tenant_id` | `uuid` | NOT NULL, FK → `tenants.id` | Aislamiento multi-tenant. |
| `order_id` | `uuid` | NOT NULL, FK → `orders.id` | Operación asociada. |
| `token` | `uuid` | NOT NULL, UNIQUE | El UUID opaco que va en la URL. |
| `scope` | `text` | NOT NULL, CHECK IN (`'public:read'`, `'driver:write'`) | Define los permisos del token. |
| `driver_name` | `text` | NULLABLE | Solo relevante si `scope = 'driver:write'`. |
| `state` | `text` | NOT NULL, CHECK IN (`'active'`, `'soft_expired'`, `'hard_expired'`, `'expired'`, `'revoked'`) | Estado del ciclo de vida. |
| `expires_at` | `timestamptz` | NOT NULL | Expiración dura. |
| `revoked_at` | `timestamptz` | NULLABLE | Fecha de revocación manual. |
| `revoked_by` | `uuid` | NULLABLE, FK → `profiles.id` | Actor que revocó (auditoría). |
| `created_by` | `uuid` | NOT NULL, FK → `profiles.id` | Quién generó el token. |
| `created_at` | `timestamptz` | NOT NULL, default `now()` | — |
| `last_used_at` | `timestamptz` | NULLABLE | Última actividad (fire-and-forget). |

**Índices:**
- `UNIQUE INDEX ON (token)` — lookup sin scan, O(1).
- `INDEX ON (order_id, scope)` — revocar todos los tokens de una orden o de un scope específico.
- `INDEX ON (tenant_id, state, scope)` — listar tokens activos por tenant y tipo.

**Constraints de unicidad de token activo:**
```
Solo puede existir UN token con scope='public:read' y state IN ('active', 'soft_expired') por order_id.
Solo puede existir UN token con scope='driver:write' y state = 'active' por order_id.

→ Implementar vía trigger o lógica de servicio al momento de crear un nuevo token:
  1. Marcar el anterior como revoked (state = 'revoked', revoked_by = 'system:rotation').
  2. Insertar el nuevo.
  Ambas operaciones en la misma transacción (SERIALIZABLE o FOR UPDATE).
```

---

## 5. Flujos de Ciclo de Vida

### 5.1 Ciclo de vida del `public_token`

```
[Creación]
  Operador crea el link público en ERP
  → INSERT tracking_tokens (scope='public:read', state='active', expires_at=now+7d)
  → Si existía uno activo antes: UPDATE state='revoked', revoked_by='system:rotation'
  → Se envía URL /t/:token al cliente vía WhatsApp/SMS

[Uso]
  GET /api/track/:token
  → Lookup por token → verificar scope='public:read' y state no revocado/expirado
  → Retorna PublicTrackingView sanitizado
  → fire-and-forget: UPDATE last_used_at=now()

[Soft Expiry]
  expires_at < now()  AND  expires_at > now() - 48h
  → Retorna PublicTrackingView + header X-Link-Status: soft_expired
  → Banner en UI cliente: "Este seguimiento puede no estar actualizado"
  → UPDATE state='soft_expired' (lazy, en el mismo request)

[Hard Expiry]
  expires_at < now() - 48h  OR  state='hard_expired'
  → HTTP 410 Gone
  → UPDATE state='hard_expired' (lazy)
  → UI cliente: pantalla de error "Enlace Expirado"

[Post-entrega]
  order.delivered_at IS NOT NULL
  → expires_at se recalcula a: MIN(expires_at, delivered_at + 48h)
  → Soft → Hard sigue la misma lógica

[Revocación manual]
  Operador presiona "Revocar" en ERP
  → UPDATE state='revoked', revoked_at=now(), revoked_by=<user_id>
  → HTTP 410 en el próximo acceso
  → Irreversible: no existe endpoint para re-activar
```

### 5.2 Ciclo de vida del `driver_token`

```
[Creación]
  Operador asigna chofer a la operación
  → INSERT tracking_tokens (scope='driver:write', state='active', expires_at=eta+24h, driver_name=...)
  → Si existía token de chofer activo: UPDATE state='revoked', revoked_by='system:rotation'
  → Se envía URL /d/:token al chofer vía WhatsApp

[Uso — lectura]
  GET /api/driver/:token
  → Lookup por token → verificar scope='driver:write' y state='active'
  → Retorna DriverView (con datos sensibles limitados)

[Uso — escritura]
  POST /api/driver/event
  → Lookup por token → verificar scope='driver:write' y state='active'
  → Verificar que event.order_id === token.order_id (no puede escribir en otros pedidos)
  → Aplicar anti-ruido (DEDUP-01..04)
  → Insertar TrackingEvent
  → Actualizar orders.current_status si corresponde
  → UPDATE last_used_at=now()

[Expiración post-entrega]
  order.delivered_at IS NOT NULL
  → expires_at = NOW() + 2h (gracia para correcciones del chofer)
  → Al cumplirse: state='expired', HTTP 410

[Expiración por tiempo]
  expires_at < now()
  → state='expired', HTTP 410
  → UI chofer: "Tu acceso a esta operación ha terminado"

[Revocación manual — cambio de chofer]
  Operador reasigna operación a nuevo chofer
  → UPDATE viejo_token: state='revoked', revoked_by=<user_id>, revoked_at=now()
  → INSERT nuevo_token con nuevo uuid y driver_name
  → Sistema de revocación atómica en transacción

[Revocación de emergencia]
  Chofer pierde el teléfono / seguridad comprometida
  → Ops revoca manualmente desde ERP
  → HTTP 410 al próximo intento de acceso
```

---

## 6. Validación del Scope en el Endpoint

### Pseudocódigo del Guard de Scope

```
function requireScope(requiredScope: 'public:read' | 'driver:write'):

  tokenValue = extract from URL param (:token)

  row = SELECT * FROM tracking_tokens WHERE token = tokenValue LIMIT 1
  if NOT FOUND: return 404

  if row.state IN ('revoked', 'hard_expired', 'expired'): return 410

  if row.expires_at < now() - 48h:
    lazy_update(row.id, state='hard_expired')
    return 410

  if row.scope ≠ requiredScope:
    return 403 { error: 'wrong_scope' }
    // Nota: nunca revelar que el token existe con otro scope (evitar oracle)
    // Alternativa más segura: return 404 (si se quiere scope-blind)

  // Pasar row al handler con order_id resuelto
  return { orderId: row.order_id, driverName: row.driver_name }
```

> **Decisión de seguridad:** Cuando un `driver_token` se presenta en `/api/track/` (scope incorrecto), se devuelve `404` (no `403`). Esto evita que un atacante que consiguió un driver_token sepa que ese token existe con otro scope — principio de *scope blind response*.

---

## 7. Consideraciones de Seguridad Adicionales

| Riesgo | Mitigación |
|--------|------------|
| Token filtrado en logs | Nunca loguear el token en texto plano. LogID = hash SHA-256 truncado (primeros 8 chars). |
| Token en caché de CDN | `Cache-Control: private` para endpoints de driver. `public` solo para `/api/track/`. |
| Fuerza bruta de UUIDs | Rate limiting por IP (60 req/min). UUID v4 = 2^122 espacio → enumeración impráctica. |
| IDOR entre operaciones | El guard de scope verifica `token.order_id` antes de cada escritura. |
| Replay de eventos | Idempotencia por `event_type` + ventana de 60s. Segundo request retorna 200 sin duplicar. |
| Compromiso del token del chofer | Revocación manual en < 1 min desde el ERP. Token anterior invalidado en toda la flota de servidores. |
| URLs en historial del navegador | Sin medida técnica posible en v1. Recomendación operativa: el chofer borra el historial al terminar. |

---

## 8. Checklist de Implementación

- [ ] Crear migración: tabla `tracking_tokens` con columna `scope` y constraints
- [ ] Implementar función `rpc_create_tracking_token(order_id, scope, expires_at, driver_name?)` con revocación atómica del anterior
- [ ] Implementar guard `requireScope` reutilizable entre Edge Functions
- [ ] Configurar `Cache-Control: private` para `/api/driver/*`
- [ ] Agregar log de auditoría para `TOKEN_CREATED`, `TOKEN_REVOKED`, `TOKEN_EXPIRED` (con SHA-256 del token, nunca el token en claro)
- [ ] Migrar `tracking_links` existente a `tracking_tokens` con `scope='public:read'`
- [ ] Migrar `driver_links` a `tracking_tokens` con `scope='driver:write'`
- [ ] Añadir test de scope-blind: confirmar que driver_token en endpoint público devuelve 404, no 403

---

*Documento de especificación. Sin código SQL ni de producción implementado.*
