import { ChevronDown, LogOut, Moon, Settings, Sun } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { GlobalCommandPalette } from '@/components/productivity/GlobalCommandPalette';
import { NotificationCenter } from '@/components/productivity/NotificationCenter';
import { ROUTE_TITLES } from '@/constants/nav';
import { useTheme } from '@/hooks/useTheme';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';

export const Topbar=()=>{
    const {pathname}=useLocation(); const navigate=useNavigate(); const {context,getRole,logout,activeTenant}=useAuthStore(); const role=getRole(); const {isDark,toggle}=useTheme();
    const [profile,setProfile]=useState(false); const ref=useRef<HTMLDivElement>(null); const title=ROUTE_TITLES[pathname]||'ROTERO ERP';
    const membership=context?.memberships.find(item=>item.tenant_id===activeTenant); const tenantName=membership?.tenant_name||'Sin tenant'; const userName=context?.email?.split('@')[0]||'Usuario';
    useEffect(()=>{const close=(event:MouseEvent)=>{if(ref.current&&!ref.current.contains(event.target as Node))setProfile(false);};document.addEventListener('mousedown',close);return()=>document.removeEventListener('mousedown',close);},[]);
    const signOut=async()=>{await supabase.auth.signOut();logout();navigate('/login');};
    return <header className="z-20 flex h-16 shrink-0 items-center justify-between gap-3 border-b border-tech-border/60 bg-surface-card/85 px-4 backdrop-blur-xl lg:px-6">
        <div className="flex min-w-0 flex-1 items-center gap-4"><h2 className="hidden whitespace-nowrap text-sm font-black text-primary xl:block">{title}</h2><GlobalCommandPalette tenantId={activeTenant} role={role}/></div>
        <div className="flex items-center gap-2"><div className="hidden items-center gap-2 rounded-xl border bg-surface px-3 py-2 sm:flex"><span className="h-2 w-2 rounded-full bg-emerald-500"/><span className="max-w-36 truncate text-xs font-bold text-slate-600">{tenantName}</span><ChevronDown size={12} className="text-slate-400"/></div><NotificationCenter tenantId={activeTenant}/><button onClick={toggle} className="rounded-xl p-2 text-slate-400 hover:bg-primary-50 hover:text-primary" aria-label={isDark?'Modo claro':'Modo oscuro'}>{isDark?<Sun size={18}/>:<Moon size={18}/>}</button><div className="relative" ref={ref}><button onClick={()=>setProfile(value=>!value)} className="flex items-center gap-2 rounded-xl p-1 hover:bg-slate-50"><span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary text-xs font-black text-white">{userName.slice(0,2).toUpperCase()}</span><span className="hidden text-left md:block"><b className="block max-w-28 truncate text-xs text-slate-700">{userName}</b><span className="block text-[9px] font-bold uppercase text-slate-400">{role}</span></span></button>{profile&&<div className="absolute right-0 mt-2 w-52 overflow-hidden rounded-xl border bg-white py-1 shadow-xl"><button onClick={()=>{setProfile(false);navigate('/security/settings');}} className="flex w-full items-center gap-2 px-4 py-3 text-xs font-bold text-slate-600 hover:bg-slate-50"><Settings size={14}/>Configuración</button><button onClick={()=>void signOut()} className="flex w-full items-center gap-2 px-4 py-3 text-xs font-bold text-red-600 hover:bg-red-50"><LogOut size={14}/>Cerrar sesión</button></div>}</div></div>
    </header>;
};
