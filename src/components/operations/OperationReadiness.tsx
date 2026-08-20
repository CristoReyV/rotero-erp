import { AlertTriangle, CheckCircle2, CircleDashed, KeyRound } from 'lucide-react';
import type { Operation360Data } from '@/types/operations';

function Check({ ok, label, detail }: { ok: boolean; label: string; detail: string }) {
    return <div className={`rounded-xl border p-3 ${ok ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'}`}><div className="flex items-center gap-2">{ok ? <CheckCircle2 size={16} className="text-emerald-600" /> : <CircleDashed size={16} className="text-amber-600" />}<p className="text-xs font-bold text-slate-700">{label}</p></div><p className="mt-1 pl-6 text-[11px] text-slate-500">{detail}</p></div>;
}

export function OperationReadiness({ data, canManageTracking, onGenerateTokens }: { data: Operation360Data; canManageTracking: boolean; onGenerateTokens: () => void }) {
    const { readiness, incidentSummary, documentSummary, billing, operation } = data;
    return <div className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <Check ok={readiness.is_minimum_planned_complete} label="Planeación" detail="Servicio, lugares y ventana operativa válidos." />
            <Check ok={readiness.is_assignment_complete} label="Proveedor / asignación" detail={operation.execution_type === 'third_party' ? 'Proveedor contratado y salida planeada.' : 'Chofer y unidad internos asignados.'} />
            <Check ok={!documentSummary.has_missing_required} label="Documentos requeridos" detail={`${documentSummary.present_required_count}/${documentSummary.required_count} presentes.`} />
            <Check ok={!incidentSummary.has_blocking_incidents} label="Incidencias bloqueantes" detail={`${incidentSummary.blocking_incident_count} abierta(s).`} />
            <Check ok={readiness.has_driver_token} label="Capability chofer" detail="La capability se crea o rota solo mediante acción Admin explícita." />
            <Check ok={readiness.has_public_token} label="Tracking público" detail="Enlace público activo cuando aplica." />
            <Check ok={documentSummary.pod_present} label="Prueba de entrega (POD)" detail={documentSummary.pod_present ? 'POD presente en documentos.' : 'POD pendiente o no requerido.'} />
            <Check ok={billing.is_billed} label="Billing" detail={billing.has_billing_record ? `Estado: ${billing.status ?? 'sin confirmar'}` : 'Sin registro de billing.'} />
            <Check ok={readiness.is_tracking_ready} label="Despacho" detail="Planeación, asignación y capacidades completas." />
        </div>
        {readiness.blocking_reasons.length > 0 && <div className="flex gap-2 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800"><AlertTriangle size={16} className="shrink-0" /><span>Bloqueos actuales: {readiness.blocking_reasons.join(', ')}.</span></div>}
        {canManageTracking && (!readiness.has_driver_token || !readiness.has_public_token) && <button type="button" onClick={onGenerateTokens} className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><KeyRound size={15} /> Generar capacidades explícitamente</button>}
    </div>;
}
