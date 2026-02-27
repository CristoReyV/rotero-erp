import React, { useState, useEffect, useMemo } from 'react';
import { Plus, Search, History, ShieldCheck, AlertCircle, Truck, FileText, XCircle, CheckCircle, Loader2, Info } from 'lucide-react';
import { KPICard } from '@/components/KPICard';
import { Badge } from '@/components/Badge';
import { useAuthStore } from '@/store/authStore';
import { listCFDIs, createCFDI, getCFDIDetail, updateCFDI, upsertCartaPorte } from '@/services/billing.service';
import type { CFDIListRow, CFDIWithDetail } from '@/types/billing';
import type { BadgeVariant } from '@/types/common';
import { motion } from 'motion/react';

const getStatusVariant = (status: string): BadgeVariant => {
    switch (status) {
        case 'Timbrado': return 'success';
        case 'Pendiente': return 'warning';
        case 'Error': return 'danger';
        case 'Cancelado': return 'default';
        default: return 'default';
    }
};

const getStatusIcon = (status: string) => {
    switch (status) {
        case 'Timbrado': return <CheckCircle size={14} className="text-emerald-500" />;
        case 'Pendiente': return <History size={14} className="text-amber-500" />;
        case 'Error': return <XCircle size={14} className="text-red-500" />;
        case 'Cancelado': return <XCircle size={14} className="text-slate-500" />;
        default: return null;
    }
};

const BillingPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [cfdis, setCfdis] = useState<CFDIListRow[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [searchRfc, setSearchRfc] = useState('');
    const [activeTab, setActiveTab] = useState('Todos');

    const [showNewModal, setShowNewModal] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [newClientRfc, setNewClientRfc] = useState('');
    const [newTotal, setNewTotal] = useState('');
    const [newStatus, setNewStatus] = useState<'timbrado' | 'draft'>('timbrado');

    const [selectedCfdiId, setSelectedCfdiId] = useState<string | null>(null);
    const [selectedDetail, setSelectedDetail] = useState<CFDIWithDetail | null>(null);
    const [loadingDetail, setLoadingDetail] = useState(false);

    // Carta Porte Upsert Form
    const [cpOrigin, setCpOrigin] = useState('');
    const [cpDest, setCpDest] = useState('');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await listCFDIs(activeTenant, {
                rfc: searchRfc || undefined,
                searchText: searchTerm || undefined
            });
            setCfdis(data);
        } catch (err) {
            console.error('Failed to load CFDIs:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant, searchRfc, searchTerm]);

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !newClientRfc) return;
        setIsSubmitting(true);
        try {
            await createCFDI(activeTenant, {
                rfc_receptor: newClientRfc,
                rfc_emisor: 'DEF000000000', // Mock sender for now
                total: newTotal ? Number(newTotal) : 0,
                status: newStatus
            });
            setShowNewModal(false);
            setNewClientRfc('');
            setNewTotal('');
            setNewStatus('timbrado');
            await fetchData();
        } catch (err) {
            console.error('Failed to create CFDI:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleRowClick = async (cfdi: CFDIListRow) => {
        if (!cfdi.db_id) return; // Ignore if mock lacking ID mapping
        setSelectedCfdiId(cfdi.db_id);
        setLoadingDetail(true);
        try {
            const data = await getCFDIDetail(cfdi.db_id);
            setSelectedDetail(data);
            setCpOrigin(data.carta_porte?.origin || '');
            setCpDest(data.carta_porte?.destination || '');
        } catch (err) {
            console.error('Failed to load CFDI detail:', err);
        } finally {
            setLoadingDetail(false);
        }
    };

    const handleUpdateStatus = async (newStat: 'timbrado' | 'cancelado' | 'error') => {
        if (!selectedCfdiId) return;
        setIsSubmitting(true);
        try {
            await updateCFDI(selectedCfdiId, { status: newStat });
            // refresh
            const data = await getCFDIDetail(selectedCfdiId);
            setSelectedDetail(data);
            await fetchData();
        } catch (err) {
            console.error('Failed to update status:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleUpsertCp = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!selectedCfdiId) return;
        setIsSubmitting(true);
        try {
            await upsertCartaPorte(selectedCfdiId, {
                origin: cpOrigin,
                destination: cpDest,
                trans_type: 'Autotransporte Federal'
            });
            // refresh
            const data = await getCFDIDetail(selectedCfdiId);
            setSelectedDetail(data);
            await fetchData();
        } catch (err) {
            console.error('Failed to update CP:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const filteredCfdis = useMemo(() => {
        if (activeTab === 'Todos') return cfdis;
        return cfdis.filter(c => c.status === activeTab);
    }, [cfdis, activeTab]);

    return (
        <div className="space-y-6 relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Facturación & CFDI 4.0</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Salud fiscal y timbrado electrónico ({filteredCfdis.length} visibles)</p>
                </div>
                <div className="flex items-center gap-2">
                    <div className="flex items-center gap-1.5 px-3 py-1.5 bg-emerald-50 border border-emerald-200/60 rounded-full">
                        <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse-dot" />
                        <span className="text-[10px] font-bold text-emerald-700 uppercase tracking-wider">PAC Online</span>
                    </div>
                    {!isViewer && (
                        <button onClick={() => setShowNewModal(true)} className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all">
                            <Plus size={14} /> Nuevo CFDI
                        </button>
                    )}
                </div>
            </div>

            {/* Fiscal health cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <KPICard title="Folios Restantes" value="240" icon={FileText} className="animate-fade-in animate-fade-in-delay-1" />
                <KPICard title="Timbrados" value={String(cfdis.filter(c => c.status === 'Timbrado').length)} change="ok" trend="up" icon={CheckCircle} className="animate-fade-in animate-fade-in-delay-2" />
                <KPICard title="Pendientes" value={String(cfdis.filter(c => c.status === 'Pendiente' || c.status === 'Borrador').length)} icon={History} className="animate-fade-in animate-fade-in-delay-3" />
                <KPICard title="Errores / Canc." value={String(cfdis.filter(c => c.status === 'Error' || c.status === 'Cancelado').length)} icon={AlertCircle} className="animate-fade-in animate-fade-in-delay-4" />
            </div>

            {/* Quick actions (Visual placeholders only, not implemented complex flows yet except for top line) */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                {[
                    { icon: Plus, label: 'Nuevo CFDI 4.0', desc: 'Generador de facturas', accent: true, onClick: !isViewer ? () => setShowNewModal(true) : undefined },
                    { icon: Truck, label: 'Carta Porte', desc: 'Complemento logístico', accent: false },
                    { icon: ShieldCheck, label: 'Validar RFC', desc: 'Verificación SAT', accent: false },
                    { icon: XCircle, label: 'Cancelar UUID', desc: 'Proceso de cancelación', accent: false },
                ].map((action, i) => (
                    <button key={i} onClick={action.onClick} className={`p-4 rounded-2xl border text-left transition-all duration-200 group hover:scale-[1.02]
          ${action.accent
                            ? 'gradient-primary text-white border-transparent shadow-md shadow-primary/15'
                            : 'bg-surface-card border-tech-border/60 hover:border-primary/30 hover:shadow-sm'}`}>
                        <action.icon size={20} className={`mb-2 ${action.accent ? 'text-white/80' : 'text-primary group-hover:text-primary-light'}`} strokeWidth={1.8} />
                        <p className={`text-sm font-bold ${action.accent ? 'text-white' : 'text-slate-700'}`}>{action.label}</p>
                        <p className={`text-[10px] mt-0.5 ${action.accent ? 'text-white/60' : 'text-slate-400'}`}>{action.desc}</p>
                    </button>
                ))}
            </div>

            {/* Search + Filter */}
            <div className="flex flex-wrap gap-3 items-center">
                <div className="relative flex-1 max-w-sm">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        value={searchRfc}
                        onChange={(e) => setSearchRfc(e.target.value)}
                        placeholder="ENTER RFC (E.G. XAXX010101000)"
                        className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 uppercase focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all font-mono"
                    />
                </div>
                <div className="relative flex-1 max-w-sm">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        placeholder="Buscar UUID o Serie/Folio..."
                        className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
                <div className="flex bg-surface-card rounded-xl border border-tech-border/60 p-0.5 gap-0.5">
                    {['Todos', 'Timbrado', 'Pendiente', 'Error', 'Borrador', 'Cancelado'].map((tab) => (
                        <button
                            key={tab}
                            onClick={() => setActiveTab(tab)}
                            className={`text-[11px] font-semibold px-3.5 py-1.5 rounded-lg transition-all 
              ${tab === activeTab ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}
                        >
                            {tab}
                        </button>
                    ))}
                </div>
            </div>

            {/* SAT History Table */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="p-5 flex justify-between items-center border-b border-tech-border/40">
                    <h3 className="font-bold text-slate-800">Historial SAT</h3>
                </div>
                <div className="divide-y divide-tech-border/40 min-h-[300px]">
                    {loading ? (
                        <div className="flex justify-center p-10"><Loader2 className="animate-spin text-slate-400" /></div>
                    ) : filteredCfdis.length === 0 ? (
                        <div className="p-10 text-center text-slate-400">Sin resultados</div>
                    ) : (
                        filteredCfdis.map((cfdi, i) => (
                            <div key={i} onClick={() => handleRowClick(cfdi)} className="flex items-center gap-4 px-5 py-4 hover:bg-primary-50/20 transition-colors cursor-pointer group">
                                <div className="shrink-0">
                                    {getStatusIcon(cfdi.status)}
                                </div>
                                <div className="flex-1 min-w-0">
                                    <div className="flex items-center gap-2">
                                        <p className="text-[13px] font-semibold text-slate-700">{cfdi.client}</p>
                                        <Badge variant={getStatusVariant(cfdi.status)}>{cfdi.status}</Badge>
                                    </div>
                                    <p className="text-[10px] text-slate-400 mt-0.5 font-mono">
                                        UUID: {cfdi.uuid} · Ref: {cfdi.folio}
                                    </p>
                                </div>
                                <div className="text-right shrink-0">
                                    <p className="text-[13px] font-bold text-slate-800">{cfdi.amount}</p>
                                    <p className={`text-[10px] font-semibold ${cfdi.cp === 'Validado' ? 'text-emerald-600' : cfdi.cp === 'Error RFC' ? 'text-red-500' : 'text-amber-500'}`}>
                                        {cfdi.cp}
                                    </p>
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </div>

            {/* Modals & Drawers */}

            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="bg-white rounded-2xl w-full max-w-sm shadow-xl overflow-hidden">
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Generar CFDI Draft</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">RFC Receptor *</label>
                                <input required autoFocus type="text" value={newClientRfc} onChange={(e) => setNewClientRfc(e.target.value.toUpperCase())}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 font-mono"
                                    placeholder="XAXX010101000" />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Total M.N.</label>
                                <input type="number" min="0" step="any" value={newTotal} onChange={(e) => setNewTotal(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="0.00" />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Estatus Inicial</label>
                                <select value={newStatus} onChange={(e) => setNewStatus(e.target.value as any)} className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20">
                                    <option value="draft">Borrador (Draft)</option>
                                    <option value="timbrado">Timbrado Completo (Auto UUID)</option>
                                </select>
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button type="button" onClick={() => setShowNewModal(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} Crear
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* CFDI Detail Drawer */}
            {selectedCfdiId && (
                <div className="fixed inset-y-0 right-0 z-50 flex items-center justify-center bg-slate-900/20 backdrop-blur-sm p-4 w-full">
                    <div className="flex-1 h-full w-full" onClick={() => setSelectedCfdiId(null)}></div>
                    <motion.div initial={{ opacity: 0, x: 100 }} animate={{ opacity: 1, x: 0 }} className="bg-white h-full shadow-2xl overflow-y-auto w-full max-w-md absolute right-0">
                        <div className="sticky top-0 bg-white/90 backdrop-blur-md px-6 py-4 border-b border-slate-100 flex items-center justify-between z-10">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800 font-mono">Detalle CFDI</h2>
                            </div>
                            <button onClick={() => setSelectedCfdiId(null)} className="text-slate-400 hover:text-slate-600 bg-slate-50 p-2 rounded-lg">✕</button>
                        </div>
                        <div className="p-6">
                            {loadingDetail || !selectedDetail ? (
                                <div className="flex justify-center p-10"><Loader2 className="animate-spin text-slate-400" /></div>
                            ) : (
                                <div className="space-y-6">

                                    <div className="bg-slate-50 p-4 rounded-xl border border-slate-100 flex flex-col gap-2">
                                        <div className="flex justify-between items-center text-sm">
                                            <span className="text-slate-500">Estado Local</span>
                                            <Badge variant={getStatusVariant(selectedDetail.status)}>{selectedDetail.status.toUpperCase()}</Badge>
                                        </div>
                                        <div className="flex justify-between items-center text-sm">
                                            <span className="text-slate-500">UUID SAT</span>
                                            <span className="font-semibold text-slate-700 font-mono text-xs">{selectedDetail.uuid}</span>
                                        </div>
                                        <div className="flex justify-between items-center text-sm">
                                            <span className="text-slate-500">Receptor</span>
                                            <span className="font-semibold text-slate-700">{selectedDetail.rfc_receptor}</span>
                                        </div>
                                        <div className="flex justify-between items-center text-sm border-t border-slate-200 pt-2 mt-1">
                                            <span className="text-slate-500">Total Pago</span>
                                            <span className="font-bold text-slate-800">${(selectedDetail.total || 0).toLocaleString()} {selectedDetail.currency}</span>
                                        </div>
                                    </div>

                                    {!isViewer && selectedDetail.status !== 'cancelado' && (
                                        <div className="flex flex-wrap gap-2 pt-2">
                                            {selectedDetail.status !== 'timbrado' && (
                                                <button disabled={isSubmitting} onClick={() => handleUpdateStatus('timbrado')} className="flex-1 py-2 bg-emerald-50 text-emerald-700 font-semibold rounded-lg text-sm border border-emerald-100 hover:bg-emerald-100 transition-colors text-center">
                                                    Marcar Timbrado
                                                </button>
                                            )}
                                            <button disabled={isSubmitting} onClick={() => handleUpdateStatus('cancelado')} className="flex-1 py-2 bg-red-50 text-red-700 font-semibold rounded-lg text-sm border border-red-100 hover:bg-red-100 transition-colors text-center">
                                                Cancelar CFDI
                                            </button>
                                        </div>
                                    )}

                                    <div className="pt-4 border-t border-slate-100">
                                        <h3 className="font-bold text-slate-800 flex items-center gap-2 mb-4">
                                            <Info size={16} className="text-primary" /> Carta Porte (Complemento)
                                        </h3>

                                        {selectedDetail.carta_porte ? (
                                            <div className="p-3 border border-slate-100 rounded-xl bg-slate-50/50 text-sm mb-4">
                                                <div className="flex justify-between border-b border-slate-200 pb-1 mb-1">
                                                    <span className="text-slate-500">Origen</span> <span className="font-semibold">{selectedDetail.carta_porte.origin || 'N/A'}</span>
                                                </div>
                                                <div className="flex justify-between">
                                                    <span className="text-slate-500">Destino</span> <span className="font-semibold">{selectedDetail.carta_porte.destination || 'N/A'}</span>
                                                </div>
                                            </div>
                                        ) : (
                                            <p className="text-sm text-slate-500 italic bg-white border border-dashed border-slate-200 p-4 rounded-xl text-center mb-4">
                                                Sin complemento de carta porte asociado.
                                            </p>
                                        )}

                                        {!isViewer && selectedDetail.status !== 'cancelado' && (
                                            <form onSubmit={handleUpsertCp} className="space-y-4">
                                                <div className="grid grid-cols-2 gap-2">
                                                    <input
                                                        type="text" value={cpOrigin} onChange={(e) => setCpOrigin(e.target.value)}
                                                        placeholder="Origen (C.P.)" className="px-3 py-2 border border-slate-200 rounded-lg text-sm w-full focus:outline-none focus:ring-2 focus:ring-primary/20"
                                                    />
                                                    <input
                                                        type="text" value={cpDest} onChange={(e) => setCpDest(e.target.value)}
                                                        placeholder="Destino (C.P.)" className="px-3 py-2 border border-slate-200 rounded-lg text-sm w-full focus:outline-none focus:ring-2 focus:ring-primary/20"
                                                    />
                                                </div>
                                                <button disabled={isSubmitting} type="submit" className="w-full py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold rounded-lg text-sm transition-colors flex items-center justify-center gap-2">
                                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} {selectedDetail.carta_porte ? 'Actualizar Carta Porte' : 'Vincular Carta Porte'}
                                                </button>
                                            </form>
                                        )}
                                    </div>

                                </div>
                            )}
                        </div>
                    </motion.div>
                </div>
            )}
        </div>
    );
};

export default BillingPage;
