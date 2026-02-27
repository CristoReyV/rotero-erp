# Tracking Opción A — Diseño de Integración Supabase

> **Módulo:** OPS_TRACK · **Fecha:** 2026-02-22
> **Estado:** Diseño. No implementar aún.
> **Referencias:** `TRACKING_MODULE.md`, `TRACKING_SECURITY.md`, `TRACKING_EVENT_RULES.md`, `rotero_erp_architecture.md` §3

---

## 1. Esquema de Tablas

### 1.1 `tracking_events`

Almacena cada punto reportado del timeline (GPS, manual, sistema).

```sql
CREATE TABLE tracking_events (
    -- RT-01: campos base multi-tenant
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES tenants(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid NOT NULL REFERENCES auth.users(id),
    is_deleted      boolean NOT NULL DEFAULT false,

    -- FK a la orden logística
    order_id        uuid NOT NULL REFERENCES orders(id),

    -- Tipo de evento (union type en BD)
    event_type      text NOT NULL CHECK (event_type IN (
                        'departure', 'in_transit', 'customs_entry',
                        'customs_exit', 'arrival', 'delivered', 'exception'
                    )),

    -- Coordenadas GPS crudas (nunca expuestas al público)
    lat             double precision NOT NULL,
    lng             double precision NOT NULL,

    -- Resultado del reverse geocoding (puede ser NULL si falló)
    municipality    text,           -- 'Ciénega de Flores'
    state           text,           -- 'Nuevo León'
    country_code    text NOT NULL DEFAULT 'MX' CHECK (country_code IN ('MX', 'US')),

    -- Metadata
    source          text NOT NULL DEFAULT 'gps' CHECK (source IN ('gps', 'manual', 'system')),
    note            text,

    -- Timestamp del evento real (puede diferir de created_at por latencia)
    event_timestamp timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_tracking_events_order     ON tracking_events (order_id, event_timestamp);
CREATE INDEX idx_tracking_events_tenant    ON tracking_events (tenant_id, order_id);
CREATE INDEX idx_tracking_events_type      ON tracking_events (order_id, event_type)
    WHERE is_deleted = false;
```

**Notas de diseño:**
- `lat`/`lng` como `double precision` — no PostGIS. No necesitamos GIS queries, solo almacenamiento. PostGIS agrega 50MB+ de extensión para un `ST_Distance()` que resolvemos en app con haversine.
- `event_timestamp` separado de `created_at` para cubrir inserciones con delay (conectividad, batch sync).
- `municipality` puede ser `NULL` cuando el geocoding falló (DED-05). Estos eventos existen para trazabilidad interna pero no se proyectan al público.

### 1.2 `tracking_links`

Un link público de seguimiento por orden.

```sql
CREATE TABLE tracking_links (
    -- RT-01: campos base multi-tenant
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       uuid NOT NULL REFERENCES tenants(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid NOT NULL REFERENCES auth.users(id),
    is_deleted      boolean NOT NULL DEFAULT false,

    -- FK a la orden (UNIQUE: solo 1 link activo por orden — REV-02)
    order_id        uuid NOT NULL REFERENCES orders(id),

    -- Token público (capability-based auth — SEC-05)
    token           uuid NOT NULL DEFAULT gen_random_uuid(),

    -- Ciclo de vida
    is_active       boolean NOT NULL DEFAULT true,
    expires_at      timestamptz NOT NULL,

    -- Auditoría de acceso
    last_accessed_at    timestamptz,

    -- Revocación (REV-01, REV-03)
    revoked_at      timestamptz,
    revoked_by      uuid REFERENCES auth.users(id),

    -- Constraint: solo 1 link activo por orden
    CONSTRAINT uq_active_link_per_order
        UNIQUE (order_id) WHERE (is_active = true AND is_deleted = false)
);

-- Índice único en token (lookup por la ruta pública)
CREATE UNIQUE INDEX idx_tracking_links_token ON tracking_links (token);

-- Índice para búsqueda por orden
CREATE INDEX idx_tracking_links_order ON tracking_links (order_id)
    WHERE is_deleted = false;
```

