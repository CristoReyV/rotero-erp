import { X } from 'lucide-react';
import type { ReactNode } from 'react';

export function BulkActionBar({ count, onClear, children, summary }: { count: number; onClear: () => void; children: ReactNode; summary?: ReactNode }) {
    if (!count) return null;
    return <div className="sticky top-2 z-30 flex min-w-0 flex-wrap items-center gap-2 rounded-2xl border border-primary/20 bg-surface-card p-3 shadow-lg shadow-slate-900/10"><span className="rounded-xl bg-primary px-3 py-2 text-xs font-black text-white">{count} seleccionados</span>{summary && <span className="min-w-0 break-words text-xs font-semibold text-slate-500">{summary}</span>}<div className="flex w-full min-w-0 flex-wrap items-center gap-2 sm:ml-auto sm:w-auto">{children}<button onClick={onClear} aria-label="Limpiar selección" className="flex h-11 w-11 items-center justify-center rounded-xl border text-slate-500" title="Limpiar selección"><X size={14} /></button></div></div>;
}
