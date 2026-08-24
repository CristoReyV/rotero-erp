import React from 'react';
import { Outlet, Link, useLocation } from 'react-router-dom';
import { Users, Settings, Activity, Bot } from 'lucide-react';

const SecurityPage = () => {
    const { pathname } = useLocation();

    const tabs = [
        { id: 'users', label: 'Usuarios', icon: Users, path: '/security/users' },
        { id: 'audit', label: 'Auditoría', icon: Activity, path: '/security/audit' },
        { id: 'settings', label: 'Configuración', icon: Settings, path: '/security/settings' },
        { id: 'automations', label: 'Automatizaciones', icon: Bot, path: '/security/automations' },
    ];

    return (
        <div className="space-y-6">
            {/* Page Header */}
            <div>
                <h1 className="text-2xl font-bold text-slate-800">Administración</h1>
                <p className="text-sm text-slate-400 mt-0.5">Control de acceso, auditoría y parametrización del tenant</p>
            </div>

            {/* Navigation Tabs */}
            <div className="flex bg-surface-card rounded-2xl border border-tech-border/60 p-1 gap-1 w-full sm:w-fit shadow-sm overflow-x-auto no-scrollbar">
                {tabs.map((tab) => {
                    const Icon = tab.icon;
                    const isActive = pathname === tab.path || (tab.id === 'users' && pathname === '/security');
                    return (
                        <Link
                            key={tab.id}
                            to={tab.path}
                            className={`flex items-center gap-2 px-6 py-2.5 rounded-xl text-xs font-bold transition-all whitespace-nowrap
                                ${isActive
                                    ? 'bg-primary text-white shadow-md shadow-primary/20'
                                    : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}
                        >
                            <Icon size={16} strokeWidth={isActive ? 2.5 : 2} />
                            {tab.label}
                        </Link>
                    );
                })}
            </div>

            {/* Nested Page Content */}
            <div className="min-h-[400px]">
                <Outlet />
            </div>
        </div>
    );
};

export default SecurityPage;
