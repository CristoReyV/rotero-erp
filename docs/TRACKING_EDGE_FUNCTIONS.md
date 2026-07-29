# Edge Functions — Tracking Module
> **Versión:** 1.1 · **Fecha de reconciliación:** 2026-07-29
> **Módulo:** OPS_TRACK · **Ref:** TRACKING_TOKEN_SECURITY_DESIGN.md

> **Estado verificado del árbol:** existen `track-public`, `driver-view` y
> `track-driver`. `track-admin` no está implementada en el árbol actual y queda
> fuera del alcance de SEC.4. Los fragmentos siguientes describen el contrato y
> el comportamiento vigente; el código fuente es la autoridad final.

---

## Arquitectura de Edge Functions

```
supabase/functions/
├── track-public/          ← GET /functions/v1/track-public?token=<PUBLIC_TOKEN>
│   └── index.ts
├── driver-view/           ← GET /functions/v1/driver-view?token=<DRIVER_TOKEN>
│   └── index.ts
├── track-driver/          ← POST /functions/v1/track-driver
│   └── index.ts
└── _shared/
    ├── cors.ts            ← Headers CORS comunes
    ├── rate-limit.ts      ← Rate limiting en memoria (Deno.KV o Map)
    └── response.ts        ← Helpers de respuesta JSON
```

---

## 1. `track-public/index.ts` — GET PublicTrackingView

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse, errorResponse } from "../_shared/response.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return errorResponse(405, "method_not_allowed");
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token || token.length < 30) {
    // NL-11: Misma respuesta que token no encontrado
    return errorResponse(404, "not_found");
  }

  // Rate limiting por IP
  const ip = req.headers.get("x-forwarded-for") || "unknown";
  if (!checkRateLimit(`public:${ip}`, 60, 60_000)) {
    return errorResponse(429, "rate_limited", { "Retry-After": "60" });
  }

  // Rate limiting por token
  if (!checkRateLimit(`public:${token.substring(0, 8)}`, 120, 60_000)) {
    return errorResponse(429, "rate_limited", { "Retry-After": "60" });
  }

  // Call RPC with service_role (bypasses RLS)
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data, error } = await supabase.rpc("rpc_get_public_tracking", {
    p_token: token,
  });

  if (error) {
    console.error("[track-public] RPC error:", error.message);
    return errorResponse(500, "internal_error");
  }

  // Map RPC status to HTTP codes
  const status = data?.status;
  const httpCode = {
    success: 200,
    soft_expired: 200,
    not_found: 404,
    revoked: 403,
    hard_expired: 410,
  }[status] || 404;

  // Log de acceso best-effort. Se espera para que el runtime ejecute la
  // operación, pero un fallo del log no invalida la respuesta principal.
  const [tokenHash, ipHash] = await Promise.all([
    hashString(token),
    hashString(ip + new Date().toISOString().slice(0, 10)),
  ]);
  await Promise.allSettled([
    supabase.from("tracking_access_log").insert({
      token_hash: tokenHash,
      ip_hash: ipHash,
      user_agent: (req.headers.get("user-agent") || "").substring(0, 200),
      country_code: req.headers.get("cf-ipcountry") || null,
    }),
  ]);

  return jsonResponse(httpCode, data, {
    ...corsHeaders,
    "X-Robots-Tag": "noindex, nofollow",
    "Cache-Control": "public, max-age=60, stale-while-revalidate=30",
  });
});

