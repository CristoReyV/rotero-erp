import React, { useState, useRef, useEffect, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Search, Bell, ChevronDown, Sparkles, LogOut, Settings, X, Check, AlertTriangle, Info, Truck, Moon, Sun } from 'lucide-react';
import { ROUTE_TITLES } from '@/constants/nav';
import { useAuthStore } from '@/store/authStore';
import { useTheme } from '@/hooks/useTheme';
import { supabase } from '@/lib/supabase';

// ── Notification system (placeholder until real-time is wired) ─────────────
interface AppNotification {
    id: string;
    icon: 'info' | 'warning' | 'success' | 'truck';
    title: string;
    body: string;
    time: string;
    read: boolean;
}

const INITIAL_NOTIFICATIONS: AppNotification[] = [
    { id: 'n1', icon: 'truck', title: 'Operación OP-8492', body: 'Llegó al punto de entrega', time: 'Hace 12 min', read: false },
    { id: 'n2', icon: 'warning', title: 'Token próximo a vencer', body: 'El link de tracking de OP-8493 vence en 2h', time: 'Hace 45 min', read: false },
    { id: 'n3', icon: 'success', title: 'Deal cerrado', body: 'Campaña Navideña 2026 marcada como ganada', time: 'Hace 2h', read: true },
];

const NOTIFICATION_ICONS = {
    info: Info,
    warning: AlertTriangle,
    success: Check,
    truck: Truck,
} as const;

const NOTIFICATION_COLORS = {
    info: 'text-blue-500 bg-blue-50',
    warning: 'text-amber-500 bg-amber-50',
    success: 'text-emerald-500 bg-emerald-50',
    truck: 'text-indigo-500 bg-indigo-50',
} as const;

