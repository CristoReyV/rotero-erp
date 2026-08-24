import { supabase } from '@/lib/supabase';
import { mapDbOperationToUI, type DbOperation } from '@/services/operationsContracts';
import type { Place } from '@/types/tracking';
import type {
    CrossingType,
    DocumentRequirementLevel,
    EvidenceKind,
    IncidentCategory,
    Operation,
    Operation360Data,
    OperationAssignPayload,
    OperationAssignmentHistoryItem,
    OperationBillingSummary,
    OperationCrossing,
    OperationDocument,
    OperationDocumentStatus,
    OperationDocumentSummary,
    OperationDocumentType,
    OperationEvidenceItem,
    OperationIncident,
    OperationPlanningPayload,
    OperationReadiness,
    OperationTrackingEvent,
    IncidentSummary,
} from '@/types/operations';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export type OperationInsertPayload = {
    reference_code: string;
    route_summary?: string;
    client_display_name?: string;
    destination_city?: string;
    eta_display?: string;
    status?: string;
    origin_place?: Place;
    destination_place?: Place;
    eta?: string;
};

const OPERATION_ERROR_MESSAGES: Record<string, string> = {
    unauthorized: 'No tienes permisos para realizar esta acción.',
    not_found: 'La operación o el registro ya no está disponible.',
    invalid_payload: 'Revisa los datos capturados.',
    invalid_operational_window: 'La ventana operativa debe terminar después de su inicio.',
    invalid_eta: 'La ETA no puede ser anterior al inicio de la ventana operativa.',
    missing_provider: 'Selecciona el proveedor contratado.',
    invalid_provider: 'El proveedor no pertenece al tenant activo.',
    provider_inactive: 'El proveedor está inactivo.',
    provider_compliance_blocked: 'El proveedor tiene bloqueos configurados de cumplimiento.',
    missing_planned_departure: 'Captura la salida planeada.',
    missing_reassignment_reason: 'Describe el motivo del cambio de asignación.',
    invalid_external_url: 'La URL debe iniciar con http:// o https://.',
    invalid_incident: 'La incidencia seleccionada no pertenece a esta operación.',
    missing_content: 'Agrega una referencia, archivo o enlace.',
    national_operation: 'Los cruces solo aplican a operaciones internacionales.',
    tracking_not_ready: 'Faltan capacidades explícitas de Tracking para iniciar tránsito.',
    assignment_not_ready: 'La asignación contratada todavía no está completa.',
    blocking_incidents_open: 'Hay incidencias bloqueantes abiertas.',
    billing_not_issued: 'Billing debe estar emitido antes del cierre normal.',
    missing_delivered_event: 'Falta el evento de entrega de Tracking.',
    invalid_transition: 'La transición no corresponde al estado actual.',
};

function getRpcErrorMessage(code: string): string {
    return OPERATION_ERROR_MESSAGES[code] ?? `No fue posible completar la acción (${code}).`;
}

function assertRpcResult<T>(data: T | { error?: string } | null, error: { message?: string } | null): T {
    if (error) { const code=Object.keys(OPERATION_ERROR_MESSAGES).find(key=>error.message?.includes(key)); throw new Error(code?getRpcErrorMessage(code):error.message || 'Error de comunicación con Operations.'); }
    if (data && typeof data === 'object' && 'error' in data && typeof data.error === 'string') {
        throw new Error(getRpcErrorMessage(data.error));
    }
    return data as T;
}

export async function listOperations(tenantId: string): Promise<Operation[]> {
    if (USE_MOCKS) {
        const { getMockOperations } = await import('@/mocks/operations.mock');
        return getMockOperations();
    }
    const { data, error } = await supabase.rpc('rpc_list_operations', { p_tenant_id: tenantId });
    return assertRpcResult<DbOperation[]>(data, error).map(mapDbOperationToUI);
}

export async function getOperation(operationId: string): Promise<Operation | null> {
    if (USE_MOCKS) {
        const { getMockOperations } = await import('@/mocks/operations.mock');
        return (await getMockOperations()).find((item) => item.db_id === operationId || item.id === operationId) ?? null;
    }
    const { data, error } = await supabase.rpc('rpc_get_operation', { p_operation_id: operationId });
    if (!error && data?.error === 'not_found') return null;
    return mapDbOperationToUI(assertRpcResult<DbOperation>(data, error));
}

