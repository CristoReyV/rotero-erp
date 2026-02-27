import type { BadgeVariant } from '@/types/common';

/**
 * State definitions per Architecture §3.1
 * Each state has: code (key), label (display), badge (variant color).
 * Transitions documented as comments — enforcement is server-side (RN-08).
 */

// --- Operations (Orders) ---
// Transitions: draft → confirmed|cancelled, confirmed → planned|cancelled,
// planned → loading|cancelled, loading → dispatched, dispatched → in_transit,
// in_transit → in_customs|delivered, in_customs → in_transit,
// delivered → invoiced, invoiced → collected
export const ORDER_STATES = {
    draft: { label: 'Borrador', badge: 'default' as BadgeVariant },
    confirmed: { label: 'Confirmada', badge: 'info' as BadgeVariant },
    planned: { label: 'Planificada', badge: 'info' as BadgeVariant },
    loading: { label: 'En Carga', badge: 'warning' as BadgeVariant },
    dispatched: { label: 'Despachada', badge: 'warning' as BadgeVariant },
    in_transit: { label: 'En Tránsito', badge: 'info' as BadgeVariant },
    in_customs: { label: 'En Aduana', badge: 'warning' as BadgeVariant },
    delivered: { label: 'Entregada', badge: 'success' as BadgeVariant },
    invoiced: { label: 'Facturada', badge: 'success' as BadgeVariant },
    collected: { label: 'Cobrada', badge: 'success' as BadgeVariant },
    cancelled: { label: 'Cancelada', badge: 'danger' as BadgeVariant },
} as const;

// --- Billing (CFDI) ---
// Transitions: draft → pending_stamp, pending_stamp → stamped|error,
// stamped → sent|cancelled, sent → paid|cancelled, error → pending_stamp
export const CFDI_STATES = {
    draft: { label: 'Borrador', badge: 'default' as BadgeVariant },
    pending_stamp: { label: 'Pendiente de Timbrado', badge: 'warning' as BadgeVariant },
    stamped: { label: 'Timbrado', badge: 'success' as BadgeVariant },
    sent: { label: 'Enviado', badge: 'info' as BadgeVariant },
    error: { label: 'Error', badge: 'danger' as BadgeVariant },
    paid: { label: 'Pagado', badge: 'success' as BadgeVariant },
    cancelled: { label: 'Cancelado', badge: 'danger' as BadgeVariant },
} as const;

// --- Customs (Pedimentos / Anexo 24) ---
// Transitions: registered → active, active → audited|closed,
// audited → active|closed
export const PEDIMENTO_STATES = {
    registered: { label: 'Registrado', badge: 'default' as BadgeVariant },
    active: { label: 'Activo', badge: 'info' as BadgeVariant },
    audited: { label: 'Auditado', badge: 'warning' as BadgeVariant },
    closed: { label: 'Cerrado', badge: 'success' as BadgeVariant },
    expired: { label: 'Vencido', badge: 'danger' as BadgeVariant },
} as const;

// --- CRM (Opportunities) ---
// Transitions: prospect → qualified|archived, qualified → quoting|archived,
// quoting → negotiation|archived, negotiation → won|lost,
// archived → prospect (reactivate)
export const CRM_STATES = {
    prospect: { label: 'Prospecto', badge: 'default' as BadgeVariant },
    qualified: { label: 'Calificado', badge: 'info' as BadgeVariant },
    quoting: { label: 'Cotización', badge: 'info' as BadgeVariant },
    negotiation: { label: 'Negociación', badge: 'warning' as BadgeVariant },
    won: { label: 'Ganado', badge: 'success' as BadgeVariant },
    lost: { label: 'Perdido', badge: 'danger' as BadgeVariant },
    archived: { label: 'Archivado', badge: 'default' as BadgeVariant },
} as const;

// --- Finance (CxC) ---
// Transitions: pending → partial|paid|overdue, partial → paid|overdue,
// overdue → partial|paid|written_off
export const FINANCE_STATES = {
    pending: { label: 'Por Cobrar', badge: 'warning' as BadgeVariant },
    partial: { label: 'Parcial', badge: 'info' as BadgeVariant },
    overdue: { label: 'Vencida', badge: 'danger' as BadgeVariant },
    paid: { label: 'Pagada', badge: 'success' as BadgeVariant },
    written_off: { label: 'Castigada', badge: 'danger' as BadgeVariant },
} as const;

// --- Tracking Events ---
export const TRACKING_EVENT_TYPES = {
    departure: { label: 'Salida de Almacén', badge: 'info' as BadgeVariant, icon: 'truck' },
    in_transit: { label: 'En Camino', badge: 'info' as BadgeVariant, icon: 'map-pin' },
    customs_entry: { label: 'Ingreso a Aduana', badge: 'warning' as BadgeVariant, icon: 'shield' },
    customs_exit: { label: 'Liberado de Aduana', badge: 'success' as BadgeVariant, icon: 'shield-check' },
    arrival: { label: 'Llegada a Destino', badge: 'success' as BadgeVariant, icon: 'flag' },
    delivered: { label: 'Entregado', badge: 'success' as BadgeVariant, icon: 'check-circle' },
    exception: { label: 'Incidencia', badge: 'danger' as BadgeVariant, icon: 'alert-triangle' },
} as const;

// --- Tracking Defaults ---
export const TRACKING_DEFAULTS = {
    cooldownMinutes: 15,
    maxPublicEvents: 12,
    linkExpirationDays: 7,
    linkMaxExpirationDays: 30,
    postDeliveryVisibilityHours: 48,
    rateLimitPerMinute: 60,
    geocodeMaxRetries: 3,
    /** Rotate IP hash salt every N hours to prevent cross-day tracking (AUD) */
    tokenHashSaltRotationHours: 24,
    /** Block IP after N failed token lookups in 5 min (AUD-01) */
    bruteForceThreshold: 10,
} as const;

// --- Tracking Link Status ---
export const TRACKING_LINK_STATES = {
    active: { label: 'Activo', badge: 'success' as BadgeVariant },
    soft_expired: { label: 'Vencido', badge: 'warning' as BadgeVariant },
    hard_expired: { label: 'Expirado', badge: 'default' as BadgeVariant },
    revoked: { label: 'Revocado', badge: 'danger' as BadgeVariant },
} as const;
