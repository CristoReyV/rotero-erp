import { supabase } from '@/lib/supabase';
import type {
    CFDIStatus, CFDI, CFDIListRow, CFDIFilters, CFDICreatePayload,
    CFDIUpdatePatch, CartaPorteUpsertPayload, CFDIWithDetail, FiscalReadiness
} from '@/types/billing';
import { normalizeFiscalError, withFiscalMutationGuard } from './fiscalContracts';

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

function fiscalRpcResult<T>(data: unknown, error: { message?: string } | null): T {
    if (error) throw new Error('No fue posible comunicarse con la orquestación fiscal.');
    if (data && typeof data === 'object' && 'error' in data) {
        throw new Error(normalizeFiscalError((data as { error: unknown }).error));
    }
    return data as T;
}

export async function getFiscalReadiness(cfdiId: string): Promise<FiscalReadiness> {
    if (USE_MOCKS) return {
        cfdi_id: cfdiId, fiscal_status: 'draft', validation: { valid: false, missing_fields: ['concepts'], cfdi_version: '4.0' },
        provider: { configured: false, code: null, environment: 'sandbox' }, last_attempt: null,
    };
    const { data, error } = await supabase.rpc('rpc_get_fiscal_readiness', { p_cfdi_id: cfdiId });
    return fiscalRpcResult<FiscalReadiness>(data, error);
}

export async function validateFiscalDocument(cfdiId: string): Promise<void> {
    return withFiscalMutationGuard(`${cfdiId}:validate`, async () => {
        const { data, error } = await supabase.rpc('rpc_prepare_cfdi_for_api', { p_cfdi_id: cfdiId });
        fiscalRpcResult(data, error);
    });
}

export async function queueFiscalStamp(cfdiId: string): Promise<void> {
    return withFiscalMutationGuard(`${cfdiId}:stamp`, async () => {
        const { data, error } = await supabase.rpc('rpc_queue_fiscal_stamp', { p_cfdi_id: cfdiId });
        fiscalRpcResult(data, error);
    });
}

export async function retryFiscalRequest(requestId: string): Promise<void> {
    return withFiscalMutationGuard(`${requestId}:retry`, async () => {
        const { data, error } = await supabase.rpc('rpc_retry_fiscal_request', { p_request_id: requestId });
        fiscalRpcResult(data, error);
    });
}

export async function queueFiscalStatusCheck(cfdiId: string): Promise<void> {
    return withFiscalMutationGuard(`${cfdiId}:status`, async () => {
        const { data, error } = await supabase.rpc('rpc_queue_fiscal_status_check', { p_cfdi_id: cfdiId });
        fiscalRpcResult(data, error);
    });
}

export async function requestFiscalCancellation(cfdiId: string, reason: string): Promise<void> {
    return withFiscalMutationGuard(`${cfdiId}:cancel`, async () => {
        const { data, error } = await supabase.rpc('rpc_request_fiscal_cancellation', { p_cfdi_id: cfdiId, p_reason: reason });
        fiscalRpcResult(data, error);
    });
}
