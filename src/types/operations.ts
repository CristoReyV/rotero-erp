import type { BadgeVariant } from './common';

export interface Operation {
    id: string; // The visual ID, e.g. OP-8492
    db_id?: string; // The real DB UUID, needed for RPC calls
    client: string;
    type: string;
    status: string;
    route: string;
    owner: string;
    variant: BadgeVariant;
}

export interface TimelineStep {
    time: string;
    event: string;
    desc: string;
    done?: boolean;
    current?: boolean;
    future?: boolean;
}
