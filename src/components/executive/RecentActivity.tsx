import { ArrowUpRight, History } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import type { RecentActivityItem } from '@/types/executive';

export function RecentActivity({ items }: { items: RecentActivityItem[] }) {
    const navigate=useNavigate();
    return <section className="rounded-2xl border bg-white"><header className="border-b px-5 py-4"><h2 className="flex items-center gap-2 font-black text-slate-800"><History size={17}/>Actividad reciente</h2><p className="text-xs text-slate-400">Eventos normalizados; nunca se muestra el JSON de auditoría.</p></header><div className="divide-y">{items.length===0?<p className="p-8 text-center text-sm text-slate-400">Sin actividad en el periodo.</p>:items.slice(0,12).map((item)=><button key={item.id} onClick={()=>navigate(item.route)} className="flex w-full items-center gap-3 px-5 py-3 text-left hover:bg-slate-50"><span className="h-2 w-2 rounded-full bg-primary"/><span className="min-w-0 flex-1"><b className="block truncate text-xs text-slate-700">{item.title}</b><span className="block truncate text-[11px] text-slate-400">{item.subtitle} · {new Date(item.occurred_at).toLocaleString('es-MX')}</span></span><span className="rounded-full bg-slate-100 px-2 py-1 text-[9px] font-bold uppercase text-slate-500">{item.module}</span><ArrowUpRight size={13} className="text-slate-300"/></button>)}</div></section>;
}
