import { supabase } from '@/lib/supabase';
import type {
    DocumentEntityType, DocumentFile, DocumentFileFilters, DocumentFilePage, DocumentFileStatus,
    DocumentSourceOption, DocumentTemplate, DocumentTemplateType, DocumentUploadContract,
    GeneratedDocument, UploadDocumentInput,
} from '@/types/documents';
import type { OperationDocumentType } from '@/types/operations';
import { formatFileSize, registerWithCompensation, validateDocumentFile } from './documentsContracts';

export { formatFileSize, registerWithCompensation, validateDocumentFile } from './documentsContracts';

const ERROR_MESSAGES: Record<string, string> = {
    unauthorized: 'No tienes permiso para este contexto documental.',
    invalid_payload: 'Revisa el archivo y su clasificación.',
    invalid_source_entity: 'La entidad seleccionada no pertenece a la empresa activa.',
    invalid_target_entity: 'No es posible relacionar el archivo con esa entidad.',
    invalid_source_module: 'La clasificación no corresponde al módulo de origen.',
    invalid_storage_path: 'No fue posible construir una ruta segura para el archivo.',
    file_too_large: 'El archivo excede el límite configurado en Storage.',
    file_type_not_allowed: 'El tipo o la extensión del archivo no están permitidos.',
    invalid_checksum: 'No fue posible verificar la integridad del archivo.',
    storage_object_not_found: 'Storage no confirmó el archivo antes de registrarlo.',
    storage_path_already_registered: 'Este objeto de Storage ya está registrado.',
    cancel_reason_required: 'Captura el motivo de cancelación.',
    document_number_conflict: 'El folio documental ya existe.',
};

function rpcResult<T>(data: unknown, error: { message?: string } | null): T {
    if (error) throw new Error('No fue posible comunicarse con el servicio documental.');
    if (data && typeof data === 'object' && 'error' in data) {
        const code = String((data as { error: unknown }).error);
        throw new Error(ERROR_MESSAGES[code] ?? 'No fue posible completar la acción documental.');
    }
    return data as T;
}

export async function getDocumentUploadContract(tenantId: string): Promise<DocumentUploadContract> {
    const { data, error } = await supabase.rpc('rpc_get_document_upload_contract', { p_tenant_id: tenantId });
    return rpcResult<DocumentUploadContract>(data, error);
}

export async function sha256(file: Blob): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function buildStoragePath(input: Pick<UploadDocumentInput, 'tenantId' | 'sourceModule' | 'entityType' | 'entityId' | 'file'>): string {
    const extension = input.file.name.split('.').pop()?.toLowerCase() ?? 'bin';
    return `${input.tenantId}/${input.sourceModule}/${input.entityType}/${input.entityId}/${crypto.randomUUID()}.${extension}`;
}

export async function uploadDocumentFile(input: UploadDocumentInput, onProgress?: (phase: 'validating' | 'uploading' | 'registering') => void): Promise<DocumentFile> {
    onProgress?.('validating');
    const contract = await getDocumentUploadContract(input.tenantId);
    const validation = validateDocumentFile(input.file, contract);
    if (validation) throw new Error(validation);
    const [checksum, storagePath] = await Promise.all([sha256(input.file), Promise.resolve(buildStoragePath(input))]);

    onProgress?.('uploading');
    const upload = await supabase.storage.from(contract.bucket).upload(storagePath, input.file, {
        contentType: input.file.type, upsert: false, cacheControl: '3600',
    });
    if (upload.error) throw new Error('No fue posible cargar el archivo en Storage.');

    onProgress?.('registering');
    return registerWithCompensation(async () => {
        const { data, error } = await supabase.rpc('rpc_register_document_file', {
            p_tenant_id: input.tenantId,
            p_payload: {
                storage_path: storagePath, file_name: input.file.name, mime_type: input.file.type,
                size_bytes: input.file.size, checksum_sha256: checksum, file_kind: input.fileKind,
                source_module: input.sourceModule, source_entity_type: input.entityType,
                source_entity_id: input.entityId, notes: input.notes, metadata: input.metadata ?? {},
            },
        });
        return rpcResult<DocumentFile>(data, error);
    }, async () => {
        const { error } = await supabase.storage.from(contract.bucket).remove([storagePath]);
        if (error) throw error;
    });
}

export async function listDocumentFiles(tenantId: string, filters: DocumentFileFilters = {}): Promise<DocumentFilePage> {
    const { data, error } = await supabase.rpc('rpc_list_document_files', { p_tenant_id: tenantId, p_filters: filters });
    const result = rpcResult<DocumentFilePage | DocumentFile[]>(data, error);
    return Array.isArray(result) ? { items: result, next_cursor: null } : result;
}

