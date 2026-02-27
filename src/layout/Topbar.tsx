import { useState, useRef, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Search, Bell, ChevronDown, Sparkles, LogOut, Settings } from 'lucide-react';
import { ROUTE_TITLES } from '@/constants/nav';
import { useAuthStore } from '@/store/authStore';
import { supabase } from '@/lib/supabase';

export const Topbar = () => {
    const { pathname } = useLocation();
    const navigate = useNavigate();
    const title = ROUTE_TITLES[pathname] || 'ROTERO ERP';
    const { context, getRole, logout, activeTenant } = useAuthStore();
    const role = getRole();
    const [showProfileMenu, setShowProfileMenu] = useState(false);
    const menuRef = useRef<HTMLDivElement>(null);

    const activeMembership = context?.memberships.find(m => m.tenant_id === activeTenant);
    const tenantName = activeMembership?.tenant_name || 'Sin Tenant';
    const userName = context?.email?.split('@')[0] || 'Usuario';
    const userInitials = userName.substring(0, 2).toUpperCase();

    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
                setShowProfileMenu(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    const handleLogout = async () => {
        await supabase.auth.signOut();
        logout();
        navigate('/login');
    };

    return (
        <header className="h-16 bg-surface-card/80 backdrop-blur-xl border-b border-tech-border/60 flex items-center justify-between px-6 shrink-0 z-20">
            <div className="flex items-center gap-5 flex-1 min-w-0">
                <h2 className="text-base font-bold text-primary whitespace-nowrap">{title}</h2>

                {/* Search */}
                <div className="max-w-sm w-full relative hidden md:block">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        placeholder="Buscar PO, Tracking, Pedimento..."
                        className="w-full pl-9 pr-4 py-2 bg-surface border border-tech-border rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
            </div>

            <div className="flex items-center gap-3">
                {/* Tenant selector */}
                <div className="flex items-center gap-2 px-3 py-1.5 bg-surface border border-tech-border rounded-xl cursor-pointer hover:border-primary/20 hover:shadow-sm transition-all group">
                    <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse-dot" />
                    <span className="text-xs font-semibold text-slate-600 group-hover:text-primary transition-colors">{tenantName}</span>
                    <ChevronDown size={13} className="text-slate-400" />
                </div>

                {/* Notifications */}
                <button className="relative p-2 text-slate-400 hover:text-primary hover:bg-primary-50 rounded-xl transition-all">
                    <Bell size={19} strokeWidth={1.8} />
                    <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-accent-red rounded-full ring-2 ring-white" />
                </button>

                {/* Divider */}
                <div className="h-8 w-px bg-tech-border mx-1" />

                {/* User profile */}
                <div className="relative" ref={menuRef}>
                    <div
                        className="flex items-center gap-2.5 cursor-pointer group"
                        onClick={() => setShowProfileMenu(!showProfileMenu)}
                    >
                        <div className="text-right hidden sm:block">
                            <p className="text-xs font-semibold text-slate-700 group-hover:text-primary transition-colors capitalize">{userName}</p>
                            <p className="text-[10px] text-slate-400 font-medium capitalize">{role || 'Usuario'}</p>
                        </div>
                        <div className="w-9 h-9 rounded-xl gradient-primary flex items-center justify-center text-white text-xs font-bold shadow-md shadow-primary/15 ring-2 ring-white select-none">
                            {userInitials}
                        </div>
                    </div>

                    {/* Dropdown Menu */}
                    {showProfileMenu && (
                        <div className="absolute right-0 top-full mt-2 w-48 bg-white rounded-xl shadow-lg border border-slate-100 py-2 animate-fade-in origin-top-right">
                            <div className="px-4 py-2 border-b border-slate-50 mb-1 sm:hidden">
                                <p className="text-xs font-bold text-slate-700 truncate">{context?.email}</p>
                                <p className="text-[10px] text-slate-400 capitalize">{role}</p>
                            </div>
                            <button
                                onClick={() => { setShowProfileMenu(false); /* Optional: Navigate to Settings */ }}
                                className="w-full flex items-center gap-2 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50 hover:text-primary transition-colors text-left"
                            >
                                <Settings size={15} />
                                Configuración
                            </button>
                            <button
                                onClick={handleLogout}
                                className="w-full flex items-center gap-2 px-4 py-2 text-sm text-accent-red hover:bg-red-50 transition-colors text-left"
                            >
                                <LogOut size={15} />
                                Cerrar Sesión
                            </button>
                        </div>
                    )}
                </div>
            </div>
        </header>
    );
};
