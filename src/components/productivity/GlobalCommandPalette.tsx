import { BadgeDollarSign, Building2, Database, FilePlus2, FileSearch, Landmark, Search, Truck, Upload, Wallet, X } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import type { ProductRole } from '@/constants/roles';
import { globalSearch } from '@/services/executive.service';
import { searchCompliance } from '@/services/compliance.service';
import { searchClaims } from '@/services/claims.service';

interface Action { id:string; label:string; subtitle:string; route:string; icon:typeof Search }
const adminActions:Action[]=[
    {id:'quote',label:'Nueva cotización',subtitle:'Abrir Comercial',route:'/commercial?view=quotes&action=new-quote',icon:FilePlus2},
    {id:'customer',label:'Nuevo cliente',subtitle:'Directorio comercial',route:'/commercial?view=clients&action=new-customer',icon:Building2},
    {id:'provider',label:'Nuevo proveedor',subtitle:'Red operativa',route:'/commercial?view=providers&action=new-provider',icon:Truck},
    {id:'buy-rate',label:'Nueva tarifa proveedor',subtitle:'BUY · precio contratado',route:'/commercial?view=rates&action=new-buy-rate',icon:BadgeDollarSign},
    {id:'sell-rate',label:'Nueva tarifa cliente',subtitle:'SELL · precio negociado',route:'/commercial?view=rates&action=new-sell-rate',icon:BadgeDollarSign},
    {id:'rates',label:'Buscar tarifas',subtitle:'Carriles y versiones vigentes',route:'/commercial?view=rates',icon:Search},
    {id:'compliance',label:'Cumplimiento y contratos',subtitle:'Matriz y vencimientos',route:'/commercial?view=compliance',icon:FileSearch},
    {id:'new-claim',label:'Nueva reclamación',subtitle:'Abrir Reclamaciones',route:'/claims?action=new',icon:FilePlus2},
    {id:'search-claims',label:'Buscar reclamación',subtitle:'Folio, operación, cliente o proveedor',route:'/claims',icon:Search},
    {id:'critical-claims',label:'Reclamaciones críticas',subtitle:'Atención inmediata Admin',route:'/claims?view=critical',icon:FileSearch},
    {id:'open-customer',label:'Abrir cliente',subtitle:'Relación comercial',route:'/commercial?view=clients',icon:Building2},
    {id:'open-provider',label:'Abrir proveedor',subtitle:'Relación comercial',route:'/commercial?view=providers',icon:Truck},
    {id:'ar',label:'Nueva AR',subtitle:'Cuenta por cobrar',route:'/finance?view=ar&action=new',icon:Landmark},
    {id:'ap',label:'Nueva AP',subtitle:'Cuenta por pagar',route:'/finance?view=ap&action=new',icon:Wallet},
    {id:'operations',label:'Operaciones',subtitle:'Control operativo',route:'/operations',icon:Truck},
    {id:'documents',label:'Documentos',subtitle:'Expedientes y archivos',route:'/documents',icon:FileSearch},
    {id:'import-customers',label:'Importar clientes',subtitle:'CSV seguro · Datos',route:'/data?view=import&entity=customers',icon:Upload},
    {id:'import-providers',label:'Importar proveedores',subtitle:'CSV seguro · Datos',route:'/data?view=import&entity=providers',icon:Upload},
    {id:'import-operations',label:'Importar operaciones',subtitle:'Siempre Planeada · ejecución contratada',route:'/data?view=import&entity=operations',icon:Upload},
    {id:'export-data',label:'Exportar datos',subtitle:'Centro de exportación paginada',route:'/data?view=export',icon:Database},
];
const financeActions:Action[]=[
    {id:'ar',label:'Nueva AR',subtitle:'Cuenta por cobrar',route:'/finance?view=ar&action=new',icon:Landmark},
    {id:'ap',label:'Nueva AP',subtitle:'Cuenta por pagar',route:'/finance?view=ap&action=new',icon:Wallet},
    {id:'collection',label:'Registrar cobro',subtitle:'Selecciona una AR',route:'/finance?view=ar',icon:Landmark},
    {id:'payment',label:'Registrar pago',subtitle:'Selecciona una AP',route:'/finance?view=ap',icon:Wallet},
    {id:'due',label:'Vencimientos',subtitle:'Cobros y pagos próximos',route:'/finance?view=due',icon:FileSearch},
];

