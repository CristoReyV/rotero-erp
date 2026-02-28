export interface Member {
    user_id: string;
    role: 'admin' | 'operator' | 'viewer';
    created_at: string;
    email: string;
    name: string | null;
}

export interface Invitation {
    id: string;
    tenant_id: string;
    email: string;
    role: 'admin' | 'operator' | 'viewer';
    expires_at: string;
    accepted_at: string | null;
    created_at: string;
}

export interface AuditEvent {
    id: string;
    action: string;
    entity_type: string;
    entity_id: string | null;
    created_at: string;
    metadata: Record<string, any>;
    actor_id: string | null;
    actor_email: string | null;
    actor_name: string | null;
}

export interface AuditFilters {
    entity_type?: string;
    action?: string;
    start?: string;
    end?: string;
}

export interface AuditResponse {
    items: AuditEvent[];
    total: number;
    distinct_entities: string[];
    distinct_actions: string[];
}

export interface TenantSettings {
    tenant_id: string;
    brand_name: string;
    primary_color: string;
    logo_url: string | null;
    timezone: string;
    notifications_enabled: boolean;
    allow_demo_mode: boolean;
    created_at: string;
    updated_at: string;
}
