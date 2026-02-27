# Tracking Opción A — Reglas de Generación de Eventos "En Camino"

> **Módulo:** OPS_TRACK · **Fecha:** 2026-02-22
> **Referencia:** `TRACKING_MODULE.md`, `TRACKING_SECURITY.md`
> **Tipo:** Especificación funcional + pseudoreglas. Sin código completo.

---

## 1. Problema

Cada actualización GPS genera un par `lat/lng`. El servicio `trackingGeo.service.ts` lo resuelve a `Place { municipality, state }`. **Sin filtrado**, una operación Laredo→Monterrey de 3 horas generaría ~12 eventos idénticos "En camino: Sabinas Hidalgo" si el camión circula dentro del mismo municipio.

**Objetivo:** Que el timeline público muestre **solo transiciones relevantes** entre municipios, sin ruido.

---

## 2. Reglas de Deduplicación

### 2.1 Regla DED-01: No repetir municipio consecutivo

```
SI  nuevo.municipality === último_evento_visible.municipality
  Y nuevo.state === último_evento_visible.state
ENTONCES  → DESCARTAR (no crear evento)
```

**Comparación:** Case-insensitive + trim. Normalizado con `toTitleCase()` al momento del geocoding (ya implementado en el servicio).

**Excepción:** Si `countryCode` cambió (cruce fronterizo US↔MX), siempre generar evento aunque el nombre del municipio coincida accidentalmente.

### 2.2 Regla DED-02: Cooldown temporal

```
SI  (ahora - último_evento_visible.timestamp) < cooldownMinutes
ENTONCES  → DESCARTAR (muy pronto)
```

#### ¿Por qué cambiar de 15 min a 30 min?

| Factor | Con 15 min | Con 30 min |
|--------|:----------:|:----------:|
| Eventos/hora (máximo) | 4 | 2 |
| Laredo→MTY (3h, ~8 municipios) | Hasta 12 eventos | Hasta 6 eventos |
| CDMX última milla (30 min, ~4 delegaciones) | Hasta 2 eventos | Hasta 1 evento |
| Ruido en timeline B2C | **Moderado** | **Bajo** |
| Percepción de actualización | Alta pero "spammy" | Equilibrada |

**Decisión: `cooldownMinutes: 30` como default.**

**Justificación operativa:**
- El destinatario B2B/B2C típico revisa el tracking 2-3 veces durante una entrega.
- Un evento cada 30 min en una operación de 3-6h produce 6-12 entradas, que es el rango ideal (VIS-01: máximo 12 visibles).
- 30 min coincide con el intervalo natural de cambio de municipio en autopistas MX (velocidad promedio 80-100 km/h, municipios promedio 30-50 km de largo).

**Configurable por operación:** El campo `TrackingRuleConfig.cooldownMinutes` ya existe. Permite override por escenario:

| Escenario | Override sugerido |
|-----------|:-:|
| Nacional estándar (autopista) | 30 min (default) |
| Frontera US→MX (tramos largos) | 45 min |
| Última milla urbana | 10 min |
| Ruta corta (<100 km) | 15 min |

### 2.3 Regla DED-03: Distancia mínima geográfica

```
SI  distancia(nuevo.location, último_evento_visible.location) < 5 km
ENTONCES  → DESCARTAR (no se movió lo suficiente)
```

**Por qué:** Evita que fluctuaciones de GPS dentro de una zona industrial o punto de descanso generen eventos espurios. Incluso si Nominatim resuelve un municipio diferente (por estar en el límite), 5 km es insuficiente para considerarlo avance real.

**Cálculo:** Haversine simplificado. Aceptable con `Math.acos()` para distancias >100m.

```
function haversineKm(a: GeoPoint, b: GeoPoint): number {
    const R = 6371;
    const dLat = (b.lat - a.lat) * Math.PI / 180;
    const dLon = (b.lng - a.lng) * Math.PI / 180;
    const x = Math.sin(dLat/2)**2 +
              Math.cos(a.lat * Math.PI/180) *
              Math.cos(b.lat * Math.PI/180) *
              Math.sin(dLon/2)**2;
    return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1-x));
}
```

### 2.4 Orden de evaluación (pipeline completo)

