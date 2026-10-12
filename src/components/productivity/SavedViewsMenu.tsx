import { Bookmark, Check, Pencil, Star, Trash2 } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { MobileSheet } from '@/components/MobileSheet';
import { MOBILE_MEDIA_QUERY, useMediaQuery } from '@/hooks/useMediaQuery';
import { deleteSavedView, listSavedViews, saveView } from '@/services/executive.service';
import type { ProductivityModule, SavedView } from '@/types/executive';

export function SavedViewsMenu({ tenantId, module, filters, onApply }: { tenantId: string | null; module: ProductivityModule; filters: Record<string, unknown>; onApply: (filters: Record<string, unknown>) => void }) {
    const [open, setOpen] = useState(false);
    const [views, setViews] = useState<SavedView[]>([]);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const ref = useRef<HTMLDivElement>(null);
    const isMobile = useMediaQuery(MOBILE_MEDIA_QUERY);
    const load = useCallback(async () => {
        if (!tenantId) return;
        try { setViews(await listSavedViews(tenantId, module)); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar vistas.'); }
    }, [tenantId, module]);

    useEffect(() => { void load(); }, [load]);
    useEffect(() => {
        if (isMobile) return;
        const close = (event: MouseEvent) => {
            if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false);
        };
        document.addEventListener('mousedown', close);
        return () => document.removeEventListener('mousedown', close);
    }, [isMobile]);

    const create = async () => {
        if (!tenantId) return;
        const name = window.prompt('Nombre de la vista');
        if (!name?.trim()) return;
        setBusy(true); setError(null);
        try {
            await saveView(tenantId, { module, name: name.trim(), filters, is_default: views.length === 0 });
            await load(); setOpen(true);
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar la vista.'); }
        finally { setBusy(false); }
    };
    const rename = async (view: SavedView) => { if (!tenantId) return; const name = window.prompt('Nuevo nombre', view.name); if (!name?.trim()) return; await saveView(tenantId, { ...view, name: name.trim() }); await load(); };
    const makeDefault = async (view: SavedView) => { if (!tenantId) return; await saveView(tenantId, { ...view, is_default: true }); await load(); };
    const remove = async (view: SavedView) => { if (!tenantId || !window.confirm(`Eliminar la vista “${view.name}”?`)) return; await deleteSavedView(tenantId, view.id, module); await load(); };

    const content = <>
        <div className="flex items-center justify-between gap-3 border-b px-3 py-2">
            <b className="truncate text-xs text-slate-700">{module}</b>
            <button type="button" onClick={() => void create()} className="min-h-11 shrink-0 px-2 text-[10px] font-black uppercase text-primary">Guardar actual</button>
        </div>
        {error && <p className="p-3 text-xs text-red-600">{error}</p>}
        <div className="max-h-[min(60dvh,24rem)] overflow-y-auto overscroll-contain">
            {views.length === 0 ? <p className="p-6 text-center text-xs text-slate-400">Aún no hay vistas.</p> : views.map((view) => <div key={view.id} className="flex min-w-0 items-center gap-1 border-b p-2 last:border-0">
                <button type="button" onClick={() => { onApply(view.filters); setOpen(false); }} className="min-h-11 min-w-0 flex-1 rounded-lg px-2 py-2 text-left hover:bg-slate-50">
                    <span className="flex min-w-0 items-center gap-1 text-xs font-bold text-slate-700">{view.is_default && <Check size={12} className="shrink-0 text-emerald-600" />}<span className="truncate">{view.name}</span></span>
                </button>
                <button type="button" onClick={() => void makeDefault(view)} aria-label={`Marcar ${view.name} como predeterminada`} className="flex h-11 w-11 shrink-0 items-center justify-center text-slate-400 hover:text-amber-500"><Star size={14} /></button>
                <button type="button" onClick={() => void rename(view)} aria-label={`Renombrar ${view.name}`} className="flex h-11 w-11 shrink-0 items-center justify-center text-slate-400 hover:text-primary"><Pencil size={14} /></button>
                <button type="button" onClick={() => void remove(view)} aria-label={`Eliminar ${view.name}`} className="flex h-11 w-11 shrink-0 items-center justify-center text-slate-400 hover:text-red-500"><Trash2 size={14} /></button>
            </div>)}
        </div>
    </>;

    return <div className="relative" ref={ref}>
        <button type="button" disabled={!tenantId || busy} aria-expanded={open} aria-haspopup="dialog" aria-label="Abrir vistas guardadas" onClick={() => setOpen((value) => !value)} className="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border bg-surface-card px-3 text-xs font-bold text-slate-600 disabled:opacity-50">
            <Bookmark size={15} /><span className="hidden sm:inline">Vistas guardadas</span>
        </button>
        {open && !isMobile && <div className="absolute right-0 z-30 mt-2 w-72 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border bg-surface-card shadow-2xl">{content}</div>}
        {isMobile && <MobileSheet open={open} title="Vistas guardadas" subtitle="Aplica o administra tus vistas del módulo" onClose={() => setOpen(false)}>{content}</MobileSheet>}
    </div>;
}
