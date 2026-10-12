import { AlertCircle, ArrowRight, Clock3 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Badge } from '@/components/Badge';
import { SEMANTIC_TONE_STYLES, type SemanticTone } from '@/components/SemanticPanel';
import type { AttentionItem, AttentionSeverity } from '@/types/executive';

const severityPresentation: Record<AttentionSeverity, { label: string; tone: SemanticTone; badge: 'danger' | 'warning' | 'info' | 'default' }> = {
    critical: { label: 'Crítica', tone: 'danger', badge: 'danger' },
    high: { label: 'Alta', tone: 'warning', badge: 'warning' },
    medium: { label: 'Media', tone: 'info', badge: 'info' },
    low: { label: 'Baja', tone: 'neutral', badge: 'default' },
};

export function AttentionCenter({ items }: { items: AttentionItem[] }) {
    const navigate=useNavigate();
    return <section className="min-w-0 max-w-full overflow-hidden rounded-2xl border bg-surface-card">
        <header className="flex min-w-0 items-start justify-between gap-3 border-b px-4 py-4 sm:px-5"><div className="min-w-0"><h2 className="font-black text-slate-800">Requiere atención</h2><p className="text-xs leading-relaxed text-slate-400">Prioridades operativas sin tareas duplicadas.</p></div><Badge variant="danger">{items.length}</Badge></header>
        <div className="max-h-[520px] min-w-0 divide-y overflow-y-auto">{items.length===0?<div className="p-8 text-center text-sm text-slate-400 sm:p-10">No hay pendientes críticos para este contexto.</div>:items.map((item)=>{const presentation=severityPresentation[item.severity];const tone=SEMANTIC_TONE_STYLES[presentation.tone];return <button key={`${item.kind}-${item.entity_id}`} onClick={()=>navigate(item.route)} className="flex w-full min-w-0 items-start gap-2.5 p-3 text-left active:bg-semantic-neutral-soft sm:gap-3 sm:p-4 sm:hover:bg-semantic-neutral-soft">
            <span className={`mt-0.5 shrink-0 rounded-lg border p-2 ${tone.soft} ${tone.border}`}><AlertCircle size={15}/></span><span className="min-w-0 flex-1"><span className="flex min-w-0 flex-wrap items-start gap-2"><b className="min-w-0 flex-1 break-words text-sm text-slate-800">{item.title}</b><Badge variant={presentation.badge}>{presentation.label}</Badge></span><span className="mt-1 block break-words text-xs leading-relaxed text-slate-500">{item.reference} · {item.subtitle}</span>{item.due_at&&<span className="mt-1 flex min-w-0 items-center gap-1 text-[10px] text-slate-400"><Clock3 size={11} className="shrink-0"/>{new Date(item.due_at).toLocaleDateString('es-MX')}</span>}</span><ArrowRight size={15} className="mt-2 shrink-0 text-slate-300"/>
        </button>})}</div>
    </section>;
}
