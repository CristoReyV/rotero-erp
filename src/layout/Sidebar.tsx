import { useState } from 'react';
import { PanelLeftClose, PanelLeftOpen, HelpCircle, LogOut, X, BookOpen, Keyboard, Mail, ExternalLink } from 'lucide-react';
import { NAV_ITEMS } from '@/constants/nav';
import { SidebarItem } from './SidebarItem';

export const Sidebar = () => {
    const [isOpen, setIsOpen] = useState(true);
    const [showHelp, setShowHelp] = useState(false);

    return (
        <>
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
                    <button
                        onClick={() => setShowHelp(true)}
                        className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[13px] font-medium text-slate-500 hover:bg-white/5 hover:text-slate-300 transition-all"
                    >
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

            {/* Help Modal */}
            {showHelp && (
                <div
                    className="fixed inset-0 z-[100] flex items-center justify-center bg-slate-900/40 backdrop-blur-sm p-6"
                    onClick={() => setShowHelp(false)}
                >
                    <div
                        className="bg-white rounded-2xl shadow-2xl w-full max-w-md animate-fade-in"
                        onClick={(e) => e.stopPropagation()}
                    >
                        {/* Header */}
                        <div className="flex items-center justify-between px-6 pt-6 pb-4 border-b border-slate-100">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 gradient-accent rounded-xl flex items-center justify-center text-white font-black text-lg shadow-md">
                                    R
                                </div>
                                <div>
                                    <h2 className="text-base font-bold text-slate-800">Centro de Ayuda</h2>
                                    <p className="text-[11px] text-slate-400 font-medium">ROTERO ERP · Beta interna v1.0</p>
                                </div>
                            </div>
                            <button
                                onClick={() => setShowHelp(false)}
                                className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                            >
                                <X size={18} />
                            </button>
                        </div>

                        {/* Content */}
                        <div className="p-6 space-y-4">
                            {/* Quick links */}
                            <div>
                                <h3 className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-3">Recursos</h3>
                                <div className="space-y-2">
                                    <a
                                        href="/docs/beta_guide/GUIA_DE_USO.md"
                                        target="_blank"
                                        rel="noreferrer"
                                        className="flex items-center gap-3 p-3 rounded-xl border border-slate-100 hover:border-primary/20 hover:bg-primary/[0.02] transition-all group"
                                    >
                                        <div className="p-2 bg-blue-50 text-blue-500 rounded-lg group-hover:bg-blue-100 transition-colors">
                                            <BookOpen size={16} strokeWidth={2} />
                                        </div>
                                        <div className="flex-1">
                                            <p className="text-sm font-bold text-slate-700">Guía de Uso</p>
                                            <p className="text-[11px] text-slate-400 font-medium">Manual completo del ERP</p>
                                        </div>
                                        <ExternalLink size={14} className="text-slate-300" />
                                    </a>
                                </div>
                            </div>

                            {/* Keyboard shortcuts */}
                            <div>
                                <h3 className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-3">Atajos de Teclado</h3>
                                <div className="bg-slate-50 rounded-xl p-4 space-y-2.5">
                                    <div className="flex items-center justify-between">
                                        <span className="text-xs font-medium text-slate-600">Buscar</span>
                                        <div className="flex gap-1">
                                            <kbd className="px-1.5 py-0.5 text-[10px] font-bold text-slate-400 bg-white border border-slate-200 rounded shadow-sm">⌘</kbd>
                                            <kbd className="px-1.5 py-0.5 text-[10px] font-bold text-slate-400 bg-white border border-slate-200 rounded shadow-sm">K</kbd>
                                        </div>
                                    </div>
                                    <div className="flex items-center justify-between">
                                        <span className="text-xs font-medium text-slate-600">Cerrar panel</span>
                                        <kbd className="px-1.5 py-0.5 text-[10px] font-bold text-slate-400 bg-white border border-slate-200 rounded shadow-sm">Esc</kbd>
                                    </div>
                                </div>
                            </div>

                            {/* Support */}
                            <div>
                                <h3 className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-3">Soporte</h3>
                                <div className="flex items-center gap-3 p-3 rounded-xl border border-slate-100 bg-slate-50/50">
                                    <div className="p-2 bg-emerald-50 text-emerald-500 rounded-lg">
                                        <Mail size={16} strokeWidth={2} />
                                    </div>
                                    <div>
                                        <p className="text-sm font-bold text-slate-700">soporte@rotero.mx</p>
                                        <p className="text-[11px] text-slate-400 font-medium">Lun-Vie 9:00 – 18:00 CST</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        {/* Footer */}
                        <div className="px-6 py-4 border-t border-slate-100 bg-slate-50/50 rounded-b-2xl">
                            <p className="text-[10px] text-slate-400 font-medium text-center">
                                © 2026 WLS Rotero · Todos los derechos reservados
                            </p>
                        </div>
                    </div>
                </div>
            )}
        </>
    );
};
