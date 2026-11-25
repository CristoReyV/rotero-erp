import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SourceTextModule, SyntheticModule } from 'node:vm';
import ts from 'typescript';
import { parseCsv, serializeCsv } from '@/utils/csv';
import type { deliveryCsv, deliveryPage } from './companyDelivery.service';

const source = readFileSync(new URL('./companyDelivery.service.ts', import.meta.url), 'utf8');

test('staging 61 lists, searches and exports operations using the existing RPC', async () => {
    const calls: Record<string, unknown>[] = [];
    const operations = Array.from({ length: 51 }, (_, index) => {
        const id = 'A-' + String(index + 1).padStart(2, '0');
        return { id, company_id: 'company-a', reference_code: id, customer_price_amount: 900 };
    });
    const supabase = {
        async rpc(name: string, payload: Record<string, unknown>) {
            assert.equal(name, 'rpc_delivery_operations_page');
            calls.push(payload);
            const results = operations.filter((operation) => operation.reference_code.includes(String(payload.p_search)));
            const page = results.filter((operation) => (
                payload.p_after_id == null || operation.id > String(payload.p_after_id)
            )).slice(0, Number(payload.p_limit));
            const cursor = page.at(-1)?.id;
            return {
                data: {
                    items: page,
                    total: results.length,
                    next_cursor: cursor && results.some((operation) => operation.id > cursor) ? cursor : null,
                },
                error: null,
            };
        },
    };
    const imports: Record<string, Record<string, unknown>> = {
        '@/lib/supabase': { supabase },
        '@/store/companyStore': { scopedResponse: (request: () => Promise<unknown>) => request() },
        '@/utils/csv': { serializeCsv },
    };
    const service = new SourceTextModule(ts.transpileModule(source, {
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
    }).outputText);
    await service.link((name) => {
        const values = imports[name];
        assert.ok(values);
        return new SyntheticModule(Object.keys(values), function () {
            for (const [key, value] of Object.entries(values)) this.setExport(key, value);
        });
    });
    await service.evaluate();
    const api = service.namespace as { deliveryCsv: typeof deliveryCsv; deliveryPage: typeof deliveryPage };

    const first = await api.deliveryPage('tenant', 'operations', 'A-');
    assert.equal(first.total, 51);
    assert.equal(first.items.length, 50);
    assert.equal(first.next_cursor, 'A-50');
    const second = await api.deliveryPage('tenant', 'operations', 'A-', first.next_cursor);
    assert.deepEqual(second.items.map(({ id }) => id), ['A-51']);
    assert.deepEqual((await api.deliveryPage('tenant', 'operations', 'A-51')).items.map(({ id }) => id), ['A-51']);
    assert.equal((await api.deliveryPage('tenant', 'operations', 'B-')).total, 0);

    const csv = parseCsv(await api.deliveryCsv('tenant', 'operations', 'A-'));
    const idColumn = csv.headers.indexOf('id');
    assert.ok(idColumn >= 0);
    assert.deepEqual(csv.rows.map((row) => row[idColumn]), [...first.items, ...second.items].map(({ id }) => id));
    assert.ok(!csv.headers.includes('customer_price_amount'));

    assert.deepEqual(calls, [
        ['A-', null, false], ['A-', 'A-50', false], ['A-51', null, false],
        ['B-', null, false], ['A-', null, true], ['A-', 'A-50', true],
    ].map(([p_search, p_after_id, p_export]) => ({ p_tenant_id: 'tenant', p_search, p_after_id, p_limit: 50, p_export })));
});
