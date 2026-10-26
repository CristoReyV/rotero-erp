import { serializeCsv } from '../utils/csv';
import type { CompanyOperationsClient } from './companyOperations.service';

// Prepared only; backend EXECUTE remains closed and no route instantiates this.
export const COMPANY_FINANCE_COLUMNS = [
    'id',
    'company_id',
    'operation_id',
    'direction',
    'reference',
    'counterparty_name',
    'currency',
    'status',
    'due_date',
    'amount',
    'paid_amount',
    'credit_amount',
    'balance_amount',
    'created_at',
] as const;
const MONEY = ['amount', 'paid_amount', 'credit_amount', 'balance_amount'] as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTICE = 'resolved_only; payroll and unclassified legacy remain outside this protection';
const record = (v: unknown): v is Record<string, unknown> =>
    v !== null && typeof v === 'object' && !Array.isArray(v);
const keys = (v: Record<string, unknown>, expected: readonly string[]) =>
    Object.keys(v).length === expected.length && expected.every((key) => Object.hasOwn(v, key));
const fail = (reason: string): never => {
    throw new Error(`company_finance_${reason}`);
};
type Invoice = Record<string, unknown> & { id: string; company_id: string };
export interface FinanceReadFilters {
    search?: string;
    direction?: '' | 'ar' | 'ap';
    currency?: '' | 'MXN' | 'USD';
}

