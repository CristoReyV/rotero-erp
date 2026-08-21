import { ArrowDownRight, ArrowUpRight, CircleDollarSign, Clock3 } from 'lucide-react';
import { KPICard } from '@/components/KPICard';
import type { FinanceOverview as Overview } from '@/types/finance';
import { money } from './financeUi';

export function FinanceOverview({ overview }: { overview: Overview }) {
    return <div className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <KPICard title="Por cobrar · MXN" value={money(overview.total_ar_open)} icon={ArrowUpRight} />
            <KPICard title="Por pagar · MXN" value={money(overview.total_ap_open)} icon={ArrowDownRight} />
            <KPICard title="Cobranza vencida · MXN" value={money(overview.total_overdue)} icon={Clock3} />
            <KPICard title="Pagos del mes · MXN" value={money(overview.paid_this_month)} icon={CircleDollarSign} />
        </div>
        {(overview.currencies?.length ?? 0) > 0 && <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <div className="mb-4"><h2 className="font-black text-slate-800">Control por moneda</h2><p className="text-xs text-slate-400">Sin mezclar USD con MXN ni reescribir tipos de cambio históricos.</p></div>
            <div className="grid gap-3 md:grid-cols-2">{overview.currencies?.map((item) => <div key={item.currency} className="rounded-xl border border-slate-100 bg-slate-50 p-4">
                <div className="flex items-center justify-between"><strong className="text-sm text-slate-700">{item.currency}</strong><span className="text-[10px] font-bold uppercase text-slate-400">{item.open_count} abiertas</span></div>
                <div className="mt-3 grid grid-cols-2 gap-3 text-xs"><div><p className="text-slate-400">Por cobrar</p><p className="mt-1 font-black text-emerald-700">{money(item.ar_open, item.currency)}</p></div><div><p className="text-slate-400">Por pagar</p><p className="mt-1 font-black text-rose-700">{money(item.ap_open, item.currency)}</p></div></div>
            </div>)}</div>
        </section>}
    </div>;
}