export const Topbar = () => {
    const { pathname } = useLocation();
    const navigate = useNavigate();
    const title = ROUTE_TITLES[pathname] || 'ROTERO ERP';
    const { context, getRole, logout, activeTenant } = useAuthStore();
    const role = getRole();
    const { isDark, toggle: toggleTheme } = useTheme();
    const [showProfileMenu, setShowProfileMenu] = useState(false);
    const [showNotifications, setShowNotifications] = useState(false);
    const [notifications, setNotifications] = useState<AppNotification[]>(INITIAL_NOTIFICATIONS);
    const [searchQuery, setSearchQuery] = useState('');
    const menuRef = useRef<HTMLDivElement>(null);
    const notifRef = useRef<HTMLDivElement>(null);
    const searchRef = useRef<HTMLInputElement>(null);

    const unreadCount = notifications.filter(n => !n.read).length;

    const activeMembership = context?.memberships.find(m => m.tenant_id === activeTenant);
    const tenantName = activeMembership?.tenant_name || 'Sin Tenant';
    const userName = context?.email?.split('@')[0] || 'Usuario';
    const userInitials = userName.substring(0, 2).toUpperCase();

    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
                setShowProfileMenu(false);
            }
            if (notifRef.current && !notifRef.current.contains(event.target as Node)) {
                setShowNotifications(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    // Cmd+K / Ctrl+K to focus search
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
                e.preventDefault();
                searchRef.current?.focus();
            }
            if (e.key === 'Escape') {
                searchRef.current?.blur();
                setShowNotifications(false);
                setShowProfileMenu(false);
            }
        };
        document.addEventListener('keydown', handleKeyDown);
        return () => document.removeEventListener('keydown', handleKeyDown);
    }, []);

    const markAllRead = useCallback(() => {
        setNotifications(prev => prev.map(n => ({ ...n, read: true })));
    }, []);

    const dismissNotification = useCallback((id: string) => {
        setNotifications(prev => prev.filter(n => n.id !== id));
    }, []);

    const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Enter' && searchQuery.trim()) {
            // Navigate to operations with search query
            navigate(`/operations?q=${encodeURIComponent(searchQuery.trim())}`);
            setSearchQuery('');
            searchRef.current?.blur();
        }
    };

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
                        ref={searchRef}
                        type="text"
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        onKeyDown={handleSearchKeyDown}
                        placeholder="Buscar PO, Tracking, Pedimento..."
                        className="w-full pl-9 pr-16 py-2 bg-surface border border-tech-border rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                    <kbd className="absolute right-3 top-1/2 -translate-y-1/2 text-[10px] font-bold text-slate-300 bg-slate-100 border border-slate-200 px-1.5 py-0.5 rounded">⌘K</kbd>
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
                <div className="relative" ref={notifRef}>
                    <button
                        onClick={() => { setShowNotifications(!showNotifications); setShowProfileMenu(false); }}
                        className="relative p-2 text-slate-400 hover:text-primary hover:bg-primary-50 rounded-xl transition-all"
                    >
                        <Bell size={19} strokeWidth={1.8} />
                        {unreadCount > 0 && (
                            <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-accent-red rounded-full ring-2 ring-white" />
                        )}
                    </button>

                    {showNotifications && (
                        <div className="absolute right-0 top-full mt-2 w-80 bg-white rounded-xl shadow-2xl border border-slate-100 overflow-hidden animate-fade-in origin-top-right z-50">
                            <div className="flex items-center justify-between px-4 py-3 border-b border-slate-100">
                                <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Notificaciones</h3>
                                {unreadCount > 0 && (
                                    <button
                                        onClick={markAllRead}
                                        className="text-[10px] font-bold text-primary hover:text-primary/80 transition-colors uppercase tracking-wider"
                                    >
                                        Marcar leídas
                                    </button>
                                )}
                            </div>
                            <div className="max-h-72 overflow-y-auto">
                                {notifications.length === 0 ? (
                                    <div className="px-4 py-8 text-center">
                                        <Bell size={24} className="mx-auto text-slate-200 mb-2" />
                                        <p className="text-xs font-medium text-slate-400">Sin notificaciones</p>
                                    </div>
                                ) : (
                                    notifications.map(n => {
                                        const IconCmp = NOTIFICATION_ICONS[n.icon];
                                        const colorClass = NOTIFICATION_COLORS[n.icon];
                                        return (
                                            <div
                                                key={n.id}
                                                className={`flex items-start gap-3 px-4 py-3 border-b border-slate-50 last:border-0 hover:bg-slate-50/50 transition-colors group ${!n.read ? 'bg-blue-50/30' : ''}`}
                                            >
                                                <div className={`p-1.5 rounded-lg shrink-0 mt-0.5 ${colorClass}`}>
                                                    <IconCmp size={14} strokeWidth={2.5} />
                                                </div>
                                                <div className="flex-1 min-w-0">
                                                    <p className={`text-xs font-bold truncate ${!n.read ? 'text-slate-800' : 'text-slate-500'}`}>{n.title}</p>
                                                    <p className="text-[11px] text-slate-400 font-medium truncate">{n.body}</p>
                                                    <p className="text-[10px] text-slate-300 font-medium mt-1">{n.time}</p>
                                                </div>
                                                <button
                                                    onClick={(e) => { e.stopPropagation(); dismissNotification(n.id); }}
                                                    className="p-1 text-slate-300 hover:text-red-400 rounded opacity-0 group-hover:opacity-100 transition-all shrink-0"
                                                >
                                                    <X size={12} />
                                                </button>
                                            </div>
                                        );
                                    })
                                )}
                            </div>
                        </div>
                    )}
                </div>

                {/* Dark mode toggle */}
                <button
                    onClick={toggleTheme}
                    className="p-2 text-slate-400 hover:text-primary hover:bg-primary-50 rounded-xl transition-all"
                    aria-label={isDark ? 'Activar modo claro' : 'Activar modo oscuro'}
                    title={isDark ? 'Modo claro' : 'Modo oscuro'}
                >
                    {isDark ? <Sun size={19} strokeWidth={1.8} /> : <Moon size={19} strokeWidth={1.8} />}
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
                                onClick={() => { setShowProfileMenu(false); navigate('/security/settings'); }}
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
