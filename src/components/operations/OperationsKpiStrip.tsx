import { CheckCircle2, ClipboardList, Radio, Route, Truck, Warehouse } from 'lucide-react';
import type { Operation } from '@/types/operations';
import { getOperationsCounts } from './operationsControl';

interface OperationsKpiStripProps {
    operations: Operation[];
}

export function OperationsKpiStrip({ operations }: OperationsKpiStripProps) {
    const counts = getOperationsCounts(operations);
    const items = [
        { label: 'Activas', value: counts.active, icon: Radio, tone: 'text-blue-700 bg-blue-50' },
        { label: 'Planeadas', value: counts.planned, icon: ClipboardList, tone: 'text-amber-700 bg-amber-50' },
        { label: 'Asignadas', value: counts.assigned, icon: Truck, tone: 'text-indigo-700 bg-indigo-50' },
        { label: 'En tránsito', value: counts.inTransit, icon: Route, tone: 'text-sky-700 bg-sky-50' },
        { label: 'Entregadas', value: counts.delivered, icon: CheckCircle2, tone: 'text-emerald-700 bg-emerald-50' },
        { label: 'Cerradas', value: counts.closed, icon: Warehouse, tone: 'text-slate-600 bg-slate-100' },
    ];

    return (
        <section aria-label="Resumen operativo" className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
            {items.map(({ label, value, icon: Icon, tone }) => (
                <div key={label} className="rounded-2xl border border-tech-border/60 bg-surface-card p-4 shadow-sm shadow-slate-200/20">
                    <div className="flex items-center justify-between gap-3">
                        <div>
                            <p className="text-[10px] font-bold uppercase tracking-widest text-slate-400">{label}</p>
                            <p className="mt-1 text-2xl font-bold text-slate-800">{value}</p>
                        </div>
                        <span className={`rounded-xl p-2.5 ${tone}`}><Icon size={18} /></span>
                    </div>
                </div>
            ))}
        </section>
    );
}
