import { AlertTriangle, FileWarning, Landmark, ReceiptText, Route, Truck } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import type { ExecutiveDashboard } from '@/types/executive';

const money = (value: number) => new Intl.NumberFormat('es-MX', {
    style: 'currency', currency: 'MXN', maximumFractionDigits: 0,
}).format(value);

export function ExecutiveKpiGrid({ dashboard }: { dashboard: ExecutiveDashboard }) {
    const navigate = useNavigate();
    const cards = [
        { label: 'Operaciones activas', value: dashboard.operations.active, detail: `${dashboard.operations.in_transit} en tránsito`, icon: Truck, route: '/operations?view=active' },
        { label: 'Incidencias bloqueantes', value: dashboard.operations.blocking_incidents, detail: `${dashboard.operations.dispatch_blockers} bloqueos de despacho`, icon: AlertTriangle, route: '/operations?view=all&tab=incidents' },
        { label: 'AR pendiente', value: money(dashboard.finance.ar_outstanding), detail: `${money(dashboard.finance.ar_overdue)} vencido`, icon: Landmark, route: '/finance?view=ar&status=overdue' },
        { label: 'AP pendiente', value: money(dashboard.finance.ap_outstanding), detail: `${money(dashboard.finance.ap_overdue)} vencido`, icon: ReceiptText, route: '/finance?view=ap&status=overdue' },
        { label: 'Documentos requeridos', value: dashboard.documents.required_missing, detail: `${dashboard.documents.pod_pending} POD pendientes`, icon: FileWarning, route: '/documents?view=operations' },
        { label: 'Listas para facturar', value: dashboard.operations.billing_ready, detail: `${dashboard.operations.billing_blocked} bloqueadas`, icon: Route, route: '/operations?view=all&tab=economics' },
    ];
    return <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{cards.map(({ label,value,detail,icon:Icon,route }) =>
        <button key={label} onClick={()=>navigate(route)} className="rounded-2xl border bg-white p-5 text-left transition hover:-translate-y-0.5 hover:border-primary/30 hover:shadow-lg">
            <div className="flex items-start justify-between"><div><p className="text-[10px] font-bold uppercase tracking-widest text-slate-400">{label}</p><p className="mt-2 text-2xl font-black text-slate-900">{value}</p><p className="mt-1 text-xs text-slate-500">{detail}</p></div><span className="rounded-xl bg-primary-50 p-2.5 text-primary"><Icon size={19}/></span></div>
        </button>)}</div>;
}