export async function markDocumentFileStatus(fileId: string, status: DocumentFileStatus, notes?: string): Promise<DocumentFile> {
    const { data, error } = await supabase.rpc('rpc_mark_document_file_status', { p_file_id: fileId, p_status: status, p_notes: notes });
    return rpcResult<DocumentFile>(data, error);
}

export async function createDocumentSignedUrl(file: DocumentFile, download = false): Promise<string> {
    const { data, error } = await supabase.storage.from(file.storage_bucket).createSignedUrl(file.storage_path, 300, { download });
    if (error || !data?.signedUrl) throw new Error('No fue posible autorizar el acceso temporal al archivo.');
    return data.signedUrl;
}

export async function relateDocumentFile(fileId: string, entityType: DocumentEntityType, entityId: string, notes?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_relate_document_file', { p_file_id: fileId, p_entity_type: entityType, p_entity_id: entityId, p_notes: notes });
    rpcResult(data, error);
}

export async function attachOperationDocumentFile(operationId: string, documentType: OperationDocumentType, fileId: string, note?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_attach_operation_document_file', { p_operation_id: operationId, p_document_type: documentType, p_file_id: fileId, p_note: note });
    rpcResult(data, error);
}

export async function addOperationFileEvidence(operationId: string, fileId: string, incidentId?: string | null, note?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_add_operation_file_evidence', { p_operation_id: operationId, p_file_id: fileId, p_incident_id: incidentId ?? null, p_note: note });
    rpcResult(data, error);
}

export async function relateQuoteDocumentsToOperation(quoteId: string, operationId: string): Promise<number> {
    const { data, error } = await supabase.rpc('rpc_relate_quote_documents_to_operation', { p_quote_id: quoteId, p_operation_id: operationId });
    return rpcResult<{ related_count: number }>(data, error).related_count;
}

export async function listGeneratedDocuments(tenantId: string, filters: Record<string, unknown> = {}): Promise<GeneratedDocument[]> {
    const { data, error } = await supabase.rpc('rpc_list_generated_documents', { p_tenant_id: tenantId, p_filters: filters });
    const result = rpcResult<{ items: GeneratedDocument[] } | GeneratedDocument[]>(data, error);
    return Array.isArray(result) ? result : result.items;
}

export async function listDocumentTemplates(tenantId: string, templateType?: DocumentTemplateType): Promise<DocumentTemplate[]> {
    const { data, error } = await supabase.rpc('rpc_list_document_templates_v2', { p_tenant_id: tenantId, p_template_type: templateType ?? null });
    return rpcResult<DocumentTemplate[]>(data, error);
}

export async function listDocumentSourceOptions(tenantId: string, templateType: DocumentTemplateType, search?: string): Promise<DocumentSourceOption[]> {
    const { data, error } = await supabase.rpc('rpc_list_document_source_options', { p_tenant_id: tenantId, p_template_type: templateType, p_search: search ?? null });
    return rpcResult<DocumentSourceOption[]>(data, error);
}

export async function generateDocument(tenantId: string, templateType: DocumentTemplateType, entityType: DocumentEntityType, entityId: string): Promise<GeneratedDocument> {
    const { data, error } = await supabase.rpc('rpc_generate_document', { p_tenant_id: tenantId, p_template_type: templateType, p_entity_type: entityType, p_entity_id: entityId, p_options: {} });
    return rpcResult<GeneratedDocument>(data, error);
}

export async function markGeneratedDocumentPrinted(id: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_mark_generated_document_printed', { p_document_id: id }); rpcResult(data, error);
}

export async function cancelGeneratedDocument(id: string, reason: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_cancel_generated_document', { p_document_id: id, p_reason: reason }); rpcResult(data, error);
}

export function previewGeneratedHtml(document: GeneratedDocument, print = false): void {
    const url = URL.createObjectURL(new Blob([document.html_snapshot], { type: 'text/html;charset=utf-8' }));
    if (print) {
        const frame = window.document.createElement('iframe');
        frame.style.position = 'fixed'; frame.style.width = '0'; frame.style.height = '0'; frame.style.border = '0';
        frame.addEventListener('load', () => frame.contentWindow?.print(), { once: true });
        frame.src = url; window.document.body.appendChild(frame);
        window.setTimeout(() => { frame.remove(); URL.revokeObjectURL(url); }, 60_000);
        return;
    }
    window.open(url, '_blank', 'noopener,noreferrer');
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
