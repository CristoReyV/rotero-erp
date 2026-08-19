export type DealStage = 'lead' | 'qualified' | 'proposal' | 'won' | 'lost';
export type DealPriority = 'low' | 'medium' | 'high';

export interface Deal {
    id: string;
    title: string;
    company?: string;
    contact_name?: string;
    contact_email?: string;
    contact_phone?: string;
    value?: number;
    currency: string;
    stage: DealStage;
    priority: DealPriority;
    owner_user_id?: string;
    notes?: string;
    last_touch_at?: string;
    created_at: string;
    updated_at: string;
    customer_id?: string;
    quote_status?: QuoteStatus;
    quote_reference?: string;
    quote_payload?: QuotePayload;
    converted_operation_id?: string;
}

export interface DealDetail extends Deal {
    owner_name?: string;
}

export interface DealActivity {
    id: string;
    deal_id: string;
    type: 'note' | 'call' | 'email' | 'meeting' | 'status_change';
    body?: string;
    created_by?: string;
    creator_name?: string;
    created_at: string;
}

export interface DealActivityPayload {
    type: 'note' | 'call' | 'email' | 'meeting' | 'status_change';
    body?: string;
}

export interface DealCreatePayload {
    title: string;
    company?: string;
    contact_name?: string;
    contact_email?: string;
    contact_phone?: string;
    value?: number;
    currency?: string;
    stage?: DealStage;
    priority?: DealPriority;
    notes?: string;
    owner_user_id?: string;
}

export interface DealUpdatePatch {
    title?: string;
    company?: string;
    contact_name?: string;
    contact_email?: string;
    contact_phone?: string;
    value?: number;
    currency?: string;
    stage?: DealStage;
    priority?: DealPriority;
    notes?: string;
    owner_user_id?: string;
}

export interface DealFilters {
    stage?: DealStage;
    owner?: string;
    priority?: DealPriority;
    searchText?: string;
}

// Map back to UI legacy interface
export interface LegacyDealItem {
    db_id?: string;
    name: string;
    value: string;
    prob: string;
}

export interface PipelineColumn {
    id?: string; // e.g. 'lead', 'qualified', 'proposal', 'won' or localized names
    title: string; // The translated title
    count: number;
    deals: LegacyDealItem[];
}

export interface DealNote {
    id: string;
    note: string;
    author_name: string;
    created_at: string;
}

export interface DealChecklistItem {
    id: string;
    stage: string;
    label: string;
    is_done: boolean;
    updated_at: string;
}

export type CommercialCurrency = 'MXN' | 'USD';
export type QuoteStatus = 'draft' | 'in_review' | 'approved' | 'rejected' | 'converted';
export type OperationScope = 'national' | 'international';

export interface CommercialPlace {
    municipality: string;
    state: string;
    countryCode: 'MX' | 'US';
}

export interface CargoSummary {
    description: string;
    pieces?: number;
    unit?: string;
    weightKg?: number;
    measurements?: string;
}

export interface Customer {
    id: string;
    tenant_id: string;
    display_name: string;
    legal_name?: string;
    contact_name?: string;
    contact_email?: string;
    contact_phone?: string;
    tax_id?: string;
    billing_email?: string;
    notes?: string;
    is_active: boolean;
    preferred_currency: CommercialCurrency;
    deal_count: number;
    quote_count: number;
    operation_count: number;
    quoted_totals: Partial<Record<CommercialCurrency, number>>;
    operation_sell_totals: Partial<Record<CommercialCurrency, number>>;
}

export type CustomerPayload = Pick<Customer, 'display_name'> & Partial<Pick<Customer,
    'legal_name' | 'contact_name' | 'contact_email' | 'contact_phone' | 'tax_id' |
    'billing_email' | 'notes' | 'is_active' | 'preferred_currency'
>>;

export interface Customer360 {
    customer: Customer;
    summary: {
        deal_count: number;
        quote_count: number;
        operation_count: number;
        quoted_totals: Partial<Record<CommercialCurrency, number>>;
        operation_sell_totals: Partial<Record<CommercialCurrency, number>>;
    };
    deals: Deal[];
    quotes: Quote[];
    operations: Array<{
        id: string;
        reference_code: string;
        status: string;
        route_summary?: string;
        customer_price_amount?: number;
        pricing_currency?: CommercialCurrency;
    }>;
}

export interface LogisticsProvider {
    id: string;
    tenant_id: string;
    display_name: string;
    legal_name?: string;
    tax_id?: string;
    contact_name?: string;
    contact_email?: string;
    contact_phone?: string;
    billing_email?: string;
    notes?: string;
    is_active: boolean;
    quote_count: number;
    operation_count: number;
    contracted_cost_totals: Partial<Record<CommercialCurrency, number>>;
}

export type LogisticsProviderPayload = Pick<LogisticsProvider, 'display_name'> & Partial<Pick<LogisticsProvider,
    'legal_name' | 'tax_id' | 'contact_name' | 'contact_email' | 'contact_phone' |
    'billing_email' | 'notes' | 'is_active'
>>;

export interface QuotePayload {
    provider_id?: string;
    provider_name?: string;
    origin_place?: CommercialPlace;
    destination_place?: CommercialPlace;
    operation_scope: OperationScope;
    execution_type?: 'third_party';
    service_type?: string;
    service_catalog_item_id?: string;
    service_catalog_snapshot?: Record<string, unknown>;
    provider_cost_amount?: number;
    customer_price_amount?: number;
    currency: CommercialCurrency;
    operational_window_start?: string;
    operational_window_end?: string;
    cargo_summary?: CargoSummary;
    requested_date?: string;
    valid_until?: string;
    notes?: string;
}

export interface Quote extends Deal {
    customer_id: string;
    quote_status: QuoteStatus;
    quote_reference: string;
    quote_payload: QuotePayload;
    customer_name: string;
    provider_name?: string;
    converted_operation_reference?: string;
}

export interface QuoteUpsertPayload extends QuotePayload {
    customer_id: string;
    title: string;
    priority?: DealPriority;
}

export interface QuoteFilters {
    status?: QuoteStatus;
    customer_id?: string;
    provider_id?: string;
    searchText?: string;
}

export interface QuoteConversionResult {
    operation_id: string;
    operation_reference: string;
    already_converted: boolean;
}

