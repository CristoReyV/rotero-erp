import { supabase } from '@/lib/supabase';
import { scopedResponse } from '@/store/companyStore';
import { sha256, validateDocumentFile } from './documents.service';
import type { DocumentUploadContract } from '@/types/documents';
import type { CompanyFile } from './companyDelivery.service';

export type DocumentParent = 'operation' | 'finance_invoice' | 'billing_document';
export interface CompanyDocument extends CompanyFile {
    status: 'active' | 'superseded' | 'cancelled';
    access_class: 'operational' | 'financial';
    events: Array<{ id: string; action: string; previous_file_id: string | null; created_at: string }>;
}
const messages: Record<string, string> = {
    unauthorized: 'No tienes permiso documental para este contexto.',
    upload_expired: 'La autorización de carga venció. Selecciona otra vez el archivo.',
    replacement_conflict: 'La versión cambió. Actualiza el expediente antes de sustituirla.',
    storage_object_not_verified: 'La carga no coincide con el archivo autorizado.',
    file_type_or_size_not_allowed: 'El tipo o tamaño del archivo no están permitidos.',
};
async function call<T>(name: string, args: Record<string, unknown>): Promise<T> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc(name, args);
        if (error || data?.error) throw new Error(messages[String(data?.error)] ?? 'No fue posible confirmar la acción documental.');
        return data as T;
    });
}
export async function companyDocumentHistory(tenant: string, kind: DocumentParent, id: string): Promise<CompanyDocument[]> {
    const data = await call<{ items: CompanyDocument[] }>('rpc_delivery_document_history', {
        p_tenant_id: tenant, p_entity_type: kind, p_entity_id: id,
    });
    if (!Array.isArray(data.items)) throw new Error('No fue posible verificar las versiones.');
    return data.items;
}
export async function companyDocumentSources(tenant: string, query: string): Promise<Array<{ kind: DocumentParent; id: string; label: string }>> {
    const data = await call<{ items: Array<{ kind: DocumentParent; id: string; label: string }> }>('rpc_delivery_document_sources', {
        p_tenant_id: tenant, p_query: query,
    });
    return data.items;
}
export async function uploadCompanyDocument(tenant: string, kind: DocumentParent, parent: string, file: File,
    accessClass: 'operational' | 'financial', previous?: string, reason?: string): Promise<void> {
    return scopedResponse(async () => {
        const contract = await call<DocumentUploadContract>('rpc_delivery_upload_contract', { p_tenant_id: tenant });
        const invalid = validateDocumentFile(file, contract);
        if (invalid) throw new Error(invalid);
        const checksum = await sha256(file);
        const prepared = await call<{ id: string; bucket: string; path: string; file_id: string | null }>('rpc_delivery_prepare_upload', {
            p_tenant_id: tenant, p_request_id: crypto.randomUUID(), p_payload: {
                entity_type: kind, entity_id: parent, access_class: accessClass, file_name: file.name,
                mime_type: file.type, size_bytes: file.size, checksum_sha256: checksum,
                replaces_file_id: previous ?? null, reason: reason?.trim() || null,
            },
        });
        if (prepared.file_id) return;
        const upload = await supabase.storage.from(prepared.bucket).upload(prepared.path, file, { contentType: file.type, upsert: false });
        if (upload.error) throw new Error('No fue posible completar la carga privada.');
        // A failed finalization does not delete historical bytes or bypass RLS.
        // Its intent is retained for targeted reconciliation by its recorded ID.
        await call('rpc_delivery_finalize_upload', { p_tenant_id: tenant, p_upload_id: prepared.id });
    });
}
export async function cancelCompanyDocument(tenant: string, id: string, reason: string): Promise<void> {
    await call('rpc_delivery_cancel_file', { p_tenant_id: tenant, p_file_id: id, p_reason: reason });
}
