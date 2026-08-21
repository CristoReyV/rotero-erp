export type InvoiceDirection = 'ar' | 'ap';
export type InvoiceStatus = 'draft' | 'open' | 'paid' | 'overdue' | 'void';
export type PaymentMethod = 'transfer' | 'cash' | 'card' | 'other';
export type FinanceCurrency = 'MXN' | 'USD';

export interface FinanceInvoice {
    id: string; tenant_id?: string; direction: InvoiceDirection; counterparty_name: string;
    reference?: string | null; amount: number; currency: FinanceCurrency; amount_mxn?: number | null;
    status: InvoiceStatus; effective_status?: InvoiceStatus; due_date?: string | null; paid_at?: string | null;
    received_at?: string | null; notes?: string | null; exchange_rate?: number | null;
    exchange_rate_date?: string | null; exchange_rate_source?: string | null;
    customer_id?: string | null; provider_id?: string | null; operation_id?: string | null;
    operation_reference?: string | null; billing_document_id?: string | null; linked_cfdi_id?: string | null;
    billing_reference?: string | null; billing_fiscal_uuid?: string | null;
    paid_amount?: number; credit_amount?: number; balance_amount?: number;
    voided_at?: string | null; void_reason?: string | null; created_at: string; updated_at?: string;
}

export interface FinanceCurrencyOverview {
    currency: FinanceCurrency; ar_open: number; ap_open: number; ar_overdue: number; ap_overdue: number; open_count: number;
}

export interface FinanceOverview {
    total_ar_open: number; total_ap_open: number; total_overdue: number; paid_this_month: number;
    count_open_invoices: number; currencies?: FinanceCurrencyOverview[];
    chart: { labels: string[]; values: number[] };
}

export interface FinanceInvoiceFilters {
    search?: string; status?: InvoiceStatus; direction?: InvoiceDirection; currency?: FinanceCurrency;
    operation_id?: string; customer_id?: string; provider_id?: string; due_from?: string; due_to?: string; limit?: number;
}

export interface FinanceCreateInvoicePayload {
    direction: InvoiceDirection; counterparty_name?: string; reference?: string; amount: number;
    currency?: FinanceCurrency; status?: 'draft' | 'open'; due_date?: string; received_at?: string; notes?: string;
    customer_id?: string; provider_id?: string; operation_id?: string; billing_document_id?: string; linked_cfdi_id?: string;
    exchange_rate?: number; exchange_rate_date?: string; exchange_rate_source?: 'manual' | 'invoice';
    over_registration_override?: boolean; over_registration_reason?: string;
}

export interface FinanceRecordPaymentPayload {
    invoice_id: string; amount: number; paid_at?: string; method?: PaymentMethod; note?: string; bank_reference?: string;
    currency?: FinanceCurrency; exchange_rate?: number; exchange_rate_date?: string; exchange_rate_source?: 'manual' | 'invoice';
    prepare_complement?: boolean;
}

export interface FinancePayment {
    id: string; invoice_id: string; amount: number; currency: FinanceCurrency; amount_mxn?: number | null;
    paid_at: string; method: PaymentMethod; note?: string | null; bank_reference?: string | null;
    exchange_rate?: number | null; exchange_rate_date?: string | null; direction?: InvoiceDirection;
    counterparty_name?: string; reference?: string | null; operation_id?: string | null; invoice_status?: InvoiceStatus;
}

export interface FinanceCreditNote {
    id: string; folio?: string | null; note_type: 'customer_credit' | 'provider_credit'; total: number;
    currency: FinanceCurrency; total_mxn?: number | null; status: 'draft' | 'applied' | 'cancelled';
    issue_date: string; reason?: string | null; created_at: string;
}

export interface PaymentComplement {
    id: string; finance_invoice_id: string; finance_payment_id?: string | null; payment_date: string;
    method: PaymentMethod; amount: number; currency: FinanceCurrency; status: 'draft' | 'ready' | 'issued' | 'cancelled';
    bank_reference?: string | null; counterparty_name?: string; reference?: string | null;
}

export interface FinanceTimelineItem { event_type: string; occurred_at: string; details: Record<string, unknown> }

export interface FinanceInvoiceDetail {
    invoice: FinanceInvoice; payments: FinancePayment[]; credit_notes: FinanceCreditNote[];
    payment_complements: PaymentComplement[]; timeline: FinanceTimelineItem[];
}

export interface FinanceDueAlert {
    id: string; direction: InvoiceDirection; counterparty_name: string; reference?: string | null;
    amount: number; balance_amount: number; currency: FinanceCurrency; due_date: string;
    days_to_due: number; alert_type: 'overdue' | 'due_soon'; operation_reference?: string | null;
}

export interface OperationFinanceSummary {
    operation_id: string; operation_reference: string; currency: FinanceCurrency;
    expected_revenue: number; expected_cost: number; expected_margin: number;
    registered_ar: number; registered_ap: number; remaining_ar_to_register: number; remaining_ap_to_register: number;
}

export interface FinanceProfitabilityOperation {
    operation_id: string; reference_code: string; customer_id?: string | null; provider_id?: string | null;
    currency: FinanceCurrency; expected_revenue: number; expected_cost: number; expected_margin: number;
    registered_ar: number; registered_ap: number; registered_margin: number; cash_in: number; cash_out: number;
    cash_margin: number; outstanding_ar: number; outstanding_ap: number;
}

export interface FinanceProfitability {
    operations: FinanceProfitabilityOperation[]; customers: Array<Record<string, unknown>>;
    providers: Array<Record<string, unknown>>; currency_policy: 'separate';
}

export type FinanceExportRow = Record<string, string | number | null>;

export interface ProfitabilityItem { client: string; amount: string; width: string }
export interface ShipmentItem { route: string; unit: string; type: string; amount: string; status: string; statusColor: string }
