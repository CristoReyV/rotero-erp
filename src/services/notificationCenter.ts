import type { InternalNotification, NotificationFeed } from '../types/executive';
import { withDeadline } from '../utils/asyncDeadline';

export interface NotificationScope { userId: string; tenantId: string; role: string }
export interface NotificationCenterPorts {
    list: (tenant: string, unread: boolean, cursor: NotificationFeed['next_cursor']) => Promise<NotificationFeed>;
    markRead: (tenant: string, ids: string[] | null) => Promise<void>;
    dismiss: (tenant: string, id: string) => Promise<void>;
}
export interface NotificationCenterState {
    scope: NotificationScope | null;
    items: InternalNotification[];
    unread: number;
    nextCursor: NotificationFeed['next_cursor'];
    loading: boolean;
    busy: boolean;
    error: string | null;
}
export type NotificationAutomaticEvent = 'mount' | 'navigation' | 'focus' | 'online' | 'context';

export function createNotificationCenter(ports: NotificationCenterPorts, timeoutMs = 12_000) {
    const empty = (scope: NotificationScope | null): NotificationCenterState => ({
        scope, items: [], unread: 0, nextCursor: null, loading: false, busy: false, error: null,
    });
    let state = empty(null);
    let revision = 0;
    let readId = 0;
    let abort = new AbortController();
    const listeners = new Set<() => void>();
    const publish = (next: NotificationCenterState) => { state = next; listeners.forEach(listener => listener()); };
    const current = (lease: number) => lease === revision && state.scope !== null;
    const setScope = (scope: NotificationScope | null) => {
        if (state.scope?.userId === scope?.userId && state.scope?.tenantId === scope?.tenantId
            && state.scope?.role === scope?.role) return false;
        revision += 1;
        readId += 1;
        abort.abort();
        abort = new AbortController();
        publish(empty(scope));
        return true;
    };
    const load = async (more = false) => {
        const scope = state.scope;
        if (!scope || (more && !state.nextCursor)) return;
        const lease = revision;
        const id = ++readId;
        const cursor = more ? state.nextCursor : null;
        publish({ ...state, loading: true, error: null });
        try {
            const feed = await withDeadline(() => ports.list(scope.tenantId, false, cursor), timeoutMs, abort.signal);
            if (!current(lease) || id !== readId) return;
            publish({ ...state, items: more
                ? [...state.items, ...feed.items.filter(item => !state.items.some(existing => existing.id === item.id))]
                : feed.items, unread: feed.unread_count, nextCursor: feed.next_cursor, loading: false });
        } catch {
            if (current(lease) && id === readId) publish({ ...state, loading: false,
                error: 'No fue posible cargar el listado de notificaciones. Puedes reintentar.' });
        }
    };
    // Automatic events have only the read port; no materialization is exposed here.
    const automatic = (_event: NotificationAutomaticEvent) => load();
    const action = async (task: (scope: NotificationScope) => Promise<void>) => {
        if (!state.scope || state.busy) return false;
        const scope = state.scope;
        const lease = revision;
        publish({ ...state, busy: true, error: null });
        try {
            await withDeadline(() => task(scope), timeoutMs, abort.signal);
            if (!current(lease)) return false;
            publish({ ...state, busy: false });
            return true;
        } catch {
            if (current(lease)) publish({ ...state, busy: false,
                error: 'No fue posible confirmar la acción. Actualiza el listado antes de reintentar.' });
            return false;
        }
    };
    const openItem = async (item: InternalNotification) => {
        if (!state.scope || !state.items.some(existing => existing.id === item.id)) return null;
        const lease = revision;
        if (!item.read_at && !await action(scope => ports.markRead(scope.tenantId, [item.id]))) return null;
        return current(lease) ? item.route : null;
    };
    const markAll = async () => {
        if (await action(scope => ports.markRead(scope.tenantId, null))) await load();
    };
    const dismiss = async (id: string) => {
        if (!state.items.some(item => item.id === id)) return;
        if (await action(scope => ports.dismiss(scope.tenantId, id))) await load();
    };
    return { setScope, load, automatic, openItem, markAll, dismiss, getSnapshot: () => state,
        subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; } };
}
