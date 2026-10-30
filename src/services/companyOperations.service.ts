import { serializeCsv } from '../utils/csv';

// Prepared only. No route imports this client; backend EXECUTE remains revoked.
export const COMPANY_OPERATION_COLUMNS = [
    'id',
    'company_id',
    'reference_code',
    'status',
    'service_type',
    'route_summary',
    'client_display_name',
    'provider_name',
    'operation_scope',
    'execution_type',
    'priority',
    'planned_departure',
    'operational_window_start',
    'operational_window_end',
    'created_at',
] as const;
type Column = typeof COMPANY_OPERATION_COLUMNS[number];
export type CompanyOperation = Record<Column, string | null> & {
    id: string;
    company_id: string;
    reference_code: string;
    status: string;
    created_at: string;
};
export interface CompanyOperationsPage {
    items: CompanyOperation[];
    total: number;
    next_cursor: string | null;
    scope: { tenant_id: string; company_id: string };
    classification_notice: string;
}
export interface CompanyOperationsClient {
    rpc(name: string, parameters: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTICE = 'resolved_only; pending/conflict remain in the unchanged legacy workflow';
const PAGE_SIZE = 100;
const MAX_EXPORT_ROWS = 5000;
const record = (v: unknown): v is Record<string, unknown> =>
    v !== null && typeof v === 'object' && !Array.isArray(v);
const exactKeys = (v: Record<string, unknown>, keys: readonly string[]) =>
    Object.keys(v).length === keys.length && keys.every((key) => Object.hasOwn(v, key));
const fail = (reason: string): never => {
    throw new Error(`company_operations_${reason}`);
};

function operation(v: unknown, companyId: string): v is CompanyOperation {
    return record(v) && exactKeys(v, COMPANY_OPERATION_COLUMNS) &&
        COMPANY_OPERATION_COLUMNS.every((key) => typeof v[key] === 'string' || v[key] === null) &&
        typeof v.id === 'string' && UUID.test(v.id) && v.company_id === companyId &&
        typeof v.reference_code === 'string' && typeof v.status === 'string' &&
        typeof v.created_at === 'string';
}

/** Bind one immutable tenant/company scope. Dispose on identity/permission changes. */
export function createCompanyOperationsService(
    client: CompanyOperationsClient,
    tenantId: string,
    companyId: string,
) {
    if (!UUID.test(tenantId) || !UUID.test(companyId)) fail('invalid_scope');
    let disposed = false;
    const current = () => {
        if (disposed) fail('context_changed');
    };
    const invoke = async (name: string, parameters: Record<string, unknown>): Promise<unknown> => {
        current();
        let response: { data: unknown; error: unknown };
        try {
            response = await client.rpc(name, {
                p_tenant_id: tenantId,
                p_company_id: companyId,
                ...parameters,
            });
        } catch {
            current();
            return fail('transport');
        }
        current();
        if (response.error) fail('transport');
        if (record(response.data) && typeof response.data.error === 'string') {
            const known = ['unauthorized', 'not_found', 'invalid_filters', 'invalid_cursor'];
            return fail(known.includes(response.data.error) ? response.data.error : 'request_failed');
        }
        return response.data;
    };
    const page = async (
        exporting: boolean,
        search = '',
        afterId: string | null = null,
        limit = 50,
    ): Promise<CompanyOperationsPage> => {
        if (
            typeof search !== 'string' || search.length > 160 || !Number.isInteger(limit) || limit < 1 ||
            limit > 100 ||
            (afterId !== null && !UUID.test(afterId))
        ) fail('invalid_filters');
        const result = await invoke(
            exporting ? 'rpc_multi06_export_operations_page' : 'rpc_multi06_list_operations',
            {
                p_search: search,
                p_after_id: afterId,
                p_limit: limit,
            },
        );
        if (
            !record(result) ||
            !exactKeys(result, ['items', 'total', 'next_cursor', 'scope', 'classification_notice']) ||
            !record(result.scope) || !exactKeys(result.scope, ['tenant_id', 'company_id']) ||
            result.scope.tenant_id !== tenantId || result.scope.company_id !== companyId ||
            !Number.isSafeInteger(result.total) || (result.total as number) < 0 ||
            !Array.isArray(result.items) || result.items.length > limit ||
            result.items.length > (result.total as number) ||
            !result.items.every((item) => operation(item, companyId)) ||
            new Set(result.items.map((item) => item.id)).size !== result.items.length ||
            result.classification_notice !== NOTICE
        ) return fail('invalid_response');
        if (
            result.next_cursor !== null &&
            (typeof result.next_cursor !== 'string' || !UUID.test(result.next_cursor) ||
                result.next_cursor !== result.items.at(-1)?.id || result.next_cursor === afterId)
        ) return fail('invalid_response');
        return result as unknown as CompanyOperationsPage;
    };
    return {
        list: (search = '', afterId: string | null = null, limit = 50) => page(false, search, afterId, limit),
        async get(operationId: string): Promise<CompanyOperation> {
            if (!UUID.test(operationId)) fail('invalid_operation');
            const result = await invoke('rpc_multi06_get_operation', { p_operation_id: operationId });
            if (
                !record(result) || !exactKeys(result, ['item']) || !operation(result.item, companyId) ||
                result.item.id !== operationId
            ) return fail('invalid_response');
            return result.item;
        },
        async exportCsv(search = ''): Promise<{ csv: string; count: number; classificationNotice: string }> {
            const rows: CompanyOperation[] = [];
            const seen = new Set<string>();
            let cursor: string | null = null;
            do {
                const result = await page(true, search, cursor, PAGE_SIZE);
                if (rows.length + result.items.length > MAX_EXPORT_ROWS) fail('export_limit');
                for (const item of result.items) {
                    if (seen.has(item.id)) fail('invalid_response');
                    seen.add(item.id);
                    rows.push(item);
                }
                cursor = result.next_cursor;
            } while (cursor !== null);
            current();
            return {
                csv: serializeCsv(rows, [...COMPANY_OPERATION_COLUMNS]),
                count: rows.length,
                classificationNotice: NOTICE,
            };
        },
        dispose() {
            disposed = true;
        },
    };
}
