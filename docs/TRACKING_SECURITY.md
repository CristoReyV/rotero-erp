# Hardening del Link Público de Tracking `/t/:token`

> **Módulo:** OPS_TRACK · **Tipo:** Decisión de seguridad (sin código)
> **Referencia:** TRACKING_MODULE.md §6, Arquitectura ERP §3

---

## 1. Token & Link Security

### 1.1 Formato del token

| Propiedad | Decisión | Justificación |
|-----------|----------|---------------|
| **Formato** | UUID v4 (RFC 4122) | 122 bits de entropía aleatoria. No secuencial, no predecible. |
| **Largo** | 36 caracteres (`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`) | Estándar universal, compatible con cualquier DB y URL. |
| **Generación** | `crypto.randomUUID()` (backend) | Usa CSPRNG del sistema operativo, no `Math.random()`. |
| **Almacenamiento** | Columna `token` con índice `UNIQUE` en `tracking_links` | Lookup O(1) por token. |
| **Sensibilidad** | Tratar como **capability token** (quien lo tiene, tiene acceso) | Similar a un link de Google Docs "anyone with the link". |

> **CAUTION:** El token **nunca** debe contener ni codificar: `orderId`, `tenantId`, `userId`, ni ningún dato interno. Es un handle opaco.

### 1.2 Expiración

| Regla | Valor | Comportamiento |
|-------|:-----:|----------------|
| **EXP-01** Soft-expiry | `expiresAt` + 0h | A partir de `expiresAt`, mostrar banner: _"Este seguimiento ha expirado. Los datos pueden no estar actualizados."_ pero **seguir mostrando** el último estado conocido (read-only). |
| **EXP-02** Hard-expiry | `expiresAt` + 48h | Después de 48h post-expiración, bloquear completamente. Responder HTTP 410 Gone: _"Este link de seguimiento ya no está disponible."_ |
| **EXP-03** Default TTL | **7 días** desde creación | Cubre ventana típica de operación terrestre MX (Laredo→CDMX ≈ 2 días + margen). |
| **EXP-04** Máximo configurable | **30 días** | Configurable por tenant. Evita links perpetuos olvidados. |
| **EXP-05** Post-entrega | `delivered_at` + 48h | Si la orden llega antes de la expiración, el link permanece visible 48h extra para que el cliente verifique la entrega, luego entra en hard-expiry. |

### 1.3 Revocación manual

| Regla | Descripción |
|-------|-------------|
| **REV-01** | Cualquier `ops_coordinator` u `ops_director` puede revocar un link activo. |
| **REV-02** | Revocación es **irreversible**. Se marca `revokedAt` + `revokedBy`. |
| **REV-03** | Un link revocado responde HTTP 403: _"Este enlace fue desactivado por el operador."_ |
| **REV-04** | La revocación queda en audit log con actor, timestamp e IP. |

### 1.4 Rotación de token

| Regla | Descripción |
|-------|-------------|
| **ROT-01** | Solo puede existir **un link activo** por orden (`is_active = true`). |
| **ROT-02** | Al regenerar, el token anterior pasa a `is_active = false`, `revokedAt = now()`, `revokedBy = 'system:rotation'`. |
| **ROT-03** | El nuevo token hereda el mismo `expiresAt` original, no se extiende. Para extender, el operador debe crear un link completamente nuevo. |

---

## 2. Data Leakage (NO-LEAK)

### 2.1 Campos PROHIBIDOS en la vista pública

| Categoría | Campos prohibidos | Riesgo si se filtra |
|-----------|-------------------|---------------------|
| **Identificadores** | `orderId` (DB), `tenantId`, `userId`, `operationId`, `trackingEventId` | Permite enumerar recursos backend |
| **Personal operador** | Nombre, teléfono, email, foto, placa del vehículo | Privacidad / seguridad física |
| **Fiscal** | RFC, razón social, dirección fiscal del remitente o destinatario | Fraude fiscal, suplantación |
| **Direcciones exactas** | Calle, número, colonia, código postal del origen/destino | Seguridad del almacén, robo dirigido |
| **Montos** | Valor declarado, costo de flete, cotización | Competencia, extorsión |
| **Coordenadas exactas** | `lat`/`lng` con más de 2 decimales | Ubica al operador/almacén con precisión < 100m |
| **Notas internas** | `TrackingEvent.note` (a menos que esté marcada como "pública") | Puede contener datos sensibles |
| **Metadatos técnicos** | IPs de servidores, API keys, versiones de software | Superficie de ataque |

