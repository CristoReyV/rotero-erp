import React, { useState, useEffect } from 'react';
import { Save, Globe, Palette, Clock, Bell, Loader2, CheckCircle2 } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getTenantSettings, updateTenantSettings } from '@/services/admin.service';
import type { TenantSettings } from '@/types/settings';

const SettingsPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const userRole = useAuthStore((s) => s.getRole());
    const isAdmin = userRole === 'admin';

    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [saved, setSaved] = useState(false);
    const [settings, setSettings] = useState<TenantSettings | null>(null);

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await getTenantSettings(activeTenant);
            setSettings(data);
        } catch (error) {
            console.error('Failed to load settings', error);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    const handleSave = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !isAdmin || !settings) return;

        setSaving(true);
        setSaved(false);
        try {
            await updateTenantSettings(activeTenant, settings);
            setSaved(true);
            setTimeout(() => setSaved(false), 3000);
        } catch (error) {
            alert('Error al guardar configuración');
        } finally {
            setSaving(false);
        }
    };

    if (loading && !settings) {
        return (
            <div className="flex flex-col items-center justify-center p-20 min-h-[50vh] text-slate-400 gap-4">
                <Loader2 className="animate-spin" size={32} />
                <p className="text-sm">Cargando Configuración...</p>
            </div>
        );
    }

    const s = settings!;

    return (
        <div className="max-w-4xl space-y-6 animate-in fade-in duration-500">
            <form onSubmit={handleSave} className="space-y-6">
                {/* Branding Section */}
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-tech-border/40 bg-surface/30 flex items-center gap-2">
                        <Palette size={16} className="text-primary" />
                        <h3 className="text-xs font-bold text-slate-700 uppercase tracking-widest">Identidad y Marca</h3>
                    </div>
                    <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-6">
                        <div className="space-y-2">
                            <label className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">Nombre de la Empresa</label>
                            <input
                                type="text"
                                value={s.brand_name}
                                disabled={!isAdmin}
                                onChange={e => setSettings({ ...s, brand_name: e.target.value })}
                                className="w-full px-4 py-2.5 bg-surface border border-tech-border/60 rounded-xl text-sm focus:ring-2 focus:ring-primary/10 focus:border-primary/40 outline-none transition-all disabled:bg-slate-50 disabled:text-slate-400"
                            />
                        </div>
                        <div className="space-y-2">
                            <label className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">Color Primario (Hex)</label>
                            <div className="flex gap-2">
                                <input
                                    type="text"
                                    value={s.primary_color}
                                    disabled={!isAdmin}
                                    onChange={e => setSettings({ ...s, primary_color: e.target.value })}
                                    className="flex-1 px-4 py-2.5 bg-surface border border-tech-border/60 rounded-xl text-sm font-mono focus:ring-2 focus:ring-primary/10 focus:border-primary/40 outline-none transition-all disabled:bg-slate-50"
                                />
                                <div className="w-10 h-10 rounded-xl border border-tech-border/60 shrink-0" style={{ backgroundColor: s.primary_color }} />
                            </div>
                        </div>
                        <div className="md:col-span-2 space-y-2">
                            <label className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">URL del Logo (Square/Landscape)</label>
                            <input
                                type="text"
                                value={s.logo_url || ''}
                                disabled={!isAdmin}
                                placeholder="https://ejemplo.com/logo.png"
                                onChange={e => setSettings({ ...s, logo_url: e.target.value })}
                                className="w-full px-4 py-2.5 bg-surface border border-tech-border/60 rounded-xl text-sm focus:ring-2 focus:ring-primary/10 focus:border-primary/40 outline-none transition-all disabled:bg-slate-50"
                            />
                        </div>
                    </div>
                </div>

                {/* Regional Section */}
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden shadow-sm">
                    <div className="px-6 py-4 border-b border-tech-border/40 bg-surface/30 flex items-center gap-2">
                        <Globe size={16} className="text-secondary" />
                        <h3 className="text-xs font-bold text-slate-700 uppercase tracking-widest">Localización y Operación</h3>
                    </div>
                    <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-6">
                        <div className="space-y-2">
                            <label className="text-[11px] font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                                <Clock size={12} /> Zona Horaria
                            </label>
                            <select
                                value={s.timezone}
                                disabled={!isAdmin}
                                onChange={e => setSettings({ ...s, timezone: e.target.value })}
                                className="w-full px-4 py-2.5 bg-surface border border-tech-border/60 rounded-xl text-sm focus:ring-2 focus:ring-primary/10 focus:border-primary/40 outline-none transition-all disabled:bg-slate-50"
                            >
                                <option value="America/Mexico_City">México Central (CDMX)</option>
                                <option value="America/Monterrey">Monterrey</option>
                                <option value="America/Tijuana">Tijuana / Pacífico</option>
                                <option value="UTC">Universal Time (UTC)</option>
                            </select>
                        </div>
                        <div className="space-y-2">
                            <label className="text-[11px] font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                                <Bell size={12} /> Notificaciones
                            </label>
                            <div className="flex items-center gap-3 py-2">
                                <button
                                    type="button"
                                    disabled={!isAdmin}
                                    onClick={() => setSettings({ ...s, notifications_enabled: !s.notifications_enabled })}
                                    className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${s.notifications_enabled ? 'bg-primary' : 'bg-slate-200'}`}
                                >
                                    <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${s.notifications_enabled ? 'translate-x-5' : 'translate-x-0'}`} />
                                </button>
                                <span className="text-xs text-slate-500 font-medium">{s.notifications_enabled ? 'Habilitadas' : 'Silenciadas'}</span>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Submit row */}
                {isAdmin && (
                    <div className="flex items-center justify-end gap-3 pt-2">
                        {saved && (
                            <span className="flex items-center gap-1.5 text-xs font-bold text-emerald-600 animate-in fade-in slide-in-from-right-4 transition-all">
                                <CheckCircle2 size={16} /> Configuración Guardada
                            </span>
                        )}
                        <button
                            type="submit"
                            disabled={saving}
                            className="flex items-center gap-2 px-6 py-2.5 gradient-primary text-white rounded-xl text-sm font-bold shadow-md shadow-primary/20 hover:shadow-lg transition-all disabled:opacity-50"
                        >
                            {saving ? <Loader2 size={18} className="animate-spin" /> : <Save size={18} />}
                            Guardar Cambios
                        </button>
                    </div>
                )}
            </form>
        </div>
    );
};

export default SettingsPage;
