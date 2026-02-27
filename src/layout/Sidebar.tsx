import { useState } from 'react';
import { PanelLeftClose, PanelLeftOpen, HelpCircle, LogOut } from 'lucide-react';
import { NAV_ITEMS } from '@/constants/nav';
import { SidebarItem } from './SidebarItem';

export const Sidebar = () => {
    const [isOpen, setIsOpen] = useState(true);

    return (
        <aside
            className={`bg-sidebar transition-all duration-300 flex flex-col shrink-0 z-30 ${isOpen ? 'w-[260px]' : 'w-[72px]'}`}
        >
            {/* Logo */}
            <div className="px-5 py-5 flex items-center gap-3">
                <div className="w-9 h-9 gradient-accent rounded-xl flex items-center justify-center text-white font-black text-lg shadow-lg shadow-accent-red/25 shrink-0">
                    R
                </div>
                {isOpen && (
                    <div className="overflow-hidden whitespace-nowrap">
                        <h1 className="text-white font-extrabold text-base tracking-tight">ROTERO ERP</h1>
                        <p className="text-[9px] text-white/40 font-semibold uppercase tracking-[0.2em] mt-0.5">Beta interna v1.0</p>
                    </div>
                )}
            </div>

            {/* Divider */}
            <div className="mx-5 h-px bg-white/8 mb-2" />

            {/* Nav */}
            <nav className="flex-1 py-1 space-y-0.5 overflow-y-auto no-scrollbar">
                {NAV_ITEMS.map((item) => (
                    <SidebarItem
                        key={item.path}
                        icon={item.icon}
                        label={item.label}
                        to={item.path}
                        collapsed={!isOpen}
                    />
                ))}
            </nav>

            {/* Bottom section */}
            <div className="mx-3 mb-2 space-y-0.5">
                <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[13px] font-medium text-slate-500 hover:bg-white/5 hover:text-slate-300 transition-all">
                    <div className="flex items-center justify-center w-8 h-8 rounded-lg">
                        <HelpCircle size={18} strokeWidth={1.8} />
                    </div>
                    {isOpen && <span>Ayuda</span>}
                </button>
            </div>

            <div className="mx-5 h-px bg-white/8" />

            {/* Collapse toggle */}
            <div className="p-3 flex items-center justify-center">
                <button
                    onClick={() => setIsOpen(!isOpen)}
                    className="p-2 text-slate-500 hover:text-white hover:bg-white/8 rounded-lg transition-all"
                    aria-label={isOpen ? 'Colapsar menú' : 'Expandir menú'}
                >
                    {isOpen ? <PanelLeftClose size={18} /> : <PanelLeftOpen size={18} />}
                </button>
            </div>
        </aside>
    );
};
