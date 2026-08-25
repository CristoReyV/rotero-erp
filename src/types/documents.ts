export type DocumentSourceModule = 'operations' | 'commercial' | 'billing' | 'finance' | 'documents' | 'claims';
export type DocumentEntityType = 'operation' | 'quote' | 'customer' | 'provider' | 'billing_document' | 'generated_document' | 'finance_invoice' | 'claim';
export type DocumentFileKind = 'generated_pdf' | 'fiscal_xml' | 'fiscal_pdf' | 'provider_upload' | 'operation_evidence' | 'supporting_file' | 'html_snapshot';
export type DocumentFileStatus = 'active' | 'superseded' | 'cancelled';
export type GeneratedDocumentStatus = 'draft' | 'final' | 'cancelled';
export type DocumentTemplateType = 'commercial_quote' | 'operation_summary' | 'operation_document' | 'payment_complement' | 'credit_note' | 'provider_document' | 'finance_internal_receipt' | 'finance_note' | 'payroll_receipt';

export interface DocumentUploadContract {
    bucket: 'tenant-documents';
    private: true;
    max_file_size: number;
    allowed_mime_types: string[];
    signed_url_ttl_seconds: number;
}

export interface DocumentFile {
    id: string;
    tenant_id: string;
    storage_bucket: 'tenant-documents';
    storage_path: string;
    file_name: string;
    mime_type: string;
    size_bytes: number;
    checksum_sha256?: string | null;
    file_kind: DocumentFileKind;
    source_module: DocumentSourceModule;
    source_entity_type: DocumentEntityType;
    source_entity_id: string;
    status: DocumentFileStatus;
    notes?: string | null;
    metadata: Record<string, unknown>;
    uploaded_by?: string | null;
    created_at: string;
    updated_at: string;
    entity_reference?: string;
    can_manage?: boolean;
}

export interface DocumentFileFilters {
    search?: string;
    source_module?: DocumentSourceModule;
    source_entity_type?: DocumentEntityType;
    source_entity_id?: string;
    file_kind?: DocumentFileKind;
    status?: DocumentFileStatus;
    date_from?: string;
    date_to?: string;
    limit?: number;
    cursor_created_at?: string;
    cursor_id?: string;
}

export interface DocumentFilePage { items: DocumentFile[]; next_cursor: { created_at: string; id: string } | null; }

export interface GeneratedDocument {
    id: string;
    tenant_id: string;
    template_id?: string | null;
    template_version_id?: string | null;
    template_name?: string | null;
    template_type: DocumentTemplateType;
    entity_type: DocumentTemplateType;
    entity_id: string;
    document_number?: string | null;
    source_module?: DocumentSourceModule | null;
    related_entity_type?: DocumentEntityType | null;
    related_entity_id?: string | null;
    entity_reference?: string;
    status: GeneratedDocumentStatus;
    html_snapshot: string;
    data_snapshot: Record<string, unknown>;
    metadata: Record<string, unknown>;
    print_count: number;
    generated_at: string;
    finalized_at?: string | null;
    cancelled_at?: string | null;
    can_manage?: boolean;
}

export interface DocumentTemplate {
    id: string; template_type: DocumentTemplateType; module?: string | null; name: string;
    version: number; status: string; is_active: boolean; active_version_id?: string | null;
}

export interface DocumentSourceOption {
    id: string; label: string; description: string; module: string; status?: string; created_at?: string;
}

export interface UploadDocumentInput {
    tenantId: string;
    file: File;
    sourceModule: DocumentSourceModule;
    entityType: DocumentEntityType;
    entityId: string;
    fileKind: DocumentFileKind;
    notes?: string;
    metadata?: Record<string, unknown>;
}