export function createCompanyFinanceService(
    client: CompanyOperationsClient,
    tenant: string,
    companyIds: readonly string[],
    consolidated = false,
) {
    const companies = [...companyIds];
    if (
        !UUID.test(tenant) || !companies.length || companies.some((id) => !UUID.test(id)) ||
        new Set(companies).size !== companies.length || (!consolidated && companies.length !== 1)
    ) fail('invalid_scope');
    let disposed = false;
    const current = () => {
        if (disposed) fail('context_changed');
    };
    const scope = (v: unknown) =>
        record(v) && keys(v, ['tenant_id', 'company_ids', 'consolidated']) && v.tenant_id === tenant &&
        v.consolidated === consolidated && Array.isArray(v.company_ids) &&
        v.company_ids.length === companies.length &&
        v.company_ids.every((id, i) => id === companies[i]);
    const invoice = (v: unknown): v is Invoice =>
        record(v) && keys(v, COMPANY_FINANCE_COLUMNS) &&
        typeof v.id === 'string' && UUID.test(v.id) && typeof v.company_id === 'string' &&
        companies.includes(v.company_id) &&
        (v.operation_id === null || typeof v.operation_id === 'string' && UUID.test(v.operation_id)) &&
        ['ar', 'ap'].includes(String(v.direction)) && ['MXN', 'USD'].includes(String(v.currency)) &&
        MONEY.every((key) => typeof v[key] === 'number' && Number.isFinite(v[key])) &&
        ['reference', 'due_date'].every((key) => v[key] === null || typeof v[key] === 'string') &&
        ['counterparty_name', 'status', 'created_at'].every((key) => typeof v[key] === 'string');
    const invoke = async (name: string, args: Record<string, unknown>) => {
        current();
        let response: { data: unknown; error: unknown };
        try {
            response = await client.rpc(name, { p_tenant_id: tenant, ...args });
        } catch {
            current();
            return fail('transport');
        }
        current();
        if (response.error) return fail('transport');
        if (record(response.data) && typeof response.data.error === 'string') {
            return fail(
                ['unauthorized', 'not_found', 'invalid_cursor', 'invalid_filters'].includes(
                        response.data.error,
                    )
                    ? response.data.error
                    : 'request_failed',
            );
        }
        return response.data;
    };
    const page = async (
        exporting: boolean,
        filters: FinanceReadFilters = {},
        after: string | null = null,
        limit = 50,
    ) => {
        const search = filters.search ?? '';
        if (
            search.length > 160 || !Number.isInteger(limit) || limit < 1 || limit > 100 ||
            (after !== null && !UUID.test(after))
        ) fail('invalid_filters');
        const data = await invoke(
            exporting ? 'rpc_multi07_export_invoices_page' : 'rpc_multi07_list_invoices',
            {
                p_company_ids: companies,
                p_search: search,
                p_direction: filters.direction ?? '',
                p_currency: filters.currency ?? '',
                p_after_id: after,
                p_limit: limit,
                p_consolidated: consolidated,
            },
        );
        if (
            !record(data) ||
            !keys(data, ['items', 'total', 'next_cursor', 'scope', 'classification_notice']) ||
            !scope(data.scope) || data.classification_notice !== NOTICE ||
            !Number.isSafeInteger(data.total) || (data.total as number) < 0 ||
            !Array.isArray(data.items) || data.items.length > limit ||
            data.items.length > (data.total as number) ||
            !data.items.every(invoice) || new Set(data.items.map((v) => v.id)).size !== data.items.length ||
            (data.next_cursor !== null &&
                (data.next_cursor !== data.items.at(-1)?.id || data.next_cursor === after))
        ) return fail('invalid_response');
        return data as {
            items: Invoice[];
            total: number;
            next_cursor: string | null;
            classification_notice: string;
        };
    };
    return {
        list: (filters: FinanceReadFilters = {}, after: string | null = null, limit = 50) =>
            page(false, filters, after, limit),
        async summary() {
            const data = await invoke('rpc_multi07_finance_summary', {
                p_company_ids: companies,
                p_consolidated: consolidated,
            });
            if (
                !record(data) ||
                !keys(data, ['groups', 'scope', 'currency_policy', 'classification_notice']) ||
                !scope(data.scope) ||
                data.currency_policy !== 'separate' || data.classification_notice !== NOTICE ||
                !Array.isArray(data.groups) ||
                !data.groups.every((g) =>
                    record(g) &&
                    keys(g, ['company_id', 'currency', 'direction', 'invoice_count', ...MONEY]) &&
                    (consolidated ? g.company_id === null : companies.includes(String(g.company_id))) &&
                    ['MXN', 'USD'].includes(String(g.currency)) &&
                    ['ar', 'ap'].includes(String(g.direction)) &&
                    Number.isSafeInteger(g.invoice_count) && (g.invoice_count as number) >= 0 &&
                    MONEY.every((key) => typeof g[key] === 'number' && Number.isFinite(g[key]))
                )
            ) return fail('invalid_response');
            return data;
        },
        async get(invoiceId: string) {
            if (companies.length !== 1 || !UUID.test(invoiceId)) return fail('invalid_scope');
            const data = await invoke('rpc_multi07_get_invoice', {
                p_company_id: companies[0],
                p_invoice_id: invoiceId,
            });
            if (
                !record(data) || !keys(data, ['item', 'payments', 'credit_notes', 'complements']) ||
                !invoice(data.item) || data.item.id !== invoiceId
            ) return fail('invalid_response');
            for (
                const [key, columns] of [
                    ['payments', ['id', 'invoice_id', 'amount', 'currency', 'paid_at', 'method']],
                    ['credit_notes', ['id', 'invoice_id', 'amount', 'currency', 'status']],
                    ['complements', ['id', 'invoice_id', 'payment_id', 'amount', 'currency', 'status']],
                ] as const
            ) {
                const children = data[key];
                if (
                    !Array.isArray(children) ||
                    !children.every((r) =>
                        record(r) && keys(r, columns) && r.invoice_id === invoiceId &&
                        typeof r.id === 'string' && UUID.test(r.id) && typeof r.amount === 'number' &&
                        Number.isFinite(r.amount) &&
                        ['MXN', 'USD'].includes(String(r.currency)) &&
                        columns.every((column) =>
                            column === 'amount' || (column === 'payment_id'
                                ? r[column] === null || typeof r[column] === 'string' && UUID.test(r[column])
                                : typeof r[column] === 'string')
                        )
                    )
                ) return fail('invalid_response');
            }
            return data;
        },
        async exportCsv(filters: FinanceReadFilters = {}) {
            const rows: Invoice[] = [];
            const seen = new Set<string>();
            let after: string | null = null;
            do {
                const result = await page(true, filters, after, 100);
                if (rows.length + result.items.length > 5000) fail('export_limit');
                for (const item of result.items) {
                    if (seen.has(item.id)) fail('invalid_response');
                    seen.add(item.id);
                    rows.push(item);
                }
                after = result.next_cursor;
            } while (after !== null);
            current();
            return {
                csv: serializeCsv(rows, [...COMPANY_FINANCE_COLUMNS]),
                count: rows.length,
                classificationNotice: NOTICE,
            };
        },
        dispose() {
            disposed = true;
        },
    };
}
