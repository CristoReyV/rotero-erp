import { supabase } from '@/lib/supabase';
import type {
    ReportModuleDef,
    ReportConfig,
    ReportsFinancialSummary,
    ReportsPipelineSummary,
    ReportsInventorySummary,
    ReportsOperationsSummary
} from '@/types/reports';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export async function getReportModules(): Promise<ReportModuleDef[]> {
    if (USE_MOCKS) {
        const { getMockReportsModules } = await import('@/mocks/reports.mock');
        return getMockReportsModules();
    }
    // Static modules placeholder for now
    return [
        { name: 'Operaciones', iconName: 'TrendingUp', count: 4, color: 'bg-blue-50 text-blue-600' },
        { name: 'Inventario', iconName: 'BarChart3', count: 3, color: 'bg-emerald-50 text-emerald-600' },
        { name: 'Fiscal / CFDI', iconName: 'FileText', count: 5, color: 'bg-amber-50 text-amber-600' },
        { name: 'Rentabilidad', iconName: 'PieChart', count: 2, color: 'bg-purple-50 text-purple-600' },
    ];
}

export async function getFinancialSummary(tenantId: string): Promise<ReportsFinancialSummary> {
    if (USE_MOCKS) {
        const { getMockFinancialSummary } = await import('@/mocks/reports.mock');
        return getMockFinancialSummary();
    }

    const { data, error } = await supabase.rpc('rpc_reports_financial_summary', { p_tenant_id: tenantId, p_period: 'monthly' });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as ReportsFinancialSummary;
}

export async function getPipelineSummary(tenantId: string): Promise<ReportsPipelineSummary> {
    if (USE_MOCKS) {
        const { getMockPipelineSummary } = await import('@/mocks/reports.mock');
        return getMockPipelineSummary();
    }

    const { data, error } = await supabase.rpc('rpc_reports_pipeline_summary', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as ReportsPipelineSummary;
}

export async function getInventorySummary(tenantId: string): Promise<ReportsInventorySummary> {
    if (USE_MOCKS) {
        const { getMockInventorySummary } = await import('@/mocks/reports.mock');
        return getMockInventorySummary();
    }

    const { data, error } = await supabase.rpc('rpc_reports_inventory_summary', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as ReportsInventorySummary;
}

export async function getOperationsSummary(tenantId: string): Promise<ReportsOperationsSummary> {
    if (USE_MOCKS) {
        const { getMockOperationsSummary } = await import('@/mocks/reports.mock');
        return getMockOperationsSummary();
    }

    const { data, error } = await supabase.rpc('rpc_reports_operations_summary', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as ReportsOperationsSummary;
}
