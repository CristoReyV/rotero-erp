import { useCallback, useEffect, useState } from 'react';
import { ArrowRight, BriefcaseBusiness, CalendarDays, FileCheck2, Loader2, RefreshCw, Wallet } from 'lucide-react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { AttentionCenter } from '@/components/executive/AttentionCenter';
import { ExecutiveKpiGrid } from '@/components/executive/ExecutiveKpiGrid';
import { RecentActivity } from '@/components/executive/RecentActivity';
import { DailyDigestCard } from '@/components/productivity/DailyDigestCard';
import { getExecutiveDashboard } from '@/services/executive.service';
import { useAuthStore } from '@/store/authStore';
import type { ExecutiveDashboard, ExecutiveDatePreset } from '@/types/executive';

const presets:Array<{value:ExecutiveDatePreset;label:string}>=[
    {value:'today',label:'Hoy'},{value:'7d',label:'7 días'},{value:'30d',label:'30 días'},
    {value:'month',label:'Mes'},{value:'year',label:'Año'},{value:'custom',label:'Personalizado'},
];
const isPreset=(value:string|null):value is ExecutiveDatePreset=>presets.some(item=>item.value===value);
const isoDate=(date:Date)=>date.toISOString().slice(0,10);
function resolveRange(preset:ExecutiveDatePreset,from:string|null,to:string|null){
    const end=new Date(); let start=new Date(end);
    if(preset==='today')start.setHours(0,0,0,0);
    if(preset==='7d'){start.setDate(start.getDate()-6);start.setHours(0,0,0,0);}
    if(preset==='30d'){start.setDate(start.getDate()-29);start.setHours(0,0,0,0);}
    if(preset==='month')start=new Date(end.getFullYear(),end.getMonth(),1);
    if(preset==='year')start=new Date(end.getFullYear(),0,1);
    if(preset==='custom'){
        const customStart=from?new Date(`${from}T00:00:00`):new Date(end.getFullYear(),end.getMonth(),1);
        const customEnd=to?new Date(`${to}T23:59:59.999`):end;
        return {start:customStart,end:customEnd};
    }
    return {start,end};
}
const money=(value:number)=>new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN',maximumFractionDigits:0}).format(value);