### 2.2 DTO público permitido (`PublicTrackingView`)

| Campo | Tipo | Ejemplo | Fuente |
|-------|------|---------|--------|
| `orderRef` | `string` | `"ROT-24-001"` | Referencia externa (no el ID de DB) |
| `route` | `string` | `"Laredo → Monterrey"` | Solo nombres de ciudades destino |
| `currentStatus` | `string` | `"En Tránsito"` | Estado humanizado |
| `eta` | `string?` | `"Hoy, 14:00"` | Solo hora estimada, sin dirección |
| `currentLocation` | `GeoPoint?` | `{ lat: 25.67, lng: -100.31 }` | **Redondeado a 2 decimales** (ver §2.3) |
| `events[]` | `PublicTimelineEvent[]` | ver abajo | Máximo 12 eventos (VIS-01) |

**`PublicTimelineEvent`:**

| Campo | Tipo | Ejemplo |
|-------|------|---------|
| `id` | `string` | `"evt-3"` (ordinal, NO el ID de DB) |
| `title` | `string` | `"En camino"` |
| `subtitle` | `string` | `"Sabinas Hidalgo, Nuevo León · 11:18 AM"` |
| `timestamp` | `string` | `"11:18 AM"` (hora local del tenant) |
| `status` | `'done' \| 'current' \| 'future'` | `"current"` |
| `icon` | `string` | `"map-pin"` (nombre de ícono Lucide) |

### 2.3 Decisión: Coordenadas en el mapa público

| Opción | Privacidad | UX | **Decisión** |
|--------|:----------:|:--:|:------------:|
| lat/lng exacto (6 dec) | ❌ Localiza al operador con 11 cm | ✅ Excelente | Descartado |
| lat/lng redondeado a 2 dec (~1.1 km) | ✅ Solo zona general | ✅ Buena | **✅ Elegido** |
| Solo municipio (sin coordenadas) | ✅ Máxima | ❌ Mapa inservible | Descartado |

**Justificación:** 2 decimales ofrece ~1.1 km de imprecisión. El cliente ve en qué zona del municipio está el envío, pero no puede ubicar al operador ni al almacén con precisión. Es el balance correcto entre utilidad del mapa y privacidad operativa.

> **IMPORTANT:**
> - **GEO-01:** Todo `GeoPoint` expuesto en `PublicTrackingView.currentLocation` DEBE pasar por `Math.round(coord * 100) / 100` antes de salir del backend.
> - **GEO-02:** Los tiles del mapa (Carto/OSM) son públicos y no filtran nada del sistema.
> - **GEO-03:** Si la orden está en estado `delivered`, omitir `currentLocation` completamente (no revelar almacén de destino).
> - **GEO-04:** Si `place` es null (geocode falló), omitir `currentLocation` (no exponer coords sin contexto).

---

## 3. Rate Limiting (Producción)

### 3.1 Límites recomendados

| Nivel | Límite | Ventana | Respuesta al exceder |
|-------|:------:|:-------:|---------------------|
| **Por IP** | 60 requests | 1 minuto | HTTP 429 + header `Retry-After: 60` |
| **Por token** | 120 requests | 1 minuto | HTTP 429 (un token compartido en grupo de WhatsApp puede recibir ráfagas legítimas) |
| **Global** | 1000 req/s | — | Protección contra DDoS a nivel CDN/WAF |

### 3.2 Caching CDN

