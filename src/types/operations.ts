import type { BadgeVariant } from './common';

export type OperationStatus = 'draft' | 'planned' | 'assigned' | 'in_transit' | 'delivered' | 'cancelled' | 'closed';

export interface Operation {
    id: string; // The visual ID, e.g. OP-8492
    db_id?: string; // The real DB UUID, needed for RPC calls
    client: string;
    type: string;
    status: OperationStatus | string;
    route: string;
    owner: string;
    variant: BadgeVariant;

    // Hardening assignment fields
    driver_id?: string;
    vehicle_id?: string;
    driver_name?: string;
    vehicle_ref?: string;
    planned_departure?: string;
    priority?: 'low' | 'normal' | 'high' | string;
    required_documents?: any[];
}

export interface TimelineStep {
    time: string;
    event: string;
    desc: string;
    done?: boolean;
    current?: boolean;
    future?: boolean;
}