async function hashString(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

### Notas de diseño:
- **Rate limit en memoria:** Usa un `Map<string, number[]>` con sliding window. En producción a escala, migrar a Deno KV o Upstash Redis.
- **Access log best-effort:** El INSERT se espera mediante `Promise.allSettled`; su fallo no invalida la respuesta principal.
- **Cache-Control:** 60s TTL + stale-while-revalidate para absorber ráfagas de WhatsApp.
- **X-Robots-Tag:** Previene indexación de las respuestas.

---

## 2. `driver-view/index.ts` — GET DriverView

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse, errorResponse } from "../_shared/response.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return errorResponse(405, "method_not_allowed");
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("token");

  if (!token || token.length < 30) {
    return errorResponse(404, "not_found");
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data, error } = await supabase.rpc("rpc_get_driver_view", {
    p_token: token,
  });

  if (error) {
    console.error("[driver-view] RPC error:", error.message);
    return errorResponse(500, "internal_error");
  }

  const httpCode = data?.status === "success" ? 200 : 
                   data?.status === "revoked" ? 403 :
                   data?.status === "expired" ? 403 : 404;

  return jsonResponse(httpCode, data, {
    ...corsHeaders,
    "X-Robots-Tag": "noindex, nofollow",
    "Cache-Control": "no-store",  // Vista del chofer nunca se cachea
  });
});
```

---

## 3. `track-driver/index.ts` — POST TrackingEvent

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse, errorResponse } from "../_shared/response.ts";
import { checkRateLimit } from "../_shared/rate-limit.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed");
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "invalid_json");
  }

  const {
    driverToken,
    action,
    location,
    manualPlace,
    incident,
    clientTimestamp,
    offlineQueued,
  } = body;

  // Basic input validation
  if (!driverToken || !action || !clientTimestamp) {
    return errorResponse(400, "missing_fields");
  }

  const validActions = ["departure", "in_transit", "arrival", "delivered", "incident"];
  if (!validActions.includes(action)) {
    return errorResponse(400, "invalid_action");
  }

  // Rate limiting by IP (20 req/hour for driver writes)
  const ip = req.headers.get("x-forwarded-for") || "unknown";
  if (!checkRateLimit(`driver:${ip}`, 20, 3_600_000)) {
    return errorResponse(429, "rate_limited", { "Retry-After": "300" });
  }

  // Resolve source and coordinates
  const source = location?.source || "none";
  const lat = source === "gps" ? location?.lat : null;
  const lng = source === "gps" ? location?.lng : null;
  const accuracy = source === "gps" ? location?.accuracy : null;

  // Resolve municipality
  let municipality = manualPlace?.municipality || null;
  let stateName = manualPlace?.state || null;

  // If GPS coordinates provided, call reverse geocoding
  // NOTE: In production, use a geocoding service here (Nominatim proxy, Google, etc.)
  // For now, municipalities come from manual selection or are resolved by geocoding service.
  if (source === "gps" && lat && lng && !municipality) {
    // TODO: Call internal geocoding service
    // const geo = await reverseGeocode(lat, lng);
    // municipality = geo?.municipality;
    // stateName = geo?.state;
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data, error } = await supabase.rpc("rpc_post_driver_event", {
    p_token: driverToken,
    p_action: action,
    p_source: source,
    p_lat: lat,
    p_lng: lng,
    p_accuracy: accuracy,
    p_municipality: municipality,
    p_state_name: stateName,
    p_country_code: "MX",
    p_incident_type: action === "incident" ? incident?.type : null,
    p_incident_note: action === "incident" ? incident?.note : null,
    p_client_timestamp: clientTimestamp,
    p_offline_queued: offlineQueued || false,
  });

  if (error) {
    console.error(
      `[track-driver] RPC error for ${driverToken.substring(0, 8)}...:`,
      error.message,
    );
    return errorResponse(500, "internal_error");
  }

  // The RPC returns {http, accepted, reason?, eventId?, ...}
  const httpCode = data?.http || 500;

  return jsonResponse(httpCode, data, {
    ...corsHeaders,
    "X-Robots-Tag": "noindex, nofollow",
  });
});
```

---

## 4. `_shared/cors.ts`

```typescript
// Allowlist vigente en el árbol actual.
const ALLOWED_ORIGINS = [
  "https://erp.rotero.mx",
  "https://tracking.rotero.mx",
  "https://roterowlsbeta.netlify.app",
  "https://staging.rotero.mx",
  "http://localhost:3000",
  "http://localhost:5173",
];

export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") || "";
  const headers = {
    "Access-Control-Allow-Headers": "content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
  if (ALLOWED_ORIGINS.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}
```

La implementación no usa wildcard: un origen no incluido no recibe
`Access-Control-Allow-Origin`. El dominio
`https://rotero-erp-staging.netlify.app` todavía no forma parte de la allowlist;
su incorporación queda pendiente para SEC.4C.

---

## 5. `_shared/rate-limit.ts`

```typescript
/**
 * In-memory sliding window rate limiter.
 * Suitable for single-instance Edge Functions.
 * For multi-instance, use Deno KV or Upstash Redis.
 */
const windows = new Map<string, number[]>();

export function checkRateLimit(key: string, maxRequests: number, windowMs: number): boolean {
  const now = Date.now();
  const timestamps = windows.get(key) || [];

  // Remove expired entries
  const valid = timestamps.filter((t) => now - t < windowMs);

  if (valid.length >= maxRequests) {
    windows.set(key, valid);
    return false;
  }

  valid.push(now);
  windows.set(key, valid);

  // Cleanup: remove keys older than windowMs to prevent memory leak
  if (windows.size > 10000) {
    for (const [k, v] of windows) {
      if (v.length === 0 || now - v[v.length - 1] > windowMs * 2) {
        windows.delete(k);
      }
    }
  }

  return true;
}
```

---

## 6. `_shared/response.ts`

```typescript
export function jsonResponse(status: number, body: any, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}

export function errorResponse(status: number, reason: string, extraHeaders: Record<string, string> = {}): Response {
  return jsonResponse(status, { status: reason }, extraHeaders);
}
```

---

## 7. Flujo Completo Request → Response

### GET `/functions/v1/track-public?token=<PUBLIC_TOKEN>`

