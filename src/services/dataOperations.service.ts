import { supabase } from '@/lib/supabase';
import type { ExportEntity, ExportFilters, ExportPage, ImportBatch, ImportEntity, ImportMapping, ImportMode, ImportSummary, ImportValidation, ImportValidationItem } from '@/types/dataOperations';

const CHUNK_SIZE = 200; export const MAX_IMPORT_ROWS = 1000; export const MAX_SYNC_EXPORT_ROWS = 5000;

function assertRpc<T>(data: unknown, error: { message: string } | null): T {
    if (error) throw new Error(error.message);
    if (data && typeof data === 'object' && 'error' in data) throw new Error(String((data as { error: unknown }).error));
    return data as T;
}
function chunks<T>(items: T[], size = CHUNK_SIZE): T[][] { return Array.from({ length: Math.ceil(items.length / size) }, (_, index) => items.slice(index * size, (index + 1) * size)); }

export async function validateImport(tenantId: string, entity: ImportEntity, mode: ImportMode, rows: Array<Record<string, unknown>>): Promise<ImportValidation> {
    if (!rows.length || rows.length > MAX_IMPORT_ROWS) throw new Error('El archivo debe contener entre 1 y 1,000 filas.');
    const results: ImportValidationItem[] = []; const summary: ImportSummary = { total: 0, create: 0, update: 0, skip: 0, errors: 0, warnings: 0 };
    for (const part of chunks(rows)) {
        const { data, error } = await supabase.rpc('rpc_validate_bulk_import', { p_tenant_id: tenantId, p_entity_type: entity, p_mode: mode, p_rows: part });
        const response = assertRpc<ImportValidation>(data, error); results.push(...response.results);
        (Object.keys(summary) as Array<keyof ImportSummary>).forEach((key) => { summary[key] += response.summary[key] ?? 0; });
    }
    const occurrences = new Map<string, number>();
    rows.forEach((row) => { const key = String(row.external_key ?? '').trim().toLowerCase(); if (key) occurrences.set(key, (occurrences.get(key) ?? 0) + 1); });
    results.forEach((item) => {
        const key = item.external_key?.trim().toLowerCase();
        if (key && (occurrences.get(key) ?? 0) > 1 && !item.errors.some((issue) => issue.code === 'duplicate_external_key_in_file')) {
            item.errors.push({ code: 'duplicate_external_key_in_file', message: 'external_key está repetido dentro del archivo.' });
            if (item.action !== 'error') { summary[item.action] -= 1; summary.errors += 1; item.action = 'error'; }
        }
    });
    return { entity_type: entity, mode, results, summary };
}

export async function applyImport(tenantId: string, entity: ImportEntity, mode: ImportMode, filename: string, idempotencyKey: string, rows: Array<Record<string, unknown>>, summary: ImportSummary): Promise<{ batchId: string; results: ImportValidationItem[] }> {
    const { data: startData, error: startError } = await supabase.rpc('rpc_start_bulk_import', {
        p_tenant_id: tenantId, p_entity_type: entity, p_filename: filename, p_mode: mode, p_idempotency_key: idempotencyKey,
        p_total_rows: rows.length, p_validation_summary: summary,
    });
    const batch = assertRpc<{ id: string }>(startData, startError); const results: ImportValidationItem[] = []; const parts = chunks(rows);
    for (let index = 0; index < parts.length; index += 1) {
        const { data, error } = await supabase.rpc('rpc_apply_bulk_import', {
            p_tenant_id: tenantId, p_batch_id: batch.id, p_chunk_key: `chunk-${String(index).padStart(4, '0')}`,
            p_rows: parts[index], p_is_last: index === parts.length - 1,
        });
        results.push(...assertRpc<{ items: ImportValidationItem[] }>(data, error).items);
    }
    return { batchId: batch.id, results };
}

export async function listImportBatches(tenantId: string): Promise<ImportBatch[]> {
    const { data, error } = await supabase.rpc('rpc_list_import_batches', { p_tenant_id: tenantId, p_limit: 50 });
    return assertRpc<{ items: ImportBatch[] }>(data, error).items;
}
export async function listImportMappings(tenantId: string, entity: ImportEntity): Promise<ImportMapping[]> {
    const { data, error } = await supabase.rpc('rpc_list_import_mappings', { p_tenant_id: tenantId, p_entity_type: entity });
    return assertRpc<{ items: ImportMapping[] }>(data, error).items;
}
export async function saveImportMapping(tenantId: string, entity: ImportEntity, name: string, mapping: Record<string, string>, id?: string): Promise<ImportMapping> {
    const { data, error } = await supabase.rpc('rpc_save_import_mapping', { p_tenant_id: tenantId, p_payload: { id, entity_type: entity, name, mapping } });
    return assertRpc<ImportMapping>(data, error);
}
export async function deleteImportMapping(tenantId: string, id: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_delete_import_mapping', { p_tenant_id: tenantId, p_mapping_id: id }); assertRpc(data, error);
}

export async function exportData(tenantId: string, entity: ExportEntity, filters: ExportFilters): Promise<Array<Record<string, unknown>>> {
    const items: Array<Record<string, unknown>> = []; let cursor: ExportPage['next_cursor'] = null;
    do {
        const { data, error } = await supabase.rpc('rpc_export_data_page', { p_tenant_id: tenantId, p_entity_type: entity, p_filters: filters, p_cursor: cursor, p_limit: 500 });
        const page = assertRpc<ExportPage>(data, error); items.push(...page.items); cursor = page.next_cursor;
        if (items.length >= MAX_SYNC_EXPORT_ROWS && cursor) throw new Error('La exportación supera 5,000 filas. Acota fechas o filtros.');
    } while (cursor);
    return items;
}

export async function bulkUpdateOperations(tenantId: string, ids: string[], action: 'set_priority' | 'add_note', payload: Record<string, unknown>): Promise<number> {
    const { data, error } = await supabase.rpc('rpc_bulk_update_operations', { p_tenant_id: tenantId, p_operation_ids: ids, p_action: action, p_payload: payload });
    return assertRpc<{ updated: number }>(data, error).updated;
}
export async function recordDataAction(tenantId: string, action: 'export_requested' | 'bulk_action', entity: ExportEntity, count: number, detail?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_record_data_action', { p_tenant_id: tenantId, p_action: action, p_entity_type: entity, p_count: count, p_detail: detail }); assertRpc(data, error);
}