**Notas de diseño:**
- `token` es UUID v4 (36 chars). No contiene `order_id` ni `tenant_id` — el token es opaco.
- `UNIQUE (order_id) WHERE (is_active = true)` — partial unique index que garantiza REV-02 a nivel de BD.
- Links revocados (`is_active = false`) no se borran (REV-03): permanecen para auditoría.

---

## 2. Políticas RLS (Row Level Security)

### 2.1 Principio general

```
                   ┌──────────────┐
                   │  Supabase    │
                   │  Auth Layer  │
                   └──────┬───────┘
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
       Authenticated   Authenticated   Anonymous
       (ERP user)      (ERP user)      (Public)
              │           │              │
     tracking_events  tracking_links   tracking_links
       CRUD by         CRUD by          SELECT ONLY
       tenant_id       tenant_id        por token match
```

### 2.2 Políticas para `tracking_events`

```sql
-- Habilitar RLS
ALTER TABLE tracking_events ENABLE ROW LEVEL SECURITY;

-- POL-TE-01: SELECT — usuarios autenticados del mismo tenant
CREATE POLICY "tenant_tracking_events_select"
    ON tracking_events FOR SELECT
    TO authenticated
    USING (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND is_deleted = false
    );

-- POL-TE-02: INSERT — solo coordinadores y directores operativos
CREATE POLICY "ops_tracking_events_insert"
    ON tracking_events FOR INSERT
    TO authenticated
    WITH CHECK (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND EXISTS (
            SELECT 1 FROM user_memberships
            WHERE user_id = auth.uid()
              AND role IN ('super_admin', 'ops_director', 'ops_coordinator')
        )
    );

-- POL-TE-03: UPDATE — solo para corregir geocoding (municipality/state NULL → resolved)
CREATE POLICY "ops_tracking_events_update"
    ON tracking_events FOR UPDATE
    TO authenticated
    USING (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND is_deleted = false
    )
    WITH CHECK (
        -- Solo se permiten updates a municipality, state, country_code, updated_at
        -- La protección de columnas se hace en la RPC, no en RLS
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
    );

-- POL-TE-04: DELETE — nadie borra. Soft delete via is_deleted.
-- (No se crea policy DELETE → denied by default)

-- POL-TE-05: Acceso anónimo — NINGUNO a tracking_events directamente
-- Los anónimos acceden solo via la RPC rpc_get_public_tracking() que lee
-- tracking_events internamente con SECURITY DEFINER.
```

### 2.3 Políticas para `tracking_links`

```sql
-- Habilitar RLS
ALTER TABLE tracking_links ENABLE ROW LEVEL SECURITY;

-- POL-TL-01: SELECT (autenticado) — usuarios del mismo tenant
CREATE POLICY "tenant_tracking_links_select"
    ON tracking_links FOR SELECT
    TO authenticated
    USING (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND is_deleted = false
    );

-- POL-TL-02: INSERT (autenticado) — coordinadores y directores
CREATE POLICY "ops_tracking_links_insert"
    ON tracking_links FOR INSERT
    TO authenticated
    WITH CHECK (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND EXISTS (
            SELECT 1 FROM user_memberships
            WHERE user_id = auth.uid()
              AND role IN ('super_admin', 'ops_director', 'ops_coordinator')
        )
    );

-- POL-TL-03: UPDATE (autenticado) — solo revocar (is_active, revoked_at, revoked_by)
CREATE POLICY "ops_tracking_links_update"
    ON tracking_links FOR UPDATE
    TO authenticated
    USING (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND is_deleted = false
    )
    WITH CHECK (
        tenant_id = (SELECT tenant_id FROM user_memberships WHERE user_id = auth.uid() LIMIT 1)
        AND EXISTS (
            SELECT 1 FROM user_memberships
            WHERE user_id = auth.uid()
              AND role IN ('super_admin', 'ops_director', 'ops_coordinator')
        )
    );

-- POL-TL-04: SELECT (anónimo) — solo si token válido, activo y no expirado
-- NOTA: Esta policy permite que la RPC anónima haga el lookup por token
CREATE POLICY "anon_tracking_links_select_by_token"
    ON tracking_links FOR SELECT
    TO anon
    USING (
        is_active = true
        AND is_deleted = false
        AND expires_at > now()
        -- El filtro por token se aplica en la query WHERE de la RPC
    );
```

