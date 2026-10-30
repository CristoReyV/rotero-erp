import assert from 'node:assert/strict';
import { test } from 'node:test';
import { COMPANY_FINANCE_COLUMNS, createCompanyFinanceService } from './companyFinance.service';
import { parseCsv } from '../utils/csv';
const t = '00000000-0000-4000-8000-000000000001';
const a = '00000000-0000-4000-8000-000000000002';
const b = '00000000-0000-4000-8000-000000000003';
const id = '00000000-0000-4000-8000-000000000004';
const id2 = '00000000-0000-4000-8000-000000000005';
const notice = 'resolved_only; payroll and unclassified legacy remain outside this protection';
const item = (invoiceId = id, company = a) => ({
    id: invoiceId,
    company_id: company,
    operation_id: null,
    direction: 'ar',
    reference: '=formula,"q"\nnext',
    counterparty_name: 'Synthetic counterparty',
    currency: 'MXN',
    status: 'open',
    due_date: null,
    amount: 100,
    paid_amount: 20,
    credit_amount: 10,
    balance_amount: 70,
    created_at: '2026-01-01T00:00:00+00:00',
});
const page = (
    items: unknown[] = [item()],
    cursor: string | null = null,
    companies = [a],
    consolidated = false,
) => ({
    items,
    total: 2,
    next_cursor: cursor,
    scope: { tenant_id: t, company_ids: companies, consolidated },
    classification_notice: notice,
});
const client = (data: unknown) => ({ rpc: async () => ({ data, error: null }) });

test('list/detail/CSV keep scope and exact financial projection, with CSV formula escaping', async () => {
    const calls: string[] = [];
    const service = createCompanyFinanceService(
        {
            rpc: async (name, args) => {
                calls.push(name);
                assert.equal(args.p_tenant_id, t);
                if (name === 'rpc_multi07_get_invoice') {
                    return {
                        data: { item: item(), payments: [], credit_notes: [], complements: [] },
                        error: null,
                    };
                }
                assert.deepEqual(args.p_company_ids, [a]);
                return { data: args.p_after_id === id ? page([item(id2)]) : page([item()], id), error: null };
            },
        },
        t,
        [a],
    );
    assert.equal((await service.list()).items.length, 1);
    assert.ok((await service.get(id)).item);
    const exported = await service.exportCsv();
    assert.equal(exported.count, 2);
    const parsed = parseCsv(exported.csv);
    assert.deepEqual(parsed.headers, [...COMPANY_FINANCE_COLUMNS]);
    assert.equal(parsed.rows[0][4], '\'=formula,"q"\nnext');
    assert.ok(!/notes|bank_reference|snapshot|SYNTHETIC_PRIVATE_CANARY/.test(exported.csv));
    assert.equal(calls.filter((c) => c === 'rpc_multi07_export_invoices_page').length, 2);
});
test('unauthorized never returns a payload/CSV or falls back to tenant-wide legacy', async () => {
    let calls = 0;
    const service = createCompanyFinanceService(
        {
            rpc: async () => {
                calls++;
                return { data: { error: 'unauthorized' }, error: null };
            },
        },
        t,
        [a],
    );
    await assert.rejects(service.list(), /unauthorized/);
    await assert.rejects(service.exportCsv(), /unauthorized/);
    assert.equal(calls, 2);
});
test('foreign company/scope, raw private fields and malformed numeric values are rejected before CSV', async () => {
    for (
        const data of [
            page([item(id, b)]),
            page([{ ...item(), notes: 'SYNTHETIC_PRIVATE_CANARY' }]),
            page([{ ...item(), amount: '100' }]),
            page([{ ...item(), balance_amount: Infinity }]),
            { ...page(), scope: { tenant_id: t, company_ids: [b], consolidated: false } },
            { ...page(), classification_notice: '' },
            { ...page(), next_cursor: id2 },
        ]
    ) {
        await assert.rejects(
            createCompanyFinanceService(client(data), t, [a]).exportCsv(),
            /invalid_response/,
        );
    }
});
test('consolidation requires an explicit mode and response scope cannot expand', async () => {
    assert.throws(() => createCompanyFinanceService(client(null), t, [a, b]), /invalid_scope/);
    assert.throws(() => createCompanyFinanceService(client(null), t, [a, a], true), /invalid_scope/);
    const result = {
        groups: [{
            company_id: null,
            currency: 'MXN',
            direction: 'ar',
            invoice_count: 2,
            amount: 300,
            paid_amount: 20,
            credit_amount: 10,
            balance_amount: 270,
        }],
        currency_policy: 'separate',
        scope: { tenant_id: t, company_ids: [a, b], consolidated: true },
        classification_notice: notice,
    };
    assert.ok(await createCompanyFinanceService(client(result), t, [a, b], true).summary());
    await assert.rejects(
        createCompanyFinanceService(client({ ...result, scope: { ...result.scope, company_ids: [a] } }), t, [
            a,
            b,
        ], true).summary(),
        /invalid_response/,
    );
});
test('revocation on a later page and repeated cursors abort the entire export', async () => {
    let calls = 0;
    const service = createCompanyFinanceService(
        {
            rpc: async () => ({
                data: ++calls === 1 ? page([item()], id) : { error: 'unauthorized' },
                error: null,
            }),
        },
        t,
        [a],
    );
    await assert.rejects(service.exportCsv(), /unauthorized/);
    await assert.rejects(
        createCompanyFinanceService(client(page([item()], id)), t, [a]).exportCsv(),
        /invalid_response/,
    );
});
test('context disposal discards late financial data and prevents follow-up calls', async () => {
    let finish!: (v: { data: unknown; error: null }) => void;
    let calls = 0;
    const service = createCompanyFinanceService(
        {
            rpc: () => {
                calls++;
                return new Promise((resolve) => {
                    finish = resolve;
                });
            },
        },
        t,
        [a],
    );
    const pending = service.list();
    service.dispose();
    finish({ data: page(), error: null });
    await assert.rejects(pending, /context_changed/);
    await assert.rejects(service.list(), /context_changed/);
    assert.equal(calls, 1);
});
test('detail rejects foreign invoice children and nested private content', async () => {
    const detail = {
        item: item(),
        payments: [{
            id: id2,
            invoice_id: b,
            amount: 20,
            currency: 'MXN',
            paid_at: '2026-01-01',
            method: 'cash',
        }],
        credit_notes: [],
        complements: [],
    };
    await assert.rejects(createCompanyFinanceService(client(detail), t, [a]).get(id), /invalid_response/);
    detail.payments[0].invoice_id = id;
    await createCompanyFinanceService(client(detail), t, [a]).get(id);
    await assert.rejects(
        createCompanyFinanceService(
            client({ ...detail, payments: [{ ...detail.payments[0], method: { note: 'private' } }] }),
            t,
            [a],
        ).get(id),
        /invalid_response/,
    );
});