export default function DashboardPage(){
    const tenantId=useAuthStore(state=>state.activeTenant); const role=useAuthStore(state=>state.getRole()); const navigate=useNavigate(); const [params,setParams]=useSearchParams();
    const requested=params.get('range'); const preset:ExecutiveDatePreset=isPreset(requested)?requested:'month'; const from=params.get('from'); const to=params.get('to');
    const [data,setData]=useState<ExecutiveDashboard|null>(null); const [loading,setLoading]=useState(true); const [error,setError]=useState<string|null>(null);
    const load=useCallback(async()=>{if(!tenantId)return;setLoading(true);setError(null);try{const range=resolveRange(preset,from,to);setData(await getExecutiveDashboard(tenantId,range.start,range.end));}catch(cause){setError(cause instanceof Error?cause.message:'No fue posible cargar Executive Dashboard.');}finally{setLoading(false);}},[tenantId,preset,from,to]);
    useEffect(()=>{void load();},[load]);
    const setPreset=(value:ExecutiveDatePreset)=>{const next=new URLSearchParams(params);next.set('range',value);if(value!=='custom'){next.delete('from');next.delete('to');}setParams(next,{replace:true});};
    const setDate=(key:'from'|'to',value:string)=>{const next=new URLSearchParams(params);next.set('range','custom');if(value)next.set(key,value);else next.delete(key);setParams(next,{replace:true});};
    if(!tenantId)return <div className="rounded-2xl border bg-white p-12 text-center text-sm text-slate-400">Selecciona una organización activa.</div>;
    return <div className="space-y-5"><header className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between"><div><p className="text-xs font-black uppercase tracking-[.22em] text-primary">ROTERO Command Center</p><h1 className="mt-1 text-2xl font-black text-slate-900">Executive Dashboard 2.0</h1><p className="mt-1 text-sm text-slate-500">Estado real y acciones prioritarias para {role==='finance'?'Finanzas':'Administración'}.</p></div><div className="flex flex-wrap items-center gap-2"><div className="flex flex-wrap gap-1 rounded-xl border bg-white p-1">{presets.map(item=><button key={item.value} onClick={()=>setPreset(item.value)} className={`rounded-lg px-3 py-2 text-[10px] font-black uppercase ${preset===item.value?'bg-primary text-white':'text-slate-500 hover:bg-slate-50'}`}>{item.label}</button>)}</div><button onClick={()=>void load()} className="rounded-xl border bg-white p-2.5 text-slate-500" title="Actualizar"><RefreshCw size={16} className={loading?'animate-spin':''}/></button></div></header>
        {preset==='custom'&&<div className="flex flex-wrap items-center gap-3 rounded-xl border bg-white p-3 text-xs text-slate-500"><CalendarDays size={15}/><label>Desde <input type="date" value={from??isoDate(new Date(new Date().getFullYear(),new Date().getMonth(),1))} onChange={event=>setDate('from',event.target.value)} className="ml-2 rounded-lg border px-2 py-1.5"/></label><label>Hasta <input type="date" value={to??isoDate(new Date())} onChange={event=>setDate('to',event.target.value)} className="ml-2 rounded-lg border px-2 py-1.5"/></label></div>}
        {error&&<div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>}
        {loading&&!data?<div className="flex h-64 items-center justify-center rounded-2xl border bg-white"><Loader2 className="animate-spin text-primary"/></div>:data&&<>
            <DailyDigestCard tenantId={tenantId}/>
            <ExecutiveKpiGrid dashboard={data}/>
            <div className="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(360px,.85fr)]"><AttentionCenter items={data.attention}/><RecentActivity items={data.recent_activity}/></div>
            <div className={`grid gap-4 ${data.commercial?'xl:grid-cols-4':'xl:grid-cols-3'}`}>
                <Summary icon={BriefcaseBusiness} title="Operations" route="/operations" onOpen={navigate} rows={[["En tránsito",data.operations.in_transit],["Entregadas",data.operations.delivered],["Bloqueos",data.operations.dispatch_blockers]]}/>
                {data.commercial&&<Summary icon={ArrowRight} title="Commercial" route="/commercial?view=quotes" onOpen={navigate} rows={[["En revisión",data.commercial.in_review],["Por convertir",data.commercial.pending_conversion],["Conversión real",`${data.commercial.conversion_rate}%`]]}/>}
                <Summary icon={Wallet} title="Finance" route="/finance" onOpen={navigate} rows={[["AR vencida",money(data.finance.ar_overdue)],["AP vencida",money(data.finance.ap_overdue)],["Vence pronto",data.finance.due_soon]]}/>
                <Summary icon={FileCheck2} title="Documents" route="/documents?view=operations" onOpen={navigate} rows={[["Requeridos faltantes",data.documents.required_missing],["POD pendientes",data.documents.pod_pending],["Facturación bloqueada",data.operations.billing_blocked]]}/>
            </div>
        </>}
    </div>;
}

function Summary({icon:Icon,title,route,rows,onOpen}:{icon:typeof Wallet;title:string;route:string;rows:Array<[string,string|number]>;onOpen:(route:string)=>void}){
    return <button onClick={()=>onOpen(route)} className="rounded-2xl border bg-white p-5 text-left hover:border-primary/30 hover:shadow-lg"><div className="flex items-center justify-between"><h2 className="flex items-center gap-2 font-black text-slate-800"><Icon size={17} className="text-primary"/>{title}</h2><ArrowRight size={15} className="text-slate-300"/></div><dl className="mt-4 space-y-2">{rows.map(([label,value])=><div key={label} className="flex justify-between gap-3 text-xs"><dt className="text-slate-400">{label}</dt><dd className="font-black text-slate-700">{value}</dd></div>)}</dl></button>;
}
