import { findRoteroEnabledTenantId, isProductRole, isRoteroEnabledRole } from '../constants/roles';
import type { AuthContext } from '../store/authStore';
import { RequestTimeoutError, withDeadline } from '../utils/asyncDeadline';

// Session lookup and the small context RPC each get 12s, then fail closed with retry.
export const AUTH_REQUEST_TIMEOUT_MS = 12_000;
export type AccessStatus = 'loading' | 'unauthenticated' | 'authorized' | 'disabled' | 'error';
export interface AuthAccessState { status: AccessStatus; userId: string | null; message?: string }
export interface AccessSession { userId: string }
export interface SignInInput { email: string; password: string }

export interface AuthAccessPorts {
    getSession: () => Promise<AccessSession | null>;
    getContext: (signal: AbortSignal) => PromiseLike<unknown>;
    signIn: (input: SignInInput) => Promise<AccessSession | null>;
    signOut: () => Promise<void>;
    onAuthChange: (callback: (event: string, session: AccessSession | null) => void) => () => void;
    store: {
        getContext: () => AuthContext | null;
        getTenant: () => string | null;
        commit: (context: AuthContext, tenant: string) => void;
        clear: () => void;
        subscribe: (callback: () => void) => () => void;
    };
}

function validatedContext(value: unknown, userId: string): AuthContext | null {
    if (!value || typeof value !== 'object') return null;
    const ctx = value as AuthContext;
    if (ctx.user_id !== userId || typeof ctx.email !== 'string' || !ctx.email.trim()
        || !Array.isArray(ctx.memberships) || !ctx.memberships.length) return null;
    const tenants = new Set<string>();
    for (const membership of ctx.memberships) {
        if (!membership || typeof membership.tenant_id !== 'string' || !membership.tenant_id.trim()
            || typeof membership.tenant_name !== 'string' || !membership.tenant_name.trim()
            || !isProductRole(membership.role) || tenants.has(membership.tenant_id)) return null;
        tenants.add(membership.tenant_id);
    }
    return ctx;
}

