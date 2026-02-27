import { supabase } from '@/lib/supabase';
import type {
    CFDIStatus, CFDI, CFDIListRow, CFDIFilters, CFDICreatePayload,
    CFDIUpdatePatch, CartaPorteUpsertPayload, CFDIWithDetail
} from '@/types/billing';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

// Utility to format currency
const formatCurrency = (amount: number, currency = 'MXN') => {
    return new Intl.NumberFormat('es-MX', {
        style: 'currency',
        currency: currency
    }).format(amount);
};

// Map status to what the UI badge expects
const mapStatusToUI = (status: CFDIStatus): string => {
    switch (status) {
        case 'timbrado': return 'Timbrado';
        case 'draft': return 'Borrador';
        case 'error': return 'Error';
        case 'cancelado': return 'Cancelado';
        default: return 'Pendiente';
    }
};

// Map real db CFDI to the UI row structure expected by BillingPage
const mapCFDIToRow = (cfdi: CFDI): CFDIListRow => {
    return {
        db_id: cfdi.id,
        folio: `${cfdi.serie || ''}${cfdi.folio || ''}` || 'S/F',
        client: cfdi.receptor_name || cfdi.rfc_receptor,
        uuid: cfdi.uuid,
        amount: formatCurrency(cfdi.total, cfdi.currency),
        status: mapStatusToUI(cfdi.status),
        cp: cfdi.has_carta_porte ? 'Validado' : (cfdi.has_complemento_pago ? 'Comp. Pago' : 'Requiere CP')
    };
};

export async function listCFDIs(tenantId: string, filters: CFDIFilters = {}): Promise<CFDIListRow[]> {
    if (USE_MOCKS) {
        const { MOCK_CFDIS } = await import('@/mocks/billing.mock');
        // We pretend db_id exists on mocks for the UI clicking to work gracefully if missing
        return MOCK_CFDIS.map(mock => ({ ...mock, db_id: mock.uuid })) as unknown as CFDIListRow[];
    }

    const { data, error } = await supabase.rpc('rpc_list_cfdis', {
        p_tenant_id: tenantId,
        p_filters: filters
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return (data || []).map((dbRow: CFDI) => mapCFDIToRow(dbRow));
}

export async function getCFDIDetail(cfdiId: string): Promise<CFDIWithDetail> {
    if (USE_MOCKS) {
        // Just a dummy return if using mocks
        return {} as CFDIWithDetail;
    }

    const { data, error } = await supabase.rpc('rpc_get_cfdi_detail', {
        p_cfdi_id: cfdiId
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as CFDIWithDetail;
}

export async function createCFDI(tenantId: string, payload: CFDICreatePayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-id' };

    const { data, error } = await supabase.rpc('rpc_create_cfdi', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updateCFDI(cfdiId: string, patch: CFDIUpdatePatch): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_cfdi', {
        p_cfdi_id: cfdiId,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function upsertCartaPorte(cfdiId: string, payload: CartaPorteUpsertPayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-cp-id' };

    const { data, error } = await supabase.rpc('rpc_upsert_carta_porte', {
        p_cfdi_id: cfdiId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}
