import { supabase } from '@/lib/supabase';
import { scopedResponse } from '@/store/companyStore';
import { serializeCsv } from '@/utils/csv';

export type DeliveryRow = Record<string, string | number | null>;
export interface DeliveryPage {
    items: DeliveryRow[];
    total: number;
    next_cursor: string | null;
    company_ids: string[];
    classification_notice: string;
}
export const OPERATION_EXPORT_COLUMNS = [
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
];
export const RECEIVABLE_EXPORT_COLUMNS = [
    'id',
    'company_id',
    'operation_id',
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
];

export async function deliveryPage(
    tenantId: string,
    kind: 'operations' | 'receivables',
    search = '',
    cursor: string | null = null,
    exporting = false,
): Promise<DeliveryPage> {
    const { data, error } = await supabase.rpc(`rpc_delivery_${kind}_page`, {
        p_tenant_id: tenantId,
        p_search: search,
        p_after_id: cursor,
        p_limit: 50,
        p_export: exporting,
    });
    if (error || data?.error) throw new Error('No fue posible consultar este alcance empresarial.');
    if (
        !Array.isArray(data?.items) || !Number.isSafeInteger(data?.total) || data.total < 0 ||
        !(data.next_cursor === null || typeof data.next_cursor === 'string')
    ) throw new Error('Contrato empresarial inválido.');
    return data;
}

export async function deliveryCsv(
    tenantId: string,
    kind: 'operations' | 'receivables',
    search: string,
): Promise<string> {
    return scopedResponse(async () => {
        const rows: DeliveryRow[] = [];
        const seen = new Set<string>();
        let cursor: string | null = null;
        let total: number | null = null;
        do {
            const page = await deliveryPage(tenantId, kind, search, cursor, true);
            if (total !== null && total !== page.total) {
                throw new Error('El listado cambió; vuelve a exportar.');
            }
            total = page.total;
            if (total > 5000) throw new Error('Acota la búsqueda a 5000 registros antes de exportar.');
            rows.push(...page.items);
            cursor = page.next_cursor;
            if (cursor && seen.has(cursor)) throw new Error('Paginación inválida.');
            if (cursor) seen.add(cursor);
        } while (cursor);
        if (rows.length !== total) throw new Error('El listado cambió; vuelve a exportar.');
        return serializeCsv(
            rows,
            kind === 'operations' ? OPERATION_EXPORT_COLUMNS : RECEIVABLE_EXPORT_COLUMNS,
        );
    });
}

export interface CompanyFile {
    id: string;
    file_name: string;
    mime_type: string;
    size_bytes: number;
    created_at: string;
}
export async function operationFiles(
    tenantId: string,
    operationId: string,
    entityType = 'operation',
): Promise<CompanyFile[]> {
    const { data, error } = await supabase.rpc('rpc_delivery_entity_files', {
        p_tenant_id: tenantId,
        p_entity_id: operationId,
        p_entity_type: entityType,
    });
    if (error || data?.error || !Array.isArray(data?.items)) {
        throw new Error('No se pudo verificar el expediente documental.');
    }
    return data.items;
}

export async function downloadCompanyFile(
    tenantId: string,
    fileId: string,
): Promise<{ blob: Blob; name: string }> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_file_download', {
            p_tenant_id: tenantId,
            p_file_id: fileId,
        });
        if (
            error || data?.error || data?.id !== fileId || data.bucket !== 'tenant-documents' ||
            typeof data.path !== 'string'
        ) throw new Error('Descarga no autorizada.');
        // Authenticated Storage download rechecks RLS. No new signed URL is issued.
        const response = await supabase.storage.from(data.bucket).download(data.path);
        if (response.error || !response.data) throw new Error('Archivo no disponible.');
        return { blob: response.data, name: data.file_name };
    });
}