```
┌───────────────────────────────────────┐
│  GPS update: { lat, lng, timestamp }  │
└───────────────┬───────────────────────┘
                ▼
        ¿Orden en estado `in_transit`?
            │ No → DESCARTAR
            ▼ Sí
        Reverse geocode → Place | null
            │ null → EVENTO SILENCIOSO (DED-05)
            ▼ ok
        DED-03: ¿distancia ≥ 5 km?          ← barato, sin I/O
            │ No → DESCARTAR
            ▼ Sí
        DED-01: ¿municipio diferente?         ← comparación de strings
            │ No → DESCARTAR
            ▼ Sí
        DED-02: ¿cooldown cumplido (≥30 min)?
            │ No → DESCARTAR
            ▼ Sí
        ¿Modo checkpoints?
            │ Sí → DED-04: ¿municipio en lista?
            │          │ No → DESCARTAR
            │          ▼ Sí
            ▼ No (modo auto)
        ✅ CREAR TrackingEvent { type: 'in_transit', place }
```

**Nota de performance:** Las validaciones DED-03, DED-01, DED-02 se ejecutan **antes** de cualquier posible escritura. Son operaciones en memoria puras. El geocoding (la operación costosa) se hace antes del pipeline pero sus resultados alimentan las compariciones.

---

## 3. Modo Checkpoints (DED-04)

### 3.1 Concepto

Para rutas recurrentes (e.g., Laredo→MTY que se hace 10 veces/semana), el operador define una lista de municipios clave. Solo esos municipios generan eventos visibles.

### 3.2 Estructura de datos

Ya definido en `TrackingRuleConfig.checkpoints?: Place[]`:

```typescript
// Ejemplo: Ruta Laredo → MTY
const rutaLaredoMTY: TrackingRuleConfig = {
    mode: 'checkpoints',
    cooldownMinutes: 30,
    geocodeProvider: 'nominatim',
    maxRetries: 3,
    checkpoints: [
        { municipality: 'Nuevo Laredo', state: 'Tamaulipas', countryCode: 'MX' },
        { municipality: 'Sabinas Hidalgo', state: 'Nuevo León', countryCode: 'MX' },
        { municipality: 'Ciénega de Flores', state: 'Nuevo León', countryCode: 'MX' },
        { municipality: 'Monterrey', state: 'Nuevo León', countryCode: 'MX' },
    ],
};
```

### 3.3 Lógica de match

```
DED-04:
  PARA CADA checkpoint en config.checkpoints:
      SI  nuevo.municipality ≈ checkpoint.municipality  (case-insensitive)
        Y nuevo.state ≈ checkpoint.state
        Y checkpoint NO ha sido reportado ya en esta operación
      ENTONCES  → MATCH (proceder a crear evento)

  SI ningún match → DESCARTAR
```

**"≈" (fuzzy match):** Comparación normalizada. Tanto el checkpoint como el geocoding pasan por `toTitleCase()` + `trim()`. No se usa Levenshtein (demasiado permisivo para nombres geográficos — "Monterrey" vs "Monclova" son edits distance 4, pero son ciudades completamente distintas).

### 3.4 Checkpoints ya reportados

Se mantiene un `Set<string>` por operación con los checkpoints alcanzados:

```
hitCheckpoints = Set { "Nuevo Laredo|Tamaulipas", "Sabinas Hidalgo|Nuevo León" }
```

**Un checkpoint puede ser alcanzado una sola vez.** Si el camión retrocede y pasa de nuevo por Sabinas Hidalgo, **no** genera un segundo evento.

**Justificación:** En modo checkpoints, el cliente espera un timeline limpio de 4-5 puntos. Un retroceso se reportaría como `exception`, no como re-alcanzar un checkpoint.

### 3.5 Auto vs Checkpoints — Cuándo usar cada uno

| Criterio | Auto | Checkpoints |
|----------|:----:|:-----------:|
| Ruta nueva/ad-hoc | ✅ | ❌ |
| Ruta recurrente (>5 veces/mes) | ⚠️ (puede generar ruido) | ✅ |
| Cliente quiere detalle fino | ✅ | ❌ |
| Cliente quiere solo hitos | ❌ | ✅ |
| Config necesaria | Ninguna | Lista de checkpoints |
| Default (si no se configura) | ✅ | — |

---

## 4. Casos Borde

### CB-GEO: Geocoding falla

```
Regla DED-05:
  SI  reverseGeocode() retorna place: null
  ENTONCES:
    - Guardar TrackingEvent con place: null, type: 'in_transit'
    - Marcar source: 'gps' (el dato GPS sí se recibió)
    - Este evento NO aparece en el timeline público (VIS-06)
    - El evento SÍ se guarda en BD interna (trazabilidad/debug)
    - Log nivel WARN: "Geocode failed for order {orderId} at {lat},{lng}"
    - Reintentar hasta maxRetries (default 3) con backoff exponencial:
      retry 1: 2s, retry 2: 4s, retry 3: 8s
    - Si los 3 reintentos fallan: desistir. El siguiente update GPS
      intentará de nuevo con las nuevas coordenadas.
```

