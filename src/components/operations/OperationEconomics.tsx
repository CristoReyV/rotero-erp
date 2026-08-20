import { ArrowUpRight, CircleDollarSign } from 'lucide-react';
import { Link } from 'react-router-dom';
import type { Operation360Data } from '@/types/operations';
import { calculateOperationMargin } from './operation360';

export function OperationEconomics({ data }: { data: Operation360Data }) {
    const op = data.operation;
    const margin = calculateOperationMargin(op.provider_cost_amount, op.customer_price_amount);
    const currency = op.pricing_currency || 'MXN';
    const money = (value?: number | null) => value == null ? 'Datos por confirmar' : new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(value);
    return <div className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {[['Costo proveedor', money(op.provider_cost_amount)], ['Venta cliente', money(op.customer_price_amount)], ['Utilidad bruta', money(margin.amount)], ['Margen', margin.percentage == null ? 'Datos por confirmar' : `${margin.percentage.toFixed(1)}%`]].map(([label, value]) => <div key={label} className="rounded-2xl border border-slate-200 bg-slate-50 p-4"><p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">{label}</p><p className="mt-2 text-lg font-bold text-slate-800">{value}</p></div>)}
        </div>
        <p className="text-xs text-slate-500">Valores en {currency}. No se realiza conversión FX ni se mezclan monedas.</p>
        <div className="rounded-2xl border border-slate-200 p-4"><div className="flex items-center gap-2"><CircleDollarSign size={18} className="text-primary" /><h3 className="font-bold text-slate-700">Resumen de Billing</h3></div><div className="mt-3 grid gap-3 sm:grid-cols-3"><div><p className="text-[10px] font-bold uppercase text-slate-400">Estado</p><p className="mt-1 text-sm font-semibold">{data.billing.status || 'Sin registro'}</p></div><div><p className="text-[10px] font-bold uppercase text-slate-400">Referencia</p><p className="mt-1 text-sm font-semibold">{data.billing.billing_reference || 'Datos por confirmar'}</p></div><div><p className="text-[10px] font-bold uppercase text-slate-400">Emitido</p><p className="mt-1 text-sm font-semibold">{data.billing.is_billed ? 'Sí' : 'No'}</p></div></div><Link to="/billing" className="mt-4 inline-flex items-center gap-1 text-xs font-bold text-primary hover:underline">Abrir Billing <ArrowUpRight size={13} /></Link></div>
    </div>;
}
