import React, { useState, useEffect } from 'react';
import { Download, Loader2, Search, Filter } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getAuditLogs } from '@/services/admin.service';
import type { AuditEvent } from '@/types/settings';

const SecurityAuditPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const [loading, setLoading] = useState(true);
    const [auditLogs, setAuditLogs] = useState<AuditEvent[]>([]);
    const [searchTerm, setSearchTerm] = useState('');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const logs = await getAuditLogs(activeTenant, 50);
            setAuditLogs(logs);
        } catch (error) {
            console.error('Failed to load audit logs', error);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    const filteredLogs = auditLogs.filter(log =>
        log.action.toLowerCase().includes(searchTerm.toLowerCase()) ||
        (log.actor_name && log.actor_name.toLowerCase().includes(searchTerm.toLowerCase())) ||
        log.entity_type.toLowerCase().includes(searchTerm.toLowerCase())
    );

    if (loading && auditLogs.length === 0) {
        return (
            <div className="flex flex-col items-center justify-center p-20 min-h-[50vh] text-slate-400 gap-4">
                <Loader2 className="animate-spin" size={32} />
                <p className="text-sm">Cargando Auditoría...</p>
            </div>
        );
    }

    return (
        <div className="space-y-6 animate-in fade-in duration-500">
            {/* Header / Actions */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="relative max-w-md w-full">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        placeholder="Filtrar por acción, usuario o módulo..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-9 pr-4 py-2 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
                <div className="flex items-center gap-2">
                    <button className="flex items-center gap-2 px-3 py-2 bg-surface-card border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-600 hover:text-primary transition-all">
                        <Filter size={14} /> Filtros Avanzados
                    </button>
                    <button className="flex items-center gap-2 px-4 py-2 gradient-primary text-white rounded-xl text-xs font-semibold shadow-md shadow-primary/20 hover:shadow-lg transition-all">
                        <Download size={14} /> Exportar Log
                    </button>
                </div>
            </div>

            {/* Logs List */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden shadow-sm">
                <div className="px-5 py-4 border-b border-tech-border/40 bg-surface/50 flex justify-between items-center">
                    <h3 className="text-xs font-bold text-slate-400 uppercase tracking-widest">Registro de Eventos</h3>
                    <span className="text-[10px] bg-primary/10 text-primary px-2 py-0.5 rounded-full font-bold uppercase tracking-wider">
                        Real-time
                    </span>
                </div>
                <div className="overflow-x-auto">
                    <table className="w-full text-left text-sm">
                        <thead>
                            <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60 bg-surface/30">
                                <th className="px-6 py-3">Fecha y Hora</th>
                                <th className="px-6 py-3">Actor</th>
                                <th className="px-6 py-3">Acción</th>
                                <th className="px-6 py-3">Módulo / Entidad</th>
                                <th className="px-6 py-3 text-right">Detalles</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-tech-border/30">
                            {filteredLogs.length === 0 && (
                                <tr>
                                    <td colSpan={5} className="p-10 text-center text-slate-400 italic">No se han encontrado registros</td>
                                </tr>
                            )}
                            {filteredLogs.map((log) => (
                                <tr key={log.id} className="hover:bg-primary-50/20 transition-colors group">
                                    <td className="px-6 py-4 text-[11px] text-slate-500 font-medium">
                                        {new Date(log.created_at).toLocaleString('es-MX', {
                                            day: '2-digit', month: '2-digit', year: 'numeric',
                                            hour: '2-digit', minute: '2-digit', second: '2-digit'
                                        })}
                                    </td>
                                    <td className="px-6 py-4">
                                        <div className="flex items-center gap-2">
                                            <div className="w-6 h-6 rounded-md bg-slate-100 flex items-center justify-center text-[10px] font-bold text-slate-500">
                                                {(log.actor_name || log.actor_email || 'S').slice(0, 1).toUpperCase()}
                                            </div>
                                            <span className="text-[13px] font-semibold text-slate-700">{log.actor_name || log.actor_email || 'Sistema'}</span>
                                        </div>
                                    </td>
                                    <td className="px-6 py-4">
                                        <span className="text-[11px] font-bold text-slate-600 bg-slate-100 px-2 py-0.5 rounded-md uppercase tracking-tighter">
                                            {log.action}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4">
                                        <span className={`text-[11px] font-semibold px-2 py-0.5 rounded-md
                                            ${log.entity_type === 'invitation' ? 'bg-amber-50 text-amber-600' :
                                                log.entity_type === 'membership' ? 'bg-red-50 text-red-600' :
                                                    'bg-blue-50 text-blue-600'}`}>
                                            {log.entity_type.toUpperCase()}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        <button className="text-[11px] font-bold text-primary hover:underline">Ver JSON</button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
};

export default SecurityAuditPage;