**Nota importante:** La policy `anon` en `tracking_links` solo permite `SELECT`. El anónimo **nunca** puede escribir ni en `tracking_links` ni en `tracking_events`.

---

## 3. RPC: `rpc_get_public_tracking`

### 3.1 Contrato

```sql
CREATE OR REPLACE FUNCTION rpc_get_public_tracking(p_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER          -- Se ejecuta con permisos del owner, no del caller
SET search_path = public
AS $$
DECLARE
    v_link      tracking_links%ROWTYPE;
    v_order     orders%ROWTYPE;
    v_events    jsonb;
    v_location  jsonb;
    v_result    jsonb;
BEGIN
    -- 1. Buscar link por token
    SELECT * INTO v_link
    FROM tracking_links
    WHERE token = p_token
      AND is_deleted = false
    LIMIT 1;

    -- Token no existe
    IF v_link IS NULL THEN
        RETURN jsonb_build_object(
            'error', 'not_found',
            'message', 'Link de seguimiento no encontrado',
            'http_status', 404
        );
    END IF;

    -- Token revocado
    IF v_link.is_active = false THEN
        RETURN jsonb_build_object(
            'error', 'revoked',
            'message', 'Este enlace fue desactivado por el operador',
            'http_status', 403
        );
    END IF;

    -- Token expirado (hard)
    IF v_link.expires_at < now() THEN
        RETURN jsonb_build_object(
            'error', 'expired',
            'message', 'Este enlace de seguimiento ha expirado',
            'http_status', 410
        );
    END IF;

    -- 2. Actualizar last_accessed_at (fire-and-forget, no transactional)
    UPDATE tracking_links
    SET last_accessed_at = GREATEST(last_accessed_at, now()),
        updated_at = now()
    WHERE id = v_link.id;

    -- 3. Obtener orden para route, orderRef, status
    SELECT * INTO v_order
    FROM orders
    WHERE id = v_link.order_id
      AND is_deleted = false;

    -- 4. Expiración soft: delivered + 48h
    IF v_order.status = 'delivered' THEN
        DECLARE
            v_delivered_at timestamptz;
        BEGIN
            SELECT event_timestamp INTO v_delivered_at
            FROM tracking_events
            WHERE order_id = v_link.order_id
              AND event_type = 'delivered'
              AND is_deleted = false
            ORDER BY event_timestamp DESC
            LIMIT 1;

            IF v_delivered_at IS NOT NULL
               AND v_delivered_at + interval '48 hours' < now() THEN
                RETURN jsonb_build_object(
                    'error', 'expired',
                    'message', 'Seguimiento completado',
                    'http_status', 410
                );
            END IF;
        END;
    END IF;

    -- 5. Construir timeline público (sanitizado)
    --    SOLO eventos con municipality NOT NULL (VIS-06)
    --    Máximo 12 eventos (VIS-01)
    --    Sin IDs internos, sin lat/lng raw, sin source
    SELECT jsonb_agg(evt ORDER BY evt_order)
    INTO v_events
    FROM (
        SELECT
            jsonb_build_object(
                'id', 'evt-' || ROW_NUMBER() OVER (ORDER BY event_timestamp),
                'title', CASE event_type
                    WHEN 'departure'     THEN 'Salida de Almacén'
                    WHEN 'in_transit'    THEN 'En camino'
                    WHEN 'customs_entry' THEN 'Ingreso a Aduana'
                    WHEN 'customs_exit'  THEN 'Liberado de Aduana'
                    WHEN 'arrival'       THEN 'Llegada a destino'
                    WHEN 'delivered'     THEN 'Entregado'
                    WHEN 'exception'     THEN 'Incidencia reportada'
                END,
                'subtitle', COALESCE(municipality, '') || ', ' || COALESCE(state, '') ||
                            ' · ' || to_char(event_timestamp AT TIME ZONE 'America/Mexico_City', 'HH12:MI AM'),
                'timestamp', event_timestamp,
                'status', CASE
                    WHEN event_timestamp = (
                        SELECT MAX(e2.event_timestamp) FROM tracking_events e2
                        WHERE e2.order_id = te.order_id AND e2.municipality IS NOT NULL
                          AND e2.is_deleted = false
                    ) THEN 'current'
                    ELSE 'done'
                END,
                'icon', CASE event_type
                    WHEN 'departure'     THEN 'truck'
                    WHEN 'in_transit'    THEN 'map-pin'
                    WHEN 'customs_entry' THEN 'shield'
                    WHEN 'customs_exit'  THEN 'shield-check'
                    WHEN 'arrival'       THEN 'flag'
                    WHEN 'delivered'     THEN 'check-circle'
                    WHEN 'exception'     THEN 'alert-triangle'
                END
            ) AS evt,
            ROW_NUMBER() OVER (ORDER BY event_timestamp) AS evt_order
        FROM tracking_events te
        WHERE order_id = v_link.order_id
          AND is_deleted = false
          AND municipality IS NOT NULL       -- VIS-06: geocode fallido = invisible
        ORDER BY event_timestamp
        LIMIT 12                             -- VIS-01: máximo 12
    ) sub;

    -- 6. Última ubicación ofuscada (GEO-01: 2 decimales)
    IF v_order.status != 'delivered' THEN         -- GEO-03: omitir si delivered
        SELECT jsonb_build_object(
            'lat', ROUND(lat::numeric, 2),        -- GEO-01: ~1.1km precision
            'lng', ROUND(lng::numeric, 2)
        ) INTO v_location
        FROM tracking_events
        WHERE order_id = v_link.order_id
          AND is_deleted = false
          AND municipality IS NOT NULL             -- GEO-04: omitir si geocode falló
        ORDER BY event_timestamp DESC
        LIMIT 1;
    END IF;

    -- 7. Ensamblar PublicTrackingView
    v_result := jsonb_build_object(
        'orderRef',       v_order.reference,                    -- e.g. 'ROT-24-001'
        'route',          v_order.origin || ' → ' || v_order.destination,
        'currentStatus',  v_order.status_label,
        'events',         COALESCE(v_events, '[]'::jsonb),
        'eta',            v_order.eta
    );

    -- Solo agregar currentLocation si existe (no null)
    IF v_location IS NOT NULL THEN
        v_result := v_result || jsonb_build_object('currentLocation', v_location);
    END IF;

    RETURN v_result;
END;
$$;

-- Permitir ejecución anónima
GRANT EXECUTE ON FUNCTION rpc_get_public_tracking(uuid) TO anon;
GRANT EXECUTE ON FUNCTION rpc_get_public_tracking(uuid) TO authenticated;
```

