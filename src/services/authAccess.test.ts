import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { createAuthAccess, type AccessSession, type AuthAccessPorts } from './authAccess';
import type { AuthContext } from '../store/authStore';

const cleanup: Array<() => void> = [];
afterEach(() => { cleanup.splice(0).forEach(stop => stop()); });
function deferred<T>() {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>(done => { resolve = done; });
    return { promise, resolve };
}
async function until(condition: () => boolean) {
    for (let i = 0; i < 100; i++) { if (condition()) return; await delay(2); }
    assert.fail('controlled operation did not settle');
}
const contextOf = (user = 'user-a', role: AuthContext['memberships'][number]['role'] = 'admin'): AuthContext => ({
    user_id: user, email: `${user}@example.invalid`,
    memberships: [{ tenant_id: 'tenant-a', tenant_name: 'Test tenant', role }],
});
function fixture(timeout = 80) {
    let context: AuthContext | null = contextOf('previous-user');
    let tenant: string | null = 'previous-tenant';
    const storeListeners = new Set<() => void>();
    let callback: (event: string, session: AccessSession | null) => void = () => {};
    let unsubscribed = 0;
    let contextCalls = 0;
    const committed: string[] = [];
    const ports: AuthAccessPorts = {
        getSession: async () => ({ userId: 'user-a' }),
        getContext: async () => { contextCalls++; return contextOf(); },
        signIn: async () => ({ userId: 'user-a' }),
        signOut: async () => {},
        onAuthChange: next => { callback = next; return () => { unsubscribed++; }; },
        store: {
            getContext: () => context, getTenant: () => tenant,
            clear: () => { context = null; tenant = null; storeListeners.forEach(next => next()); },
            commit: (next, selected) => { context = next; tenant = selected; committed.push(next.user_id); storeListeners.forEach(next => next()); },
            subscribe: next => { storeListeners.add(next); return () => { storeListeners.delete(next); }; },
        },
    };
    const access = createAuthAccess(ports, timeout);
    return { ports, access, start: () => { const stop = access.start(); cleanup.push(stop); return stop; },
        emit: (event: string, session: AccessSession | null) => callback(event, session),
        callback: () => callback, context: () => context, tenant: () => tenant, committed,
        contextCalls: () => contextCalls, unsubscribed: () => unsubscribed, listeners: () => storeListeners.size,
        setTenant: (next: string | null) => { tenant = next; storeListeners.forEach(listener => listener()); } };
}

test('no session clears persisted context and finishes without a protected outlet', async () => {
    const f = fixture(); f.ports.getSession = async () => null;
    f.start(); assert.equal(f.context(), null);
    await until(() => f.access.getSnapshot().status === 'unauthenticated');
    assert.equal(f.tenant(), null); assert.equal(f.contextCalls(), 0);
});
test('valid session loads server context and enabled tenant; cached permissions alone never grant access', async () => {
    const f = fixture(); f.start(); assert.equal(f.access.getSnapshot().status, 'loading');
    assert.equal(f.context(), null);
    await until(() => f.access.getSnapshot().status === 'authorized');
    assert.equal(f.context()?.user_id, 'user-a'); assert.equal(f.tenant(), 'tenant-a');
});