export async function createOperation(tenantId: string, payload: OperationInsertPayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-operation' };
    const { data, error } = await supabase.rpc('rpc_create_operation', {
        p_tenant_id: tenantId,
        p_reference_code: payload.reference_code,
        p_route_summary: payload.route_summary,
        p_client_display_name: payload.client_display_name,
        p_destination_city: payload.destination_city,
        p_eta_display: payload.eta_display,
        p_status: payload.status,
        p_origin_place: payload.origin_place,
        p_destination_place: payload.destination_place,
        p_eta: payload.eta,
    });
    return assertRpcResult<{ id: string }>(data, error);
}

export async function completeOperationPlanning(operationId: string, payload: OperationPlanningPayload): Promise<void> {
    if (USE_MOCKS) return;
    const { data, error } = await supabase.rpc('rpc_complete_operation_planning_v2', {
        p_operation_id: operationId,
        p_service_type: payload.service_type,
        p_origin_place: payload.origin_place,
        p_destination_place: payload.destination_place,
        p_operational_window_start: payload.operational_window_start,
        p_operational_window_end: payload.operational_window_end,
        p_notes: payload.notes,
        p_cargo_summary: payload.cargo_summary ?? {},
        p_route_summary: payload.route_summary,
        p_destination_city: payload.destination_city,
        p_eta: payload.eta || null,
        p_eta_display: payload.eta_display,
        p_operation_scope: payload.operation_scope,
        p_execution_type: payload.execution_type,
        p_provider_cost_amount: payload.provider_cost_amount,
        p_customer_price_amount: payload.customer_price_amount,
        p_pricing_currency: payload.pricing_currency,
        p_service_catalog_item_id: payload.service_catalog_item_id,
        p_service_catalog_snapshot: payload.service_catalog_snapshot ?? {},
        p_boxes_placed_days: payload.boxes_placed_days,
        p_documentation_received_at: payload.documentation_received_at,
        p_documentation_received_note: payload.documentation_received_note,
    });
    assertRpcResult(data, error);
}

export async function assignOperation(tenantId: string, operationId: string, payload: OperationAssignPayload): Promise<void> {
    if (USE_MOCKS) return;
    const { data, error } = await supabase.rpc('rpc_assign_operation_v3', {
        p_tenant_id: tenantId,
        p_operation_id: operationId,
        p_execution_type: payload.execution_type,
        p_provider_id: payload.provider_id,
        p_provider_name: payload.provider_name,
        p_external_driver: payload.external_driver ?? {},
        p_external_vehicle: payload.external_vehicle ?? {},
        p_driver_id: payload.driver_id,
        p_driver_name: payload.driver_name,
        p_vehicle_id: payload.vehicle_id,
        p_vehicle_ref: payload.vehicle_ref,
        p_planned_departure: payload.planned_departure,
        p_priority: payload.priority,
        p_reason: payload.reason,
        p_force_override: payload.force_override ?? false,
    });
    assertRpcResult(data, error);
}

async function readRpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await supabase.rpc(name, args);
    return assertRpcResult<T>(data, error);
}

export async function getOperationRequirements(operationId: string): Promise<{
    has_driver_assigned: boolean;
    has_provider_assignment: boolean;
    has_driver_token: boolean;
    has_public_token: boolean;
    has_delivered_event: boolean;
}> {
    if (USE_MOCKS) return { has_driver_assigned: false, has_provider_assignment: true, has_driver_token: false, has_public_token: false, has_delivered_event: false };
    return readRpc('rpc_get_operation_requirements', { p_operation_id: operationId });
}

