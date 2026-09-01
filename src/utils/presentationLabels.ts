import type { FiscalSafeError, FiscalStatus } from '@/types/billing';
import type { ClaimPriority, ClaimStatus, ClaimType } from '@/types/claims';
import type { DocumentFileKind, DocumentFileStatus, DocumentSourceModule, DocumentTemplateType, GeneratedDocumentStatus } from '@/types/documents';
import type { PaymentMethod } from '@/types/finance';

const fallback = (label: string) => label;

export const READINESS_REASON_LABELS: Record<string, string> = {
    missing_planning_data: 'Planeación incompleta',
    missing_assignment: 'Proveedor sin asignar',
    driver_unavailable: 'Operador no disponible',
    vehicle_unavailable: 'Unidad no disponible',
    tracking_not_ready: 'Enlaces de seguimiento pendientes',
    missing_driver_capability: 'Falta enlace para el operador',
    missing_public_capability: 'Falta enlace público',
    provider_compliance_blocked: 'Proveedor con requisitos pendientes',
};

export function getReadinessReasonLabel(value: string): string {
    return READINESS_REASON_LABELS[value] ?? fallback('Requisito operativo pendiente');
}

export const CLAIM_TYPE_LABELS: Record<ClaimType, string> = {
    delay: 'Retraso',
    damage: 'Daño',
    shortage: 'Faltante',
    loss: 'Pérdida',
    documentation: 'Documentación',
    billing: 'Facturación',
    service_quality: 'Calidad del servicio',
    provider_performance: 'Desempeño del proveedor',
    compliance: 'Cumplimiento',
    other: 'Otra',
};

export const CLAIM_STATUS_LABELS: Record<ClaimStatus, string> = {
    open: 'Abierta',
    triage: 'Clasificación inicial',
    investigating: 'En investigación',
    awaiting_customer: 'Esperando al cliente',
    awaiting_provider: 'Esperando al proveedor',
    action_in_progress: 'Acciones en curso',
    resolved: 'Resuelta',
    closed: 'Cerrada',
    cancelled: 'Cancelada',
};

export const CLAIM_PRIORITY_LABELS: Record<ClaimPriority, string> = {
    critical: 'Crítica', high: 'Alta', medium: 'Media', low: 'Baja',
};

export const CLAIM_EVENT_LABELS: Record<string, string> = {
    created: 'Creado',
    status_changed: 'Cambio de estado',
    assigned: 'Responsable asignado',
    note: 'Nota agregada',
    customer_contact: 'Contacto con cliente',
    provider_contact: 'Contacto con proveedor',
    evidence_added: 'Evidencia agregada',
    exposure_changed: 'Exposición actualizada',
    responsibility_changed: 'Responsabilidad actualizada',
    root_cause_changed: 'Causa raíz actualizada',
    resolution: 'Resolución registrada',
    reopened: 'Reabierto',
    closed: 'Cerrado',
    cancelled: 'Cancelado',
    action_created: 'Acción creada',
    action_completed: 'Acción concluida',
    settlement: 'Acuerdo registrado',
};

export const CLAIM_ACTION_STATUS_LABELS: Record<string, string> = {
    open: 'Abierta', in_progress: 'En curso', done: 'Concluida', cancelled: 'Cancelada',
};

export function getClaimEventLabel(value: string): string {
    return CLAIM_EVENT_LABELS[value] ?? fallback('Evento registrado');
}

export const DOCUMENT_KIND_LABELS: Record<DocumentFileKind, string> = {
    generated_pdf: 'PDF generado',
    fiscal_xml: 'XML fiscal',
    fiscal_pdf: 'PDF fiscal',
    provider_upload: 'Archivo del proveedor',
    operation_evidence: 'Evidencia operativa',
    supporting_file: 'Archivo de soporte',
    html_snapshot: 'Vista HTML archivada',
};

export const DOCUMENT_STATUS_LABELS: Record<DocumentFileStatus, string> = {
    active: 'Activo', superseded: 'Sustituido', cancelled: 'Cancelado',
};

export const GENERATED_DOCUMENT_STATUS_LABELS: Record<GeneratedDocumentStatus, string> = {
    draft: 'Borrador', final: 'Final', cancelled: 'Cancelado',
};

export const DOCUMENT_MODULE_LABELS: Record<DocumentSourceModule, string> = {
    operations: 'Operaciones', commercial: 'Comercial', billing: 'Facturación',
    finance: 'Finanzas', documents: 'Documentos', claims: 'Reclamaciones',
};

