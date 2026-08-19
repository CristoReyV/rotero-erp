import { Clock3 } from 'lucide-react';
import type { Operation360Data } from '@/types/operations';
import { formatOperationDate } from './operationsControl';
import { buildOperationTimeline } from './operation360';

const DOTS = { info: 'bg-sky-500', warning: 'bg-amber-500', danger: 'bg-red-500', success: 'bg-emerald-500' } as const;
export function OperationTimeline({ data }: { data: Operation360Data }) {
    const items = buildOperationTimeline(data);
    if (!items.length) return <div className="rounded-2xl border border-dashed border-slate-300 p-10 text-center text-sm text-slate-400"><Clock3 className="mx-auto mb-2" />Todavía no hay eventos cronológicos.</div>;
    return <div className="space-y-0">{items.map((item) => <div key={item.id} className="grid grid-cols-[120px_20px_1fr] gap-3"><p className="pt-1 text-[11px] text-slate-400">{formatOperationDate(item.timestamp)}</p><div className="relative flex justify-center"><span className={`relative z-10 mt-1.5 h-2.5 w-2.5 rounded-full ${DOTS[item.severity ?? 'info']}`} /><span className="absolute inset-y-0 w-px bg-slate-200" /></div><div className="pb-5"><div className="rounded-xl border border-slate-200 bg-white p-3"><div className="flex justify-between gap-3"><p className="text-sm font-bold text-slate-700 capitalize">{item.label}</p><span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">{item.source}</span></div>{item.detail && <p className="mt-1 text-xs text-slate-500">{item.detail}</p>}</div></div></div>)}</div>;
}