export async function getOperation360Data(operationId: string): Promise<Operation360Data> {
    const operation = await getOperation(operationId);
    if (!operation) throw new Error('La operación ya no está disponible.');
    if (USE_MOCKS) {
        return {
            operation,
            assignmentHistory: [], incidents: [], evidence: [], documents: [], crossings: [], trackingEvents: [],
            incidentSummary: { open_incident_count: 0, blocking_incident_count: 0, has_open_incidents: false, has_blocking_incidents: false, can_close_operation: true, evidence_count: 0 },
            documentSummary: { required_count: 0, present_required_count: 0, missing_required_count: 0, has_missing_required: false, is_documentation_complete: true, pod_present: false, pod_required: false },
            readiness: { is_minimum_planned_complete: false, is_assignment_complete: false, is_tracking_ready: false, can_transition_to_assigned: false, can_transition_to_in_transit: false, has_driver_token: false, has_public_token: false, blocking_reasons: [] },
            billing: { has_billing_record: false, is_billing_ready: false, billing_blockers: [], is_billed: false, can_admin_close: false, pod_present: false, documentation_complete: true },
        };
    }
    const args = { p_operation_id: operationId };
    const [assignmentHistory, incidents, incidentSummary, evidence, documents, documentSummary, crossings, trackingEvents, readiness, billing] = await Promise.all([
        readRpc<OperationAssignmentHistoryItem[]>('rpc_list_operation_assignment_history', args),
        readRpc<OperationIncident[]>('rpc_list_operation_incidents', args),
        readRpc<IncidentSummary>('rpc_get_operation_incident_summary', args),
        readRpc<OperationEvidenceItem[]>('rpc_list_operation_evidence', { ...args, p_incident_id: null }),
        readRpc<OperationDocument[]>('rpc_list_operation_documents', args),
        readRpc<OperationDocumentSummary>('rpc_get_operation_document_summary', args),
        operation.operation_scope === 'international' ? readRpc<OperationCrossing[]>('rpc_list_operation_crossings', args) : Promise.resolve([]),
        readRpc<OperationTrackingEvent[]>('rpc_list_operation_tracking_events', args),
        readRpc<OperationReadiness>('rpc_get_operation_dispatch_readiness', args),
        readRpc<OperationBillingSummary>('rpc_get_operation_billing_summary', args),
    ]);
    return { operation, assignmentHistory, incidents, incidentSummary, evidence, documents, documentSummary, crossings, trackingEvents, readiness, billing };
}

export async function createOperationIncident(operationId: string, payload: { category: IncidentCategory; title: string; description?: string; is_blocking: boolean }): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_create_operation_incident', {
        p_operation_id: operationId, p_category: payload.category, p_title: payload.title,
        p_description: payload.description, p_is_blocking: payload.is_blocking, p_tracking_event_id: null,
    });
}

export async function resolveOperationIncident(incidentId: string, note: string): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_resolve_operation_incident', { p_incident_id: incidentId, p_resolution_note: note });
}

export async function dismissOperationIncident(incidentId: string, note: string): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_dismiss_operation_incident', { p_incident_id: incidentId, p_dismiss_note: note });
}

export async function addOperationEvidence(operationId: string, payload: { incident_id?: string | null; kind: EvidenceKind; note?: string; file_ref?: string; external_url?: string }): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_add_operation_evidence', {
        p_operation_id: operationId, p_incident_id: payload.incident_id ?? null,
        p_kind: payload.kind, p_note: payload.note, p_file_ref: payload.file_ref, p_external_url: payload.external_url,
    });
}

export async function upsertOperationDocument(operationId: string, payload: {
    document_type: OperationDocumentType;
    requirement_level: DocumentRequirementLevel;
    status: OperationDocumentStatus;
    document_reference?: string;
    file_ref?: string;
    external_url?: string;
    note?: string;
}): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_upsert_operation_document', {
        p_operation_id: operationId, p_document_type: payload.document_type,
        p_requirement_level: payload.requirement_level, p_status: payload.status,
        p_document_reference: payload.document_reference, p_file_ref: payload.file_ref,
        p_external_url: payload.external_url, p_note: payload.note,
    });
}

export async function upsertOperationCrossing(operationId: string, payload: { id?: string; crossed_at: string; crossing_point: string; crossing_type: CrossingType; note?: string }): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_upsert_operation_crossing', { p_operation_id: operationId, p_payload: payload });
}

export async function deleteOperationCrossing(crossingId: string): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_delete_operation_crossing', { p_crossing_id: crossingId });
}

export async function transitionOperationStatus(operationId: string, toStatus: string): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_transition_operation_status', { p_operation_id: operationId, p_to_status: toStatus });
}

export async function overrideOperationStatus(operationId: string, toStatus: string, reason: string): Promise<void> {
    if (USE_MOCKS) return;
    await readRpc('rpc_override_operation_status', { p_operation_id: operationId, p_to_status: toStatus, p_reason: reason });
}