export const DOCUMENT_TEMPLATE_LABELS: Record<DocumentTemplateType, string> = {
    commercial_quote: 'Cotización comercial',
    operation_summary: 'Resumen operativo',
    operation_document: 'Documento operativo',
    payment_complement: 'Complemento de pago',
    credit_note: 'Nota de crédito',
    provider_document: 'Documento del proveedor',
    finance_internal_receipt: 'Recibo financiero interno',
    finance_note: 'Nota financiera',
    payroll_receipt: 'Recibo de nómina',
};

const FISCAL_FIELD_LABELS: Record<string, string> = {
    concepts: 'Conceptos',
    'payment.method': 'Método de pago',
};

const joinSpanish = (labels: string[]) => labels.length < 2 ? labels[0] ?? '' : `${labels.slice(0, -1).join(', ')} y ${labels.at(-1)}`;

export function formatFiscalMissingFields(fields: string[]): string {
    const known = fields.map((field) => FISCAL_FIELD_LABELS[field]).filter((label): label is string => Boolean(label));
    const unknownCount = fields.length - known.length;
    if (unknownCount > 0) known.push(unknownCount === 1 ? 'otro dato fiscal requerido' : 'otros datos fiscales requeridos');
    const sentenceLabels=known.map((label,index)=>index===0?label:`${label.charAt(0).toLocaleLowerCase('es-MX')}${label.slice(1)}`);
    return sentenceLabels.length ? `Faltan: ${joinSpanish(sentenceLabels)}` : 'Faltan datos fiscales requeridos';
}

export const FISCAL_STATUS_LABELS: Record<FiscalStatus, string> = {
    draft: 'Borrador', ready_for_api: 'Listo para envío', queued: 'En cola', submitting: 'Enviando',
    processing: 'En proceso', stamped: 'Timbrado', rejected: 'Rechazado', api_error: 'Error del proveedor',
    cancellation_requested: 'Cancelación solicitada', cancelled: 'Cancelado', cancellation_rejected: 'Cancelación rechazada',
};

export const FISCAL_ERROR_LABELS: Record<FiscalSafeError, string> = {
    provider_not_configured: 'Proveedor fiscal no configurado', validation_failed: 'Validación fiscal incompleta',
    provider_unavailable: 'Proveedor fiscal no disponible', provider_timeout: 'El proveedor fiscal no respondió a tiempo',
    provider_rejected: 'Solicitud rechazada por el proveedor', already_processing: 'La solicitud ya está en proceso',
    already_stamped: 'El comprobante ya está timbrado', invalid_transition: 'El cambio de estado no está permitido',
    cancellation_failed: 'No fue posible cancelar', artifact_unavailable: 'El archivo fiscal no está disponible',
    status_conflict: 'El estado fiscal cambió durante la operación',
};

export function getFiscalProviderLabel(code?: string | null): string {
    if (!code) return 'No configurado';
    if (code === 'soft_management') return 'Soft Management';
    return 'Proveedor configurado';
}

export function getFiscalAttemptLabel(status?: string | null): string {
    if (!status) return 'Sin estado';
    return ({ queued: 'En cola', processing: 'En proceso', succeeded: 'Completado', failed: 'Fallido', cancelled: 'Cancelado' } as Record<string, string>)[status] ?? 'Estado registrado';
}

export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
    transfer: 'Transferencia', cash: 'Efectivo', card: 'Tarjeta', other: 'Otro',
};

export const FINANCE_RECORD_STATUS_LABELS: Record<string, string> = {
    draft: 'Borrador', applied: 'Aplicada', ready: 'Listo', issued: 'Emitido', cancelled: 'Cancelado',
};

export const FINANCE_EVENT_LABELS: Record<string, string> = {
    invoice_created: 'Cuenta creada', payment_recorded: 'Pago registrado',
    credit_note_draft: 'Nota de crédito en borrador', credit_note_applied: 'Nota de crédito aplicada',
    credit_note_cancelled: 'Nota de crédito cancelada', complement_draft: 'Complemento en borrador',
    complement_ready: 'Complemento listo', complement_issued: 'Complemento emitido',
    complement_cancelled: 'Complemento cancelado',
};

export function getFinanceEventLabel(value: string): string {
    return FINANCE_EVENT_LABELS[value] ?? fallback('Movimiento financiero registrado');
}