**Impacto en UI:** El cliente no ve un "hueco" en el timeline. Simplemente el siguiente municipio exitoso aparecerá cuando se resuelva. El tiempo mostrado será el del siguiente evento exitoso.

### CB-GPS: Ubicación brinca por error GPS

**Escenario:** El camión está en Sabinas Hidalgo (NL), pero el GPS reporta momentáneamente coordenadas en Oaxaca por error de triangulación.

```
Regla DED-06 (Anti-teleport):
  SI  distancia(nuevo.location, último_evento_visible.location) > 300 km
    Y (ahora - último_evento_visible.timestamp) < 120 min
  ENTONCES  → DESCARTAR + log WARN "GPS teleport detected"

  JUSTIFICACIÓN:
    - A 100 km/h, un camión recorre máximo 200 km en 2h
    - Si la distancia > 300 km en < 2h, es imposible por carretera
    - Umbral de 300 km (no 200) por tolerancia a rutas indirectas
```

**Parámetros:**
- `MAX_TELEPORT_KM = 300`
- `TELEPORT_WINDOW_MIN = 120`
- No configurable por operación (es protección del sistema, no regla de negocio)

### CB-SPAM: Operador actualiza demasiado seguido

**Escenario:** El botón "Forzar Sincronización" se presiona 20 veces en 1 minuto.

```
Protecciones actuales (ya implementadas):
  1. geohash cache  → mismas coordenadas = cache hit (0ms, no API call)
  2. Nominatim throttle → máximo 1 req/s (ya en trackingGeo.service.ts)
  3. cooldown 30 min → el pipeline DED-02 descarta si no han pasado 30 min

Protección adicional sugerida:
  DED-07 (UI debounce):
    - Deshabilitar botón "Forzar Sincronización" por 30 segundos después de click
    - Mostrar countdown en el botón: "Sincronizar (28s)"
    - Es UI-only, no lógica de negocio

  DED-08 (Backend futuro):
    - Rate limit por tenant: máximo 10 syncs/hora
    - Si excede: HTTP 429 + "Se alcanzó el límite de sincronizaciones. Intente en {N} minutos."
```

### CB-RETURN: Camión retrocede

```
Modo auto:
  - El retroceso SE reporta. Si el camión vuelve a Sabinas Hidalgo
    después de haber pasado por Ciénega de Flores, se genera un nuevo
    evento "En camino: Sabinas Hidalgo" (cooldown permitiendo).
  - Es correcto: refleja la realidad operativa (desvío, regreso por carga).

Modo checkpoints:
  - Un checkpoint ya alcanzado NO se re-reporta (hitCheckpoints Set).
  - El retroceso se ignora silenciosamente salvo que genere un `exception`.
```

### CB-BORDER: Cruce de frontera

```
Regla DED-09:
  SI  nuevo.countryCode ≠ último_evento_visible.countryCode
  ENTONCES  → SIEMPRE crear evento, aunque municipio sea igual
            → Ignorar cooldown para este caso específico
            → Label: "Cruce fronterizo: {municipality}, {state} ({countryCode})"
```

### CB-STALE: Orden ya no está en `in_transit`

```
Regla DED-10:
  SI  orden.status ∉ ['in_transit']
  ENTONCES  → DESCARTAR silenciosamente
  
  Estados que bloquean generación:
    draft, confirmed, at_origin, in_customs, delivered, cancelled

  Estados que permiten generación:
    in_transit (único)
```

---

## 5. Resumen de Reglas

| Código | Regla | Prioridad | Capa |
|--------|-------|:---------:|------|
| **DED-01** | No repetir municipio consecutivo | Alta | Pipeline |
| **DED-02** | Cooldown 30 min (configurable) | Alta | Pipeline |
| **DED-03** | Distancia mínima 5 km | Media | Pipeline |
| **DED-04** | Checkpoints: solo municipios listados | Media | Pipeline (solo modo checkpoints) |
| **DED-05** | Geocode falla: evento silencioso | Alta | Geocoding |
| **DED-06** | Anti-teleport: >300 km en <2h | Alta | Pipeline |
| **DED-07** | UI debounce: 30s entre clicks de sync | Baja | UI |
| **DED-08** | Rate limit tenant: 10 syncs/hora | Baja | Backend futuro |
| **DED-09** | Cruce fronterizo: bypass cooldown | Media | Pipeline |
| **DED-10** | Solo generar si orden en `in_transit` | Alta | Pre-pipeline |