### 3.2 Contrato de respuesta TypeScript (ya existente)

La respuesta de la RPC se castea directamente a `PublicTrackingView`:

```typescript
// Éxito (HTTP 200)
interface PublicTrackingView {
    orderRef: string;              // 'ROT-24-001'
    route: string;                 // 'Laredo → Monterrey'
    currentStatus: string;         // 'En Tránsito'
    events: PublicTimelineEvent[]; // máx 12
    eta?: string;                  // 'Hoy, 14:00'
    currentLocation?: GeoPoint;    // { lat: 25.96, lng: -100.17 } (2 decimales)
}

// Error (HTTP 403/404/410)
interface TrackingError {
    error: 'not_found' | 'revoked' | 'expired';
    message: string;
    http_status: number;
}
```

### 3.3 Llamada desde el frontend

```typescript
// En TrackingPublicPage.tsx (futuro)
const { token } = useParams<{ token: string }>();

const { data, error } = await supabase
    .rpc('rpc_get_public_tracking', { p_token: token });

if (data?.error) {
    // Mostrar pantalla de error según data.http_status
} else {
    // Renderizar PublicTrackingView normalmente
    const trackingData: PublicTrackingView = data;
}
```

---

## 4. Flujo de Datos Completo

### 4.1 Flujo de escritura (inserción de evento)

