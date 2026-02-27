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
}

export interface DealActivity {
    id: string;
    deal_id: string;
    type: 'note' | 'call' | 'email' | 'meeting' | 'status_change';
    body?: string;
    created_by?: string;
    created_at: string;
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
