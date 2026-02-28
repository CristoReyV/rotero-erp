import React, { useState, useEffect, useCallback } from 'react';
import { Download, Loader2, Search, Filter, X, ChevronDown, Eye } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getAuditLogs, exportAuditCSV } from '@/services/admin.service';
import type { AuditEvent, AuditFilters, AuditResponse } from '@/types/settings';
import { Badge } from '@/components/Badge';

const PAGE_SIZE = 50;

const SecurityAuditPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const [loading, setLoading] = useState(true);
    const [auditData, setAuditData] = useState<AuditResponse>({ items: [], total: 0, distinct_entities: [], distinct_actions: [] });
    const [searchTerm, setSearchTerm] = useState('');
    const [offset, setOffset] = useState(0);

    // Filters
    const [showFilters, setShowFilters] = useState(false);
    const [filters, setFilters] = useState<AuditFilters>({});
    const [pendingFilters, setPendingFilters] = useState<AuditFilters>({});

    // JSON Detail Modal
    const [selectedLog, setSelectedLog] = useState<AuditEvent | null>(null);

    const fetchData = useCallback(async (reset = false) => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const newOffset = reset ? 0 : offset;
            const result = await getAuditLogs(activeTenant, PAGE_SIZE, newOffset, filters);
            if (reset) {
                setAuditData(result);
                setOffset(0);
            } else if (newOffset > 0) {
                setAuditData(prev => ({
                    ...result,
                    items: [...prev.items, ...result.items],
                }));
            } else {
                setAuditData(result);
            }
        } catch (error) {
            console.error('Failed to load audit logs', error);
        } finally {
            setLoading(false);
        }
    }, [activeTenant, offset, filters]);

    useEffect(() => {
        fetchData(true);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant, filters]);

    const handleApplyFilters = () => {
        setFilters(pendingFilters);
        setOffset(0);
    };

    const handleClearFilters = () => {
        setPendingFilters({});
        setFilters({});
        setOffset(0);
    };

    const handleLoadMore = () => {
        const newOffset = offset + PAGE_SIZE;
        setOffset(newOffset);
        // Trigger fetch with new offset
        if (!activeTenant) return;
        setLoading(true);
        getAuditLogs(activeTenant, PAGE_SIZE, newOffset, filters).then(result => {
            setAuditData(prev => ({
                ...result,
                items: [...prev.items, ...result.items],
            }));
        }).catch(console.error).finally(() => setLoading(false));
    };

    const activeFilterCount = Object.values(filters).filter(Boolean).length;

    const filteredLogs = auditData.items.filter(log =>
        !searchTerm ||
        log.action.toLowerCase().includes(searchTerm.toLowerCase()) ||
        (log.actor_name && log.actor_name.toLowerCase().includes(searchTerm.toLowerCase())) ||
        log.entity_type.toLowerCase().includes(searchTerm.toLowerCase())
    );

    if (loading && auditData.items.length === 0) {
        return (
            <div className="flex flex-col items-center justify-center p-20 min-h-[50vh] text-slate-400 gap-4">
                <Loader2 className="animate-spin" size={32} />
                <p className="text-sm">Cargando Auditoría...</p>
            </div>
        );
    }

    return (
        <div className="space-y-4 animate-in fade-in duration-500">
            {/* Summary Stats */}
            <div className="flex items-center gap-3 text-[11px]">
                <Badge variant="default">{auditData.total} eventos</Badge>
                <Badge variant="success">{auditData.distinct_entities.length} tipos</Badge>
                <Badge variant="warning">{auditData.distinct_actions.length} acciones</Badge>
            </div>

            {/* Header / Actions */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
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
                    <button
                        onClick={() => setShowFilters(!showFilters)}
                        className={`flex items-center gap-2 px-3 py-2 border rounded-xl text-xs font-semibold transition-all ${activeFilterCount > 0
                                ? 'bg-primary/10 border-primary/30 text-primary'
                                : 'bg-surface-card border-tech-border/60 text-slate-600 hover:text-primary'
                            }`}
                    >
                        <Filter size={14} />
                        Filtros{activeFilterCount > 0 && ` (${activeFilterCount})`}
                        <ChevronDown size={12} className={`transition-transform ${showFilters ? 'rotate-180' : ''}`} />
                    </button>
                    <button
                        onClick={() => exportAuditCSV(filteredLogs)}
                        disabled={filteredLogs.length === 0}
                        className="flex items-center gap-2 px-4 py-2 gradient-primary text-white rounded-xl text-xs font-semibold shadow-md shadow-primary/20 hover:shadow-lg transition-all disabled:opacity-40"
                    >
                        <Download size={14} /> Exportar CSV
                    </button>
                </div>
            </div>

            {/* Advanced Filters Panel */}
            {showFilters && (
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 p-4 space-y-3 animate-in slide-in-from-top-2 duration-200">
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                        <div>
                            <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1 block">Tipo de entidad</label>
                            <select
                                value={pendingFilters.entity_type || ''}
                                onChange={(e) => setPendingFilters(f => ({ ...f, entity_type: e.target.value || undefined }))}
                                className="w-full px-3 py-2 bg-surface border border-tech-border/60 rounded-lg text-sm focus:ring-2 focus:ring-primary/15 focus:outline-none"
                            >
                                <option value="">Todos</option>
                                {auditData.distinct_entities.map(e => (
                                    <option key={e} value={e}>{e}</option>
                                ))}
                            </select>
                        </div>
                        <div>
                            <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1 block">Acción</label>
                            <select
                                value={pendingFilters.action || ''}
                                onChange={(e) => setPendingFilters(f => ({ ...f, action: e.target.value || undefined }))}
                                className="w-full px-3 py-2 bg-surface border border-tech-border/60 rounded-lg text-sm focus:ring-2 focus:ring-primary/15 focus:outline-none"
                            >
                                <option value="">Todas</option>
                                {auditData.distinct_actions.map(a => (
                                    <option key={a} value={a}>{a}</option>
                                ))}
                            </select>
                        </div>
                        <div>
                            <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1 block">Desde</label>
                            <input
                                type="datetime-local"
                                value={pendingFilters.start ? pendingFilters.start.slice(0, 16) : ''}
                                onChange={(e) => setPendingFilters(f => ({ ...f, start: e.target.value ? new Date(e.target.value).toISOString() : undefined }))}
                                className="w-full px-3 py-2 bg-surface border border-tech-border/60 rounded-lg text-sm focus:ring-2 focus:ring-primary/15 focus:outline-none"
                            />
                        </div>
                        <div>
                            <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-1 block">Hasta</label>
                            <input
                                type="datetime-local"
                                value={pendingFilters.end ? pendingFilters.end.slice(0, 16) : ''}
                                onChange={(e) => setPendingFilters(f => ({ ...f, end: e.target.value ? new Date(e.target.value).toISOString() : undefined }))}
                                className="w-full px-3 py-2 bg-surface border border-tech-border/60 rounded-lg text-sm focus:ring-2 focus:ring-primary/15 focus:outline-none"
                            />
                        </div>
                    </div>
                    <div className="flex items-center gap-2 pt-1">
                        <button
                            onClick={handleApplyFilters}
                            className="px-4 py-1.5 gradient-primary text-white rounded-lg text-xs font-bold shadow-sm"
                        >
                            Aplicar
                        </button>
                        <button
                            onClick={handleClearFilters}
                            className="px-4 py-1.5 border border-tech-border/60 text-slate-500 rounded-lg text-xs font-bold hover:bg-slate-50 transition-colors"
                        >
                            Limpiar
                        </button>
                    </div>
                </div>
            )}

            {/* Logs Table */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden shadow-sm">
                <div className="px-5 py-4 border-b border-tech-border/40 bg-surface/50 flex justify-between items-center">
                    <h3 className="text-xs font-bold text-slate-400 uppercase tracking-widest">Registro de Eventos</h3>
                    <span className="text-[10px] bg-primary/10 text-primary px-2 py-0.5 rounded-full font-bold uppercase tracking-wider">
                        {filteredLogs.length} / {auditData.total}
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
                                                    log.entity_type === 'operation' ? 'bg-blue-50 text-blue-600' :
                                                        log.entity_type === 'tracking_token' ? 'bg-emerald-50 text-emerald-600' :
                                                            'bg-slate-50 text-slate-600'}`}>
                                            {log.entity_type.toUpperCase()}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        <button
                                            onClick={() => setSelectedLog(log)}
                                            className="flex items-center gap-1 text-[11px] font-bold text-primary hover:underline ml-auto"
                                        >
                                            <Eye size={12} /> Ver JSON
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>

                {/* Pagination */}
                {auditData.items.length < auditData.total && (
                    <div className="px-5 py-3 border-t border-tech-border/40 flex justify-center">
                        <button
                            onClick={handleLoadMore}
                            disabled={loading}
                            className="px-6 py-2 text-xs font-bold text-primary border border-primary/30 rounded-xl hover:bg-primary/5 transition-all disabled:opacity-40"
                        >
                            {loading ? (
                                <span className="flex items-center gap-2"><Loader2 size={12} className="animate-spin" /> Cargando...</span>
                            ) : (
                                `Cargar más (${auditData.items.length} de ${auditData.total})`
                            )}
                        </button>
                    </div>
                )}
            </div>

            {/* JSON Detail Modal */}
            {selectedLog && (
                <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setSelectedLog(null)}>
                    <div
                        className="bg-surface-card rounded-2xl border border-tech-border/60 shadow-2xl max-w-lg w-full max-h-[80vh] overflow-hidden animate-in zoom-in-95 duration-200"
                        onClick={(e) => e.stopPropagation()}
                    >
                        <div className="px-5 py-4 border-b border-tech-border/40 flex items-center justify-between">
                            <div>
                                <h3 className="text-sm font-bold text-slate-700">Detalle del Evento</h3>
                                <p className="text-[10px] text-slate-400 mt-0.5">{selectedLog.id}</p>
                            </div>
                            <button onClick={() => setSelectedLog(null)} className="p-1 rounded-lg hover:bg-slate-100 transition-colors">
                                <X size={16} className="text-slate-400" />
                            </button>
                        </div>
                        <div className="p-5 space-y-3 overflow-y-auto max-h-[60vh]">
                            <div className="grid grid-cols-2 gap-3 text-[11px]">
                                <div>
                                    <span className="text-slate-400 font-bold uppercase tracking-wider">Acción</span>
                                    <p className="text-slate-700 font-semibold mt-0.5">{selectedLog.action}</p>
                                </div>
                                <div>
                                    <span className="text-slate-400 font-bold uppercase tracking-wider">Entidad</span>
                                    <p className="text-slate-700 font-semibold mt-0.5">{selectedLog.entity_type}</p>
                                </div>
                                <div>
                                    <span className="text-slate-400 font-bold uppercase tracking-wider">Actor</span>
                                    <p className="text-slate-700 font-semibold mt-0.5">{selectedLog.actor_name || selectedLog.actor_email || 'Sistema'}</p>
                                </div>
                                <div>
                                    <span className="text-slate-400 font-bold uppercase tracking-wider">Fecha</span>
                                    <p className="text-slate-700 font-semibold mt-0.5">
                                        {new Date(selectedLog.created_at).toLocaleString('es-MX')}
                                    </p>
                                </div>
                            </div>
                            {selectedLog.entity_id && (
                                <div className="text-[11px]">
                                    <span className="text-slate-400 font-bold uppercase tracking-wider">Entity ID</span>
                                    <p className="text-slate-600 font-mono mt-0.5 text-[10px] bg-slate-50 px-2 py-1 rounded-md">{selectedLog.entity_id}</p>
                                </div>
                            )}
                            <div className="text-[11px]">
                                <span className="text-slate-400 font-bold uppercase tracking-wider">Metadata (JSON)</span>
                                <pre className="mt-1 p-3 bg-slate-900 text-emerald-400 rounded-xl text-[10px] font-mono overflow-x-auto leading-relaxed whitespace-pre-wrap">
                                    {JSON.stringify(selectedLog.metadata, null, 2)}
                                </pre>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default SecurityAuditPage;
