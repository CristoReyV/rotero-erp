import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SourceTextModule, SyntheticModule } from 'node:vm';
import ts from 'typescript';

async function adapter() {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
    const code =
        ts.transpileModule(readFileSync(new URL('./executive.service.ts', import.meta.url), 'utf8'), {
            compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
        }).outputText;
    const source = new SourceTextModule(code);
    const client = {
        rpc: async (name: string, args: Record<string, unknown>) => {
            calls.push({ name, args });
            return { data: { items: [], unread_count: 0, next_cursor: null, has_more: false }, error: null };
        },
    };
    const mock = new SyntheticModule(['supabase'], function () {
        this.setExport('supabase', client);
    });
    await source.link((specifier) => {
        assert.equal(specifier, '@/lib/supabase', 'No real client or dynamic import is permitted');
        return mock;
    });
    await source.evaluate();
    return {
        calls,
        service: source.namespace as unknown as {
            listInternalNotifications: (tenant: string, unread: boolean, cursor: unknown) => Promise<unknown>;
            markInternalNotificationsRead: (tenant: string, ids: string[] | null) => Promise<void>;
            dismissInternalNotification: (tenant: string, id: string) => Promise<void>;
        },
    };
}

test('actual notification service lists only through the versioned read-only RPC', async () => {
    const { calls, service } = await adapter();
    await service.listInternalNotifications('test-tenant', false, null);
    assert.deepEqual(calls, [{
        name: 'rpc_delivery_notifications',
        args: {
            p_tenant_id: 'test-tenant',
        },
    }]);
    const migration = readFileSync(
        new URL('../../supabase/migrations/20261027185849_delivery_read_contracts.sql', import.meta.url),
        'utf8',
    );
    const definition = migration.slice(
        migration.indexOf('CREATE FUNCTION public.rpc_delivery_notifications'),
        migration.indexOf('DO $acl$'),
    );
    assert.match(definition, /STABLE/);
    assert.match(definition, /private\.delivery_scope_allowed/);
    assert.doesNotMatch(definition, /\b(INSERT|UPDATE|DELETE|CALL|EXECUTE)\b/i);
});
test('actual mark-read payload matches the SQL parameter name, including mark-all', async () => {
    const { calls, service } = await adapter();
    const migration = readFileSync(
        new URL('../../supabase/migrations/20260825000000_f5_executive_productivity.sql', import.meta.url),
        'utf8',
    );
    assert.match(
        migration,
        /rpc_mark_internal_notifications_read\(p_tenant_id uuid, p_notification_ids uuid\[\]/,
    );
    await service.markInternalNotificationsRead('test-tenant', ['one']);
    await service.markInternalNotificationsRead('test-tenant', null);
    assert.deepEqual(calls, [
        {
            name: 'rpc_mark_internal_notifications_read',
            args: { p_tenant_id: 'test-tenant', p_notification_ids: ['one'] },
        },
        {
            name: 'rpc_mark_internal_notifications_read',
            args: { p_tenant_id: 'test-tenant', p_notification_ids: null },
        },
    ]);
});
test('actual dismiss payload retains tenant and notification identifiers', async () => {
    const { calls, service } = await adapter();
    await service.dismissInternalNotification('test-tenant', 'one');
    assert.deepEqual(calls, [{
        name: 'rpc_dismiss_internal_notification',
        args: { p_tenant_id: 'test-tenant', p_notification_id: 'one' },
    }]);
});
