import type { ProductRole } from '@/constants/roles';

export type ExecutiveDatePreset = 'today' | '7d' | '30d' | 'month' | 'year' | 'custom';
export type AttentionSeverity = 'critical' | 'high' | 'medium' | 'low';
export type ProductivityModule = 'operations' | 'commercial' | 'documents' | 'finance';

export interface AttentionItem {
    kind: string;
    severity: AttentionSeverity;
    title: string;
    subtitle: string;
    reference: string;
    entity_type: string;
    entity_id: string;
    module: ProductivityModule;
    route: string;
    occurred_at: string;
    due_at: string | null;
}

export interface RecentActivityItem {
    id: string;
    module: ProductivityModule | 'security';
    title: string;
    subtitle: string;
    entity_type: string;
    entity_id: string | null;
    occurred_at: string;
    route: string;
}

export interface ExecutiveDashboard {
    role: Extract<ProductRole, 'admin' | 'finance'>;
    range: { start: string | null; end: string | null };
    operations: {
        active: number;
        in_transit: number;
        delivered: number;
        closed: number;
        blocking_incidents: number;
        dispatch_blockers: number;
        billing_ready: number;
        billing_blocked: number;
    };
    commercial?: {
        draft: number;
        in_review: number;
        approved: number;
        pending_conversion: number;
        converted: number;
        conversion_rate: number;
    };
    finance: {
        ar_outstanding: number;
        ar_overdue: number;
        ap_outstanding: number;
        ap_overdue: number;
        due_soon: number;
        collections_month: number;
        provider_payments_month: number;
    };
    documents: { required_missing: number; pod_pending: number };
    attention: AttentionItem[];
    recent_activity: RecentActivityItem[];
}

export interface InternalNotification {
    id: string;
    module: ProductivityModule;
    kind: string;
    priority: AttentionSeverity;
    title: string;
    body: string;
    route: string;
    entity_type: string;
    entity_id: string;
    occurred_at: string;
    due_at: string | null;
    read_at: string | null;
    created_at: string;
    is_automated: boolean;
    automation_rule_code: string | null;
    first_seen_at: string | null;
    last_seen_at: string | null;
    escalation_level: number;
    escalated_at: string | null;
    metadata: Record<string, unknown>;
}

export interface NotificationFeed {
    items: InternalNotification[];
    unread_count: number;
}

export interface GlobalSearchResult {
    type: 'operation' | 'customer' | 'provider' | 'quote' | 'document' | 'finance_invoice';
    id: string;
    primary_label: string;
    secondary_label: string;
    status: string;
    module: ProductivityModule;
    route: string;
    rank: number;
}

export interface SavedView {
    id: string;
    module: ProductivityModule;
    name: string;
    filters: Record<string, unknown>;
    sort: Record<string, unknown>;
    is_default: boolean;
    created_at: string;
    updated_at: string;
}

export interface SaveViewPayload {
    id?: string;
    module: ProductivityModule;
    name: string;
    filters: Record<string, unknown>;
    sort?: Record<string, unknown>;
    is_default?: boolean;
}
