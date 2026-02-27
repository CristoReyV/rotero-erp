# Módulo de Tracking (Opción A) – Documentación Técnica

> **Módulo:** OPS_TRACK (Operaciones → Tracking & GPS)
> **Fecha de implementación:** 2026-02-22
> **Estado actual:** Vista simulada (Mocks + UI completa). Listo para integración con backend.

---

## 1. Descripción Funcional
El módulo de Tracking Opción A está diseñado para gestionar el seguimiento en tiempo real de las órdenes logísticas basándose en eventos geolocalizados ("En Camino" por municipio).

Consta de dos vistas principales:
1. **`/tracking` (Uso Interno):** Dashboard para operadores y coordinadores logísticos. Permite la visualización de todos los embarques activos, sus ubicaciones más recientes y el acceso a los enlaces públicos (tokens uuid) para compartirlos con los clientes.
2. **`/t/:token` (Vista Pública):** Pantalla estática "solo lectura" enfocada 100% en la experiencia del cliente (B2B/B2C). Muestra un diseño minimalista, sin distracciones operativas, centrada puramente en la bitácora cronológica con animaciones de radar / pulso CSS. Asegura _Zero Leakage_ de datos internos y sensibles.

## 2. Modelos de Datos en TypeScript (`src/types/tracking.ts`)

La arquitectura de datos de tracking se centra en 3 entidades primarias:

- **`TrackingEvent`:** Base de todo evento reportado (manual, automático por GPS, del sistema). Un `TrackingEvent` alimenta la tabla interna.
- **`TrackingLink`:** Configuración de seguridad y expiración de los hipervínculos compartibles. Permite forzar revocaciones de visualización en vivo.
- **`PublicTrackingView` y `PublicTimelineEvent`:** Los DTOs (Data Transfer Objects) sanitizados. Todo lo que cruza hacia la ruta pública `/t/:token` debe estar estructurado en este formato para omitir IDs de bases de datos, perfiles de operador y lat/lng en raw data.

## 3. Mock Data & Escenarios (`src/mocks/tracking.mock.ts`)

La estructura actual funciona con la data mockeada lista para simular el comportamiento *event-driven*. 

Para cambiar los estados visuales en el timeline de la TrackingPublicPage durante la fase de desarrollo, basta con modificar el atributo `status` en los objetos de la constante `MOCK_PUBLIC_TIMELINE_EVENTS`:
- `done`: Eventos ya ocurridos. Renderizan con palomita sólida.
- `current`: Último evento válido detectado. Genera una animación "ping" verde y etiqueta de "AHORA".
- `future`: Eventos esperados o programados. Renderizan de color tenue sin llenar.

## 4. Guía de Integración Backend (Supabase) a futuro

Cuando el backend Supabase esté disponible, el flujo de cambio deberá ser el siguiente:

1. **Tablas Base:**
   - Crear tabla `tracking_links` (auth: anónimo permitido vía UUID match).
   - Crear tabla `tracking_events` (auth: protegida para la API de reverse geocoding corporativa).

2. **Endpoints (RPC / API Route):**
   - Una API o RPC que resuelva `GET /api/track/:token`. No debe devolver todas las filas de la base de datos, sino exclusivamente un objeto casteado como `PublicTrackingView`.
   - Modificar `TrackingPublicPage` para que lance una petición SWR/React Query usando el `token` recogido de `useParams()`.

3. **Reverse Geocoding (El core de Opción A):**
   - Implementar un worker remoto o API route (Netlify / Supabase Edge Functions) que consuma un API de mapas (Nominatim, Google Geocoding).
   - Este *geocoder* recibirá los lat/lng puros de las apps de conductores, verificará si el `municipality` y `state` corresponden a los del evento anterior.
   - Si cambió, y el `cooldown` de 15 minutos ha sido superado, forzará la inserción de un nuevo registro `TrackingEvent` con tipo `in_transit`.

## 5. Seguridad y Auditoría

La especificación completa de seguridad está en [`TRACKING_SECURITY.md`](./TRACKING_SECURITY.md). Resumen de decisiones:

- **Expiración:** Hard (7 días, inmutable) + Soft (48h post-entrega). Hard siempre gana.
- **Revocación:** `isActive = false` es irreversible. Campos `revokedAt` / `revokedBy` para auditoría.
- **Zero Leakage:** 13 campos auditados. `lat/lng` ofuscado a 2 decimales (~1.1 km). IDs públicos son ordinales (`evt-1`), no IDs de BD.
- **Rate Limiting:** 60 req/min/IP (CDN), 30 req/min/token (API). Sliding window.
- **Logging:** IPs hasheadas con salt 24h. Alertas automáticas para brute-force y scraping.
- **HTTP Responses:** 200 (ok), 403 (revocado), 404 (no existe), 410 (expirado), 429 (rate limit).
