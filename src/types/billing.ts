export type CFDIStatus = 'draft' | 'timbrado' | 'cancelado' | 'error';
export type FiscalStatus =
    | 'draft' | 'ready_for_api' | 'queued' | 'submitting' | 'processing' | 'stamped'
    | 'rejected' | 'api_error' | 'cancellation_requested' | 'cancelled' | 'cancellation_rejected';

export type FiscalSafeError =
    | 'provider_not_configured' | 'validation_failed' | 'provider_unavailable' | 'provider_timeout'
    | 'provider_rejected' | 'already_processing' | 'already_stamped' | 'invalid_transition'
    | 'cancellation_failed' | 'artifact_unavailable' | 'status_conflict';

export interface CFDI {
    id: string; // The database UUID
    operation_id?: string | null;
    uuid: string; // The fiscal UUID
    serie?: string;
    folio: string;
    rfc_emisor: string;
    rfc_receptor: string;
    receptor_name?: string;
    subtotal?: number;
    total: number;
    currency: string;
    status: CFDIStatus;
    has_carta_porte: boolean;
    has_complemento_pago: boolean;
    issued_at?: string;
    cancelled_at?: string;
    pac_provider?: string;
    fiscal_status: FiscalStatus;
    fiscal_provider?: string | null;
    provider_document_id?: string | null;
    fiscal_stamped_at?: string | null;
    fiscal_cancelled_at?: string | null;
    fiscal_last_checked_at?: string | null;
    fiscal_error_code?: FiscalSafeError | null;
    fiscal_error_message_safe?: string | null;
    request_fingerprint?: string | null;
    provider_version?: string | null;
    cfdi_version: string;
    xml_document_file_id?: string | null;
    pdf_document_file_id?: string | null;
    notes?: string;
    created_at: string;
}

export interface CartaPorte {
    id: string;
    trans_type?: string;
    vehicle_plate?: string;
    carrier_name?: string;
    origin?: string;
    destination?: string;
    goods_desc?: string;
    created_at: string;
}

export interface CFDIWithDetail extends CFDI {
    carta_porte?: CartaPorte;
}

export interface FiscalReadiness {
    cfdi_id: string;
    fiscal_status: FiscalStatus;
    validation: { valid: boolean; missing_fields: string[]; cfdi_version: string };
    provider: { configured: boolean; code: string | null; environment: 'sandbox' | 'production' };
    request_fingerprint?: string | null;
    provider_document_id?: string | null;
    fiscal_uuid?: string | null;
    last_checked_at?: string | null;
    safe_error_code?: FiscalSafeError | null;
    safe_error_message?: string | null;
    xml_document_file_id?: string | null;
    pdf_document_file_id?: string | null;
    last_attempt?: { request_id: string; request_type: string; status: string; attempt_count: number; safe_error_code?: string | null; updated_at: string } | null;
}

// Map real data back to the UI interface format originally used
export interface CFDIListRow {
    db_id: string;
    folio: string;
    client: string;
    uuid: string;
    amount: string; // Formatted string, e.g. "$14,250.00"
    status: string; // "Timbrado", "Pendiente", "Error", "Cancelado"
    cp: string; // E.g. "Validado", "Requiere CP"
}

export interface CFDIFilters {
    status?: CFDIStatus;
    rfc?: string;
    searchText?: string;
}

export interface CFDICreatePayload {
    uuid?: string;
    serie?: string;
    folio?: string;
    rfc_emisor: string;
    rfc_receptor: string;
    receptor_name?: string;
    subtotal?: number;
    total: number;
    currency?: string;
    status?: CFDIStatus;
    has_carta_porte?: boolean;
    has_complemento_pago?: boolean;
    issued_at?: string;
    pac_provider?: string;
    notes?: string;
}

export interface CFDIUpdatePatch {
    status?: CFDIStatus;
    cancelled_at?: string;
    notes?: string;
    has_carta_porte?: boolean;
    has_complemento_pago?: boolean;
}

export interface CartaPorteUpsertPayload {
    trans_type?: string;
    vehicle_plate?: string;
    carrier_name?: string;
    origin?: string;
    destination?: string;
    goods_desc?: string;
}
