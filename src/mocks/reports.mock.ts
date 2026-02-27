import type {
    ReportModuleDef,
    ReportConfig,
    ReportsFinancialSummary,
    ReportsPipelineSummary,
    ReportsInventorySummary,
    ReportsOperationsSummary
} from '@/types/reports';

export const MOCK_REPORT_MODULES: ReportModuleDef[] = [
    { name: 'Operaciones', iconName: 'TrendingUp', count: 4, color: 'bg-blue-50 text-blue-600' },
    { name: 'Inventario', iconName: 'BarChart3', count: 3, color: 'bg-emerald-50 text-emerald-600' },
    { name: 'Fiscal / CFDI', iconName: 'FileText', count: 5, color: 'bg-amber-50 text-amber-600' },
    { name: 'Rentabilidad', iconName: 'PieChart', count: 2, color: 'bg-purple-50 text-purple-600' },
];

export const MOCK_RECENT_REPORTS: ReportConfig[] = [
    { name: 'Margen por Ruta – Enero 2024', type: 'Rentabilidad', date: 'Hace 2h', status: 'Listo' },
    { name: 'Inventario Valorizado PEPS', type: 'Inventario', date: 'Hoy 10:00 AM', status: 'Listo' },
    { name: 'Pedimentos Pendientes Q4', type: 'Fiscal', date: 'Ayer', status: 'Procesando' },
    { name: 'Cumplimiento OTIF Semanal', type: 'Operaciones', date: '18 Feb', status: 'Listo' },
    { name: 'Balance Descargo Materiales', type: 'Fiscal', date: '15 Feb', status: 'Listo' },
];

export async function getMockReportsModules() { return MOCK_REPORT_MODULES; }
export async function getMockRecentReports() { return MOCK_RECENT_REPORTS; }

export async function getMockFinancialSummary(): Promise<ReportsFinancialSummary> {
    return {
        revenue_by_month: [120000, 150000, 110000, 180000, 140000, 210000],
        ar_open_by_month: [20000, 15000, 25000, 10000, 5000, 30000],
        ap_open_by_month: [10000, 12000, 8000, 22000, 11000, 15000],
        cashflow_by_month: [110000, 138000, 102000, 158000, 129000, 195000],
        total_revenue_ytd: 910000,
        total_expenses_ytd: 450000,
        net_position: 460000
    };
}

export async function getMockPipelineSummary(): Promise<ReportsPipelineSummary> {
    return {
        deals_by_stage: { lead: 12, contacted: 8, proposal: 5, won: 3 },
        total_pipeline_value: 350000,
        conversion_rate: 15.5
    };
}

export async function getMockInventorySummary(): Promise<ReportsInventorySummary> {
    return {
        inventory_total_value: 1250000,
        blocked_count: 5,
        low_stock_count: 12,
        top_skus_by_value: [
            { sku: 'MOCK-VLV-1', value: 450000 },
            { sku: 'MOCK-PMP-2', value: 320000 },
            { sku: 'MOCK-RT-3', value: 150000 },
        ]
    };
}

export async function getMockOperationsSummary(): Promise<ReportsOperationsSummary> {
    return {
        operations_per_month: [45, 52, 38, 65, 58, 72],
        avg_delivery_time: 36,
        active_routes_count: 14
    };
}
