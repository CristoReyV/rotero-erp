import { AlertTriangle, Bell, Bot, CheckCheck, FileText, RefreshCw, Wallet, X } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { dismissInternalNotification, listInternalNotifications, markInternalNotificationsRead } from '@/services/executive.service';
import { createNotificationCenter } from '@/services/notificationCenter';
import type { InternalNotification } from '@/types/executive';
import { isRoteroEnabledRole } from '@/constants/roles';
import { useAuthStore } from '@/store/authStore';

const icons={operations:AlertTriangle,commercial:FileText,documents:FileText,finance:Wallet} as const;
type NotificationFilter='all'|'critical'|'operations'|'finance'|'documents'|'commercial'|'automated';

export function NotificationCenter({ tenantId }: { tenantId:string|null }) {
    const { context, activeTenant, getRole } = useAuthStore();
    const role = getRole();
    const navigate = useNavigate();
    const { pathname } = useLocation();
    const [open, setOpen] = useState(false);
    const [filter, setFilter] = useState<NotificationFilter>('all');
    const ref = useRef<HTMLDivElement>(null);
    const controller = useMemo(() => createNotificationCenter({
        list: listInternalNotifications, markRead: markInternalNotificationsRead, dismiss: dismissInternalNotification,
    }), []);
    const snapshot = useSyncExternalStore(controller.subscribe, controller.getSnapshot);
    const matches = context?.user_id === snapshot.scope?.userId
        && tenantId === snapshot.scope?.tenantId && activeTenant === tenantId && role === snapshot.scope?.role;
    const items = matches ? snapshot.items : [];
    const unread = matches ? snapshot.unread : 0;
    const nextCursor = matches ? snapshot.nextCursor : null;
    const loading = matches && snapshot.loading;
    const busy = matches && snapshot.busy;
    const error = matches ? snapshot.error : null;

    useEffect(() => {
        const syncScope = () => {
            const auth = useAuthStore.getState();
            const currentRole = auth.getRole();
            const scope = auth.context?.user_id && auth.activeTenant === tenantId
                && tenantId && isRoteroEnabledRole(currentRole)
                ? { userId: auth.context.user_id, tenantId, role: currentRole } : null;
            if (controller.setScope(scope)) {
                setOpen(false);
                setFilter('all');
                if (scope) void controller.automatic('mount');
            }
        };
        syncScope();
        const unsubscribe = useAuthStore.subscribe(syncScope);
        return () => { unsubscribe(); controller.setScope(null); };
    }, [controller, tenantId]);
    useEffect(() => { void controller.automatic('navigation'); }, [controller, pathname]);
    useEffect(() => {
        const onFocus = () => { void controller.automatic('focus'); };
        const onOnline = () => { void controller.automatic('online'); };
        window.addEventListener('focus', onFocus);
        window.addEventListener('online', onOnline);
        return () => { window.removeEventListener('focus', onFocus); window.removeEventListener('online', onOnline); };
    }, [controller]);
    useEffect(() => {
        const close = (event: MouseEvent) => { if (ref.current && !ref.current.contains(event.target as Node)) setOpen(false); };
        document.addEventListener('mousedown', close);
        return () => document.removeEventListener('mousedown', close);
    }, []);
    const openItem = async (item: InternalNotification) => {
        const route = await controller.openItem(item);
        if (route) { setOpen(false); navigate(route); }
    };
    const markAll = () => controller.markAll();
    const dismiss = (id: string) => controller.dismiss(id);
    const filters:Array<{value:NotificationFilter;label:string}>=[
        {value:'all',label:'Todo'},{value:'critical',label:'Crítico'},
        {value:'operations',label:'Operaciones'},{value:'finance',label:'Finanzas'},
        {value:'documents',label:'Documentos'},
        ...(role==='admin'?[{value:'commercial' as const,label:'Comercial'}]:[]),
        {value:'automated',label:'Automatizadas'},
    ];
    const visibleItems=items.filter(item=>filter==='all'
        ||(filter==='critical'&&item.priority==='critical')
        ||(filter==='automated'&&item.is_automated)
        ||item.module===filter);
    return <div className="relative" ref={ref}><button type="button" onClick={()=>setOpen(v=>!v)} className="relative rounded-xl p-2 text-slate-400 hover:bg-primary-50 hover:text-primary" aria-label="Abrir notificaciones"><Bell size={19}/>{unread>0&&<span className="absolute right-0 top-0 flex min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[9px] font-black text-white">{Math.min(unread,99)}</span>}</button>{open&&<div className="absolute right-0 top-full z-50 mt-2 w-[min(94vw,440px)] overflow-hidden rounded-2xl border bg-white shadow-2xl"><header className="flex items-center justify-between border-b px-4 py-3"><div><b className="text-sm text-slate-800">Notificaciones</b><p className="text-[10px] text-slate-400">{unread} sin leer</p></div><div className="flex gap-1"><button type="button" onClick={()=>void controller.load()} aria-label="Actualizar listado de notificaciones" className="rounded-lg p-2 text-slate-400 hover:bg-slate-100"><RefreshCw size={14} className={loading?'animate-spin':''}/></button>{unread>0&&<button type="button" disabled={busy} onClick={()=>void markAll()} aria-label="Marcar todas las notificaciones como leídas" className="rounded-lg p-2 text-slate-400 hover:bg-slate-100"><CheckCheck size={15}/></button>}</div></header><div className="flex gap-1 overflow-x-auto border-b px-3 py-2">{filters.map(option=><button type="button" key={option.value} onClick={()=>setFilter(option.value)} className={`whitespace-nowrap rounded-lg px-2.5 py-1.5 text-[9px] font-black uppercase ${filter===option.value?'bg-primary text-white':'bg-slate-50 text-slate-400'}`}>{option.label}</button>)}</div><div className="max-h-[440px] divide-y overflow-y-auto">{error&&<p role="alert" className="p-3 text-xs text-red-700">{error}</p>}{visibleItems.length===0?<div className="p-10 text-center text-xs text-slate-400">Sin notificaciones relevantes.</div>:visibleItems.map(item=>{const Icon=icons[item.module];return <div key={item.id} className={`group flex items-start gap-3 p-4 ${item.read_at?'bg-white':'bg-blue-50/40'}`}><button type="button" disabled={busy} onClick={()=>void openItem(item)} className="flex min-w-0 flex-1 items-start gap-3 text-left"><span className="rounded-lg bg-slate-100 p-2 text-slate-600">{item.is_automated?<Bot size={14}/>:<Icon size={14}/>}</span><span className="min-w-0"><span className="block truncate text-xs font-black text-slate-800">{item.title}</span><span className="mt-0.5 block text-[11px] leading-relaxed text-slate-500">{item.body}</span><span className="mt-1 block text-[9px] font-bold uppercase text-slate-300">{item.priority} · {new Date(item.occurred_at).toLocaleString('es-MX')}{item.is_automated?` · automática L${item.escalation_level}`:''}</span></span></button><button type="button" disabled={busy} onClick={()=>void dismiss(item.id)} aria-label="Descartar notificación" className="p-1 text-slate-300 opacity-0 hover:text-red-500 group-hover:opacity-100"><X size={13}/></button></div>})}{nextCursor&&<button type="button" disabled={loading} onClick={()=>void controller.load(true)} className="w-full p-3 text-xs font-bold text-primary disabled:opacity-50">{loading?'Cargando…':'Cargar más'}</button>}</div></div>}</div>;
}
