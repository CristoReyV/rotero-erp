export type CFDIStatus = 'draft' | 'timbrado' | 'cancelado' | 'error';

export interface CFDI {
    id: string; // The database UUID
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