/** One coordinator for Login/Guard. RPC responses cannot commit their own store writes. */
export function createAuthAccess(ports: AuthAccessPorts, timeoutMs = AUTH_REQUEST_TIMEOUT_MS) {
    let state: AuthAccessState = { status: 'loading', userId: null };
    const listeners = new Set<() => void>();
    let generation = 0;
    let request: AbortController | null = null;
    let users = 0;
    let subscriptionId = 0;
    let unsubscribeAuth: (() => void) | undefined;
    let unsubscribeStore: (() => void) | undefined;
    let deferred: ReturnType<typeof setTimeout> | undefined;
    let writingStore = false;
    let suppressSessionEvents = false;
    let localSignedOut = false;
    let signInFlight: Promise<AccessSession | null> | null = null;
    let preferredTenant = ports.store.getTenant();

    const publish = (next: AuthAccessState) => { state = next; listeners.forEach(listener => listener()); };
    const writeStore = (action: () => void) => {
        writingStore = true;
        try { action(); } finally { writingStore = false; }
    };
    const invalidate = () => {
        generation += 1;
        request?.abort();
        clearTimeout(deferred);
        request = new AbortController();
        return generation;
    };
    const current = (ticket: number) => ticket === generation && !request?.signal.aborted;
    const clear = () => writeStore(ports.store.clear);
    const signedOut = () => {
        localSignedOut = true;
        suppressSessionEvents = true;
        preferredTenant = null;
        invalidate();
        clear();
        publish({ status: 'unauthenticated', userId: null });
    };
    const begin = (userId: string | null) => {
        preferredTenant = ports.store.getTenant() ?? preferredTenant;
        const ticket = invalidate();
        clear();
        publish({ status: 'loading', userId });
        return ticket;
    };
    const failed = (ticket: number, cause: unknown) => {
        if (!current(ticket)) return;
        // Ignore late SDK events/results until an explicit retry or new login.
        suppressSessionEvents = true;
        clear();
        publish({ status: 'error', userId: null, message: cause instanceof RequestTimeoutError
            ? 'La verificación de acceso tardó demasiado. Reintenta o cierra sesión.'
            : 'No fue posible verificar el acceso. Reintenta o cierra sesión.' });
    };
    const loadContext = async (ticket: number, userId: string) => {
        try {
            const value = await withDeadline(ports.getContext, timeoutMs, request!.signal);
            if (!current(ticket)) return false;
            const context = validatedContext(value, userId);
            const tenant = context ? findRoteroEnabledTenantId(context.memberships, preferredTenant) : null;
            if (!context || !tenant) {
                clear();
                publish({ status: 'disabled', userId, message: !context
                    ? 'La cuenta no tiene un contexto, membresía o empresa válidos. Reintenta o solicita revisión al administrador.'
                    : 'Esta cuenta no tiene un rol habilitado para el despliegue actual de ROTERO.' });
                return false;
            }
            writeStore(() => ports.store.commit(context, tenant));
            publish({ status: 'authorized', userId });
            return true;
        } catch (cause) { failed(ticket, cause); return false; }
    };
    const retry = async () => {
        localSignedOut = false;
        suppressSessionEvents = false;
        const ticket = begin(null);
        try {
            const session = await withDeadline(ports.getSession, timeoutMs, request!.signal);
            if (!current(ticket)) return false;
            if (!session) { signedOut(); return false; }
            if (!session.userId) throw new Error('invalid_session');
            publish({ status: 'loading', userId: session.userId });
            return await loadContext(ticket, session.userId);
        } catch (cause) { failed(ticket, cause); return false; }
    };
    const onAuthChange = (event: string, session: AccessSession | null) => {
        if (event === 'SIGNED_OUT') { signedOut(); return; }
        if (suppressSessionEvents || signInFlight) return;
        if (!session) { signedOut(); return; }
        if (!session.userId) { failed(begin(null), new Error('invalid_session')); return; }
        if (state.userId === session.userId && event !== 'USER_UPDATED'
            && (state.status === 'authorized' || state.status === 'loading')) return;
        if (state.userId !== session.userId) preferredTenant = null;
        const ticket = begin(session.userId);
        // Auth callbacks run under the SDK lock. Never await or start RPC here.
        deferred = setTimeout(() => { if (current(ticket)) void loadContext(ticket, session.userId); }, 0);
    };
    const signOut = async () => {
        signedOut(); // Clear permissions before waiting for the SDK operation.
        const ticket = generation;
        try { await withDeadline(ports.signOut, timeoutMs); return true; }
        catch {
            if (generation === ticket) publish({ status: 'unauthenticated', userId: null,
                message: 'Se cerró el acceso local, pero no se pudo confirmar el cierre de sesión. Reintenta cerrar sesión.' });
            return false;
        }
    };
    const signIn = async (input: SignInInput) => {
        // The SDK cannot cancel a password request. Do not overlap attempts:
        // a late SDK result must not switch identity after a newer login.
        if (signInFlight) {
            failed(begin(null), new Error('sign_in_pending'));
            return false;
        }
        localSignedOut = false;
        const ticket = begin(null);
        suppressSessionEvents = true;
        const flight = Promise.resolve().then(() => ports.signIn(input));
        signInFlight = flight;
        void flight.finally(() => { if (signInFlight === flight) signInFlight = null; }).catch(() => {});
        try {
            const session = await withDeadline(() => flight, timeoutMs, request!.signal);
            if (!current(ticket)) return false;
            if (!session?.userId) throw new Error('invalid_session');
            suppressSessionEvents = false;
            publish({ status: 'loading', userId: session.userId });
            return await loadContext(ticket, session.userId);
        } catch (cause) { failed(ticket, cause); return false; }
    };
    const start = () => {
        users += 1;
        if (users === 1) {
            unsubscribeStore = ports.store.subscribe(() => {
                if (writingStore) return;
                const context = ports.store.getContext();
                if (!context) { signedOut(); return; }
                if (state.status === 'authorized') {
                    const membership = context.memberships.find(item => item.tenant_id === ports.store.getTenant());
                    if (context.user_id !== state.userId || !isRoteroEnabledRole(membership?.role)) {
                        failed(generation, new Error('invalid_local_context'));
                    }
                }
            });
            const subscription = ++subscriptionId;
            unsubscribeAuth = ports.onAuthChange((event, session) => {
                if (subscription === subscriptionId && users > 0) onAuthChange(event, session);
            });
            // Login can mount while the SDK logout is still pending. Do not
            // silently restore its cached session after an explicit local exit.
            if (localSignedOut) {
                clear();
                publish({ status: 'unauthenticated', userId: null, message: state.message });
            } else {
                void retry();
            }
        }
        let released = false;
        return () => {
            if (released) return;
            released = true;
            users -= 1;
            if (users === 0) {
                subscriptionId += 1;
                invalidate();
                suppressSessionEvents = true;
                unsubscribeAuth?.();
                unsubscribeStore?.();
                clear();
                publish({ status: localSignedOut ? 'unauthenticated' : 'loading', userId: null, message: state.message });
            }
        };
    };
    return { start, retry, signIn, signOut, getSnapshot: () => state,
        subscribe: (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; } };
}
