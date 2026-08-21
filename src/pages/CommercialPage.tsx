import React, { useState, useEffect } from 'react';
import { Plus, Search, Filter, LayoutGrid, List, Map, Loader2, X, TrendingUp, Building2, FileText, Truck } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { moveDeal, createDeal, listPipelineDeals } from '@/services/commercial.service';
import type { PipelineColumn, LegacyDealItem, DealCreatePayload, DealStage } from '@/types/commercial';
import { motion } from 'motion/react';
import { DealDetailDrawer } from '@/components/commercial/DealDetailDrawer';
import { CustomerDirectory } from '@/components/commercial/CustomerDirectory';
import { ProviderDirectory } from '@/components/commercial/ProviderDirectory';
import { QuoteWorkspace } from '@/components/commercial/QuoteWorkspace';
import { PageHeader } from '@/components/PageHeader';
import { SavedViewsMenu } from '@/components/productivity/SavedViewsMenu';
import { useSearchParams } from 'react-router-dom';

const stageColors: Record<string, { dot: string; bg: string; border: string }> = {
    'Prospecto': { dot: 'bg-blue-500', bg: 'bg-blue-50', border: 'border-blue-200/40' },
    'Cotización': { dot: 'bg-amber-500', bg: 'bg-amber-50', border: 'border-amber-200/40' },
    'Negociación': { dot: 'bg-purple-500', bg: 'bg-purple-50', border: 'border-purple-200/40' },
    'Cierre': { dot: 'bg-emerald-500', bg: 'bg-emerald-50', border: 'border-emerald-200/40' },
};

const mapTitleToStage = (title: string): DealStage => {
    switch (title) {
        case 'Prospecto': return 'lead';
        case 'Cotización': return 'qualified';
        case 'Negociación': return 'proposal';
        case 'Cierre': return 'won';
        default: return 'lead';
    }
}

