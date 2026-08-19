import { supabase } from '@/lib/supabase';
import type {
    Deal, DealFilters, DealCreatePayload, DealUpdatePatch,
    DealStage, PipelineColumn, DealDetail, DealActivity, DealActivityPayload,
    Customer, Customer360, CustomerPayload, LogisticsProvider, LogisticsProviderPayload,
    Quote, QuoteConversionResult, QuoteFilters, QuoteUpsertPayload
} from '@/types/commercial';
import {
    normalizeConversionResult,
    normalizeCustomers,
    normalizeIdResult,
    normalizeProviders,
    normalizeQuotes,
} from '@/services/commercialContracts';

const USE_MOCKS = import.meta.env.DEV && import.meta.env.VITE_USE_MOCKS === 'true';

const formatValue = (val: number, cur: string) => {
    if (!val) return '0';
    if (val >= 1000000) return `$${(val / 1000000).toFixed(1)}M`;
    if (val >= 1000) return `$${(val / 1000).toFixed(0)}k`;
    return `$${val}`;
};

const getProbForStage = (stage: string): string => {
    switch (stage) {
        case 'lead': return '20%';
        case 'qualified': return '50%';
        case 'proposal': return '80%';
        case 'won': return 'Won';
        case 'lost': return 'Lost';
        default: return '0%';
    }
};

const STAGE_MAP: Record<DealStage, string> = {
    'lead': 'Prospecto',
    'qualified': 'Cotización',
    'proposal': 'Negociación',
    'won': 'Cierre',
    'lost': 'Perdido'
};

