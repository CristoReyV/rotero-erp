export interface ReportsFinancialSummary {
    revenue_by_month: number[];
    ar_open_by_month: number[];
    ap_open_by_month: number[];
    cashflow_by_month: number[];
    total_revenue_ytd: number;
    total_expenses_ytd: number;
    net_position: number;
}

export interface ReportsPipelineSummary {
    deals_by_stage: {
        lead: number;
        contacted: number;
        proposal: number;
        won: number;
        [key: string]: number;
    };
    total_pipeline_value: number;
    conversion_rate: number;
}

export interface SKUValueItem {
    sku: string;
    value: number;
}

export interface ReportsInventorySummary {
    inventory_total_value: number;
    blocked_count: number;
    low_stock_count: number;
    top_skus_by_value: SKUValueItem[];
}

export interface ReportsOperationsSummary {
    operations_per_month: number[];
    avg_delivery_time: number;
    active_routes_count: number;
}

export interface ReportConfig {
    name: string;
    type: string;
    date: string;
    status: string;
}

export interface ReportModuleDef {
    name: string;
    iconName: 'TrendingUp' | 'BarChart3' | 'FileText' | 'PieChart';
    count: number;
    color: string;
}
