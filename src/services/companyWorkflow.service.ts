import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability, scopedResponse, useCompanyStore } from '@/store/companyStore';
import type { OperationPlanningPayload, OperationIncident, OperationDocument, OperationEvidenceItem, OperationCrossing } from '@/types/operations';

export const companyWorkflowActive = () => useCompanyStore.getState().phase === 'ready';
const MESSAGES: Record<string, string> = {
    stale_operation: 'La operación cambió. Actualiza la ficha antes de guardar.',
    request_conflict: 'La petición ya se utilizó con otros datos. Actualiza la ficha.',
    financial_write_forbidden: 'Esta acción requiere permiso financiero de lectura y escritura.',
    invalid_operational_window: 'La ventana debe terminar después de su inicio.',
    invalid_transition: 'La transición no corresponde al estado actual.',
    tracking_not_ready: 'Tracking todavía no cumple las condiciones para iniciar tránsito.',
    missing_delivered_event: 'Falta el evento de entrega de Tracking.',
    billing_not_issued: 'Billing debe estar emitido antes del cierre normal.',
    invalid_provider: 'El proveedor no pertenece al contexto autorizado.',
    provider_compliance_blocked: 'El proveedor tiene bloqueos de cumplimiento.',
    unauthorized: 'No tienes capacidad para esta acción en la empresa seleccionada.',
};
const failure = (code: unknown) => new Error(MESSAGES[String(code)] ?? 'No fue posible confirmar la acción. Actualiza la ficha antes de reintentar.');

function tenant(): string {
    const state = useCompanyStore.getState();
    const value = useAuthStore.getState().activeTenant;
    if (!value || state.phase !== 'ready' || state.tenantId !== value || !state.selectedIds.length) {
        throw failure('unauthorized');
    }
    return value;
}

export async function companyOperation(operationId: string): Promise<Record<string, unknown>> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_operation_workflow', {
            p_tenant_id: tenant(), p_operation_id: operationId,
        });
        if (error || data?.error) throw failure(data?.error);
        if (data?.id !== operationId || !Number.isSafeInteger(data.workflow_revision)) {
            throw failure('invalid_response');
        }
        return data;
    });
}

export async function operationCommand(
    operationId: string,
    action: 'edit' | 'plan' | 'assign' | 'transition' | 'control',
    payload: Record<string, unknown>,
    expectedRevision: number | undefined,
    requestId = crypto.randomUUID(),
): Promise<void> {
    if (!Number.isSafeInteger(expectedRevision) || (expectedRevision ?? -1) < 0) {
        throw failure('stale_operation');
    }
    await scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_operation_action', {
            p_tenant_id: tenant(), p_operation_id: operationId, p_action: action,
            p_payload: payload, p_request_id: requestId, p_expected_revision: expectedRevision,
        });
        if (error || data?.error || data?.success !== true) throw failure(data?.error);
    });
}

export function companyPlanningPayload(payload: OperationPlanningPayload): Record<string, unknown> {
    const result: Record<string, unknown> = { ...payload };
    if (!(hasCompanyCapability('financial.full.read') && hasCompanyCapability('finance.write'))) {
        for (const key of [
            'provider_cost_amount', 'customer_price_amount', 'pricing_currency',
            'service_catalog_item_id', 'service_catalog_snapshot', 'notes',
        ]) delete result[key];
    }
    return result;
}

export async function assignableProviders(): Promise<Array<{ id: string; display_name: string }>> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_assignment_choices', { p_tenant_id: tenant() });
        if (error || data?.error || !Array.isArray(data?.providers)) throw failure(data?.error);
        return data.providers;
    });
}

export async function companyProviderEligibility(providerId: string): Promise<{
    eligible: boolean; badge: string; reasons: Array<{ name: string; status: string }>;
}> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_provider_eligibility', {
            p_tenant_id: tenant(), p_provider_id: providerId,
        });
        if (error || data?.error || typeof data?.eligible !== 'boolean') throw failure(data?.error);
        return data;
    });
}

export async function companyOperationChildren(operationId: string): Promise<{
    incidents: OperationIncident[]; documents: OperationDocument[]; evidence: OperationEvidenceItem[]; crossings: OperationCrossing[];
}> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_operation_children', { p_tenant_id: tenant(), p_operation_id: operationId });
        if (error || data?.error || !['incidents', 'documents', 'evidence', 'crossings'].every((key) => Array.isArray(data?.[key]))) throw failure(data?.error);
        return data;
    });
}

export async function operationChildCommand(operationId: string | undefined, action: string, payload: Record<string, unknown>, revision?: number): Promise<void> {
    if (!operationId) throw failure('unauthorized');
    const expected = revision ?? (await companyOperation(operationId)).workflow_revision;
    await scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_operation_child_action', {
            p_tenant_id: tenant(), p_operation_id: operationId, p_action: action, p_payload: payload,
            p_request_id: crypto.randomUUID(), p_expected_revision: expected,
        });
        if (error || data?.error || data?.success !== true) throw failure(data?.error);
    });
}
