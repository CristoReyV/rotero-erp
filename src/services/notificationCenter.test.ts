import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { createNotificationCenter, type NotificationAutomaticEvent, type NotificationCenterPorts, type NotificationScope } from './notificationCenter';
import type { InternalNotification, NotificationFeed } from '../types/executive';

const scope: NotificationScope = { userId: 'user-a', tenantId: 'tenant-a', role: 'admin' };
const item = (id = 'item-a', read = false): InternalNotification => ({
    id, module: 'operations', kind: 'test', priority: 'high', title: 'Test notice', body: 'Test',
    route: '/operations?operationId=test', entity_type: 'operation', entity_id: 'test',
    occurred_at: '2026-10-14T12:00:00Z', due_at: null, read_at: read ? '2026-10-14T12:00:00Z' : null,
    created_at: '2026-10-14T12:00:00Z', is_automated: false, automation_rule_code: null,
    first_seen_at: null, last_seen_at: null, escalation_level: 0, escalated_at: null, metadata: {},
});
const feed = (items = [item()]): NotificationFeed => ({ items, unread_count: 1, has_more: false, next_cursor: null });
function deferred<T>() {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>(done => { resolve = done; });
    return { promise, resolve };
}
function fixture(timeout = 80) {
    const calls: Array<{ rpc: string; tenant: string; ids?: string[] | null; id?: string; cursor?: NotificationFeed['next_cursor'] }> = [];
    const ports: NotificationCenterPorts = {
        list: async (tenant, _unread, cursor) => { calls.push({ rpc: 'list', tenant, cursor }); return feed(); },
        markRead: async (tenant, ids) => { calls.push({ rpc: 'mark', tenant, ids }); },
        dismiss: async (tenant, id) => { calls.push({ rpc: 'dismiss', tenant, id }); },
    };
    const center = createNotificationCenter(ports, timeout);
    center.setScope(scope);
    return { center, ports, calls };
}

