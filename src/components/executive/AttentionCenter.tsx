import { AlertCircle, ArrowRight, Clock3 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import type { AttentionItem, AttentionSeverity } from '@/types/executive';

const tone: Record<AttentionSeverity,string> = {
    critical:'border-red-200 bg-red-50 text-red-700', high:'border-amber-200 bg-amber-50 text-amber-700',
    medium:'border-blue-200 bg-blue-50 text-blue-700', low:'border-slate-200 bg-slate-50 text-slate-600',
};

export function AttentionCenter({ items }: { items: AttentionItem[] }) {
    const navigate=useNavigate();
    return <section className="rounded-2xl border bg-white">
        <header className="flex items-center justify-between border-b px-5 py-4"><div><h2 className="font-black text-slate-800">Requiere atención</h2><p className="text-xs text-slate-400">Prioridad derivada de estado canónico, sin tareas duplicadas.</p></div><span className="rounded-full bg-red-50 px-2.5 py-1 text-xs font-black text-red-700">{items.length}</span></header>
        <div className="max-h-[520px] divide-y overflow-y-auto">{items.length===0?<div className="p-10 text-center text-sm text-slate-400">No hay pendientes críticos para este contexto.</div>:items.map((item)=><button key={`${item.kind}-${item.entity_id}`} onClick={()=>navigate(item.route)} className="flex w-full items-start gap-3 p-4 text-left hover:bg-slate-50">
            <span className={`mt-0.5 rounded-lg border p-2 ${tone[item.severity]}`}><AlertCircle size={15}/></span><span className="min-w-0 flex-1"><span className="flex flex-wrap items-center gap-2"><b className="truncate text-sm text-slate-800">{item.title}</b><span className={`rounded-full border px-2 py-0.5 text-[9px] font-black uppercase ${tone[item.severity]}`}>{item.severity}</span></span><span className="mt-1 block truncate text-xs text-slate-500">{item.reference} · {item.subtitle}</span>{item.due_at&&<span className="mt-1 flex items-center gap-1 text-[10px] text-slate-400"><Clock3 size={11}/>{new Date(item.due_at).toLocaleDateString('es-MX')}</span>}</span><ArrowRight size={15} className="mt-2 shrink-0 text-slate-300"/>
        </button>)}</div>
    </section>;
}