---

## 6. Cambios Sugeridos al Código Existente

### 6.1 `src/constants/states.ts` — TRACKING_DEFAULTS

| Campo actual | Valor actual | Cambio | Nuevo valor |
|-------------|:--:|---|:--:|
| `cooldownMinutes` | 15 | Incrementar a 30 | **30** |

**Nuevo campo sugerido:**

```typescript
/** Mínima distancia (km) entre 2 eventos para considerarlo avance real (DED-03) */
minDistanceKm: 5,
/** Distancia máxima plausible en ventana de tiempo (anti-teleport DED-06) */
maxTeleportKm: 300,
/** Ventana de tiempo para validar teleport, en minutos (DED-06) */
teleportWindowMinutes: 120,
/** Debounce del botón de sync en la UI, en segundos (DED-07) */
syncDebounceSeconds: 30,
```

### 6.2 `src/services/trackingGeo.service.ts` — Nuevas funciones

| Función | Propósito | Cambio |
|---------|-----------|--------|
| `hasMunicipalityChanged()` | Ya existe (L195-203) | **Agregar** check de `countryCode` (DED-09) |
| `haversineKm()` | Cálculo de distancia entre 2 GeoPoints | **Nueva** export |
| `isTeleport()` | Detecta salto imposible de GPS (DED-06) | **Nueva** export |
| `shouldCreateEvent()` | Orquesta todas las reglas DED-01..06 en un pipeline | **Nueva** export (función pura, recibe estado previo + nuevo update) |

### 6.3 `src/types/tracking.ts` — TrackingRuleConfig

Campos nuevos opcionales:

```typescript
export interface TrackingRuleConfig {
    mode: 'auto' | 'checkpoints';
    cooldownMinutes: number;
    checkpoints?: Place[];
    geocodeProvider: 'nominatim' | 'google' | 'mapbox';
    maxRetries: number;
    /** DED-03: Min distance (km) to consider movement valid. Default 5. */
    minDistanceKm?: number;
    /** DED-06: Max plausible distance (km) in teleport window. Default 300. */
    maxTeleportKm?: number;
}
```

### 6.4 `src/pages/TrackingPage.tsx` — UI debounce (DED-07)

Agregar un `useState<number>` con countdown de 30s que deshabilita el botón tras click. No es lógica de negocio, es UX.

---

## 7. Escenario End-to-End: Laredo → Monterrey

```
Hora    GPS lat/lng          Geocode result              Pipeline          Resultado
────────────────────────────────────────────────────────────────────────────────────
10:00   27.48, -99.51        Nuevo Laredo, Tam           DED-10: in_transit ✅
                                                         (primer evento)    → CREAR departure

10:15   27.20, -99.60        Nuevo Laredo, Tam           DED-01: mismo mun  → DESCARTAR

10:35   26.80, -100.05       Lampazos, N.L.              DED-02: <30min      → DESCARTAR
                                                         (10:35 - 10:00 = 35min… ok)
                                                         DED-03: ~85 km ✅
                                                         DED-01: diferente ✅
                                                         DED-02: 35 min ✅   → CREAR in_transit

11:10   26.50, -100.18       Sabinas Hidalgo, N.L.       DED-03: ~35 km ✅
                                                         DED-01: diferente ✅
                                                         DED-02: 35 min ✅   → CREAR in_transit

11:15   26.48, -100.17       Sabinas Hidalgo, N.L.       DED-01: mismo mun  → DESCARTAR

11:45   26.10, -100.20       Ciénega de Flores, N.L.     DED-03: ~45 km ✅
                                                         DED-01: diferente ✅
                                                         DED-02: 35 min ✅   → CREAR in_transit

12:05   25.96, -100.17       General Escobedo, N.L.      DED-02: 20min <30  → DESCARTAR
                                                         (12:05 - 11:45 = 20m)

12:20   25.67, -100.32       Monterrey, N.L.             DED-02: 35 min ✅  → CREAR arrival

Timeline público resultante (5 entradas):
  ✓ Salida de Almacén — Nuevo Laredo, Tamaulipas · 10:00
  ✓ En camino — Lampazos, Nuevo León · 10:35
  ✓ En camino — Sabinas Hidalgo, Nuevo León · 11:10
  ✓ En camino — Ciénega de Flores, Nuevo León · 11:45
  ● Llegada — Monterrey, Nuevo León · 12:20
```

**Resultado:** 5 entradas limpias en 2h20m. Sin ruido. Sin repeticiones. Cada entrada representa un avance geográfico real.
