import type { BadgeVariant } from './common';

export interface DashboardOperation {
    id: string; // Used for "Referencia"
    client: string;
    status: string;
    route: string;
    eta: string;
    variant: BadgeVariant;
}

export interface FiscalAlert {
    type: 'danger' | 'warning' | 'info';
    title: string;
    description: string;
}

export interface DashboardOverview {
    kpis: {
        ops_total: number;
        ops_in_transit: number;
        billing_total: number;
        inventory_value: number;
    };
    chart: {
        data: number[];
        labels: string[];
    };
}
