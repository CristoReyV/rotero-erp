import { AlertTriangle, CheckCircle2, CircleDashed, KeyRound } from 'lucide-react';
import { SemanticPanel, SEMANTIC_TONE_STYLES } from '@/components/SemanticPanel';
import type { Operation360Data } from '@/types/operations';
import { getReadinessReasonLabel } from '@/utils/presentationLabels';

function Check({ ok, label, detail }: { ok: boolean; label: string; detail: string }) {
    const tone=ok?'success':'warning';
    return <SemanticPanel tone={tone} className="min-w-0 p-3"><div className="flex min-w-0 items-center gap-2">{ok ? <CheckCircle2 size={16} className={`shrink-0 ${SEMANTIC_TONE_STYLES.success.accent}`} /> : <CircleDashed size={16} className={`shrink-0 ${SEMANTIC_TONE_STYLES.warning.accent}`} />}<p className="min-w-0 break-words text-xs font-bold text-slate-700">{label}</p></div><p className="mt-1 break-words pl-6 text-[11px] leading-relaxed text-slate-500">{detail}</p></SemanticPanel>;
}

export function OperationReadiness({ data, canManageTracking, onGenerateTokens }: { data: Operation360Data; canManageTracking: boolean; onGenerateTokens: () => void }) {
    const { readiness, incidentSummary, documentSummary, billing, operation } = data;
    return <div className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <Check ok={readiness.is_minimum_planned_complete} label="Planeación" detail="Servicio, lugares y ventana operativa válidos." />
            <Check ok={readiness.is_assignment_complete} label="Proveedor / asignación" detail={operation.execution_type === 'third_party' ? 'Proveedor contratado y salida planeada.' : 'Chofer y unidad internos asignados.'} />
            {operation.execution_type === 'third_party' && <Check ok={readiness.provider_compliance_ready !== false} label="Elegibilidad del proveedor" detail={readiness.provider_compliance_ready === false ? 'Existe una política requerida, bloqueante y de asignación sin resolver.' : 'Sin bloqueos operativos configurados o con una excepción específica.'} />}
            <Check ok={!documentSummary.has_missing_required} label="Documentos requeridos" detail={`${documentSummary.present_required_count}/${documentSummary.required_count} presentes.`} />
            <Check ok={!incidentSummary.has_blocking_incidents} label="Incidencias bloqueantes" detail={`${incidentSummary.blocking_incident_count} abierta(s).`} />
            <Check ok={readiness.has_driver_token} label="Enlace del operador" detail="El enlace se crea o rota solo mediante una acción administrativa explícita." />
            <Check ok={readiness.has_public_token} label="Tracking público" detail="Enlace público activo cuando aplica." />
            <Check ok={documentSummary.pod_present} label="Prueba de entrega (POD)" detail={documentSummary.pod_present ? 'POD presente en documentos.' : 'POD pendiente o no requerido.'} />
            <Check ok={billing.is_billed} label="Facturación" detail={billing.has_billing_record ? 'Existe un registro de facturación relacionado.' : 'Sin registro de facturación.'} />
            <Check ok={readiness.is_tracking_ready} label="Despacho" detail="Planeación, asignación y capacidades completas." />
        </div>
        {readiness.blocking_reasons.length > 0 && <SemanticPanel tone="warning" className="flex min-w-0 gap-2 p-3 text-xs"><AlertTriangle size={16} className={`shrink-0 ${SEMANTIC_TONE_STYLES.warning.accent}`} /><span className="min-w-0 break-words text-slate-600">Bloqueos actuales: {readiness.blocking_reasons.map(getReadinessReasonLabel).join(', ')}.</span></SemanticPanel>}
        {canManageTracking && (!readiness.has_driver_token || !readiness.has_public_token) && <button type="button" onClick={onGenerateTokens} className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><KeyRound size={15} /> Generar enlaces</button>}
    </div>;
}