const invalidContexts: Array<[string, unknown]> = [
    ['missing profile/context', null],
    ['missing email', { ...contextOf(), email: null }],
    ['missing membership', { ...contextOf(), memberships: [] }],
    ['invalid membership collection', { ...contextOf(), memberships: null }],
    ['missing tenant id', { ...contextOf(), memberships: [{ tenant_id: '', tenant_name: 'Test', role: 'admin' }] }],
    ['missing tenant name', { ...contextOf(), memberships: [{ tenant_id: 'tenant-a', tenant_name: '', role: 'admin' }] }],
    ['different user', contextOf('other-user')],
    ['role not enabled', contextOf('user-a', 'operator')],
    ['duplicate tenant grant', { ...contextOf(), memberships: [...contextOf().memberships, ...contextOf().memberships] }],
];
for (const [name, value] of invalidContexts) test(`${name} fails closed in a recoverable state`, async () => {
    const f = fixture(); f.ports.getContext = async () => value; f.start();
    await until(() => f.access.getSnapshot().status === 'disabled');
    assert.ok(f.access.getSnapshot().message); assert.equal(f.context(), null); assert.equal(f.tenant(), null);
});
test('session errors are safe and retry can recover', async () => {
    const f = fixture(); f.ports.getSession = async () => { throw new Error('internal-detail'); }; f.start();
    await until(() => f.access.getSnapshot().status === 'error');
    assert.ok(!f.access.getSnapshot().message?.includes('internal-detail'));
    f.ports.getSession = async () => ({ userId: 'user-a' });
    assert.equal(await f.access.retry(), true); assert.equal(f.access.getSnapshot().status, 'authorized');
});
test('context rejection ends loading; recovery revalidates the context', async () => {
    const f = fixture(); f.ports.getContext = async () => { throw new Error('internal-detail'); }; f.start();
    await until(() => f.access.getSnapshot().status === 'error');
    f.ports.getContext = async () => contextOf(); assert.equal(await f.access.retry(), true);
});
test('never-resolving session lookup has a deadline and late result cannot restore access', async () => {
    const f = fixture(12); const session = deferred<AccessSession | null>();
    f.ports.getSession = () => session.promise; f.start();
    await until(() => f.access.getSnapshot().status === 'error');
    session.resolve({ userId: 'user-a' }); await delay(5);
    assert.equal(f.context(), null); assert.equal(f.contextCalls(), 0);
});
test('never-resolving context is aborted at deadline and cannot commit later', async () => {
    const f = fixture(12); const context = deferred<unknown>(); let signal!: AbortSignal;
    f.ports.getContext = request => { signal = request; return context.promise; }; f.start();
    await until(() => f.access.getSnapshot().status === 'error');
    assert.equal(signal.aborted, true); context.resolve(contextOf()); await delay(5);
    assert.equal(f.context(), null); assert.deepEqual(f.committed, []);
});
test('logout during loading clears immediately even while SDK signOut is pending', async () => {
    const f = fixture(); const context = deferred<unknown>(); const remote = deferred<void>();
    f.ports.getContext = () => context.promise; f.ports.signOut = () => remote.promise; f.start();
    await delay(3); const result = f.access.signOut();
    assert.equal(f.access.getSnapshot().status, 'unauthenticated'); assert.equal(f.context(), null);
    context.resolve(contextOf()); remote.resolve(); await result; await delay(3);
    assert.deepEqual(f.committed, []);
});
test('external local logout also invalidates pending work', async () => {
    const f = fixture(); const context = deferred<unknown>(); f.ports.getContext = () => context.promise;
    f.start(); await delay(3); f.ports.store.clear(); context.resolve(contextOf()); await delay(3);
    assert.equal(f.access.getSnapshot().status, 'unauthenticated'); assert.deepEqual(f.committed, []);
});
test('mounting Login during pending logout cannot restore the SDK cached session', async () => {
    const f = fixture(); const one = f.start();
    await until(() => f.access.getSnapshot().status === 'authorized');
    const remote = deferred<void>(); f.ports.signOut = () => remote.promise;
    const logout = f.access.signOut(); const calls = f.contextCalls();
    one(); f.start(); await delay(5);
    assert.equal(f.access.getSnapshot().status, 'unauthenticated');
    assert.equal(f.context(), null); assert.equal(f.contextCalls(), calls);
    f.emit('SIGNED_IN', { userId: 'user-a' }); remote.resolve(); await logout;
    assert.equal(f.context(), null);
});
test('user switch invalidates old context; SDK callback starts no RPC while lock is held', async () => {
    const f = fixture(); const old = deferred<unknown>(); let calls = 0; let lockHeld = false;
    f.ports.getContext = async () => { assert.equal(lockHeld, false); calls++; return calls === 1 ? old.promise : contextOf('user-b'); };
    f.start(); await until(() => calls === 1);
    lockHeld = true; f.emit('SIGNED_IN', { userId: 'user-b' });
    assert.equal(calls, 1); assert.equal(f.context(), null); lockHeld = false;
    await until(() => f.access.getSnapshot().status === 'authorized');
    old.resolve(contextOf()); await delay(3);
    assert.equal(f.context()?.user_id, 'user-b'); assert.deepEqual(f.committed, ['user-b']);
});
test('a late initial session lookup cannot override a newer auth event', async () => {
    const f = fixture(); const initial = deferred<AccessSession | null>(); f.ports.getSession = () => initial.promise;
    f.ports.getContext = async () => contextOf('user-b'); f.start();
    f.emit('SIGNED_IN', { userId: 'user-b' });
    await until(() => f.access.getSnapshot().status === 'authorized');
    initial.resolve({ userId: 'user-a' }); await delay(3); assert.equal(f.context()?.user_id, 'user-b');
});
test('unmount aborts, clears store and unsubscribes; old callbacks stay invalid after remount', async () => {
    const f = fixture(); const old = deferred<unknown>(); f.ports.getContext = () => old.promise;
    const stop = f.start(); await delay(3); const oldCallback = f.callback(); stop();
    assert.equal(f.listeners(), 0); assert.equal(f.unsubscribed(), 1);
    f.ports.getContext = async () => contextOf('user-b'); f.ports.getSession = async () => ({ userId: 'user-b' }); f.start();
    await until(() => f.access.getSnapshot().status === 'authorized');
    oldCallback('SIGNED_OUT', null); old.resolve(contextOf()); await delay(3);
    assert.equal(f.context()?.user_id, 'user-b'); assert.deepEqual(f.committed, ['user-b']);
});
test('sign-in deadline never grants access and late SDK events are ignored', async () => {
    const f = fixture(12); f.ports.signIn = () => new Promise(() => {}); f.start(); await delay(3);
    assert.equal(await f.access.signIn({ email: 'test@example.invalid', password: 'test' }), false);
    f.emit('SIGNED_IN', { userId: 'user-a' }); await delay(3);
    assert.equal(f.access.getSnapshot().status, 'error'); assert.equal(f.context(), null);
});
test('explicit sign-in authorizes only after server context validation', async () => {
    const f = fixture(); f.ports.getSession = async () => null; f.start();
    await until(() => f.access.getSnapshot().status === 'unauthenticated');
    assert.equal(await f.access.signIn({ email: 'test@example.invalid', password: 'test' }), true);
    assert.equal(f.context()?.user_id, 'user-a');
});
test('password requests cannot overlap and a late cancelled attempt cannot switch identity', async () => {
    const f = fixture(); f.ports.getSession = async () => null; f.start();
    await until(() => f.access.getSnapshot().status === 'unauthenticated');
    const old = deferred<AccessSession | null>(); let calls = 0;
    f.ports.signIn = () => { calls++; return old.promise; };
    const first = f.access.signIn({ email: 'first@example.invalid', password: 'test' }); await delay(2);
    await f.access.signOut();
    assert.equal(await f.access.signIn({ email: 'next@example.invalid', password: 'test' }), false);
    assert.equal(calls, 1); f.emit('SIGNED_IN', { userId: 'user-a' }); old.resolve({ userId: 'user-a' });
    assert.equal(await first, false); await delay(2); assert.equal(f.context(), null);
    f.ports.signIn = async () => ({ userId: 'user-b' }); f.ports.getContext = async () => contextOf('user-b');
    assert.equal(await f.access.signIn({ email: 'next@example.invalid', password: 'test' }), true);
    assert.equal(f.context()?.user_id, 'user-b');
});
test('failed SDK logout cannot retain local permissions', async () => {
    const f = fixture(); f.start(); await until(() => f.access.getSnapshot().status === 'authorized');
    f.ports.signOut = async () => { throw new Error('internal-detail'); };
    assert.equal(await f.access.signOut(), false); assert.equal(f.context(), null);
    assert.equal(f.access.getSnapshot().status, 'unauthenticated');
    assert.ok(!f.access.getSnapshot().message?.includes('internal-detail'));
});
test('losing the active tenant ends access explicitly instead of entering RoleGuard redirects', async () => {
    const f = fixture(); f.start(); await until(() => f.access.getSnapshot().status === 'authorized');
    f.setTenant(null); assert.equal(f.access.getSnapshot().status, 'error'); assert.equal(f.context(), null);
    assert.equal(await f.access.retry(), true); assert.equal(f.tenant(), 'tenant-a');
});
test('two consumers share one subscription; final release alone stops it', async () => {
    const f = fixture(); const one = f.start(); const two = f.start();
    await until(() => f.access.getSnapshot().status === 'authorized'); one();
    assert.equal(f.unsubscribed(), 0); assert.equal(f.context()?.user_id, 'user-a'); two();
    assert.equal(f.unsubscribed(), 1); assert.equal(f.context(), null);
});
