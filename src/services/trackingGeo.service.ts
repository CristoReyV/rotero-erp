/**
 * trackingGeo.service.ts
 * ---------------------
 * Servicio de reverse geocoding para Tracking Opción A.
 *
 * Estrategia:
 *  1. Caché por geohash: se redondean lat/lng a ~1 km² (3 decimales).
 *     Si ya se resolvió un punto cercano, se reutiliza el resultado.
 *  2. Throttle: máximo 1 petición por segundo (Nominatim TOS).
 *  3. Proveedor: Nominatim (OSM) para dev, proxy-ready para producción.
 *  4. Fallback: si falla, retorna null (UI muestra "Ubicación actualizada").
 *
 * IMPORTANTE:
 *  - No se exponen API keys. Nominatim es gratis y sin key.
 *  - Para Google Geocoding en producción se debe crear un proxy backend
 *    (Supabase Edge Function o Netlify Function) que guarde la key en env.
 */

import type { Place, GeoPoint } from '@/types/tracking';

// ---------------------------------------------------------------------------
// 1) Geohash / Rounding cache
// ---------------------------------------------------------------------------

/**
 * Genera una clave de caché redondeando lat/lng a 3 decimales (~111m precisión).
 * Dos puntos dentro del mismo cuadrante de ~111m comparten clave.
 */
function toGeoCacheKey(point: GeoPoint): string {
    const latRounded = point.lat.toFixed(3);
    const lngRounded = point.lng.toFixed(3);
    return `${latRounded},${lngRounded}`;
}

/** Caché en memoria: Map<geoCacheKey, Place | null> */
const geoCache = new Map<string, Place | null>();

/** Tiempo de vida del caché: 30 minutos */
const CACHE_TTL_MS = 30 * 60 * 1000;

/** Timestamps de cuándo se guardó cada entrada */
const cacheTimes = new Map<string, number>();

function getCachedPlace(key: string): Place | null | undefined {
    const time = cacheTimes.get(key);
    if (time && Date.now() - time > CACHE_TTL_MS) {
        geoCache.delete(key);
        cacheTimes.delete(key);
        return undefined; // expired
    }
    return geoCache.has(key) ? geoCache.get(key)! : undefined;
}

function setCachedPlace(key: string, place: Place | null): void {
    geoCache.set(key, place);
    cacheTimes.set(key, Date.now());
}

// ---------------------------------------------------------------------------
// 2) Throttle
// ---------------------------------------------------------------------------

let lastRequestTime = 0;
const MIN_INTERVAL_MS = 1100; // 1.1s para respetar Nominatim 1 req/s

function waitForThrottle(): Promise<void> {
    const elapsed = Date.now() - lastRequestTime;
    if (elapsed >= MIN_INTERVAL_MS) return Promise.resolve();
    return new Promise((resolve) => setTimeout(resolve, MIN_INTERVAL_MS - elapsed));
}

// ---------------------------------------------------------------------------
// 3) Provider: Nominatim (dev/MVP)
// ---------------------------------------------------------------------------

interface NominatimResponse {
    address?: {
        city?: string;
        town?: string;
        county?: string;
        municipality?: string;
        state?: string;
        country_code?: string;
    };
}

/**
 * Llama a Nominatim reverse geocoding.
 * Extrae municipality y state del response.
 *
 * Campos de Nominatim para México:
 *  - municipality: address.city || address.town || address.county || address.municipality
 *  - state: address.state
 *  - countryCode: address.country_code (2-letter, uppercase)
 */
