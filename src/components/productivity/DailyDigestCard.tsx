import { useCallback, useEffect, useState } from 'react';
import { AlertOctagon, ArrowRight, CalendarCheck2, FileWarning, Loader2, Wallet } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { getDailyDigest } from '@/services/automation.service';
import type { DailyDigest } from '@/types/automation';

export function DailyDigestCard({ tenantId }: { tenantId: string }) {
    const navigate = useNavigate();
    const [digest, setDigest] = useState<DailyDigest | null>(null);
    const [businessDate, setBusinessDate] = useState('');
    const [loading, setLoading] = useState(true);
    const load = useCallback(async () => {
        setLoading(true);
        try {
            const result = await getDailyDigest(tenantId);
            setDigest(result.digest);
            setBusinessDate(result.business_date);
        } finally {
            setLoading(false);
        }
    }, [tenantId]);
    useEffect(() => { void load(); }, [load]);

    if (loading) return <div className="flex h-28 items-center justify-center rounded-2xl border bg-white"><Loader2 size={18} className="animate-spin text-primary" /></div>;
    if (!digest) return <section className="rounded-2xl border bg-white p-5">
        <p className="flex items-center gap-2 text-sm font-black text-slate-800"><CalendarCheck2 size={17} className="text-primary" /> Resumen del día</p>
        <p className="mt-2 text-xs text-slate-400">El resumen de {businessDate} se generará en el siguiente ciclo diario. Las alertas activas siguen visibles en Notificaciones.</p>
    </section>;
    const totals = [
        { label: 'Críticas', value: digest.summary.critical, icon: AlertOctagon, route: '/operations' },
        { label: 'AR vencida', value: digest.summary.ar_overdue, icon: Wallet, route: '/finance?view=ar&status=overdue' },
        { label: 'AP vencida', value: digest.summary.ap_overdue, icon: Wallet, route: '/finance?view=ap&status=overdue' },
        { label: 'Docs / POD', value: digest.summary.documents_missing, icon: FileWarning, route: '/documents?view=operations' },
    ];
    if (digest.role === 'admin') totals.push({ label: 'Cotizaciones', value: digest.summary.quotes_pending, icon: ArrowRight, route: '/commercial?view=quotes' });
    return <section className="rounded-2xl border bg-white p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
            <div><p className="flex items-center gap-2 text-sm font-black text-slate-800"><CalendarCheck2 size={17} className="text-primary" /> Resumen del día</p><p className="mt-1 text-[10px] text-slate-400">{digest.business_date} · {digest.timezone} · {digest.summary.total} alertas accionables</p></div>
            <span className="rounded-lg bg-slate-50 px-3 py-1.5 text-[10px] font-black uppercase text-slate-500">{digest.summary.high} altas</span>
        </div>
        <div className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
            {totals.map(item => <button key={item.label} onClick={() => navigate(item.route)} className="flex items-center justify-between rounded-xl border p-3 text-left hover:border-primary/30 hover:bg-primary-50/30"><span className="flex items-center gap-2 text-[11px] font-bold text-slate-500"><item.icon size={14} />{item.label}</span><b className="text-sm text-slate-800">{item.value}</b></button>)}
        </div>
        {digest.items.length > 0 && <div className="mt-4 flex flex-wrap gap-2">{digest.items.slice(0, 4).map(item => <button key={item.id} onClick={() => navigate(item.route)} className="rounded-lg bg-slate-50 px-3 py-2 text-[10px] font-bold text-slate-600 hover:bg-primary-50 hover:text-primary">{item.title} <ArrowRight size={10} className="ml-1 inline" /></button>)}</div>}
    </section>;
}
