import type { BadgeVariant } from '@/types/common';
import type { Place } from '@/types/tracking';
import type { Operation } from '@/types/operations';

export interface DbOperation extends Record<string, unknown> {
    id: string;
    tenant_id?: string;
    reference_code: string;
    route_summary: string | null;
    client_display_name: string | null;
    destination_city: string | null;
    eta_display: string | null;
    status: string;
    created_at: string;
    eta: string | null;
    origin_place: Place | null;
    destination_place: Place | null;
}

function mapStatusToVariant(status: string): BadgeVariant {
    if (status === 'planned') return 'warning';
    if (status === 'assigned' || status === 'in_transit') return 'info';
    if (status === 'delivered') return 'success';
    if (status === 'cancelled') return 'danger';
    return 'default';
}

export function mapDbOperationToUI(dbOp: DbOperation): Operation {
    const record = dbOp as unknown as Operation;
    return {
        ...record,
        id: dbOp.reference_code,
        db_id: dbOp.id,
        client: dbOp.client_display_name || 'Datos por confirmar',
        type: (dbOp.service_type as string | null) || dbOp.route_summary || 'Servicio por confirmar',
        status: dbOp.status,
        route: dbOp.route_summary || dbOp.destination_city || 'Ruta por confirmar',
        owner: (dbOp.provider_name as string | null) || 'Proveedor por confirmar',
        variant: mapStatusToVariant(dbOp.status),
    };
}