```
┌─────────────────────────────────────────────────────────────────────┐
│  App del Operador (ERP / TrackingPage)                              │
│  1. Obtiene lat/lng (GPS del dispositivo o manual)                  │
│  2. Llama a Supabase Edge Function: /functions/v1/tracking-geocode  │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ POST { order_id, lat, lng }
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Edge Function: tracking-geocode                                     │
│                                                                      │
│  1. Verificar auth (JWT) y tenant_id                                 │
│  2. Verificar que la orden está en estado 'in_transit' (DED-10)     │
│  3. Obtener último evento visible de la orden                        │
│  4. Anti-teleport: distancia > 300km en < 2h? → reject (DED-06)    │
│  5. Distancia mínima: < 5km? → skip (DED-03)                        │
│  6. Reverse geocode (Nominatim/Google proxy):                        │
│     - lat/lng → { municipality, state, country_code }                │
│     - Si falla: insertar evento con municipality=NULL (DED-05)      │
│  7. Deduplicación:                                                   │
│     - Mismo municipio consecutivo? → skip (DED-01)                  │
│     - Cooldown < 30 min? → skip (DED-02)                            │
│     - Modo checkpoints: municipio en lista? (DED-04)                │
│     - Cruce fronterizo: bypass cooldown (DED-09)                    │
│  8. Si pasa todo: INSERT INTO tracking_events                        │
│  9. Return { success: true, event_type, municipality }               │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Flujo de lectura (vista pública)

```
┌───────────────────────────────────────────────┐
│  Cliente final abre /t/{token} en su browser  │
└──────────────────┬────────────────────────────┘
                   │ GET
                   ▼
┌───────────────────────────────────────────────┐
│  TrackingPublicPage.tsx                        │
│  1. useParams() → token                        │
│  2. supabase.rpc('rpc_get_public_tracking',    │
│                   { p_token: token })           │
└──────────────────┬────────────────────────────┘
                   │ PostgREST
                   ▼
┌───────────────────────────────────────────────┐
│  Postgres: rpc_get_public_tracking()           │
│                                                │
│  1. Lookup token en tracking_links             │
│  2. Validar: activo + no expirado + no revocado│
│  3. Update last_accessed_at                    │
│  4. Query tracking_events sanitizado           │
│     - Solo municipality NOT NULL               │
│     - Solo 12 eventos máximo                   │
│     - IDs ordinales (evt-1, evt-2...)          │
│     - lat/lng redondeado a 2 decimales         │
│  5. Return PublicTrackingView JSON             │
└──────────────────┬────────────────────────────┘
                   │ jsonb
                   ▼
