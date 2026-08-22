import { X } from 'lucide-react';
import type { ReactNode } from 'react';

export function BulkActionBar({ count, onClear, children, summary }: { count: number; onClear: () => void; children: ReactNode; summary?: ReactNode }) {
    if (!count) return null;
    return <div className="sticky top-2 z-30 flex flex-wrap items-center gap-2 rounded-2xl border border-primary/20 bg-white p-3 shadow-lg shadow-slate-900/10"><span className="rounded-xl bg-primary px-3 py-2 text-xs font-black text-white">{count} seleccionados</span>{summary && <span className="text-xs font-semibold text-slate-500">{summary}</span>}<div className="ml-auto flex flex-wrap items-center gap-2">{children}<button onClick={onClear} className="rounded-xl border p-2 text-slate-500" title="Limpiar selección"><X size={14} /></button></div></div>;
}
