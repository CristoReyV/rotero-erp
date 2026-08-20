import type { Operation360Data, OperationTimelineItem } from '@/types/operations';

const LABELS: Record<string, string> = {
    initial_assignment: 'Asignación contratada',
    reassignment: 'Cambio de asignación',
    unassignment: 'Asignación retirada',
    operational_note: 'Nota operativa',
    file_reference: 'Referencia de archivo',
    image_link: 'Evidencia fotográfica',
    external_link: 'Enlace de evidencia',
    open: 'Incidencia abierta',
    resolved: 'Incidencia resuelta',
    dismissed: 'Incidencia descartada',
};

export function calculateOperationMargin(providerCost?: number | null, customerPrice?: number | null) {
    if (providerCost == null || customerPrice == null) return { amount: null, percentage: null };
    const amount = customerPrice - providerCost;
    return { amount, percentage: customerPrice === 0 ? null : (amount / customerPrice) * 100 };
}

export function validateOperationalChronology(start?: string | null, end?: string | null, eta?: string | null): string | null {
    if (!start || !end) return 'Captura el inicio y fin de la ventana operativa.';
    const startMs = Date.parse(start);
    const endMs = Date.parse(end);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
        return 'La ventana operativa debe terminar después de su inicio.';
    }
    if (eta) {
        const etaMs = Date.parse(eta);
        if (!Number.isFinite(etaMs) || etaMs < startMs) return 'La ETA no puede ser anterior al inicio de la ventana.';
    }
    return null;
}

export function getSnapshotText(snapshot: Record<string, unknown> | null | undefined, keys: string[]): string {
    return getSnapshotValue(snapshot, keys) ?? 'Datos por confirmar';
}

function getSnapshotValue(snapshot: Record<string, unknown> | null | undefined, keys: string[]): string | null {
    if (!snapshot) return null;
    for (const key of keys) {
        const value = snapshot[key];
        if (typeof value === 'string' && value.trim()) return value.trim();
    }
    return null;
}

export function buildOperationTimeline(data: Operation360Data): OperationTimelineItem[] {
    const items: OperationTimelineItem[] = [];
    const operation = data.operation;
    if (operation.created_at) items.push({ id: `operation-created-${operation.db_id}`, timestamp: operation.created_at, type: 'operation', label: 'Operación creada', source: 'Operations', detail: operation.source_deal_id ? 'Originada desde cotización comercial' : 'Alta operativa' });
    if (operation.assigned_at) items.push({ id: `operation-assigned-${operation.db_id}`, timestamp: operation.assigned_at, type: 'operation', label: 'Operación asignada', source: 'Operations', detail: operation.provider_name || operation.driver_name || 'Asignación registrada', status: 'assigned', severity: 'info' });
    if (operation.closed_at) items.push({ id: `operation-closed-${operation.db_id}`, timestamp: operation.closed_at, type: 'operation', label: 'Operación cerrada', source: 'Operations', status: 'closed', severity: 'success' });
    if (operation.cancelled_at) items.push({ id: `operation-cancelled-${operation.db_id}`, timestamp: operation.cancelled_at, type: 'operation', label: 'Operación cancelada', source: 'Operations', status: 'cancelled', severity: 'danger' });

    data.assignmentHistory.forEach((item) => items.push({ id: `assignment-${item.id}`, timestamp: item.changed_at, type: 'assignment', label: LABELS[item.change_type] ?? 'Asignación actualizada', source: 'Asignación', detail: item.new_provider_name_snapshot || getSnapshotValue(item.new_external_driver_snapshot, ['name', 'display_name']) || item.new_driver_name_snapshot || item.reason || undefined, severity: item.change_type === 'reassignment' ? 'warning' : 'info' }));
    data.trackingEvents.forEach((item) => items.push({ id: `tracking-${item.id}`, timestamp: item.server_timestamp, type: 'tracking', label: item.event_type.replaceAll('_', ' '), source: 'Tracking', detail: [item.municipality, item.state_name].filter(Boolean).join(', ') || item.incident_note || undefined, status: item.event_type, severity: item.event_type === 'incident' ? 'danger' : item.event_type === 'delivered' ? 'success' : 'info' }));
    data.incidents.forEach((item) => items.push({ id: `incident-${item.id}`, timestamp: item.reported_at || item.created_at, type: 'incident', label: item.title, source: 'Incidencias', detail: item.description || LABELS[item.status], status: item.status, severity: item.status === 'open' && item.is_blocking ? 'danger' : item.status === 'open' ? 'warning' : 'success' }));
    data.crossings.forEach((item) => items.push({ id: `crossing-${item.id}`, timestamp: item.crossed_at, type: 'crossing', label: `Cruce ${item.crossing_type}`, source: 'Cruces', detail: item.crossing_point, severity: 'info' }));
    data.evidence.forEach((item) => items.push({ id: `evidence-${item.id}`, timestamp: item.created_at, type: 'evidence', label: LABELS[item.kind] ?? 'Evidencia', source: 'Evidencias', detail: item.note || item.file_ref || item.external_url || undefined, severity: 'info' }));
    data.documents.filter((item) => item.updated_at).forEach((item) => items.push({ id: `document-${item.document_type}-${item.updated_at}`, timestamp: item.updated_at!, type: 'document', label: item.display_label, source: 'Documentos', detail: item.status === 'present' ? 'Documento presente' : 'Documento pendiente', status: item.status, severity: item.status === 'present' ? 'success' : item.requirement_level === 'required' ? 'warning' : 'info' }));
    return items.sort((a, b) => Date.parse(b.timestamp) - Date.parse(a.timestamp));
}