┌───────────────────────────────────────────────┐
│  TrackingPublicPage.tsx                        │
│  - Renderizar timeline                         │
│  - Mostrar mapa con marker ofuscado            │
│  - Si error: mostrar pantalla de expiración    │
└───────────────────────────────────────────────┘
```

### 4.3 Edge Function: `tracking-geocode` (pseudocódigo)

```typescript
// supabase/functions/tracking-geocode/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (req: Request) => {
    // 1. Auth
    const authHeader = req.headers.get('Authorization');
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return new Response('Unauthorized', { status: 401 });

    // 2. Parse body
    const { order_id, lat, lng } = await req.json();

    // 3. Get user context (tenant, role)
    const { data: ctx } = await supabase
        .rpc('rpc_get_my_context');

    // 4. Verify order is in_transit
    const { data: order } = await supabase
        .from('orders')
        .select('id, status')
        .eq('id', order_id)
        .eq('tenant_id', ctx.tenant_id)
        .single();

    if (order?.status !== 'in_transit') {
        return Response.json({ skip: true, reason: 'DED-10' });
    }

    // 5. Get last visible event
    const { data: lastEvent } = await supabase
        .from('tracking_events')
        .select('*')
        .eq('order_id', order_id)
        .eq('is_deleted', false)
        .not('municipality', 'is', null)
        .order('event_timestamp', { ascending: false })
        .limit(1)
        .single();

    // 6. DED-06: Anti-teleport
    if (lastEvent) {
        const dist = haversineKm(
            { lat, lng },
            { lat: lastEvent.lat, lng: lastEvent.lng }
        );
        const minutesSince = (Date.now() - new Date(lastEvent.event_timestamp).getTime()) / 60000;
        if (dist > 300 && minutesSince < 120) {
            return Response.json({ skip: true, reason: 'DED-06' });
        }
        // DED-03: Min distance
        if (dist < 5) {
            return Response.json({ skip: true, reason: 'DED-03' });
        }
    }

    // 7. Reverse geocode (Nominatim or Google proxy)
    const place = await reverseGeocode({ lat, lng });

    // 8. DED-05: Geocode failed → silent event
    if (!place) {
        await supabase.from('tracking_events').insert({
            tenant_id: ctx.tenant_id,
            order_id, lat, lng,
            event_type: 'in_transit',
            municipality: null, state: null,
            source: 'gps', created_by: user.id,
            event_timestamp: new Date().toISOString(),
        });
        return Response.json({ created: true, silent: true, reason: 'DED-05' });
    }

    // 9. DED-01: Same municipality
    const borderCrossing = lastEvent && lastEvent.country_code !== place.countryCode;
    if (!borderCrossing && lastEvent
        && lastEvent.municipality === place.municipality
        && lastEvent.state === place.state) {
        return Response.json({ skip: true, reason: 'DED-01' });
    }

    // 10. DED-02: Cooldown (skip if border crossing — DED-09)
    if (!borderCrossing && lastEvent) {
        const minutesSince = (Date.now() - new Date(lastEvent.event_timestamp).getTime()) / 60000;
        if (minutesSince < 30) {
            return Response.json({ skip: true, reason: 'DED-02' });
        }
    }

    // 11. Insert event
    const { data: newEvent, error } = await supabase
        .from('tracking_events')
        .insert({
            tenant_id: ctx.tenant_id,
            order_id, lat, lng,
            event_type: borderCrossing ? 'customs_entry' : 'in_transit',
            municipality: place.municipality,
            state: place.state,
            country_code: place.countryCode,
            source: 'gps',
            created_by: user.id,
            event_timestamp: new Date().toISOString(),
        })
        .select()
        .single();

    return Response.json({ created: true, event: newEvent?.event_type, municipality: place.municipality });
});
```

---

## 5. Consideraciones de Seguridad (resumen alineado)

| Regla | Implementación Supabase |
|-------|------------------------|
| **SEC-01** Expiración 7d | `tracking_links.expires_at` + check en RPC |
| **SEC-03** Solo lectura pública | RPC `SECURITY DEFINER` + policy `anon` = SELECT only |
| **SEC-04** Rate limit 60 req/min | Netlify Edge o función de rate limit en Edge Function |
| **SEC-05** Token = auth | `rpc_get_public_tracking(p_token)` con `anon` grant |
| **SEC-06** Solo PublicTrackingView | RPC ensambla JSON sin IDs internos |
| **SEC-07** Revocable | `is_active = false` + check en RPC |
| **SEC-08** 1 link/orden | Partial UNIQUE index en BD |
| **SEC-09** Logging | `last_accessed_at` update en RPC |
| **GEO-01** Ofuscación | `ROUND(lat::numeric, 2)` en la RPC |
| **REV-01** Irreversible | No hay UPDATE policy que permita `is_active = false → true` |
| **DED-01..10** Deduplicación | Edge Function aplica pipeline completo antes del INSERT |

---

## 6. Orden de Implementación Sugerido

| Paso | Qué | Dependencia |
|:----:|-----|:-----------:|
| 1 | `CREATE TABLE tracking_events` (migración) | Tabla `orders` existente |
| 2 | `CREATE TABLE tracking_links` (migración) | Tabla `orders` existente |
| 3 | Aplicar RLS policies a ambas tablas | Tablas creadas + `user_memberships` |
| 4 | `CREATE FUNCTION rpc_get_public_tracking` + GRANT | Tablas + policies |
| 5 | Deploy Edge Function `tracking-geocode` | Tablas + geocoding service |
| 6 | Modificar `TrackingPublicPage.tsx`: reemplazar mock por `supabase.rpc()` | RPC disponible |
| 7 | Modificar `TrackingPage.tsx`: botón sync llama Edge Function | Edge Function disponible |
| 8 | Testing end-to-end con token real | Todos los pasos anteriores |
