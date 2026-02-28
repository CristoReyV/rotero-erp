import type { BadgeVariant } from './common';

export interface Place {
    municipality: string;
    state: string;
    countryCode: 'MX' | 'US';
}

export interface GeoPoint {
    lat: number;
    lng: number;
}

export type TrackingEventType =
    | 'departure'
    | 'in_transit'
    | 'customs_entry'
    | 'customs_exit'
    | 'arrival'
    | 'delivered'
    | 'exception';

export interface TrackingEvent {
    id: string;
    orderId: string;
    eventType: TrackingEventType;
    location: GeoPoint;
    place: Place | null;
    timestamp: string; // ISO 8601 UTC
    source: 'gps' | 'manual' | 'system';
    note?: string;
}

export interface TrackingRuleConfig {
    mode: 'auto' | 'checkpoints';
    /**
     * Cooldown entre eventos "En camino".
     * Recomendado: 30 min para logística terrestre MX.
     * Justificación: en autopista se cruzan municipios cada ~25-40 km.
     * A 80-100 km/h, 30 min garantiza al menos 35 km de distancia entre eventos,
     * eliminando duplicados por fluctuación GPS sin perder granularidad real.
     */
    cooldownMinutes: number;
    /**
     * Distancia mínima (en km) entre dos actualizaciones GPS para considerarlas distintas.
     * Default: 2 km. Por debajo de este umbral + mismo municipio = descartar.
     */
    minDistanceKm: number;
    checkpoints?: Place[];
    geocodeProvider: 'nominatim' | 'google' | 'mapbox';
    maxRetries: number;
}

export type TrackingLinkState = 'active' | 'soft_expired' | 'hard_expired' | 'revoked';

export interface TrackingLink {
    id: string;
    orderId: string;
    token: string;
    state: TrackingLinkState;
    expiresAt: string; // ISO 8601 UTC
    createdAt: string; // ISO 8601 UTC
    lastAccessedAt?: string;
    /** ISO 8601 UTC. Set when operator revokes the link. Irreversible (REV-01). */
    revokedAt?: string;
    /** UUID of the user who revoked. For audit trail (REV-04). */
    revokedBy?: string;
}

export interface PublicTrackingResponse {
    status: 'success' | 'soft_expired' | 'hard_expired' | 'revoked' | 'not_found';
    data?: PublicTrackingView;
}

export interface PublicTimelineEvent {
    /** Ordinal index (e.g. 'evt-1'), NOT the database ID. Never expose TrackingEvent.id here. */
    id: string;
    title: string;
    subtitle: string;
    timestamp: string;
    status: 'done' | 'current' | 'future';
    icon: string;
}

export interface PublicTrackingView {
    orderRef: string;
    route: string;
    currentStatus: string;
    events: PublicTimelineEvent[];
    eta?: string;
    /**
     * Last known location for the public map marker.
     * SECURITY (GEO-01): Must be rounded to 2 decimal places (~1.1 km precision).
     * SECURITY (GEO-03): Must be omitted when order status is 'delivered'.
     * SECURITY (GEO-04): Must be omitted when place is null (geocode failed).
     */
    currentLocation?: GeoPoint;
    /** Route v1: GEO-01 ofuscated route points (rounded ~1.1km, max 200) */
    routePoints?: GeoPoint[];
}

/** A GPS breadcrumb recorded during driver tracking. */
export interface RoutePoint {
    lat: number;
    lng: number;
    recorded_at: string;
    accuracy_m?: number;
    source: 'gps' | 'network';
}

export interface DriverView {
    orderRef: string;
    route: string;
    currentStatus: 'assigned' | 'in_transit' | 'at_destination' | 'delivered';
    eta?: string;
    clientName: string;
    destinationCity: string;
    lastEvent?: {
        municipality: string;
        timestamp: string;
    };
}

export interface DriverTrackingResponse {
    status: 'success' | 'expired' | 'revoked' | 'not_found';
    data?: DriverView;
}

export interface DriverEventPayload {
    driverToken: string;
    action: 'departure' | 'in_transit' | 'arrival' | 'delivered' | 'incident';
    location?: {
        lat: number;
        lng: number;
        accuracy?: number;
        source: 'gps' | 'manual' | 'none';
    };
    manualPlace?: {
        municipality: string;
        state: string;
    };
    incident?: {
        type: string;
        note?: string;
    };
    clientTimestamp: string;
    offlineQueued?: boolean;
}

export const DRIVER_ORDER_STATES = {
    assigned: { label: 'Asignado', badge: 'default', icon: 'clipboard' },
    in_transit: { label: 'En Ruta', badge: 'info', icon: 'truck' },
    at_destination: { label: 'En Destino', badge: 'warning', icon: 'map-pin' },
    delivered: { label: 'Entregado', badge: 'success', icon: 'check-circle' },
} as const;

export const INCIDENT_TYPES = {
    customs_delay: { label: 'Retraso en aduana' },
    mechanical: { label: 'Avería mecánica' },
    accident: { label: 'Accidente' },
    road_closure: { label: 'Cierre de carretera' },
    other: { label: 'Otro' },
} as const;

export const DRIVER_ANTI_NOISE = {
    cooldownMinutes: 30,
    minDistanceKm: 2,
    maxInTransitPerTrip: 15,
    incidentCooldownMinutes: 10,
    gpsTimeoutMs: 15_000,
    minAccuracyMeters: 5_000,
    warnAccuracyMeters: 500,
    debounceMs: 3_000,
    offlineQueueMax: 10,
    offlineEventTTLHours: 4,
    offlineMaxRetries: 5,
} as const;