export async function listPipelineDeals(tenantId: string, filters: DealFilters = {}): Promise<PipelineColumn[]> {
    if (USE_MOCKS) {
        const { getMockPipeline } = await import('@/mocks/commercial.mock');
        return getMockPipeline();
    }

    const { data, error } = await supabase.rpc('rpc_list_deals', {
        p_tenant_id: tenantId,
        p_filters: filters
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    const deals: Deal[] = data || [];

    // Group by stage into the UI standard format (Lost is usually hidden or separate, but we ignore it here or could add a column)
    const pipeline: Record<string, PipelineColumn> = {
        'lead': { id: 'lead', title: 'Prospecto', count: 0, deals: [] },
        'qualified': { id: 'qualified', title: 'Cotización', count: 0, deals: [] },
        'proposal': { id: 'proposal', title: 'Negociación', count: 0, deals: [] },
        'won': { id: 'won', title: 'Cierre', count: 0, deals: [] },
    };

    deals.forEach(deal => {
        const stageId = deal.stage as keyof typeof pipeline;
        if (pipeline[stageId]) {
            pipeline[stageId].count++;
            pipeline[stageId].deals.push({
                db_id: deal.id,
                name: deal.title, // Title of the deal serves as name here
                value: formatValue(deal.value || 0, deal.currency),
                prob: getProbForStage(deal.stage)
            });
        }
    });

    return [pipeline['lead'], pipeline['qualified'], pipeline['proposal'], pipeline['won']];
}

export async function createDeal(tenantId: string, payload: DealCreatePayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-deal-uuid' };

    const { data, error } = await supabase.rpc('rpc_create_deal', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updateDeal(dealId: string, patch: DealUpdatePatch): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_deal', {
        p_deal_id: dealId,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function moveDeal(dealId: string, newStage: DealStage): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_move_deal', {
        p_deal_id: dealId,
        p_new_stage: newStage
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function getDealDetail(tenantId: string, dealId: string): Promise<DealDetail> {
    if (USE_MOCKS) {
        return {
            id: dealId,
            title: 'Mock Deal',
            currency: 'MXN',
            stage: 'lead',
            priority: 'medium',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            owner_name: 'Admin User'
        };
    }

    const { data, error } = await supabase.rpc('rpc_get_deal', { p_deal_id: dealId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data;
}

export async function getDealActivities(tenantId: string, dealId: string): Promise<DealActivity[]> {
    if (USE_MOCKS) {
        return [];
    }

    const { data, error } = await supabase.rpc('rpc_list_deal_activities', { p_deal_id: dealId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data || [];
}

export async function addDealActivity(dealId: string, payload: DealActivityPayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-activity-id' };

    const { data, error } = await supabase.rpc('rpc_add_deal_activity', {
        p_deal_id: dealId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

// --- NEW CRM ADVANCEMENT FUNCTIONS ---

export async function addDealNote(dealId: string, note: string): Promise<void> {
    if (USE_MOCKS) return;
    const { data, error } = await supabase.rpc('rpc_add_deal_note', {
        p_deal_id: dealId,
        p_note: note
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function listDealNotes(dealId: string): Promise<any[]> {
    if (USE_MOCKS) return [];
    const { data, error } = await supabase.rpc('rpc_list_deal_notes', { p_deal_id: dealId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data || [];
}

export async function listDealChecklist(dealId: string): Promise<any[]> {
    if (USE_MOCKS) return [];
    const { data, error } = await supabase.rpc('rpc_list_deal_checklist', { p_deal_id: dealId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data || [];
}

export async function toggleChecklistItem(itemId: string, isDone: boolean): Promise<void> {
    if (USE_MOCKS) return;
    const { data, error } = await supabase.rpc('rpc_toggle_deal_checklist_item', {
        p_item_id: itemId,
        p_is_done: isDone
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function listCommercialDeals(tenantId: string, filters: DealFilters = {}): Promise<Deal[]> {
    const { data, error } = await supabase.rpc('rpc_list_deals', {
        p_tenant_id: tenantId,
        p_filters: filters,
    });
    const result = assertRpcResult<unknown>(data, error);
    if (!Array.isArray(result)) throw new Error('invalid_response');
    return result as Deal[];
}

const COMMERCIAL_ERRORS: Record<string, string> = {
    unauthorized: 'No tienes permisos para consultar o modificar Comercial.',
    not_found: 'El registro ya no existe o no pertenece a tu empresa.',
    invalid_filters: 'Los filtros no son válidos.',
    invalid_payload: 'Revisa los datos capturados.',
    invalid_customer: 'El cliente seleccionado no pertenece a tu empresa.',
    invalid_provider: 'El proveedor seleccionado no pertenece a tu empresa.',
    invalid_service_catalog_item: 'El servicio seleccionado no pertenece al catálogo activo de tu empresa.',
    invalid_amount: 'Costo y precio deben ser valores positivos.',
    invalid_operational_window: 'La ventana operativa debe terminar después de su inicio.',
    duplicate_name: 'Ya existe un registro activo con ese nombre.',
    reference_conflict: 'No fue posible generar una referencia única. Intenta de nuevo.',
    quote_not_editable: 'Solo las cotizaciones en borrador pueden editarse.',
    quote_incomplete: 'Completa cliente, proveedor, ruta, costo y precio antes de continuar.',
    missing_commercial_data: 'Completa el concepto, cliente, precio y moneda de la cotización.',
    quote_payload_not_ready_for_review: 'Completa servicio, origen y destino antes de enviar.',
    quote_payload_not_ready_for_approval: 'Completa la ventana operativa y la carga antes de aceptar.',
    quote_payload_not_ready_for_conversion: 'La cotización no cumple el contrato operativo para convertirse.',
    invalid_quote_status: 'La cotización no puede avanzar desde su estado actual.',
    invalid_status: 'El estado solicitado no existe.',
    invalid_transition: 'La cotización no puede avanzar a ese estado.',
    quote_not_approved: 'La cotización debe estar aceptada antes de crear la operación.',
    already_converted: 'Esta cotización ya fue convertida a operación.',
    converted_operation_not_found: 'La cotización apunta a una operación que ya no está disponible.',
    quote_conversion_conflict: 'La cotización se convirtió al mismo tiempo en otra sesión. Actualiza e intenta de nuevo.',
    internal_error: 'No fue posible completar la operación por un error interno.',
    not_a_quote: 'La oportunidad todavía no tiene una cotización.',
    invalid_response: 'El servidor devolvió una respuesta comercial incompleta.',
};

export function getCommercialErrorMessage(error: unknown): string {
    const code = error instanceof Error ? error.message : String(error ?? '');
    return COMMERCIAL_ERRORS[code] ?? 'No fue posible completar la acción comercial.';
}

function assertRpcResult<T>(data: T & { error?: string } | null, error: { message?: string } | null): T {
    if (error) throw new Error(error.message || 'rpc_error');
    if (data?.error) throw new Error(data.error);
    return data as T;
}

export async function listCustomers(
    tenantId: string,
    filters: { searchText?: string; active?: boolean } = {},
): Promise<Customer[]> {
    const { data, error } = await supabase.rpc('rpc_list_customers', {
        p_tenant_id: tenantId,
        p_filters: filters,
    });
    return normalizeCustomers(assertRpcResult<unknown>(data, error));
}

export async function getCustomer360(customerId: string): Promise<Customer360> {
    const { data, error } = await supabase.rpc('rpc_get_customer_360', { p_customer_id: customerId });
    return assertRpcResult<Customer360>(data, error);
}

export async function upsertCustomer(
    tenantId: string,
    customerId: string | null,
    payload: CustomerPayload,
): Promise<{ id: string }> {
    const { data, error } = await supabase.rpc('rpc_upsert_customer', {
        p_tenant_id: tenantId,
        p_customer_id: customerId,
        p_payload: payload,
    });
    return normalizeIdResult(assertRpcResult<unknown>(data, error));
}

export async function listProviders(
    tenantId: string,
    filters: { searchText?: string; active?: boolean } = {},
): Promise<LogisticsProvider[]> {
    const { data, error } = await supabase.rpc('rpc_list_providers', {
        p_tenant_id: tenantId,
        p_filters: filters,
    });
    return normalizeProviders(assertRpcResult<unknown>(data, error));
}

export async function upsertProvider(
    tenantId: string,
    providerId: string | null,
    payload: LogisticsProviderPayload,
): Promise<{ id: string }> {
    const { data, error } = await supabase.rpc('rpc_upsert_provider', {
        p_tenant_id: tenantId,
        p_provider_id: providerId,
        p_payload: payload,
    });
    return normalizeIdResult(assertRpcResult<unknown>(data, error));
}

export async function listQuotes(tenantId: string, filters: QuoteFilters = {}): Promise<Quote[]> {
    const { data, error } = await supabase.rpc('rpc_list_quotes', {
        p_tenant_id: tenantId,
        p_filters: filters,
    });
    return normalizeQuotes(assertRpcResult<unknown>(data, error));
}

export async function upsertQuote(
    tenantId: string,
    dealId: string | null,
    payload: QuoteUpsertPayload,
): Promise<{ id: string }> {
    const { data, error } = await supabase.rpc('rpc_upsert_quote', {
        p_tenant_id: tenantId,
        p_deal_id: dealId,
        p_payload: payload,
    });
    return normalizeIdResult(assertRpcResult<unknown>(data, error));
}

export async function duplicateQuote(dealId: string): Promise<{ id: string }> {
    const { data, error } = await supabase.rpc('rpc_duplicate_quote', { p_deal_id: dealId });
    return normalizeIdResult(assertRpcResult<unknown>(data, error));
}

export async function submitQuoteForReview(dealId: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_submit_quote_for_review', { p_deal_id: dealId });
    assertRpcResult<{ success: boolean }>(data, error);
}

export async function approveQuote(dealId: string, note?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_approve_quote', {
        p_deal_id: dealId,
        p_approval_note: note,
    });
    assertRpcResult<{ success: boolean }>(data, error);
}

export async function rejectQuote(dealId: string, note?: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_reject_quote', {
        p_deal_id: dealId,
        p_rejection_note: note,
    });
    assertRpcResult<{ success: boolean }>(data, error);
}

export async function returnQuoteToDraft(dealId: string): Promise<void> {
    const { data, error } = await supabase.rpc('rpc_return_quote_to_draft', {
        p_deal_id: dealId,
    });
    assertRpcResult<{ success: boolean }>(data, error);
}

export async function convertQuoteToOperation(dealId: string, note?: string): Promise<QuoteConversionResult> {
    const { data, error } = await supabase.rpc('rpc_convert_quote_to_operation', {
        p_deal_id: dealId,
        p_conversion_note: note,
    });
    return normalizeConversionResult(assertRpcResult<unknown>(data, error));
}