const PipelineWorkspace = ({ requestedDealId, onDealChange }: { requestedDealId: string | null; onDealChange: (dealId: string | null) => void }) => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [columns, setColumns] = useState<PipelineColumn[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [viewMode, setViewMode] = useState('board');
    const [showFilters, setShowFilters] = useState(false);
    const [filterPriority, setFilterPriority] = useState<string>('');
    const [pipelineError, setPipelineError] = useState<string | null>(null);

    const [draggedItem, setDraggedItem] = useState<{ id: string, sourceCol: string } | null>(null);
    const [loadingId, setLoadingId] = useState<string | null>(null);

    // Modal
    const [showNewModal, setShowNewModal] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [newTitle, setNewTitle] = useState('');
    const [newCompany, setNewCompany] = useState('');
    const [newValue, setNewValue] = useState('');

    // Detail Drawer
    const [selectedDealId, setSelectedDealId] = useState<string | null>(null);
    const [showDrawer, setShowDrawer] = useState(false);
    useEffect(() => { if (requestedDealId) { setSelectedDealId(requestedDealId); setShowDrawer(true); } }, [requestedDealId]);

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        setPipelineError(null);
        try {
            const data = await listPipelineDeals(activeTenant, {
                searchText: searchTerm || undefined,
                priority: filterPriority ? (filterPriority as any) : undefined
            });
            setColumns(data);
        } catch {
            setPipelineError('No fue posible cargar las oportunidades comerciales.');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant, filterPriority]); // Re-fetch when tenant or filter changes

    // Manual search trigger to prevent constant thrashing when typing
    const handleSearch = async (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Enter') {
            fetchData();
        }
    };

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !newTitle) return;
        setIsSubmitting(true);
        try {
            await createDeal(activeTenant, {
                title: newTitle,
                company: newCompany,
                value: Number(newValue) || 0,
                currency: 'MXN',
                stage: 'lead'
            });
            setShowNewModal(false);
            setNewTitle('');
            setNewCompany('');
            setNewValue('');
            await fetchData();
        } catch {
            setPipelineError('No fue posible crear la oportunidad.');
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleDragStart = (e: React.DragEvent, deal: LegacyDealItem, sourceColTitle: string) => {
        if (isViewer || !deal.db_id) {
            e.preventDefault();
            return;
        }
        setDraggedItem({ id: deal.db_id, sourceCol: sourceColTitle });
        e.dataTransfer.setData('dealId', deal.db_id);
    };

    const handleDragOver = (e: React.DragEvent) => {
        e.preventDefault();
    };

    const handleDrop = async (e: React.DragEvent, targetColTitle: string) => {
        e.preventDefault();
        if (isViewer || !draggedItem) return;
        const dealId = e.dataTransfer.getData('dealId');
        if (!dealId || draggedItem.sourceCol === targetColTitle) {
            setDraggedItem(null);
            return;
        }

        const newStage = mapTitleToStage(targetColTitle);
        setLoadingId(dealId);

        // Optimistic UI update
        const sourceColInd = columns.findIndex(c => c.title === draggedItem.sourceCol);
        const targetColInd = columns.findIndex(c => c.title === targetColTitle);

        let movedDeal: LegacyDealItem | undefined;
        let nextCols = [...columns];

        if (sourceColInd > -1 && targetColInd > -1) {
            const tempSourceColItems = [...nextCols[sourceColInd].deals];
            const tempTargetColItems = [...nextCols[targetColInd].deals];
            const idx = tempSourceColItems.findIndex(d => d.db_id === dealId);

            if (idx > -1) {
                movedDeal = tempSourceColItems.splice(idx, 1)[0];
                tempTargetColItems.push(movedDeal);

                nextCols[sourceColInd].deals = tempSourceColItems;
                nextCols[sourceColInd].count = tempSourceColItems.length;

                nextCols[targetColInd].deals = tempTargetColItems;
                nextCols[targetColInd].count = tempTargetColItems.length;
            }
            setColumns(nextCols); // apply optimistically
        }

        try {
            // DB Update
            await moveDeal(dealId, newStage);
        } catch {
            setPipelineError('No fue posible cambiar la etapa de la oportunidad.');
            await fetchData(); // rollback
        } finally {
            setLoadingId(null);
            setDraggedItem(null);
        }
    };

    return (
        <div className="space-y-6 relative">
            {pipelineError && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{pipelineError}</div>}
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Pipeline CRM</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Gestión comercial y seguimiento de oportunidades</p>
                </div>
                <div className="flex items-center gap-2">
                    <button onClick={() => setShowFilters(true)} className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Filter size={14} /> Filtros {filterPriority && <span className="w-2 h-2 rounded-full bg-primary ml-1"></span>}
                    </button>
                    {!isViewer && (
                        <button onClick={() => setShowNewModal(true)} className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all">
                            <Plus size={14} /> Nuevo Deal
                        </button>
                    )}
                </div>
            </div>

            {/* Search + view toggle */}
            <div className="flex flex-wrap gap-3 items-center">
                <div className="relative flex-1 max-w-md">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        onKeyDown={handleSearch}
                        placeholder="Buscar cliente, Título o Deal ID (Presiona Enter)..."
                        className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
                <div className="flex bg-surface-card rounded-xl border border-tech-border/60 p-0.5 gap-0.5">
                    <button onClick={() => setViewMode('board')} className={`text-[11px] font-semibold px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all
              ${viewMode === 'board' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <LayoutGrid size={12} /> Board
                    </button>
                    <button onClick={() => setViewMode('list')} className={`text-[11px] font-semibold px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all
              ${viewMode === 'list' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <List size={12} /> List
                    </button>
                    <button onClick={() => setViewMode('map')} className={`text-[11px] font-semibold px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all
              ${viewMode === 'map' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <Map size={12} /> Map
                    </button>
                </div>
            </div>

            {/* Kanban board */}
            {loading && columns.length === 0 ? (
                <div className="flex items-center justify-center p-20">
                    <Loader2 className="animate-spin text-slate-400" size={30} />
                </div>
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    {columns.map((col) => {
                        const colors = stageColors[col.title] || stageColors['Prospecto'];
                        const totalValue = col.deals.reduce((acc, d) => {
                            const num = parseFloat((String(d.value)).replace(/[$kM,]/g, ''));
                            return acc + ((String(d.value)).includes('M') ? num * 1000 : num);
                        }, 0);

                        return (
                            <div
                                key={col.title}
                                className="bg-surface rounded-2xl border border-tech-border/60 p-3 space-y-3 min-h-[400px]"
                                onDragOver={handleDragOver}
                                onDrop={(e) => handleDrop(e, col.title)}
                            >
                                {/* Column header */}
                                <div className="flex items-center justify-between px-1">
                                    <div className="flex items-center gap-2">
                                        <div className={`w-2.5 h-2.5 rounded-full ${colors.dot}`} />
                                        <span className="text-xs font-bold text-slate-700 uppercase tracking-wider">{col.title}</span>
                                        <span className="flex items-center justify-center w-5 h-5 rounded-full bg-slate-100 text-[10px] font-bold text-slate-500">
                                            {col.count}
                                        </span>
                                    </div>
                                    <span className="text-[10px] font-semibold text-slate-400">${totalValue.toFixed(1)}k</span>
                                </div>

                                {/* Deal cards */}
                                <div className="space-y-2.5">
                                    {col.deals.length === 0 ? (
                                        <div className="p-4 rounded-xl border border-dashed border-tech-border/40 text-center text-slate-400 text-xs py-10">
                                            Sin deals en esta fase
                                        </div>
                                    ) : col.deals.map((deal, i) => (
                                        <div
                                            key={deal.db_id || i}
                                            draggable={!isViewer && !!deal.db_id}
                                            onDragStart={(e) => handleDragStart(e, deal, col.title)}
                                            onClick={() => {
                                                if (deal.db_id) {
                                                    setSelectedDealId(deal.db_id);
                                                    setShowDrawer(true);
                                                    onDealChange(deal.db_id);
                                                }
                                            }}
                                            className={`bg-surface-card rounded-xl p-4 border hover:shadow-md hover:shadow-primary/5 hover:border-primary/20 transition-all duration-200 cursor-pointer active:cursor-grabbing group relative
                                            ${deal.db_id === loadingId ? 'opacity-50 pointer-events-none border-primary/40' : 'border-tech-border/40'}
                                            ${draggedItem?.id === deal.db_id ? 'opacity-30' : ''}`}
                                        >
                                            {deal.db_id === loadingId && (
                                                <div className="absolute inset-0 flex items-center justify-center z-10 bg-white/20 rounded-xl">
                                                    <Loader2 className="animate-spin text-primary" size={16} />
                                                </div>
                                            )}
                                            <div className="flex items-start mb-2">
                                                <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${colors.bg} ${colors.border} border text-slate-700`}>
                                                    {deal.prob}
                                                </span>
                                            </div>
                                            <p className="text-sm font-bold text-slate-800 mt-1">{deal.name}</p>
                                            <div className="flex items-center justify-between mt-3 pt-3 border-t border-tech-border/30">
                                                <span className="text-sm font-bold text-primary">{deal.value} MXN</span>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}

            {/* Modal: New Deal */}
            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="bg-white rounded-2xl w-full max-w-sm shadow-xl overflow-hidden">
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Nuevo Deal</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Título / Oportunidad *</label>
                                <input required autoFocus type="text" value={newTitle} onChange={(e) => setNewTitle(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="Ej. Distribuidor Nacional" />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Empresa Cliente</label>
                                <input type="text" value={newCompany} onChange={(e) => setNewCompany(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="Ej. Comercializadora Bajío" />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Valor Estimado</label>
                                <input type="number" min="0" step="any" value={newValue} onChange={(e) => setNewValue(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="0.00" />
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button type="button" onClick={() => setShowNewModal(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} Crear Deal
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Filter Drawer */}
            {showFilters && (
                <div className="fixed inset-y-0 right-0 z-50 flex items-center justify-center bg-slate-900/20 backdrop-blur-sm p-4 w-full">
                    <div className="flex-1 h-full w-full" onClick={() => setShowFilters(false)}></div>
                    <motion.div
                        initial={{ opacity: 0, x: 100 }}
                        animate={{ opacity: 1, x: 0 }}
                        className="bg-white h-full shadow-2xl overflow-y-auto w-full max-w-sm absolute right-0 flex flex-col"
                    >
                        <div className="sticky top-0 bg-white/90 backdrop-blur-md px-6 py-4 border-b border-slate-100 flex items-center justify-between z-10">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Filtros CRM</h2>
                                <p className="text-xs text-slate-500">Refina las oportunidades</p>
                            </div>
                            <button onClick={() => setShowFilters(false)} className="text-slate-400 hover:text-slate-600 bg-slate-50 p-2 rounded-lg">
                                <X size={16} />
                            </button>
                        </div>

                        <div className="p-6 space-y-6 flex-1">
                            {/* Priority Filter */}
                            <div className="space-y-3">
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider">Prioridad</label>
                                <div className="grid grid-cols-2 gap-2">
                                    <button
                                        onClick={() => setFilterPriority('')}
                                        className={`px-3 py-2 rounded-xl text-sm font-semibold transition-all border ${!filterPriority ? 'bg-primary text-white border-primary cursor-default shadow-md shadow-primary/20' : 'bg-surface text-slate-500 border-tech-border/60 hover:border-primary/40'}`}>
                                        Todas
                                    </button>
                                    <button
                                        onClick={() => setFilterPriority('high')}
                                        className={`px-3 py-2 rounded-xl text-sm font-semibold transition-all border ${filterPriority === 'high' ? 'bg-red-500 text-white border-red-500 cursor-default shadow-md shadow-red-500/20' : 'bg-surface text-slate-500 border-tech-border/60 hover:border-red-500/40'}`}>
                                        Alta
                                    </button>
                                    <button
                                        onClick={() => setFilterPriority('medium')}
                                        className={`px-3 py-2 rounded-xl text-sm font-semibold transition-all border ${filterPriority === 'medium' ? 'bg-amber-500 text-white border-amber-500 cursor-default shadow-md shadow-amber-500/20' : 'bg-surface text-slate-500 border-tech-border/60 hover:border-amber-500/40'}`}>
                                        Media
                                    </button>
                                    <button
                                        onClick={() => setFilterPriority('low')}
                                        className={`px-3 py-2 rounded-xl text-sm font-semibold transition-all border ${filterPriority === 'low' ? 'bg-blue-500 text-white border-blue-500 cursor-default shadow-md shadow-blue-500/20' : 'bg-surface text-slate-500 border-tech-border/60 hover:border-blue-500/40'}`}>
                                        Baja
                                    </button>
                                </div>
                            </div>
                        </div>

                        <div className="p-6 border-t border-slate-100 bg-slate-50 flex items-center justify-between">
                            <button
                                onClick={() => { setFilterPriority(''); }}
                                className="text-sm font-bold text-slate-500 hover:text-slate-700 transition-colors"
                            >
                                Limpiar filtros
                            </button>
                            <button
                                onClick={() => setShowFilters(false)}
                                className="px-5 py-2.5 bg-slate-800 hover:bg-slate-900 text-white text-sm font-semibold rounded-xl transition-all shadow-md shadow-slate-800/20"
                            >
                                Aplicar
                            </button>
                        </div>
                    </motion.div>
                </div>
            )}
            {/* Deal Detail Drawer */}
            <DealDetailDrawer
                dealId={selectedDealId}
                isOpen={showDrawer}
                onClose={() => { setShowDrawer(false); onDealChange(null); }}
                onChanged={() => fetchData()}
            />
        </div>
    );
};

type CommercialTab = 'pipeline' | 'clients' | 'quotes' | 'providers';

const TABS: Array<{ id: CommercialTab; label: string; icon: typeof TrendingUp }> = [
    { id: 'pipeline', label: 'Pipeline', icon: TrendingUp },
    { id: 'clients', label: 'Clientes', icon: Building2 },
    { id: 'quotes', label: 'Cotizaciones', icon: FileText },
    { id: 'providers', label: 'Proveedores', icon: Truck },
];

const CommercialPage = () => {
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const [params,setParams]=useSearchParams(); const requested=params.get('view');
    const activeTab:CommercialTab=TABS.some(tab=>tab.id===requested)?requested as CommercialTab:'pipeline';
    const updateParams=(updates:Record<string,string|null>)=>{const next=new URLSearchParams(params);Object.entries(updates).forEach(([key,value])=>value?next.set(key,value):next.delete(key));setParams(next,{replace:true});};

    return (
        <div className="space-y-5">
            <PageHeader title="Commercial 360" subtitle="Cliente, oportunidad, proveedor, cotización y entrega a Operaciones" actions={<SavedViewsMenu tenantId={activeTenant} module="commercial" filters={{view:activeTab}} onApply={(filters)=>updateParams({view:typeof filters.view==='string'?filters.view:'pipeline',dealId:null,quoteId:null})}/>} />
            <nav aria-label="Secciones de Comercial" className="flex gap-1 overflow-x-auto rounded-2xl border bg-white p-1.5">
                {TABS.map((tab) => {
                    const Icon = tab.icon;
                    return <button key={tab.id} type="button" onClick={() => updateParams({view:tab.id,dealId:null,quoteId:null})} className={`flex min-w-fit items-center gap-2 rounded-xl px-4 py-2.5 text-xs font-bold transition ${activeTab === tab.id ? 'bg-primary text-white shadow-sm' : 'text-slate-500 hover:bg-slate-50'}`}><Icon size={15} />{tab.label}</button>;
                })}
            </nav>
            {!activeTenant ? <div className="rounded-2xl border bg-white p-8 text-center text-sm text-slate-500">No hay una empresa activa para consultar Comercial.</div> : activeTab === 'pipeline' ? <PipelineWorkspace requestedDealId={params.get('dealId')} onDealChange={(dealId)=>updateParams({dealId})}/> : activeTab === 'clients' ? <CustomerDirectory tenantId={activeTenant} requestedCustomerId={params.get('customerId')} createRequested={params.get('action')==='new-customer'} onCustomerChange={(customerId)=>updateParams({customerId})} onCreateHandled={()=>updateParams({action:null})} /> : activeTab === 'quotes' ? <QuoteWorkspace tenantId={activeTenant} /> : <ProviderDirectory tenantId={activeTenant} requestedProviderId={params.get('providerId')} createRequested={params.get('action')==='new-provider'} onProviderChange={(providerId)=>updateParams({providerId})} onCreateHandled={()=>updateParams({action:null})} />}
        </div>
    );
};

export default CommercialPage;