| Recurso | TTL cache | Justificación |
|---------|:---------:|---------------|
| HTML de `/t/:token` | **0** (no cachear) | El contenido es dinámico y personalizado por token |
| API response (RPC) | **60 segundos** (stale-while-revalidate) | Los eventos cambian cada ~30 min como máximo; 1 min de cache reduce carga al 98% |
| Tiles de mapa (OSM/Carto) | **7 días** | Son estáticos y servidos por CDN del proveedor |
| Assets (JS/CSS/fonts) | **1 año** (immutable, hash en filename) | Vite ya genera hashes en filenames |

### 3.3 Anti-scraping

| Estrategia | Implementación |
|------------|---------------|
| **Fingerprinting pasivo** | Registrar `User-Agent`, `Accept-Language`, patrones de frecuencia en logs |
| **Progressive delay** | Tras 3 requests consecutivos en < 5s desde misma IP, incrementar respuesta +500ms por hit |
| **CAPTCHA fallback** | Si una IP supera 200 req/hora al mismo token, mostrar CAPTCHA antes de servir datos |
| **No indexar** | `<meta name="robots" content="noindex, nofollow">` + `X-Robots-Tag: noindex` en response headers |
| **Honeypot tokens** | Crear tokens inválidos que simulan respuestas; cualquier acceso recurrente a estos = IP ban |

---

## 4. Auditoría y Compliance

### 4.1 Eventos de audit log (internos)

| Evento | Datos registrados | Actor |
|--------|-------------------|-------|
| **LINK_CREATED** | `orderId`, `token` (hash, no literal), `expiresAt`, `createdBy` | Usuario ERP |
| **LINK_SHARED** | `orderId`, `channel` (clipboard/whatsapp/qr), `sharedBy` | Usuario ERP |
| **LINK_REVOKED** | `orderId`, `revokedBy`, `reason?` | Usuario ERP |
| **LINK_ROTATED** | `orderId`, `oldTokenHash`, `newTokenHash`, `rotatedBy` | Usuario ERP / Sistema |
| **LINK_EXPIRED** | `orderId`, `expiresAt` | Sistema (cron/trigger) |

> **NOTE:** El token literal **nunca** se almacena en el audit log. Se guarda un hash SHA-256 truncado a 12 caracteres para correlación sin riesgo de replay.

### 4.2 Registro de accesos públicos (futuro backend)

| Campo | Tipo | Propósito |
|-------|------|-----------|
| `tokenHash` | `string` (SHA-256 truncado) | Correlación sin exponer token |
| `accessedAt` | `timestamp` | Patrón de uso |
| `ipHash` | `string` (SHA-256 de IP + salt diario) | Detectar scraping sin almacenar PII |
| `userAgent` | `string` (truncado a 200 chars) | Perfilado de dispositivos |
| `countryCode` | `string` | Geolocalización a nivel país (Cloudflare header) |

> **IMPORTANT:** **No almacenar IPs en texto plano.** Usar hash con salt rotativo diario para cumplir con principios de minimización de datos (LFPDPPP Art. 13).

---

## 5. Casos Borde

| # | Caso | Status HTTP | Mensaje al usuario | Acción del sistema |
|---|------|:-----------:|--------------------|--------------------|
| **CB-01** | Token inválido (no existe en DB) | **404** | _"Este enlace de seguimiento no existe."_ | Registrar intento + IP hash |
| **CB-02** | Token expirado (soft, < 48h) | **200** | Banner amarillo: _"Este seguimiento ha expirado. Los datos pueden no estar actualizados."_ | Mostrar último estado, datos read-only |
| **CB-03** | Token expirado (hard, > 48h) | **410 Gone** | _"Este enlace de seguimiento ya no está disponible."_ | No mostrar datos. Solo mensaje + branding |
| **CB-04** | Link revocado | **403** | _"Este enlace fue desactivado por el operador."_ | No mostrar datos. Solo mensaje + branding |
| **CB-05** | Sin ubicación (timeline vacío) | **200** | Mapa en estado "Esperando Ubicación" | Mostrar card con ETA y ruta, mapa vacío |
| **CB-06** | Geocoding falla | **200** | Timeline omite evento sin `place` (VIS-06). Mapa omite `currentLocation` (GEO-04) | Evento guardado con `place: null` internamente |
| **CB-07** | Rate limit excedido | **429** | _"Demasiadas solicitudes. Intenta de nuevo en un momento."_ | Header `Retry-After` |
| **CB-08** | Orden entregada | **200** | Timeline completo con todos los checks. Mapa sin marcador (GEO-03) | `currentLocation` omitido |
| **CB-09** | Token válido pero orden no tiene eventos aún | **200** | Solo card de ruta + ETA. Timeline vacío con mensaje: _"En espera del primer reporte de ubicación."_ | — |