export function GlobalCommandPalette({tenantId,role}:{tenantId:string|null;role:ProductRole|null}) {
    const navigate=useNavigate(); const [open,setOpen]=useState(false); const [query,setQuery]=useState(''); const [results,setResults]=useState<Array<{type:string;id:string;primary_label:string;secondary_label?:string;status?:string;route:string}>>([]); const [active,setActive]=useState(0); const [loading,setLoading]=useState(false); const input=useRef<HTMLInputElement>(null);const searchRequest=useRef(0);
    const actions=role==='admin'?adminActions:role==='finance'?financeActions:[];
    useEffect(()=>{const key=(event:KeyboardEvent)=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();setOpen(true);}if(event.key==='Escape')setOpen(false);};document.addEventListener('keydown',key);return()=>document.removeEventListener('keydown',key);},[]);
    useEffect(()=>{if(open)window.setTimeout(()=>input.current?.focus(),0);else{setQuery('');setResults([]);setActive(0);}},[open]);
    useEffect(()=>{const request=++searchRequest.current;if(!open||!tenantId||query.trim().length<2){setResults([]);setLoading(false);return;}const timer=window.setTimeout(async()=>{setLoading(true);try{const[base,compliance,claims]=await Promise.all([globalSearch(tenantId,query.trim()),role==='admin'?searchCompliance(tenantId,query.trim()):Promise.resolve([]),role==='admin'?searchClaims(tenantId,query.trim()):Promise.resolve([])]);if(request!==searchRequest.current)return;setResults([...base,...compliance,...claims.map(item=>({type:'claim',id:item.id,primary_label:item.claim_number,secondary_label:item.subject,status:item.status,route:item.route}))]);setActive(0);}finally{if(request===searchRequest.current)setLoading(false);}},250);return()=>window.clearTimeout(timer);},[open,query,tenantId,role]);
    const choices=useMemo(()=>[
        ...actions.map(action=>({key:`action-${action.id}`,label:action.label,subtitle:action.subtitle,route:action.route,kind:'Acción'})),
        ...results.map(result=>({key:`result-${result.type}-${result.id}`,label:result.primary_label,subtitle:result.secondary_label||result.status,route:result.route,kind:result.type})),
    ],[actions,results]);
    const go=(route:string)=>{setOpen(false);navigate(route);};
    const onKey=(event:ReactKeyboardEvent)=>{if(event.key==='ArrowDown'){event.preventDefault();setActive(v=>Math.min(v+1,choices.length-1));}if(event.key==='ArrowUp'){event.preventDefault();setActive(v=>Math.max(v-1,0));}if(event.key==='Enter'&&choices[active]){event.preventDefault();go(choices[active].route);}if(event.key==='Escape')setOpen(false);};
    return <><button onClick={()=>setOpen(true)} className="flex w-10 items-center gap-2 rounded-xl border bg-surface px-3 py-2 text-left text-sm text-slate-400 md:w-full md:max-w-sm"><Search size={15}/><span className="hidden flex-1 md:block">Buscar o ejecutar una acción…</span><kbd className="hidden rounded border bg-white px-1.5 py-0.5 text-[9px] font-black md:block">Ctrl K</kbd></button>{open&&<div className="fixed inset-0 z-[100] flex items-start justify-center bg-slate-950/55 p-4 pt-[10vh] backdrop-blur-sm" onMouseDown={(event)=>{if(event.currentTarget===event.target)setOpen(false);}}><div className="w-full max-w-2xl overflow-hidden rounded-2xl border bg-white shadow-2xl"><div className="flex items-center gap-3 border-b px-4"><Search size={19} className="text-slate-400"/><input ref={input} value={query} onChange={event=>setQuery(event.target.value)} onKeyDown={onKey} placeholder="Busca operaciones, documentos, AR/AP…" className="h-14 flex-1 bg-transparent text-sm outline-none"/><button onClick={()=>setOpen(false)} className="p-2 text-slate-400"><X size={17}/></button></div><div className="max-h-[60vh] overflow-y-auto p-2">{loading&&<p className="p-3 text-xs text-slate-400">Buscando…</p>}{choices.map((choice,index)=><button key={choice.key} onMouseEnter={()=>setActive(index)} onClick={()=>go(choice.route)} className={`flex w-full items-center gap-3 rounded-xl px-3 py-3 text-left ${active===index?'bg-primary text-white':'hover:bg-slate-50'}`}><span className={`rounded-lg px-2 py-1 text-[9px] font-black uppercase ${active===index?'bg-white/15':'bg-slate-100 text-slate-500'}`}>{choice.kind}</span><span className="min-w-0"><b className="block truncate text-sm">{choice.label}</b><span className={`block truncate text-[11px] ${active===index?'text-white/70':'text-slate-400'}`}>{choice.subtitle}</span></span></button>)}{!loading&&choices.length===0&&<p className="p-8 text-center text-sm text-slate-400">Escribe al menos dos caracteres.</p>}</div><footer className="flex gap-4 border-t bg-slate-50 px-4 py-2 text-[10px] font-bold text-slate-400"><span>↑↓ navegar</span><span>Enter abrir</span><span>Esc cerrar</span></footer></div></div>}</>;
}
