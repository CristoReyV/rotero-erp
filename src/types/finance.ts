export type InvoiceDirection = 'ar' | 'ap';
export type InvoiceStatus = 'draft' | 'open' | 'paid' | 'overdue' | 'void';
export type PaymentMethod = 'transfer' | 'cash' | 'card' | 'other';

export interface FinanceInvoice {
    id: string;
    direction: InvoiceDirection;
    counterparty_name: string;
    reference?: string;
    amount: number;
    currency: string;
    status: InvoiceStatus;
    due_date?: string;
    paid_at?: string;
    created_at: string;
}

export interface FinanceOverview {
    total_ar_open: number;
    total_ap_open: number;
    total_overdue: number;
    paid_this_month: number;
    count_open_invoices: number;
    chart: {
        labels: string[];
        values: number[];
    };
}

export interface FinanceCreateInvoicePayload {
    direction: InvoiceDirection;
    counterparty_name: string;
    reference?: string;
    amount: number;
    currency?: string;
    status?: InvoiceStatus;
    due_date?: string;
    notes?: string;
}

export interface FinanceRecordPaymentPayload {
    invoice_id: string;
    amount: number;
    paid_at?: string;
    method?: PaymentMethod;
    note?: string;
}

// For UI Legacy Maps
export interface ProfitabilityItem {
    client: string;
    amount: string;
    width: string;
}

export interface ShipmentItem {
    route: string;
    unit: string;
    type: string;
    amount: string;
    status: string;
    statusColor: string;
}