---

## 6. Tabla: Permitido vs Prohibido

| Dato | Público `/t/:token` | Interno `/tracking` | Justificación |
|------|:-------------------:|:-------------------:|---------------|
| Referencia de orden (`ROT-24-001`) | ✅ | ✅ | Identificador externo, sin riesgo |
| Nombre de ruta (`Laredo → MTY`) | ✅ | ✅ | Solo ciudades genéricas |
| Status humanizado | ✅ | ✅ | — |
| ETA estimada | ✅ | ✅ | Solo hora, sin dirección |
| Timeline de municipios | ✅ | ✅ | Solo municipio + estado + hora |
| Coordenadas (2 dec, ~1.1 km) | ✅ | ✅ | Zona general, no posición exacta |
| Coordenadas exactas (6 dec) | ❌ | ✅ | Solo visible internamente |
| Nombre del operador | ❌ | ✅ | Privacidad |
| Teléfono del operador | ❌ | ✅ | Seguridad |
| Placas del vehículo | ❌ | ✅ | Seguridad |
| ID de orden (UUID DB) | ❌ | ✅ | Previene enumeración |
| Tenant ID | ❌ | ✅ | Aislamiento multi-tenant |
| Valor declarado / montos | ❌ | ✅ | Riesgo de extorsión |
| RFC / datos fiscales | ❌ | ✅ | Fraude fiscal |
| Dirección exacta (calle, #) | ❌ | ✅ | Seguridad de almacenes |
| Notas internas | ❌ | ✅ | Pueden contener datos sensibles |
| Link token (literal) | ❌ (solo en URL) | ✅ | Audit log usa hash |

---

## 7. Checklist de Implementación

> Archivos a modificar cuando se conecte el backend real. Sin cambios de UI.

| # | Archivo | Cambio necesario |
|---|---------|-----------------|
| 1 | `src/types/tracking.ts` | Ya tiene `TrackingLink` con `revokedAt`, `revokedBy`. Añadir campo `tokenHash` para audit. |
| 2 | `src/constants/states.ts` | Añadir `TRACKING_LINK_STATES: { active, expired_soft, expired_hard, revoked }` con labels en español. |
| 3 | `src/services/trackingLink.service.ts` | **[NEW]** — Funciones: `createLink()`, `revokeLink()`, `rotateLink()`, `validateToken()`, `checkExpiration()`. |
| 4 | `src/pages/TrackingPublicPage.tsx` | Añadir lógica de estados de error (CB-01 a CB-09): banners de expiración, pantallas de error elegantes. |
| 5 | Supabase Migration | Tabla `tracking_links` con: `token` (UNIQUE), `is_active`, `expires_at`, `revoked_at`, `revoked_by`, `last_accessed_at`. Índice parcial UNIQUE en `(order_id) WHERE is_active = true`. |
| 6 | Supabase RLS | Policy `anon` SELECT solo si `is_active = true AND expires_at > now() - interval '48 hours' AND token = $1`. |
| 7 | Supabase RPC `rpc_get_public_tracking` | SECURITY DEFINER. Valida token, aplica soft/hard expiry, actualiza `last_accessed_at`, redondea coordenadas, retorna `PublicTrackingView`. |
| 8 | Edge Function o Middleware | Rate limiting por IP + token. Headers `X-Robots-Tag: noindex`. |
| 9 | `src/pages/TrackingPublicPage.tsx` | `<meta name="robots" content="noindex, nofollow">` en el `<head>`. |