```
Browser → Edge Function (track-public)
  ├── Rate limit check (IP + token prefix)
  ├── supabase.rpc('rpc_get_public_tracking', { p_token })
  │   ├── tracking_hash_token(p_token) → SHA-256
  │   ├── Lookup tracking_tokens WHERE token_hash = hash AND scope = 'public:read'
  │   ├── Compute effective state (active / soft_expired / hard_expired)
  │   ├── Query tracking_events → build sanitized timeline
  │   ├── Round coordinates GEO-01 (2 decimals)
  │   ├── Omit location if delivered (GEO-03) or null (GEO-04)
  │   └── Return JSONB {status, data: PublicTrackingView}
  ├── Esperar access log best-effort con Promise.allSettled
  └── Return JSON response + X-Robots-Tag + Cache-Control
```

### POST /functions/v1/track-driver

```
Driver App → Edge Function (track-driver)
  ├── Parse + validate JSON body
  ├── Rate limit check (IP, 20 req/hour)
  ├── Resolve geocoding (if source=gps and coords present)
  ├── supabase.rpc('rpc_post_driver_event', { ... })
  │   ├── tracking_hash_token(p_token) → SHA-256
  │   ├── Lookup tracking_tokens WHERE hash AND scope = 'driver:write'
  │   ├── Validate: state = 'active', not expired
  │   ├── Idempotency check (clientTimestamp ± 5s)
  │   ├── Singleton check (departure / delivered / arrival)
  │   ├── Cooldown check (30 min in_transit, 10 min incident)
  │   ├── Municipality dedup (same_municipality rejection)
  │   ├── Max events check (15 in_transit per trip)
  │   ├── Anomaly detection (300 km in < 30 min → is_suspicious)
  │   ├── INSERT tracking_events
  │   ├── UPDATE tracking_tokens.event_count
  │   └── Return JSONB {http, accepted, eventId | reason}
  └── Return JSON response
```

---

## 8. Configuración de autenticación y deploy

Las tres rutas vigentes se autentican con tokens funcionales propios
(`<PUBLIC_TOKEN>` o `<DRIVER_TOKEN>`), no con una sesión Supabase. Los callers
frontend actuales no envían `Authorization` ni `apikey`; por ello estas
funciones requieren `verify_jwt = false`.

`supabase/config.toml` todavía no contiene secciones `[functions.*]` que
declaren esa configuración. SEC.4B no modifica el archivo ni afirma que ya esté
corregido. Hasta SEC.4C, cualquier deploy debe conservar explícitamente el
comportamiento sin verificación JWT:

```bash
supabase functions deploy track-public --no-verify-jwt
supabase functions deploy driver-view   --no-verify-jwt
supabase functions deploy track-driver  --no-verify-jwt
```

### Estado de credenciales

El código vigente crea el cliente administrativo con `SUPABASE_URL` y
`SUPABASE_SERVICE_ROLE_KEY`. Esto describe el estado legacy actual, no el estado
objetivo. La migración a una secret moderna todavía no se ha implementado ni
desplegado.

### Matriz `verify_jwt`

| Function | Requiere `verify_jwt=false` | Autenticación funcional |
|----------|:---------------------------:|-------------------------|
| `track-public` | Sí | `<PUBLIC_TOKEN>` |
| `driver-view` | Sí | `<DRIVER_TOKEN>` |
| `track-driver` | Sí | `<DRIVER_TOKEN>` |

`track-admin` no está implementada en el árbol actual y queda fuera de SEC.4.
No debe crearse ni desplegarse como parte de este plan.

### Hardening pendiente

- `track-driver` todavía incluye los primeros ocho caracteres del token en el
  log de errores RPC. Su eliminación queda pendiente; SEC.4B no modifica código.
- La allowlist CORS todavía debe incorporar el dominio Netlify staging.
- `verify_jwt=false` debe quedar explícito en `supabase/config.toml`.

### Plan de migración vigente

1. **SEC.4C:** soporte dual de secret moderna con fallback legacy temporal,
   configuración explícita de `verify_jwt=false`, CORS staging y hardening del log.
2. **SEC.4D:** alta manual de la secret `tracking-edge`.
3. **SEC.4E:** canary de `driver-view`.
4. **SEC.4F:** migración de `track-public` y `track-driver`.
5. **SEC.4G:** QA integral de tracking.
6. **SEC.4H:** retirar el fallback y revocar la credencial legacy cuando no
   existan consumidores pendientes.

---

## 9. Resumen: Mapeo Ruta Frontend → Edge Function → RPC

| Frontend Route | HTTP | Edge Function | RPC | Scope |
|---------------|------|---------------|-----|-------|
| `/t/:token` | GET | `track-public` | `rpc_get_public_tracking` | `public:read` |
| `/driver/:token` (load) | GET | `driver-view` | `rpc_get_driver_view` | `driver:write` |
| `/driver/:token` (action) | POST | `track-driver` | `rpc_post_driver_event` | `driver:write` |

Las acciones internas de creación, revocación y rotación de tokens usan RPCs
del backend existente; no existe una Edge Function `track-admin` en el árbol
actual.
