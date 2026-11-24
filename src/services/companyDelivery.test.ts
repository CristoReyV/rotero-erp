import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SourceTextModule, SyntheticModule } from 'node:vm';
import ts from 'typescript';
import { parseCsv, serializeCsv } from '@/utils/csv';
import type { deliveryCsv, deliveryPage } from './companyDelivery.service';

const source = readFileSync(new URL('./companyDelivery.service.ts', import.meta.url), 'utf8');

async function setup() {
    const calls: { name: string; payload: Record<string, unknown> }[] = [];
    const supabase = {
        async rpc(name: string, payload: Record<string, unknown>) {
            calls.push({ name, payload });
            const later = payload.p_after_id !== null;
            const id = later ? 'second-row' : 'first-row';
            return {
                data: {
                    items: [{ id, reference_code: id }],
                    total: 2,
                    next_cursor: later ? null : 'first-row',
                    creation_date_timezone: 'America/Mexico_City',
                },
                error: null,
            };
        },
    };
    const modules: Record<string, Record<string, unknown>> = {
        '@/lib/supabase': { supabase },
        '@/store/companyStore': { scopedResponse: (request: () => Promise<unknown>) => request() },
        '@/utils/csv': { serializeCsv },
    };
    const code = ts.transpileModule(source, {
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
    }).outputText;
    const module = new SourceTextModule(code);
    await module.link((name) => {
        const values = modules[name];
        assert.ok(values);
        const keys = Object.keys(values);
        return new SyntheticModule(keys, function () {
            for (const key of keys) this.setExport(key, values[key]);
        });
    });
    await module.evaluate();
    const api = module.namespace as { deliveryPage: typeof deliveryPage; deliveryCsv: typeof deliveryCsv };
    return { ...api, calls };
}

test('list and every CSV page send the same creation bounds and search', async () => {
    const env = await setup();
    const period = { from: '2026-11-02', to: '2026-11-08' };
    await env.deliveryPage('tenant', 'operations', 'Cargas', null, false, period);
    const csv = parseCsv(await env.deliveryCsv('tenant', 'operations', 'Cargas', period));
    assert.deepEqual(csv.rows.map(row => row[0]), ['first-row', 'second-row']);
    assert.ok(env.calls.every(({ name }) => name === 'rpc_delivery_operations_page_by_creation'));
    assert.deepEqual(env.calls.map(({ payload }) => payload), [false, true, true].map((p_export, i) => ({
        p_tenant_id: 'tenant',
        p_search: 'Cargas',
        p_after_id: i === 2 ? 'first-row' : null,
        p_limit: 50,
        p_export,
        p_created_from: period.from,
        p_created_to: period.to,
    })));
});

test('a single bound stays null on the other end; clearing restores the existing RPC', async () => {
    const env = await setup();
    await env.deliveryPage('tenant', 'operations', '', null, false, { from: null, to: '2026-11-08' });
    assert.equal(env.calls[0].payload.p_created_from, null);
    assert.equal(env.calls[0].payload.p_created_to, '2026-11-08');
    await env.deliveryPage('tenant', 'operations', '', null, false, { from: null, to: null });
    assert.equal(env.calls[1].name, 'rpc_delivery_operations_page');
    assert.ok(!('p_created_to' in env.calls[1].payload));
    await env.deliveryPage('tenant', 'receivables', '', null, true, { from: '2026-11-02', to: null });
    assert.equal(env.calls[2].name, 'rpc_delivery_receivables_page');
    assert.ok(!('p_created_from' in env.calls[2].payload));
});
