import { supabase } from '@/lib/supabase';
import type {
    AttentionItem,
    ExecutiveDashboard,
    GlobalSearchResult,
    NotificationFeed,
    ProductivityModule,
    SavedView,
    SaveViewPayload,
} from '@/types/executive';

function assertResult<T>(data: unknown, error: { message: string } | null): T {
    if (error) throw new Error(error.message);
    if (data && typeof data === 'object' && 'error' in data) {
        throw new Error(String((data as { error: unknown }).error));
    }
    return data as T;
}

export async function getExecutiveDashboard(tenantId: string, start: Date, end: Date): Promise<ExecutiveDashboard> {
    const { data, error } = await supabase.rpc('rpc_get_executive_dashboard', {
        p_tenant_id: tenantId,
        p_start_date: start.toISOString(),
        p_end_date: end.toISOString(),
    });
    return assertResult<ExecutiveDashboard>(data, error);
}

export async function listAttentionItems(tenantId: string): Promise<AttentionItem[]> {
    const { data, error } = await supabase.rpc('rpc_list_attention_items', { p_tenant_id: tenantId });
    return assertResult<{ items: AttentionItem[] }>(data, error).items;
}

export async function refreshInternalNotifications(tenantId: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_refresh_internal_notifications', { p_tenant_id: tenantId });
    assertResult(data, error);
}

export async function listInternalNotifications(tenantId: string, unreadOnly = false, cursor:NotificationFeed['next_cursor']=null): Promise<NotificationFeed> {
    const { data, error } = await supabase.rpc('rpc_list_internal_notifications_page', {
        p_tenant_id: tenantId,
        p_unread_only: unreadOnly,
        p_cursor:cursor,
        p_limit:25,
    });
    return assertResult<NotificationFeed>(data, error);
}

export async function markInternalNotificationsRead(tenantId: string, ids: string[] | null): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_mark_internal_notifications_read', {
        p_tenant_id: tenantId,
        p_ids: ids,
    });
    assertResult(data, error);
}

export async function dismissInternalNotification(tenantId: string, notificationId: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_dismiss_internal_notification', {
        p_tenant_id: tenantId,
        p_notification_id: notificationId,
    });
    assertResult(data, error);
}

export async function globalSearch(tenantId: string, query: string, limit = 5): Promise<GlobalSearchResult[]> {
    const { data, error } = await supabase.rpc('rpc_global_search', {
        p_tenant_id: tenantId,
        p_query: query,
        p_limit: limit,
    });
    return assertResult<{ items: GlobalSearchResult[] }>(data, error).items;
}

export async function listSavedViews(tenantId: string, module: ProductivityModule): Promise<SavedView[]> {
    if (module === 'claims') {
        const { data, error } = await supabase.rpc('rpc_list_claim_saved_views', { p_tenant_id: tenantId });
        return assertResult<SavedView[]>(data, error);
    }
    const { data, error } = await supabase.rpc('rpc_list_saved_views', { p_tenant_id: tenantId, p_module: module });
    return assertResult<{ items: SavedView[] }>(data, error).items;
}

export async function saveView(tenantId: string, payload: SaveViewPayload): Promise<SavedView> {
    if (payload.module === 'claims') {
        const { data, error } = await supabase.rpc('rpc_save_claim_view', { p_tenant_id: tenantId, p_view_id: payload.id ?? null, p_payload: payload });
        return assertResult<SavedView>(data, error);
    }
    const { data, error } = await supabase.rpc('rpc_save_view', { p_tenant_id: tenantId, p_payload: payload });
    return assertResult<SavedView>(data, error);
}

export async function deleteSavedView(tenantId: string, viewId: string, module?: ProductivityModule): Promise<void> {
    if (module === 'claims') {
        const { data, error } = await supabase.rpc('rpc_delete_claim_view', { p_tenant_id: tenantId, p_view_id: viewId });
        assertResult(data, error); return;
    }
    const { data, error } = await supabase.rpc('rpc_delete_saved_view', { p_tenant_id: tenantId, p_view_id: viewId });
    assertResult(data, error);
}
