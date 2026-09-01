import React, { useState, useEffect } from 'react';
import { Plus, Search, Filter, LayoutGrid, List, Map, Loader2, X, TrendingUp, Building2, FileText, Truck, BadgeDollarSign, ShieldCheck } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { moveDeal, createDeal, listPipelineDeals } from '@/services/commercial.service';
import type { PipelineColumn, LegacyDealItem, DealCreatePayload, DealStage } from '@/types/commercial';
import { motion } from 'motion/react';
import { DealDetailDrawer } from '@/components/commercial/DealDetailDrawer';
import { CustomerDirectory } from '@/components/commercial/CustomerDirectory';
import { ProviderDirectory } from '@/components/commercial/ProviderDirectory';
import { QuoteWorkspace } from '@/components/commercial/QuoteWorkspace';
import { RateWorkspace } from '@/components/commercial/RateWorkspace';
import { ComplianceWorkspace } from '@/components/commercial/ComplianceWorkspace';
import { PageHeader } from '@/components/PageHeader';
import { SavedViewsMenu } from '@/components/productivity/SavedViewsMenu';
import { useSearchParams } from 'react-router-dom';
import { MOBILE_MEDIA_QUERY, useMediaQuery } from '@/hooks/useMediaQuery';

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
    const isMobile = useMediaQuery(MOBILE_MEDIA_QUERY);
    const [viewMode, setViewMode] = useState<'board' | 'list' | 'map'>(() => isMobile ? 'list' : 'board');
    const [viewModeTouched, setViewModeTouched] = useState(false);
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

    useEffect(() => {
        if (!viewModeTouched) setViewMode(isMobile ? 'list' : 'board');
    }, [isMobile, viewModeTouched]);

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
        <div className="relative min-w-0 max-w-full space-y-4 sm:space-y-6">
            {pipelineError && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{pipelineError}</div>}
            {/* Header */}
            <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                    <h1 className="text-xl font-bold text-slate-800 sm:text-2xl">Pipeline comercial</h1>
                    <p className="mt-0.5 text-xs text-slate-500 sm:text-sm">Gestión comercial y seguimiento de oportunidades</p>
                </div>
                <div className="flex w-full items-center gap-2 sm:w-auto">
                    {!isViewer && (
                        <button onClick={() => setShowNewModal(true)} className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-xl px-4 text-xs font-semibold text-white shadow-md shadow-accent-red/20 transition-all gradient-accent hover:shadow-lg hover:shadow-accent-red/30 sm:flex-none">
                            <Plus size={14} /> Nueva oportunidad
                        </button>
                    )}
                    <button onClick={() => setShowFilters(true)} className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-xl border border-tech-border/60 bg-surface px-3.5 text-xs font-semibold text-slate-500 transition-all hover:border-primary/30 hover:text-primary sm:flex-none">
                        <Filter size={14} /> Filtros {filterPriority && <span className="ml-1 h-2 w-2 rounded-full bg-primary"></span>}
                    </button>
                </div>
            </div>

            {/* Search + view toggle */}
            <div className="grid min-w-0 gap-2 sm:flex sm:flex-wrap sm:items-center sm:gap-3">
                <div className="relative min-w-0 flex-1 sm:max-w-md">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        onKeyDown={handleSearch}
                        placeholder="Buscar cliente, título o ID de oportunidad"
                        className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
                <div className="grid w-full grid-cols-3 gap-0.5 rounded-xl border border-tech-border/60 bg-surface-card p-0.5 sm:flex sm:w-auto">
                    <button onClick={() => { setViewModeTouched(true); setViewMode('board'); }} aria-pressed={viewMode === 'board'} className={`flex min-h-11 items-center justify-center gap-1.5 rounded-lg px-3 text-[11px] font-semibold transition-all
              ${viewMode === 'board' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <LayoutGrid size={12} /> Tablero
                    </button>
                    <button onClick={() => { setViewModeTouched(true); setViewMode('list'); }} aria-pressed={viewMode === 'list'} className={`flex min-h-11 items-center justify-center gap-1.5 rounded-lg px-3 text-[11px] font-semibold transition-all
              ${viewMode === 'list' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <List size={12} /> Lista
                    </button>
                    <button onClick={() => { setViewModeTouched(true); setViewMode('map'); }} aria-pressed={viewMode === 'map'} className={`flex min-h-11 items-center justify-center gap-1.5 rounded-lg px-3 text-[11px] font-semibold transition-all
              ${viewMode === 'map' ? 'bg-primary text-white shadow-sm' : 'text-slate-400 hover:text-primary hover:bg-primary-50'}`}>
                        <Map size={12} /> Mapa
                    </button>
                </div>
            </div>

            {/* Kanban board */}
            {loading && columns.length === 0 ? (
                <div className="flex items-center justify-center p-20">
                    <Loader2 className="animate-spin text-slate-400" size={30} />
                </div>
            ) : viewMode === 'list' ? (
                <section className="overflow-hidden rounded-2xl border bg-surface-card" data-commercial-mobile-list>
                    <div className="divide-y">{columns.flatMap((column) => column.deals.map((deal, index) => ({ deal, index, column }))).map(({ deal, index, column }) => {
                        const colors = stageColors[column.title] || stageColors.Prospecto;
                        return <button type="button" key={deal.db_id || `${column.title}-${index}`} onClick={() => { if (deal.db_id) { setSelectedDealId(deal.db_id); setShowDrawer(true); onDealChange(deal.db_id); } }} className="flex min-h-[5.5rem] w-full min-w-0 items-center gap-3 p-3 text-left hover:bg-slate-50 sm:p-4">
                            <span className={`h-10 w-1 shrink-0 rounded-full ${colors.dot}`} />
                            <span className="min-w-0 flex-1"><span className="block truncate text-sm font-bold text-slate-800">{deal.name}</span><span className="mt-1 block text-[10px] font-bold uppercase text-slate-500">{column.title} · {deal.prob}</span></span>
                            <strong className="max-w-[42%] shrink-0 truncate text-sm text-primary">{deal.value} MXN</strong>
                        </button>;
                    })}</div>
                    {columns.every((column) => column.deals.length === 0) && <p className="p-8 text-center text-sm text-slate-400">No hay oportunidades para los filtros seleccionados.</p>}
                </section>
            ) : viewMode === 'map' ? (
                <section className="rounded-2xl border border-dashed bg-surface-card p-8 text-center"><Map className="mx-auto text-slate-400" /><h2 className="mt-3 font-bold text-slate-700">Vista geográfica</h2><p className="mx-auto mt-1 max-w-md text-sm text-slate-500">Las oportunidades actuales no incluyen ubicaciones confirmadas. Usa Lista o Tablero.</p></section>
            ) : (
                <div className="flex max-w-full snap-x gap-3 overflow-x-auto overscroll-x-contain pb-2 md:grid md:grid-cols-2 md:gap-4 md:overflow-visible lg:grid-cols-4" data-commercial-board-container>
                    {columns.map((col) => {
                        const colors = stageColors[col.title] || stageColors['Prospecto'];
                        const totalValue = col.deals.reduce((acc, d) => {
                            const num = parseFloat((String(d.value)).replace(/[$kM,]/g, ''));
                            return acc + ((String(d.value)).includes('M') ? num * 1000 : num);
                        }, 0);

                        return (
                            <div
                                key={col.title}
                                className="min-h-[15rem] w-[min(82vw,19rem)] shrink-0 snap-start space-y-3 rounded-2xl border border-tech-border/60 bg-surface p-3 md:min-h-[400px] md:w-auto"
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
                                        <div className="rounded-xl border border-dashed border-tech-border/40 p-4 py-6 text-center text-xs text-slate-400 md:py-10">
                                            Sin oportunidades en esta fase
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
                                            className={`group relative cursor-pointer rounded-xl border bg-surface-card p-3 transition-all duration-200 active:cursor-grabbing hover:border-primary/20 hover:shadow-md hover:shadow-primary/5 sm:p-4
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
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-0 backdrop-blur-sm sm:p-4">
                    <motion.div role="dialog" aria-modal="true" aria-labelledby="new-deal-title" initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="h-dvh w-full max-w-sm overflow-y-auto bg-surface-card shadow-xl sm:h-auto sm:max-h-[calc(100dvh-2rem)] sm:rounded-2xl">
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 id="new-deal-title" className="text-lg font-bold text-slate-800">Nueva oportunidad</h2>
                            <button onClick={() => setShowNewModal(false)} aria-label="Cerrar nuevo deal" className="flex h-11 w-11 items-center justify-center text-slate-400 hover:text-slate-600">✕</button>
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
                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} Crear oportunidad
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Filter Drawer */}
            {showFilters && (
                <div className="fixed inset-0 z-50 flex w-full items-center justify-center bg-slate-900/30 p-0 backdrop-blur-sm sm:p-4">
                    <div className="flex-1 h-full w-full" onClick={() => setShowFilters(false)}></div>
                    <motion.div
                        initial={{ opacity: 0, x: 100 }}
                        animate={{ opacity: 1, x: 0 }}
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="commercial-filters-title"
                        className="absolute right-0 flex h-dvh w-full max-w-sm flex-col overflow-y-auto bg-surface-card shadow-2xl sm:h-full"
                    >
                        <div className="sticky top-0 z-10 flex items-center justify-between border-b bg-surface-card/95 px-4 py-3 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur-md sm:px-6 sm:py-4">
                            <div>
                                <h2 id="commercial-filters-title" className="text-lg font-bold text-slate-800">Filtros CRM</h2>
                                <p className="text-xs text-slate-500">Refina las oportunidades</p>
                            </div>
                            <button onClick={() => setShowFilters(false)} aria-label="Cerrar filtros CRM" className="flex h-11 w-11 items-center justify-center rounded-lg bg-surface text-slate-400 hover:text-slate-600">
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

                        <div className="flex items-center justify-between border-t bg-surface px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3 sm:p-6">
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

type CommercialTab = 'pipeline' | 'clients' | 'quotes' | 'providers' | 'rates' | 'compliance';

const TABS: Array<{ id: CommercialTab; label: string; icon: typeof TrendingUp }> = [
    { id: 'pipeline', label: 'Pipeline', icon: TrendingUp },
    { id: 'clients', label: 'Clientes', icon: Building2 },
    { id: 'quotes', label: 'Cotizaciones', icon: FileText },
    { id: 'providers', label: 'Proveedores', icon: Truck },
    { id: 'rates', label: 'Tarifas', icon: BadgeDollarSign },
    { id: 'compliance', label: 'Cumplimiento', icon: ShieldCheck },
];

const CommercialPage = () => {
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const [params,setParams]=useSearchParams(); const requested=params.get('view');
    const activeTab:CommercialTab=TABS.some(tab=>tab.id===requested)?requested as CommercialTab:'pipeline';
    const updateParams=(updates:Record<string,string|null>)=>{const next=new URLSearchParams(params);Object.entries(updates).forEach(([key,value])=>value?next.set(key,value):next.delete(key));setParams(next,{replace:true});};

    return (
        <div className="min-w-0 max-w-full space-y-4 sm:space-y-5">
            <PageHeader title="Comercial" subtitle="Clientes, oportunidades, proveedores y cotizaciones" actions={<SavedViewsMenu tenantId={activeTenant} module="commercial" filters={{view:activeTab}} onApply={(filters)=>updateParams({view:typeof filters.view==='string'?filters.view:'pipeline',dealId:null,quoteId:null})}/>} />
            <nav aria-label="Secciones de Comercial" className="flex max-w-full gap-1 overflow-x-auto overscroll-x-contain rounded-2xl border bg-surface-card p-1.5">
                {TABS.map((tab) => {
                    const Icon = tab.icon;
                    return <button key={tab.id} type="button" aria-pressed={activeTab === tab.id} onClick={() => updateParams({view:tab.id,dealId:null,quoteId:null})} className={`flex min-h-11 shrink-0 items-center gap-2 rounded-xl px-3 text-xs font-bold transition sm:px-4 ${activeTab === tab.id ? 'bg-primary text-white shadow-sm' : 'text-slate-500 hover:bg-slate-50'}`}><Icon size={15} />{tab.label}</button>;
                })}
            </nav>
            {!activeTenant ? <div className="rounded-2xl border bg-white p-8 text-center text-sm text-slate-500">No hay una empresa activa para consultar Comercial.</div> : activeTab === 'pipeline' ? <PipelineWorkspace requestedDealId={params.get('dealId')} onDealChange={(dealId)=>updateParams({dealId})}/> : activeTab === 'clients' ? <CustomerDirectory tenantId={activeTenant} requestedCustomerId={params.get('customerId')} createRequested={params.get('action')==='new-customer'} onCustomerChange={(customerId)=>updateParams({customerId})} onCreateHandled={()=>updateParams({action:null})} /> : activeTab === 'quotes' ? <QuoteWorkspace tenantId={activeTenant} requestedCustomerId={params.get('customerId')} /> : activeTab === 'providers' ? <ProviderDirectory tenantId={activeTenant} requestedProviderId={params.get('providerId')} createRequested={params.get('action')==='new-provider'} onProviderChange={(providerId)=>updateParams({providerId})} onCreateHandled={()=>updateParams({action:null})} /> : activeTab === 'rates' ? <RateWorkspace tenantId={activeTenant} requestedRateId={params.get('rateId')} requestedProviderId={params.get('providerId')} createType={params.get('action')==='new-buy-rate'?'BUY':params.get('action')==='new-sell-rate'?'SELL':null} onRateChange={(rateId)=>updateParams({rateId})} onCreateHandled={()=>updateParams({action:null})} /> : <ComplianceWorkspace tenantId={activeTenant} requestedTab={params.get('tab')} requestedPartnerType={params.get('partnerType')} requestedPartnerId={params.get('partnerId')} onParams={updateParams}/>}
        </div>
    );
};

export default CommercialPage;
