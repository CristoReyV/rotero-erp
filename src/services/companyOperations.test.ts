import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
    COMPANY_OPERATION_COLUMNS,
    type CompanyOperationsClient,
    createCompanyOperationsService,
} from './companyOperations.service';
import { parseCsv } from '../utils/csv';

const t = '00000000-0000-4000-8000-000000000001';
const a = '00000000-0000-4000-8000-000000000002';
const b = '00000000-0000-4000-8000-000000000003';
const op = '00000000-0000-4000-8000-000000000004';
const op2 = '00000000-0000-4000-8000-000000000005';
const notice = 'resolved_only; pending/conflict remain in the unchanged legacy workflow';
const item = (id = op) =>
    Object.fromEntries(
        COMPANY_OPERATION_COLUMNS.map((key) => [
            key,
            key === 'id'
                ? id
                : key === 'company_id'
                ? a
                : key === 'reference_code'
                ? '=formula,"quoted"\nnext'
                : key === 'status'
                ? 'planned'
                : key === 'created_at'
                ? '2026-01-01T00:00:00+00:00'
                : null,
        ]),
    );
const page = (items: unknown[] = [item()], cursor: string | null = null) => ({
    items,
    total: 2,
    next_cursor: cursor,
    scope: { tenant_id: t, company_id: a },
    classification_notice: notice,
});
const client = (data: unknown): CompanyOperationsClient => ({ rpc: async () => ({ data, error: null }) });

test('list, direct detail and CSV use immutable company scope and minimal projection', async () => {
    const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
    const service = createCompanyOperationsService(
        {
            rpc: async (name, args) => {
                calls.push({ name, args });
                const data = name.includes('get_operation')
                    ? { item: item() }
                    : args.p_after_id === op
                    ? page([item(op2)])
                    : page([item()], op);
                return { data, error: null };
            },
        },
        t,
        a,
    );
    assert.equal((await service.list('Needle', null, 1)).items.length, 1);
    assert.equal((await service.get(op)).id, op);
    const result = await service.exportCsv('Needle');
    const parsed = parseCsv(result.csv);
    assert.equal(result.count, 2);
    assert.deepEqual(parsed.headers, [...COMPANY_OPERATION_COLUMNS]);
    assert.equal(parsed.rows[0][2], '\'=formula,"quoted"\nnext');
    assert.ok(!/provider_cost|customer_price|profit|margin|FINANCIAL_CANARY/.test(result.csv));
    assert.ok(calls.every(({ args }) => args.p_tenant_id === t && args.p_company_id === a));
    assert.deepEqual(calls.filter(({ name }) => name.includes('export')).map(({ args }) => args.p_after_id), [
        null,
        op,
    ]);
    assert.equal(result.classificationNotice, notice);
});

test('RPC denial and transport errors never fall back to legacy APIs or expose raw errors', async () => {
    let calls = 0;
    const service = createCompanyOperationsService(
        {
            rpc: async () => {
                calls++;
                return { data: { error: 'unauthorized' }, error: null };
            },
        },
        t,
        a,
    );
    await assert.rejects(service.exportCsv(), /company_operations_unauthorized/);
    assert.equal(calls, 1);
    await assert.rejects(
        createCompanyOperationsService(
            {
                rpc: async () => {
                    throw new Error('SENSITIVE_BACKEND');
                },
            },
            t,
            a,
        ).list(),
        /^Error: company_operations_transport$/,
    );
});

test('foreign scope/ID and added financial or nested keys are rejected, never serialized', async () => {
    for (
        const data of [
            { ...page(), scope: { tenant_id: t, company_id: b } },
            page([{ ...item(), company_id: b }]),
            page([{ ...item(), provider_cost_amount: 12345 }]),
            page([{ ...item(), service_catalog_snapshot: { cost: 'FINANCIAL_CANARY' } }]),
            { ...page(), classification_notice: '' },
            { ...page(), next_cursor: op2 },
        ]
    ) {
        await assert.rejects(
            createCompanyOperationsService(client(data), t, a).exportCsv(),
            /invalid_response/,
        );
    }
    await assert.rejects(
        createCompanyOperationsService(client({ item: item(op2) }), t, a).get(op),
        /invalid_response/,
    );
});

test('revocation between export pages aborts the entire file', async () => {
    let calls = 0;
    const service = createCompanyOperationsService(
        {
            rpc: async () => ({
                data: ++calls === 1 ? page([item()], op) : { error: 'unauthorized' },
                error: null,
            }),
        },
        t,
        a,
    );
    await assert.rejects(service.exportCsv(), /unauthorized/);
    assert.equal(calls, 2);
});

test('duplicate/looping pages cannot duplicate rows or hang an export', async () => {
    const service = createCompanyOperationsService(client(page([item()], op)), t, a);
    await assert.rejects(service.exportCsv(), /invalid_response/);
});

test('disposing a context discards a late response and prevents further requests', async () => {
    let finish!: (v: { data: unknown; error: null }) => void;
    let calls = 0;
    const service = createCompanyOperationsService(
        {
            rpc: () => {
                calls++;
                return new Promise((resolve) => {
                    finish = resolve;
                });
            },
        },
        t,
        a,
    );
    const pending = service.list();
    service.dispose();
    finish({ data: page(), error: null });
    await assert.rejects(pending, /context_changed/);
    await assert.rejects(service.list(), /context_changed/);
    assert.equal(calls, 1);
});

test('invalid input is rejected before transport; empty scoped export retains its headers and notice', async () => {
    let calls = 0;
    const service = createCompanyOperationsService(
        {
            rpc: async () => {
                calls++;
                return { data: { ...page([]), total: 0 }, error: null };
            },
        },
        t,
        a,
    );
    await assert.rejects(service.list('', b, 0), /invalid_filters/);
    await assert.rejects(service.get('not-a-uuid'), /invalid_operation/);
    assert.equal(calls, 0);
    const empty = await service.exportCsv();
    assert.equal(empty.count, 0);
    assert.deepEqual(parseCsv(empty.csv).headers, [...COMPANY_OPERATION_COLUMNS]);
});
