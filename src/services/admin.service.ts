import { supabase } from '@/lib/supabase';
import type { TenantSettings, Invitation, AuditEvent, AuditFilters, AuditResponse, Member } from '@/types/settings';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

// --------------------------------------------------------------------------------
// Settings
// --------------------------------------------------------------------------------
export async function getTenantSettings(tenantId: string): Promise<TenantSettings> {
    if (USE_MOCKS) {
        return {
            tenant_id: tenantId,
            brand_name: 'WLS Rotero (Mock)',
            primary_color: '#0F2B5B',
            logo_url: null,
            timezone: 'America/Mexico_City',
            notifications_enabled: true,
            allow_demo_mode: false,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
        };
    }

    const { data, error } = await supabase.rpc('rpc_get_tenant_settings', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as TenantSettings;
}

export async function updateTenantSettings(tenantId: string, settings: Partial<TenantSettings>): Promise<void> {
    if (USE_MOCKS) {
        return new Promise(resolve => setTimeout(resolve, 500));
    }
    const { data, error } = await supabase.rpc('rpc_update_tenant_settings', {
        p_tenant_id: tenantId,
        p_payload: settings
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

// --------------------------------------------------------------------------------
// Members
// --------------------------------------------------------------------------------
export async function getMembers(tenantId: string): Promise<Member[]> {
    if (USE_MOCKS) {
        // Fallback robusto al viejo Security Mock
        const { getMockUsers } = await import('@/mocks/security.mock');
        const ms = await getMockUsers();
        return ms.map((m, i) => ({
            user_id: `mock-${i}`,
            role: m.role.toLowerCase().includes('admin') ? 'admin' : (m.role.includes('Auditor') ? 'viewer' : 'operator'),
            created_at: new Date().toISOString(),
            email: `${m.name.replace(' ', '.').toLowerCase()}@mock.rotero`,
            name: m.name
        }));
    }

    const { data, error } = await supabase.rpc('rpc_list_members', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as Member[];
}

export async function changeMemberRole(tenantId: string, userId: string, newRole: 'admin' | 'operator' | 'viewer'): Promise<void> {
    if (USE_MOCKS) return new Promise(r => setTimeout(r, 400));
    const { data, error } = await supabase.rpc('rpc_update_member_role', {
        p_tenant_id: tenantId, p_member_user_id: userId, p_new_role: newRole
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function deactivateMember(tenantId: string, userId: string): Promise<void> {
    if (USE_MOCKS) return new Promise(r => setTimeout(r, 400));
    const { data, error } = await supabase.rpc('rpc_deactivate_member', {
        p_tenant_id: tenantId, p_member_user_id: userId
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function inviteMember(tenantId: string, email: string, role: string): Promise<{ token?: string }> {
    if (USE_MOCKS) return { token: 'mock-token-abc-123' };
    const { data, error } = await supabase.rpc('rpc_create_invitation', {
        p_tenant_id: tenantId, p_email: email, p_role: role
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data;
}

// --------------------------------------------------------------------------------
// Audit Logs
// --------------------------------------------------------------------------------
export async function getAuditLogs(
    tenantId: string,
    limit = 50,
    offset = 0,
    filters?: AuditFilters,
): Promise<AuditResponse> {
    if (USE_MOCKS) {
        const { getMockAuditLogs } = await import('@/mocks/security.mock');
        const ms = await getMockAuditLogs();
        const items: AuditEvent[] = ms.map((m, i) => ({
            id: `audit-${i}`,
            action: m.event,
            entity_type: 'mock_entity',
            entity_id: null,
            created_at: new Date(Date.now() - i * 600000).toISOString(),
            metadata: {},
            actor_id: null,
            actor_name: m.user,
            actor_email: `${m.user}@mock.test`
        }));
        return {
            items,
            total: items.length,
            distinct_entities: ['mock_entity'],
            distinct_actions: [...new Set(items.map(i => i.action))],
        };
    }

    const { data, error } = await supabase.rpc('rpc_list_audit_log', {
        p_tenant_id: tenantId,
        p_limit: limit,
        p_offset: offset,
        p_entity_type: filters?.entity_type || null,
        p_action: filters?.action || null,
        p_start: filters?.start || null,
        p_end: filters?.end || null,
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as AuditResponse;
}

export function exportAuditCSV(items: AuditEvent[]): void {
    const header = 'Fecha,Actor,Email,Acción,Módulo,Entity ID,Metadata\n';
    const rows = items.map(log => {
        const date = new Date(log.created_at).toLocaleString('es-MX');
        const actor = (log.actor_name || 'Sistema').replace(/,/g, ' ');
        const email = (log.actor_email || '-').replace(/,/g, ' ');
        const meta = JSON.stringify(log.metadata || {}).replace(/,/g, ';');
        return `${date},${actor},${email},${log.action},${log.entity_type},${log.entity_id || '-'},"${meta}"`;
    }).join('\n');

    const blob = new Blob([header + rows], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `audit_log_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
}

