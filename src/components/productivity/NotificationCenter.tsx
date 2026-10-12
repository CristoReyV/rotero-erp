import { AlertTriangle, Bell, Bot, CheckCheck, FileText, RefreshCw, Wallet, X } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { MobileSheet } from '@/components/MobileSheet';
import { MOBILE_MEDIA_QUERY, useMediaQuery } from '@/hooks/useMediaQuery';
import { dismissInternalNotification, listInternalNotifications, markInternalNotificationsRead, refreshInternalNotifications } from '@/services/executive.service';
import type { InternalNotification, NotificationFeed } from '@/types/executive';
import { useAuthStore } from '@/store/authStore';

const icons = { operations: AlertTriangle, commercial: FileText, documents: FileText, finance: Wallet } as const;
type NotificationFilter = 'all' | 'critical' | 'operations' | 'finance' | 'documents' | 'commercial' | 'automated';

export function NotificationCenter({ tenantId }: { tenantId: string | null }) {
    const role = useAuthStore((state) => state.getRole());
    const navigate = useNavigate();
    const { pathname } = useLocation();
    const [open, setOpen] = useState(false);
    const [items, setItems] = useState<InternalNotification[]>([]);
    const [unread, setUnread] = useState(0);
    const [loading, setLoading] = useState(false);
    const [nextCursor, setNextCursor] = useState<NotificationFeed['next_cursor']>(null);
    const [filter, setFilter] = useState<NotificationFilter>('all');
    const ref = useRef<HTMLDivElement>(null);
    const requestId = useRef(0);
    const nextCursorRef = useRef<NotificationFeed['next_cursor']>(null);
    const isMobile = useMediaQuery(MOBILE_MEDIA_QUERY);

    const load = useCallback(async (refresh = true, more = false) => {
        if (!tenantId) return;
        const current = ++requestId.current;
        setLoading(true);
        try {
            if (refresh) await refreshInternalNotifications(tenantId);
            const feed = await listInternalNotifications(tenantId, false, more ? nextCursorRef.current : null);
            if (current !== requestId.current) return;
            setItems((value) => more ? [...value, ...feed.items.filter(item=>!value.some((existing) => existing.id === item.id))] : feed.items);
            setUnread(feed.unread_count);
            nextCursorRef.current = feed.next_cursor;
            setNextCursor(feed.next_cursor);
        } finally { if (current === requestId.current) setLoading(false); }
    }, [tenantId]);

    useEffect(() => { void load(true); }, [load, pathname]);
    useEffect(() => { const onFocus = () => void load(true); window.addEventListener('focus', onFocus); return () => window.removeEventListener('focus', onFocus); }, [load]);
    useEffect(() => {
        if (isMobile) return;
        const close = (event: MouseEvent) => { if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false); };
        document.addEventListener('mousedown', close);
        return () => document.removeEventListener('mousedown', close);
    }, [isMobile]);

    const openItem = async (item: InternalNotification) => { if (!tenantId) return; if (!item.read_at) await markInternalNotificationsRead(tenantId, [item.id]); setOpen(false); navigate(item.route); };
    const markAll = async () => { if (!tenantId) return; await markInternalNotificationsRead(tenantId, null); await load(false); };
    const dismiss = async (id: string) => { if (!tenantId) return; await dismissInternalNotification(tenantId, id); await load(false); };
    const filters: Array<{ value: NotificationFilter; label: string }> = [
        { value: 'all', label: 'Todo' }, { value: 'critical', label: 'Crítico' }, { value: 'operations', label: 'Operaciones' }, { value: 'finance', label: 'Finanzas' }, { value: 'documents', label: 'Documentos' },
        ...(role==='admin' ? [{ value: 'commercial' as const, label: 'Comercial' }] : []), { value: 'automated', label: 'Automatizadas' },
    ];
    const visibleItems = items.filter((item) => filter === 'all' || (filter === 'critical' && item.priority === 'critical') || (filter === 'automated' && item.is_automated) || item.module === filter);

    const tools = <div className="flex items-center justify-between gap-2 px-3 py-2">
        <span className="text-xs font-semibold text-slate-500">{unread} sin leer</span>
        <div className="flex gap-1">
            <button type="button" onClick={() => void load(true)} aria-label="Actualizar notificaciones" className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-100"><RefreshCw size={15} className={loading ? 'animate-spin' : ''} /></button>
            {unread > 0 && <button type="button" onClick={() => void markAll()} aria-label="Marcar todas las notificaciones como leídas" className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-100"><CheckCheck size={16} /></button>}
        </div>
    </div>;
    const feed = <>
        <div className="flex gap-1 overflow-x-auto overscroll-x-contain border-y px-3 py-2">{filters.map((option) => <button type="button" key={option.value} onClick={() => setFilter(option.value)} aria-pressed={filter === option.value} className={`min-h-11 shrink-0 whitespace-nowrap rounded-lg px-3 text-[9px] font-black uppercase ${filter === option.value ? 'bg-primary text-white' : 'bg-surface text-slate-500'}`}>{option.label}</button>)}</div>
        <div className="max-h-[min(62dvh,440px)] divide-y overflow-y-auto overscroll-contain">{visibleItems.length === 0 ? <div className="p-8 text-center text-xs text-slate-400">Sin notificaciones relevantes.</div> : visibleItems.map((item) => { const Icon = icons[item.module]; return <div key={item.id} className={`group flex min-w-0 items-start gap-2 p-3 ${item.read_at ? 'bg-surface-card' : 'bg-primary-50'}`}>
            <button type="button" onClick={() => void openItem(item)} className="flex min-h-11 min-w-0 flex-1 items-start gap-3 text-left"><span className="shrink-0 rounded-lg bg-surface p-2 text-slate-600">{item.is_automated ? <Bot size={14} /> : <Icon size={14} />}</span><span className="min-w-0"><span className="block truncate text-xs font-black text-slate-800">{item.title}</span><span className="mt-0.5 block break-words text-[11px] leading-relaxed text-slate-500">{item.body}</span><span className="mt-1 block break-words text-[9px] font-bold uppercase text-slate-400">{item.priority} · {new Date(item.occurred_at).toLocaleString('es-MX')}{item.is_automated ? ` · automática L${item.escalation_level}` : ''}</span></span></button>
            <button type="button" onClick={() => void dismiss(item.id)} aria-label="Descartar notificación" className="flex h-11 w-11 shrink-0 items-center justify-center text-slate-400 sm:opacity-0 sm:group-hover:opacity-100"><X size={14} /></button>
        </div>; })}{nextCursor && <button type="button" disabled={loading} onClick={() => void load(false, true)} className="min-h-11 w-full p-3 text-xs font-bold text-primary disabled:opacity-50">{loading ? 'Cargando…' : 'Cargar más'}</button>}</div>
    </>;

    return <div className="relative" ref={ref}>
        <button type="button" onClick={() => setOpen((value) => !value)} aria-expanded={open} aria-haspopup="dialog" className="relative flex h-11 w-11 items-center justify-center rounded-xl text-slate-400 hover:bg-primary-50 hover:text-primary" aria-label="Abrir notificaciones"><Bell size={19} />{unread > 0 && <span className="absolute right-0 top-0 flex min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[9px] font-black text-white">{Math.min(unread, 99)}</span>}</button>
        {open && !isMobile && <div className="absolute right-0 top-full z-50 mt-2 w-[min(440px,calc(100vw-2rem))] overflow-hidden rounded-2xl border bg-surface-card shadow-2xl"><header className="border-b px-4 py-3"><b className="text-sm text-slate-800">Notificaciones</b></header>{tools}{feed}</div>}
        {isMobile && <MobileSheet open={open} title="Notificaciones" subtitle={`${unread} sin leer`} onClose={() => setOpen(false)}>{tools}{feed}</MobileSheet>}
    </div>;
}
