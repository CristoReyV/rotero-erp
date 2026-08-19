import type { BadgeVariant } from './common';
import type { Place } from './tracking';

export type OperationStatus = 'draft' | 'planned' | 'assigned' | 'in_transit' | 'delivered' | 'cancelled' | 'closed';
export type OperationPriority = 'low' | 'normal' | 'high';
export type OperationalScope = 'national' | 'international';
export type ExecutionType = 'third_party' | 'own_fleet';
export type PricingCurrency = 'MXN' | 'USD';
export type JsonRecord = Record<string, unknown>;

export interface Operation {
    id: string;
    db_id?: string;
    tenant_id?: string;
    client: string;
    type: string;
    status: OperationStatus | string;
    route: string;
    owner: string;
    variant: BadgeVariant;
    reference_code?: string;
    created_at?: string;
    updated_at?: string;
    customer_id?: string | null;
    client_display_name?: string | null;
    source_deal_id?: string | null;
    service_type?: string | null;
    route_summary?: string | null;
    destination_city?: string | null;
    origin_place?: Place | null;
    destination_place?: Place | null;
    operation_scope?: OperationalScope;
    execution_type?: ExecutionType;
    operational_window_start?: string | null;
    operational_window_end?: string | null;
    planned_departure?: string | null;
    eta?: string | null;
    eta_display?: string | null;
    cargo_summary?: JsonRecord;
    notes?: string | null;
    provider_id?: string | null;
    provider_name?: string | null;
    external_driver?: JsonRecord;
    external_vehicle?: JsonRecord;
    driver_id?: string | null;
    vehicle_id?: string | null;
    driver_name?: string | null;
    vehicle_ref?: string | null;
    priority?: OperationPriority | string;
    provider_cost_amount?: number | null;
    customer_price_amount?: number | null;
    pricing_currency?: PricingCurrency | string;
    service_catalog_item_id?: string | null;
    service_catalog_snapshot?: JsonRecord;
    boxes_placed_days?: number | null;
    documentation_received_at?: string | null;
    documentation_received_note?: string | null;
    assigned_at?: string | null;
    closed_at?: string | null;
    cancelled_at?: string | null;
    required_documents?: unknown[];
}

export interface OperationPlanningPayload {
    service_type: string;
    origin_place: JsonRecord;
    destination_place: JsonRecord;
    operational_window_start: string;
    operational_window_end: string;
    notes?: string;
    cargo_summary?: JsonRecord;
    route_summary?: string;
    destination_city?: string;
    eta?: string;
    eta_display?: string;
    operation_scope: OperationalScope;
    execution_type: ExecutionType;
    provider_cost_amount?: number | null;
    customer_price_amount?: number | null;
    pricing_currency: PricingCurrency;
    service_catalog_item_id?: string | null;
    service_catalog_snapshot?: JsonRecord;
    boxes_placed_days?: number | null;
    documentation_received_at?: string | null;
    documentation_received_note?: string;
}

export interface OperationAssignPayload {
    execution_type: ExecutionType;
    provider_id?: string | null;
    provider_name?: string;
    external_driver?: JsonRecord;
    external_vehicle?: JsonRecord;
    driver_id?: string | null;
    driver_name?: string;
    vehicle_id?: string | null;
    vehicle_ref?: string;
    planned_departure: string;
    priority: OperationPriority;
    reason?: string;
    force_override?: boolean;
}

export interface OperationAssignmentHistoryItem {
    id: string;
    change_type: 'initial_assignment' | 'reassignment' | 'unassignment';
    old_execution_type?: ExecutionType | null;
    new_execution_type?: ExecutionType | null;
    old_provider_name_snapshot?: string | null;
    new_provider_name_snapshot?: string | null;
    old_external_driver_snapshot?: JsonRecord | null;
    new_external_driver_snapshot?: JsonRecord | null;
    old_external_vehicle_snapshot?: JsonRecord | null;
    new_external_vehicle_snapshot?: JsonRecord | null;
    old_driver_name_snapshot?: string | null;
    new_driver_name_snapshot?: string | null;
    old_vehicle_ref_snapshot?: string | null;
    new_vehicle_ref_snapshot?: string | null;
    reason?: string | null;
    changed_by: string;
    changed_at: string;
}