for (const event of ['mount', 'navigation', 'focus', 'online', 'context'] as NotificationAutomaticEvent[]) {
    test(`${event} lists without any write or materialization port`, async () => {
        const f = fixture(); await f.center.automatic(event);
        assert.deepEqual(f.calls, [{ rpc: 'list', tenant: 'tenant-a', cursor: null }]);
        assert.equal(f.center.getSnapshot().items.length, 1);
    });
}
test('combined automatic events never mark, dismiss or materialize notifications', async () => {
    const f = fixture();
    await Promise.all(['mount', 'navigation', 'focus', 'online'].map(event => f.center.automatic(event as NotificationAutomaticEvent)));
    assert.equal(f.calls.length, 4); assert.ok(f.calls.every(call => call.rpc === 'list'));
});
test('mark read occurs only on explicit opening; already-read items do not write', async () => {
    const f = fixture(); await f.center.load();
    assert.equal(f.calls.filter(call => call.rpc === 'mark').length, 0);
    assert.equal(await f.center.openItem(item()), item().route);
    assert.deepEqual(f.calls.at(-1), { rpc: 'mark', tenant: 'tenant-a', ids: ['item-a'] });
    const count = f.calls.length; assert.equal(await f.center.openItem(item('item-a', true)), item().route);
    assert.equal(f.calls.length, count);
});
test('mark all and dismiss retain current tenant/id contracts after explicit action', async () => {
    const f = fixture(); await f.center.load(); await f.center.markAll(); await f.center.dismiss('item-a');
    assert.deepEqual(f.calls.filter(call => call.rpc !== 'list'), [
        { rpc: 'mark', tenant: 'tenant-a', ids: null }, { rpc: 'dismiss', tenant: 'tenant-a', id: 'item-a' },
    ]);
});
test('list rejection is isolated and leaves a safe retryable state', async () => {
    const f = fixture(); f.ports.list = async () => { throw new Error('internal-detail'); };
    await f.center.automatic('mount'); assert.equal(f.center.getSnapshot().loading, false);
    assert.ok(f.center.getSnapshot().error); assert.ok(!f.center.getSnapshot().error?.includes('internal-detail'));
    f.ports.list = async () => feed(); await f.center.load(); assert.equal(f.center.getSnapshot().error, null);
});
test('a non-resolving list also ends loading at the deadline', async () => {
    const f = fixture(12); f.ports.list = () => new Promise(() => {});
    await f.center.load(); assert.equal(f.center.getSnapshot().loading, false);
    assert.ok(f.center.getSnapshot().error); assert.equal(f.calls.length, 0);
});
for (const change of [null, { ...scope, tenantId: 'tenant-b' }, { ...scope, userId: 'user-b' }, { ...scope, role: 'finance' }]) {
    test(`context change ${JSON.stringify(change)} clears feed, count and cursor immediately`, async () => {
        const f = fixture(); await f.center.load(); f.center.setScope(change);
        const next = f.center.getSnapshot(); assert.deepEqual(next.items, []); assert.equal(next.unread, 0);
        assert.equal(next.nextCursor, null); assert.equal(next.error, null); assert.equal(next.busy, false);
    });
}
test('late old feed cannot replace new tenant data', async () => {
    const f = fixture(); const old = deferred<NotificationFeed>(); f.ports.list = () => old.promise;
    const pending = f.center.load(); await delay(2);
    f.center.setScope({ ...scope, tenantId: 'tenant-b' }); f.ports.list = async () => feed([item('item-b')]);
    await f.center.load(); old.resolve(feed()); await pending; await delay(2);
    assert.deepEqual(f.center.getSnapshot().items.map(value => value.id), ['item-b']);
});
test('logout/unmount cancels pending results and prevents future automatic calls', async () => {
    const f = fixture(); const old = deferred<NotificationFeed>(); f.ports.list = () => old.promise;
    const pending = f.center.load(); await delay(2); f.center.setScope(null); old.resolve(feed()); await pending;
    await f.center.automatic('focus'); await f.center.automatic('online');
    assert.deepEqual(f.center.getSnapshot().items, []); assert.equal(f.center.getSnapshot().loading, false);
});
test('late mark response cannot navigate or restore feed after a user switch', async () => {
    const f = fixture(); await f.center.load(); const mark = deferred<void>(); f.ports.markRead = () => mark.promise;
    const pending = f.center.openItem(item()); await delay(2); f.center.setScope({ ...scope, userId: 'user-b' });
    mark.resolve(); assert.equal(await pending, null); assert.deepEqual(f.center.getSnapshot().items, []);
});
test('old row actions cannot write in the new context', async () => {
    const f = fixture(); await f.center.load(); f.center.setScope({ ...scope, tenantId: 'tenant-b' });
    assert.equal(await f.center.openItem(item()), null); await f.center.dismiss('item-a');
    assert.ok(f.calls.every(call => call.rpc === 'list'));
});
test('pagination preserves the server cursor and merges unique rows', async () => {
    const f = fixture(); const cursor: NotificationFeed['next_cursor'] = {
        tenant_id: 'tenant-a', user_id: 'user-a', unread_only: false, first_seen_at: '2026-10-14T12:00:00Z', id: 'item-a',
    };
    f.ports.list = async (_tenant, _unread, current) => current
        ? feed([item(), item('item-b')]) : { ...feed(), has_more: true, next_cursor: cursor };
    await f.center.load(); await f.center.load(true);
    assert.deepEqual(f.center.getSnapshot().items.map(value => value.id), ['item-a', 'item-b']);
    assert.equal(f.center.getSnapshot().nextCursor, null);
});
test('late earlier read in same context cannot overwrite latest read', async () => {
    const f = fixture(); const old = deferred<NotificationFeed>(); f.ports.list = () => old.promise;
    const first = f.center.load(); await delay(2); f.ports.list = async () => feed([item('newest')]);
    await f.center.load(); old.resolve(feed()); await first;
    assert.equal(f.center.getSnapshot().items[0].id, 'newest');
});
test('write rejection cannot navigate; next automatic load remains read-only', async () => {
    const f = fixture(); await f.center.load(); f.ports.markRead = async () => { throw new Error('internal-detail'); };
    assert.equal(await f.center.openItem(item()), null); assert.equal(f.center.getSnapshot().busy, false);
    assert.ok(f.center.getSnapshot().error); await f.center.automatic('focus');
    assert.ok(f.calls.every(call => call.rpc === 'list'));
});
test('duplicate explicit writes are suppressed while an action is pending', async () => {
    const f = fixture(); await f.center.load(); const mark = deferred<void>(); let writes = 0;
    f.ports.markRead = () => { writes++; return mark.promise; };
    const one = f.center.markAll(); await delay(2); await f.center.markAll(); assert.equal(writes, 1);
    mark.resolve(); await one; assert.equal(f.center.getSnapshot().busy, false);
});