async function nominatimReverse(point: GeoPoint): Promise<Place | null> {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.lat}&lon=${point.lng}&zoom=10&addressdetails=1&accept-language=es`;

    const res = await fetch(url, {
        headers: {
            // Nominatim TOS: provide a valid User-Agent
            'User-Agent': 'RoteroERP/1.0 (tracking-module)',
        },
    });

    if (!res.ok) return null;

    const data: NominatimResponse = await res.json();

    if (!data.address) return null;

    const municipality =
        data.address.city ||
        data.address.town ||
        data.address.municipality ||
        data.address.county ||
        '';

    const state = data.address.state || '';
    const countryCode = (data.address.country_code || 'mx').toUpperCase() as 'MX' | 'US';

    if (!municipality && !state) return null;

    return {
        municipality: toTitleCase(municipality),
        state: toTitleCase(state),
        countryCode,
    };
}

// ---------------------------------------------------------------------------
// 4) Title Case helper (normalización de nombres)
// ---------------------------------------------------------------------------

function toTitleCase(str: string): string {
    return str
        .toLowerCase()
        .split(' ')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' ');
}

// ---------------------------------------------------------------------------
// 5) Exported API
// ---------------------------------------------------------------------------

export interface ReverseGeocodeResult {
    place: Place | null;
    fromCache: boolean;
    error?: string;
}

/**
 * Resuelve un par lat/lng a Place { municipality, state, countryCode }.
 *
 * Flujo:
 *  1. Buscar en caché (por geohash redondeado).
 *  2. Si no está, esperar throttle y llamar Nominatim.
 *  3. Guardar en caché.
 *  4. Si falla, retornar place: null con error descriptivo.
 */
export async function reverseGeocode(point: GeoPoint): Promise<ReverseGeocodeResult> {
    const key = toGeoCacheKey(point);

    // 1. Cache hit?
    const cached = getCachedPlace(key);
    if (cached !== undefined) {
        return { place: cached, fromCache: true };
    }

    // 2. Throttle
    try {
        await waitForThrottle();
        lastRequestTime = Date.now();

        // 3. Call provider
        const place = await nominatimReverse(point);

        // 4. Cache result (even nulls to avoid re-fetching failed lookups)
        setCachedPlace(key, place);

        return { place, fromCache: false };
    } catch (err) {
        const message = err instanceof Error ? err.message : 'Error desconocido';
        // Cache null so we don't hammer the API on repeated failures
        setCachedPlace(key, null);
        return { place: null, fromCache: false, error: message };
    }
}

/**
 * Compara dos Places y determina si el municipio cambió.
 * Útil para decidir si generar un nuevo evento "En camino".
 */
export function hasMunicipalityChanged(
    previous: Place | null,
    current: Place | null
): boolean {
    if (!previous || !current) return true; // Si no hay referencia, siempre es "nuevo"
    return (
        previous.municipality !== current.municipality ||
        previous.state !== current.state
    );
}

/**
 * Limpia el caché de geocoding.
 * Útil para testing o para forzar re-fetch.
 */
export function clearGeoCache(): void {
    geoCache.clear();
    cacheTimes.clear();
}

/**
 * Devuelve estadísticas del caché para debugging.
 */
export function getGeoCacheStats(): { entries: number; keys: string[] } {
    return {
        entries: geoCache.size,
        keys: Array.from(geoCache.keys()),
    };
}

// ---------------------------------------------------------------------------
// 6) Deduplication & Event Gate
// ---------------------------------------------------------------------------

import type { TrackingRuleConfig } from '@/types/tracking';

/**
 * DEFAULT_RULE_CONFIG — Configuración operativa por defecto.
 *
 * cooldownMinutes = 30:
 *   En autopista MX/US se cruzan municipios cada 25-40 km.
 *   A 80-100 km/h, 30 min ≈ 40-50 km entre eventos.
 *   Evita duplicados por fluctuación GPS sin perder granularidad real.
 *   Valor < 15 min genera ruido en zonas urbanas densas.
 *   Valor > 45 min puede omitir municipios breves en rutas menores.
 *
 * minDistanceKm = 2:
 *   Umbral de "salto GPS espurio". GPS doméstico fluctúa ±50-200m.
 *   2 km garantiza que la señal se alejó realmente del punto anterior.
 */
export const DEFAULT_RULE_CONFIG: TrackingRuleConfig = {
    mode: 'auto',
    cooldownMinutes: 30,
    minDistanceKm: 2,
    geocodeProvider: 'nominatim',
    maxRetries: 3,
};

/**
 * Calcula la distancia en kilómetros entre dos puntos GPS usando la fórmula de Haversine.
 *
 * Suficientemente precisa para las escalas de logística terrestre (errores < 0.3% en
 * distancias < 500 km). No requiere ninguna dependencia externa.
 *
 * @example
 *   haversineDistanceKm({ lat: 25.67, lng: -100.31 }, { lat: 25.70, lng: -100.35 }) → ~4.2
 */
export function haversineDistanceKm(a: GeoPoint, b: GeoPoint): number {
    const R = 6371; // Radio de la Tierra en km
    const toRad = (deg: number) => (deg * Math.PI) / 180;

    const dLat = toRad(b.lat - a.lat);
    const dLng = toRad(b.lng - a.lng);

    const sinDLat = Math.sin(dLat / 2);
    const sinDLng = Math.sin(dLng / 2);

    const hav =
        sinDLat * sinDLat +
        Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinDLng * sinDLng;

    return R * 2 * Math.asin(Math.sqrt(hav));
}

/** Parámetros para la función de decisión de eventos. */
export interface ShouldGenerateEventParams {
    /** Coordenadas de la actualización GPS entrante. */
    incomingLocation: GeoPoint;
    /** Municipio/estado resuelto para `incomingLocation`. */
    incomingPlace: Place | null;
    /** Último `GeoPoint` registrado (puede ser null si es el primer evento). */
    lastLocation: GeoPoint | null;
    /** Último `Place` registrado. */
    lastPlace: Place | null;
    /** Timestamp ISO del último evento generado (para calcular cooldown). */
    lastEventAt: string | null;
    /** Configuración de reglas activa para esta operación. */
    config?: Partial<TrackingRuleConfig>;
}

/**
 * `shouldGenerateEvent` — Puerta única de deduplicación.
 *
 * Aplica las siguientes reglas **en orden** (cualquiera puede descartar):
 *
 * | # | Regla            | Condición de descarte                                                  |
 * |---|------------------|------------------------------------------------------------------------|
 * | 1 | Anti-duplicado   | `incomingPlace` == `lastPlace` (mismo municipality + state)            |
 * | 2 | Anti-salto GPS   | distancia < `minDistanceKm` Y municipio NO cambió                      |
 * | 3 | Cooldown         | tiempo desde `lastEventAt` < `cooldownMinutes`                         |
 * | 4 | Checkpoints      | modo checkpoints Y `incomingPlace` no está en la lista predefinida     |
 *
 * Si `incomingPlace` es null, retorna `false` siempre (VIS-06: no exponer).
 *
 * @returns `true` si se debe crear un evento "En camino", `false` para descartar.
 */
export function shouldGenerateEvent(params: ShouldGenerateEventParams): boolean {
    const {
        incomingLocation,
        incomingPlace,
        lastLocation,
        lastPlace,
        lastEventAt,
        config: configOverride = {},
    } = params;

    const config: TrackingRuleConfig = { ...DEFAULT_RULE_CONFIG, ...configOverride };

    // VIS-06: place null → nunca visible en público
    if (!incomingPlace) return false;

    // Regla 1: Anti-duplicado municipio consecutivo
    if (!hasMunicipalityChanged(lastPlace, incomingPlace)) return false;

    // Regla 2: Anti-salto GPS (solo aplica si el municipio no cambió,
    //          pero como la Regla 1 ya descartó el "mismo municipio",
    //          aquí cubrimos el caso "municipio distinto pero distancia insignificante"
    //          que puede ocurrir en bordes de municipio con GPS ruidoso)
    if (lastLocation) {
        const distanceKm = haversineDistanceKm(lastLocation, incomingLocation);
        if (distanceKm < config.minDistanceKm) {
            // En bordes de municipio con GPS ruidoso: descartar si la distancia
            // no justifica un cambio real
            return false;
        }
    }

    // Regla 3: Cooldown
    if (lastEventAt) {
        const minutesSinceLast = (Date.now() - new Date(lastEventAt).getTime()) / 60_000;
        if (minutesSinceLast < config.cooldownMinutes) return false;
    }

    // Regla 4: Modo checkpoints
    if (config.mode === 'checkpoints' && config.checkpoints?.length) {
        const isInCheckpoint = config.checkpoints.some(
            (cp) =>
                cp.municipality === incomingPlace.municipality &&
                cp.state === incomingPlace.state
        );
        if (!isInCheckpoint) return false;
    }

    return true;
}