export type IncidentCategory = 'delay' | 'loading_unloading' | 'vehicle_issue' | 'driver_issue' | 'documents_issue' | 'general';
export type IncidentStatus = 'open' | 'resolved' | 'dismissed';
export interface OperationIncident {
    id: string;
    operation_id: string;
    tracking_event_id?: string | null;
    category: IncidentCategory;
    title: string;
    description?: string | null;
    status: IncidentStatus;
    is_blocking: boolean;
    reported_by: string;
    reported_at: string;
    resolved_at?: string | null;
    resolution_note?: string | null;
    dismissed_at?: string | null;
    dismiss_note?: string | null;
    created_at: string;
    updated_at: string;
}

export interface IncidentSummary {
    open_incident_count: number;
    blocking_incident_count: number;
    has_open_incidents: boolean;
    has_blocking_incidents: boolean;
    can_close_operation: boolean;
    evidence_count: number;
    latest_incident_at?: string | null;
}

export type EvidenceKind = 'operational_note' | 'file_reference' | 'image_link' | 'external_link';
export interface OperationEvidenceItem {
    id: string;
    operation_id: string;
    incident_id?: string | null;
    incident_title?: string | null;
    kind: EvidenceKind;
    note?: string | null;
    file_ref?: string | null;
    external_url?: string | null;
    created_by: string;
    created_at: string;
}

export type OperationDocumentType = 'carta_porte_reference' | 'loading_order' | 'delivery_order' | 'proof_of_delivery' | 'administrative_reference' | 'supporting_reference';
export type DocumentRequirementLevel = 'required' | 'optional' | 'not_required';
export type OperationDocumentStatus = 'missing' | 'present';
export interface OperationDocument {
    id?: string | null;
    operation_id: string;
    document_type: OperationDocumentType;
    display_label: string;
    requirement_level: DocumentRequirementLevel;
    status: OperationDocumentStatus;
    document_reference?: string | null;
    file_ref?: string | null;
    external_url?: string | null;
    note?: string | null;
    updated_at?: string | null;
}

export interface OperationDocumentSummary {
    required_count: number;
    present_required_count: number;
    missing_required_count: number;
    has_missing_required: boolean;
    is_documentation_complete: boolean;
    pod_present: boolean;
    pod_required: boolean;
}

export type CrossingType = 'entry' | 'exit' | 'other';
export interface OperationCrossing {
    id: string;
    operation_id: string;
    crossed_at: string;
    crossing_point: string;
    crossing_type: CrossingType;
    note?: string | null;
    created_at: string;
    updated_at: string;
}

export interface OperationTrackingEvent {
    id: string;
    event_type: string;
    source?: string;
    server_timestamp: string;
    client_timestamp?: string;
    municipality?: string | null;
    state_name?: string | null;
    incident_type?: string | null;
    incident_note?: string | null;
}

export interface OperationReadiness {
    is_minimum_planned_complete: boolean;
    is_assignment_complete: boolean;
    is_tracking_ready: boolean;
    can_transition_to_assigned: boolean;
    can_transition_to_in_transit: boolean;
    has_driver_token: boolean;
    has_public_token: boolean;
    blocking_reasons: string[];
}

export interface OperationBillingSummary {
    id?: string | null;
    status?: 'draft' | 'issued' | 'voided' | null;
    billing_reference?: string | null;
    linked_cfdi_id?: string | null;
    issued_at?: string | null;
    voided_at?: string | null;
    has_billing_record: boolean;
    is_billing_ready: boolean;
    billing_blockers: string[];
    is_billed: boolean;
    can_admin_close: boolean;
    pod_present: boolean;
    documentation_complete: boolean;
}

export interface OperationTimelineItem {
    id: string;
    timestamp: string;
    type: 'operation' | 'assignment' | 'tracking' | 'incident' | 'crossing' | 'evidence' | 'document';
    label: string;
    source: string;
    detail?: string;
    status?: string;
    severity?: 'info' | 'warning' | 'danger' | 'success';
}

export interface Operation360Data {
    operation: Operation;
    assignmentHistory: OperationAssignmentHistoryItem[];
    incidents: OperationIncident[];
    incidentSummary: IncidentSummary;
    evidence: OperationEvidenceItem[];
    documents: OperationDocument[];
    documentSummary: OperationDocumentSummary;
    crossings: OperationCrossing[];
    trackingEvents: OperationTrackingEvent[];
    readiness: OperationReadiness;
    billing: OperationBillingSummary;
}

export interface TimelineStep {
    time: string;
    event: string;
    desc: string;
    done?: boolean;
    current?: boolean;
    future?: boolean;
}
