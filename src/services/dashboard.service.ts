import { supabase } from '@/lib/supabase';
import type { DashboardOverview, DashboardOperation, FiscalAlert } from '@/types/dashboard';
import type { BadgeVariant } from '@/types/common';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

const statusToVariant = (status: string): BadgeVariant => {
    const s = status.toLowerCase();
    if (s.includes('transit') || s.includes('progreso')) return 'info';
    if (s.includes('delivered') || s.includes('entregado')) return 'success';
    if (s.includes('pending') || s.includes('pendiente') || s.includes('aduanal')) return 'warning';
    return 'default';
};

const mapStatusToText = (status: string) => {
    switch (status) {
        case 'in_transit': return 'En Tránsito';
        case 'delivered': return 'Entregado';
        case 'pending': return 'Pendiente';
        case 'maintenance': return 'Mantenimiento';
        default: return status;
    }
};

export async function getDashboardOverview(tenantId: string, startDate?: Date, endDate?: Date): Promise<DashboardOverview> {
    if (USE_MOCKS) {
        const { mockChartData, mockChartLabels } = await import('@/mocks/dashboard.mock');
        return {
            kpis: {
                ops_total: 125,
                ops_in_transit: 12,
                billing_total: 1200000,
                inventory_value: 4800000
            },
            chart: {
                data: mockChartData,
                labels: mockChartLabels
            }
        };
    }

    const { data, error } = await supabase.rpc('rpc_dashboard_overview', {
        p_tenant_id: tenantId,
        p_start_date: startDate ? startDate.toISOString() : null,
        p_end_date: endDate ? endDate.toISOString() : null
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as DashboardOverview;
}

export async function getDashboardRecentActivity(tenantId: string, startDate?: Date, endDate?: Date): Promise<DashboardOperation[]> {
    if (USE_MOCKS) {
        const { getMockDashboardOperations } = await import('@/mocks/dashboard.mock');
        return getMockDashboardOperations();
    }

    const { data, error } = await supabase.rpc('rpc_dashboard_recent_activity', {
        p_tenant_id: tenantId,
        p_start_date: startDate ? startDate.toISOString() : null,
        p_end_date: endDate ? endDate.toISOString() : null
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return (data || []).map((dbOp: any) => ({
        id: dbOp.id,
        client: dbOp.client,
        status: mapStatusToText(dbOp.status),
        route: dbOp.route,
        eta: dbOp.eta,
        variant: statusToVariant(dbOp.status)
    }));
}

export async function getDashboardAlerts(tenantId: string, startDate?: Date, endDate?: Date): Promise<FiscalAlert[]> {
    if (USE_MOCKS) {
        const { getMockFiscalAlerts } = await import('@/mocks/dashboard.mock');
        return getMockFiscalAlerts();
    }

    const { data, error } = await supabase.rpc('rpc_dashboard_alerts', {
        p_tenant_id: tenantId,
        p_start_date: startDate ? startDate.toISOString() : null,
        p_end_date: endDate ? endDate.toISOString() : null
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as FiscalAlert[];
}
