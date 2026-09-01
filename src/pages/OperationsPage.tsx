import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { AlertTriangle, Inbox, Loader2, Plus, RefreshCw, X } from 'lucide-react';
import { motion } from 'motion/react';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { SavedViewsMenu } from '@/components/productivity/SavedViewsMenu';
import { BulkActionBar } from '@/components/productivity/BulkActionBar';
import { AssignmentDrawer } from '@/components/operations/AssignmentDrawer';
import { Operation360Panel } from '@/components/operations/Operation360Panel';
import { OperationsFilters } from '@/components/operations/OperationsFilters';
import { OperationsKpiStrip } from '@/components/operations/OperationsKpiStrip';
import { OperationsTable } from '@/components/operations/OperationsTable';
import {
    filterOperations,
    isOperationsView,
    OPERATION_STATUS_META,
    type OperationsView,
} from '@/components/operations/operationsControl';
import {
    createOperation,
    listOperations,
    overrideOperationStatus,
    transitionOperationStatus,
} from '@/services/operations.service';
import { createTrackingToken, getTrackingErrorMessage } from '@/services/trackingAdmin.service';
import { buildTrackingUrl, resolvePublicAppBaseUrl } from '@/services/trackingContracts';
import { canManageRoteroModule } from '@/constants/roles';
import { useAuthStore } from '@/store/authStore';
import type { Operation } from '@/types/operations';
import { bulkUpdateOperations, recordDataAction } from '@/services/dataOperations.service';
import { downloadCsvContent, serializeCsv } from '@/utils/csv';

const OperationsPage = () => {
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const getRole = useAuthStore((state) => state.getRole);
    const role = getRole();
    const isAdmin = role === 'admin';
    const canManageOperations = canManageRoteroModule(role, 'operations');
    const canManageTracking = canManageRoteroModule(role, 'tracking');
    const [searchParams, setSearchParams] = useSearchParams();

    const viewParam = searchParams.get('view');
    const view: OperationsView = isOperationsView(viewParam) ? viewParam : 'active';
    const statusParam = searchParams.get('status') ?? '';
    const status = statusParam in OPERATION_STATUS_META ? statusParam : '';
    const query = searchParams.get('q') ?? '';
    const selectedParam = searchParams.get('operation');
    const selectedIdParam = searchParams.get('operationId');
    const selectedTab = searchParams.get('tab');

    const [operations, setOperations] = useState<Operation[]>([]);
    const [loading, setLoading] = useState(true);
    const [loadError, setLoadError] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [createError, setCreateError] = useState<string | null>(null);
    const [showNewModal, setShowNewModal] = useState(false);
    const [showAssignmentDrawer, setShowAssignmentDrawer] = useState(false);
    const [workspaceRefreshKey, setWorkspaceRefreshKey] = useState(0);
    const [bulkIds, setBulkIds] = useState<Set<string>>(new Set()); const [bulkBusy, setBulkBusy] = useState(false);

    const [driverToken, setDriverToken] = useState<string | null>(null);
    const [publicToken, setPublicToken] = useState<string | null>(null);
    const [copiedStatus, setCopiedStatus] = useState<'driver' | 'public' | null>(null);

    const [newOpRef, setNewOpRef] = useState('');
    const [newOpClient, setNewOpClient] = useState('');
    const [transitionError, setTransitionError] = useState<string | null>(null);
    const [showOverrideModal, setShowOverrideModal] = useState(false);
    const [overrideReason, setOverrideReason] = useState('');
    const [isOverriding, setIsOverriding] = useState(false);

    const filteredOperations = useMemo(
        () => filterOperations(operations, view, status, query),
        [operations, query, status, view],
    );
    const activeOp = operations.find((operation) => operation.db_id === selectedIdParam || operation.id === selectedParam) ?? null;

    const updateParams = useCallback((updates: Record<string, string | null>) => {
        setSearchParams((current) => {
            const next = new URLSearchParams(current);
            Object.entries(updates).forEach(([key, value]) => {
                if (value) next.set(key, value);
                else next.delete(key);
            });
            return next;
        }, { replace: true });
    }, [setSearchParams]);

    const fetchOps = useCallback(async () => {
        if (!activeTenant) {
            setOperations([]);
            setLoadError('No hay un tenant activo para consultar operaciones.');
            setLoading(false);
            return;
        }

        setLoading(true);
        setLoadError(null);
        try {
            setOperations(await listOperations(activeTenant));
        } catch (error) {
            console.error('Failed to load operations:', error);
            setLoadError('No fue posible cargar la bandeja operativa.');
        } finally {
            setLoading(false);
        }
    }, [activeTenant]);

    useEffect(() => {
        void fetchOps();
    }, [fetchOps]);

    const handleCreate = async (event: FormEvent) => {
        event.preventDefault();
        if (!canManageOperations || !activeTenant || !newOpRef.trim()) return;

        setIsCreating(true);
        setCreateError(null);
        try {
            await createOperation(activeTenant, {
                reference_code: newOpRef.trim(),
                client_display_name: newOpClient.trim(),
                status: 'planned',
            });
            setShowNewModal(false);
            setNewOpRef('');
            setNewOpClient('');
            updateParams({ view: 'all', status: null, q: null, operation: null });
            await fetchOps();
        } catch (error) {
            console.error('Failed to create operation:', error);
            setCreateError(error instanceof Error ? error.message : 'No fue posible crear la operación.');
        } finally {
            setIsCreating(false);
        }
    };

    const handleGenerateTokens = async () => {
        if (!canManageTracking || !activeTenant || !activeOp?.db_id) return;

        setTransitionError(null);
        try {
            const [driverResult, publicResult] = await Promise.all([
                createTrackingToken({
                    tenantId: activeTenant,
                    operationId: activeOp.db_id,
                    scope: 'driver:write',
                    ttlHours: null,
                    forceRotate: true,
                }),
                createTrackingToken({
                    tenantId: activeTenant,
                    operationId: activeOp.db_id,
                    scope: 'public:read',
                    ttlHours: null,
                    forceRotate: true,
                }),
            ]);

            if (driverResult.kind !== 'created' || publicResult.kind !== 'created') {
                throw new Error('invalid_create_result');
            }

            setDriverToken(driverResult.token);
            setPublicToken(publicResult.token);
            setWorkspaceRefreshKey((value) => value + 1);
        } catch (error) {
            setTransitionError(getTrackingErrorMessage(error));
            throw error;
        }
    };

    const handleCopyToken = (type: 'driver' | 'public') => {
        const literal = type === 'driver' ? driverToken : publicToken;
        if (!literal) return;

        const publicAppBaseUrl = resolvePublicAppBaseUrl(
            import.meta.env.VITE_PUBLIC_APP_URL,
            window.location.origin,
        );
        const scope = type === 'driver' ? 'driver:write' : 'public:read';
        const url = buildTrackingUrl(publicAppBaseUrl, scope, literal);
        const markCopied = () => {
            setCopiedStatus(type);
            window.setTimeout(() => setCopiedStatus(null), 2000);
        };

        if (navigator.clipboard?.writeText) {
            navigator.clipboard.writeText(url).then(markCopied).catch(() => window.prompt('Copia el enlace:', url));
        } else {
            window.prompt('Copia el enlace:', url);
        }
    };

    const handleTransition = async (toStatus: string) => {
        if (!canManageOperations || !activeOp?.db_id) return;

        setTransitionError(null);
        try {
            await transitionOperationStatus(activeOp.db_id, toStatus);
            await fetchOps();
            setWorkspaceRefreshKey((value) => value + 1);
        } catch (error) {
            setTransitionError(error instanceof Error ? error.message : 'No fue posible cambiar el estado.');
            throw error;
        }
    };

    const handleOverrideCancel = async (event: FormEvent) => {
        event.preventDefault();
        if (!isAdmin || !activeOp?.db_id || overrideReason.trim().length < 10) return;

        setIsOverriding(true);
        setTransitionError(null);
        try {
            await overrideOperationStatus(activeOp.db_id, 'cancelled', overrideReason.trim());
            setShowOverrideModal(false);
            setOverrideReason('');
            await fetchOps();
            setWorkspaceRefreshKey((value) => value + 1);
        } catch (error) {
            setTransitionError(error instanceof Error ? error.message : 'No fue posible cancelar administrativamente.');
        } finally {
            setIsOverriding(false);
        }
    };

    const clearFilters = () => updateParams({ view: 'active', status: null, q: null, operation: null, operationId: null, tab: null, document: null });
    const toggleBulk = (operation: Operation) => { const id = operation.db_id ?? operation.id; setBulkIds((current) => { const next = new Set(current); if (next.has(id)) next.delete(id); else next.add(id); return next; }); };
    const toggleAllBulk = () => setBulkIds((current) => filteredOperations.every((item) => current.has(item.db_id ?? item.id)) ? new Set() : new Set(filteredOperations.map((item) => item.db_id ?? item.id)));
    const selectedOperations = operations.filter((item) => bulkIds.has(item.db_id ?? item.id));
    const exportSelected = async () => { if (!activeTenant || !selectedOperations.length) return; const rows = selectedOperations.map((item) => ({ reference_code: item.reference_code ?? item.id, status: item.status, customer: item.client, provider: item.provider_name ?? '', route: item.route, priority: item.priority ?? '', planned_departure: item.planned_departure ?? '' })); downloadCsvContent(serializeCsv(rows), `operaciones-seleccionadas-${new Date().toISOString().slice(0, 10)}.csv`); await recordDataAction(activeTenant, 'export_requested', 'operations', rows.length, 'selected'); };
    const updateSelected = async (action: 'set_priority' | 'add_note') => { if (!activeTenant || !bulkIds.size) return; const value = action === 'set_priority' ? window.prompt('Prioridad: low, normal o high', 'high') : window.prompt('Nota para agregar (máximo 240 caracteres)'); if (!value) return; setBulkBusy(true); setTransitionError(null); try { await bulkUpdateOperations(activeTenant, [...bulkIds], action, action === 'set_priority' ? { priority: value } : { note: value }); setBulkIds(new Set()); await fetchOps(); } catch (cause) { setTransitionError(cause instanceof Error ? cause.message : 'No se pudo aplicar la acción masiva.'); } finally { setBulkBusy(false); } };

    return (
        <div className="relative min-w-0 max-w-full space-y-4 sm:space-y-5">
            <PageHeader
                title="Control Center"
                subtitle="Bandeja diaria de operaciones y ejecución logística contratada"
                actions={(
                    <>
                        {canManageOperations && (
                            <button
                                type="button"
                                onClick={() => { setCreateError(null); setShowNewModal(true); }}
                                className="order-first flex min-h-11 items-center gap-2 rounded-xl bg-primary px-4 text-xs font-bold text-white shadow-md shadow-primary/20 transition hover:bg-primary-dark sm:order-none"
                            >
                                <Plus size={15} /> Nueva operación
                            </button>
                        )}
                        <SavedViewsMenu tenantId={activeTenant} module="operations" filters={{ view,status,q:query }} onApply={(filters)=>updateParams({view:typeof filters.view==='string'?filters.view:'active',status:typeof filters.status==='string'?filters.status:null,q:typeof filters.q==='string'?filters.q:null,operation:null,operationId:null,tab:null})}/>
                        <button
                            type="button"
                            onClick={() => void fetchOps()}
                            disabled={loading}
                            aria-label="Actualizar operaciones"
                            className="flex h-11 w-11 items-center justify-center rounded-xl border bg-surface-card text-xs font-bold text-slate-600 transition hover:bg-slate-50 disabled:opacity-50 sm:w-auto sm:px-3.5"
                        >
                            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                            <span className="hidden sm:inline">Actualizar</span>
                        </button>
                    </>
                )}
            />

            {loading ? (
                <div aria-label="Cargando operaciones" className="space-y-4">
                    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
                        {Array.from({ length: 6 }).map((_, index) => <div key={index} className="h-24 animate-pulse rounded-2xl bg-slate-100" />)}
                    </div>
                    <div className="h-28 animate-pulse rounded-2xl bg-slate-100" />
                    <div className="grid gap-5 xl:grid-cols-[minmax(0,1.8fr)_minmax(340px,0.9fr)]">
                        <div className="h-96 animate-pulse rounded-2xl bg-slate-100" />
                        <div className="h-96 animate-pulse rounded-2xl bg-slate-100" />
                    </div>
                </div>
            ) : loadError ? (
                <section className="rounded-2xl border border-red-200 bg-red-50 p-8 text-center">
                    <AlertTriangle className="mx-auto text-red-500" size={28} />
                    <h2 className="mt-3 font-bold text-red-800">No se pudo cargar el Control Center</h2>
                    <p className="mt-1 text-sm text-red-600">{loadError}</p>
                    <button type="button" onClick={() => void fetchOps()} className="mt-4 rounded-xl bg-red-600 px-4 py-2.5 text-xs font-bold text-white hover:bg-red-700">Reintentar</button>
                </section>
            ) : (
                <>
                    <OperationsKpiStrip operations={operations} />
                    <OperationsFilters
                        view={view}
                        status={status}
                        query={query}
                        resultCount={filteredOperations.length}
                        onViewChange={(nextView) => updateParams({ view: nextView, operation: null, operationId: null, tab: null })}
                        onStatusChange={(nextStatus) => updateParams({ status: nextStatus || null, operation: null, operationId: null, tab: null })}
                        onQueryChange={(nextQuery) => updateParams({ q: nextQuery || null, operation: null, operationId: null, tab: null })}
                        onClear={clearFilters}
                    />
                    {isAdmin && <BulkActionBar count={bulkIds.size} onClear={() => setBulkIds(new Set())}><button disabled={bulkBusy} onClick={() => void exportSelected()} className="rounded-xl border px-3 py-2 text-xs font-bold">Exportar selección</button><button disabled={bulkBusy} onClick={() => void updateSelected('set_priority')} className="rounded-xl border px-3 py-2 text-xs font-bold">Cambiar prioridad</button><button disabled={bulkBusy} onClick={() => void updateSelected('add_note')} className="rounded-xl border px-3 py-2 text-xs font-bold">Agregar nota</button></BulkActionBar>}

                    {filteredOperations.length === 0 ? (
                        <section className="rounded-2xl border border-dashed border-slate-300 bg-surface-card p-6 text-center sm:p-10">
                            <Inbox className="mx-auto text-slate-300" size={34} />
                            <h2 className="mt-3 font-bold text-slate-700">{operations.length === 0 ? 'Aún no hay operaciones' : 'No hay coincidencias'}</h2>
                            <p className="mx-auto mt-1 max-w-md text-sm text-slate-400">
                                {operations.length === 0
                                    ? 'La bandeja se actualizará cuando existan operaciones para este tenant.'
                                    : 'Ajusta la vista, el estado o el texto de búsqueda.'}
                            </p>
                            {operations.length > 0 && <button type="button" onClick={clearFilters} className="mt-4 rounded-xl bg-slate-100 px-4 py-2.5 text-xs font-bold text-slate-600 hover:bg-slate-200">Limpiar filtros</button>}
                        </section>
                    ) : (
                        <OperationsTable
                            operations={filteredOperations}
                            selectedId={activeOp?.id ?? null}
                            onSelect={(operation) => updateParams({ operation: operation.id, operationId: operation.db_id, tab: 'overview' })}
                            selectedBulkIds={bulkIds}
                            onToggleBulk={isAdmin ? toggleBulk : undefined}
                            onToggleAll={isAdmin ? toggleAllBulk : undefined}
                        />
                    )}
                </>
            )}

            {activeOp && (
                <Operation360Panel
                    operation={activeOp}
                    canManage={canManageOperations}
                    canManageTracking={canManageTracking}
                    isAdmin={isAdmin}
                    refreshKey={workspaceRefreshKey}
                    initialTab={selectedTab}
                    onTabChange={(tab) => updateParams({ tab })}
                    onClose={() => {
                        updateParams({ operation: null, operationId: null, tab: null, document: null });
                        setDriverToken(null);
                        setPublicToken(null);
                    }}
                    onAssign={() => setShowAssignmentDrawer(true)}
                    onGenerateTokens={handleGenerateTokens}
                    onTransition={handleTransition}
                    onOverrideCancel={() => { setTransitionError(null); setShowOverrideModal(true); }}
                    onOperationsRefresh={fetchOps}
                />
            )}

            {(driverToken || publicToken) && (
                <div className="fixed inset-0 z-[70] flex items-center justify-center bg-slate-950/50 p-4 backdrop-blur-sm">
                    <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl">
                        <div className="flex items-center justify-between gap-3"><div><h2 className="font-black text-slate-800">Capabilities generadas</h2><p className="mt-1 text-xs text-slate-400">Los literales solo se muestran en esta creación explícita.</p></div><button onClick={() => { setDriverToken(null); setPublicToken(null); }} className="rounded-lg bg-slate-100 p-2 text-slate-500"><X size={16} /></button></div>
                        <div className="mt-5 space-y-3">{driverToken && <div className="rounded-xl border border-slate-200 p-3"><p className="text-xs font-bold text-slate-700">Chofer del proveedor</p><code className="mt-1 block truncate text-[11px] text-slate-400">/driver/{driverToken.slice(0, 10)}…</code><button onClick={() => handleCopyToken('driver')} className="mt-2 rounded-lg bg-primary px-3 py-2 text-xs font-bold text-white">{copiedStatus === 'driver' ? 'Copiado' : 'Copiar enlace'}</button></div>}{publicToken && <div className="rounded-xl border border-slate-200 p-3"><p className="text-xs font-bold text-slate-700">Tracking público</p><code className="mt-1 block truncate text-[11px] text-slate-400">/t/{publicToken.slice(0, 10)}…</code><button onClick={() => handleCopyToken('public')} className="mt-2 rounded-lg bg-primary px-3 py-2 text-xs font-bold text-white">{copiedStatus === 'public' ? 'Copiado' : 'Copiar enlace'}</button></div>}</div>
                        <button onClick={() => { setDriverToken(null); setPublicToken(null); }} className="mt-5 w-full rounded-xl bg-slate-100 py-2.5 text-sm font-bold text-slate-600">Cerrar</button>
                    </div>
                </div>
            )}

            {showOverrideModal && activeOp && isAdmin && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-0 backdrop-blur-sm sm:p-4">
                    <motion.div role="dialog" aria-modal="true" aria-labelledby="new-operation-title" initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} className="h-dvh w-full max-w-md overflow-y-auto bg-surface-card shadow-xl sm:h-auto sm:max-h-[calc(100dvh-2rem)] sm:rounded-2xl">
                        <div className="flex items-center justify-between border-b border-red-100 bg-red-50 px-6 py-4">
                            <h2 className="flex items-center gap-2 text-lg font-bold text-red-800"><AlertTriangle size={18} /> Cancelación administrativa</h2>
                            <button type="button" onClick={() => setShowOverrideModal(false)} className="rounded-lg p-1 text-red-400 hover:bg-red-100 hover:text-red-600"><X size={17} /></button>
                        </div>
                        <form onSubmit={handleOverrideCancel} className="space-y-4 p-6">
                            <p className="rounded-xl border border-slate-200 bg-slate-50 p-3 text-xs text-slate-600">
                                La operación <b>{activeOp.id}</b> está en estado <b>{OPERATION_STATUS_META[activeOp.status]?.label ?? activeOp.status}</b>. El flujo actual requiere un motivo para usar el override existente.
                            </p>
                            <div>
                                <label htmlFor="override-reason" className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate-500">Motivo (mínimo 10 caracteres)</label>
                                <textarea id="override-reason" required autoFocus minLength={10} maxLength={280} rows={3} value={overrideReason} onChange={(event) => setOverrideReason(event.target.value)} className="w-full resize-none rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm outline-none focus:border-red-500 focus:ring-2 focus:ring-red-500/20" placeholder="Describe la razón de la cancelación…" />
                            </div>
                            {transitionError && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-xs font-semibold text-red-700">{transitionError}</div>}
                            <div className="flex justify-end gap-3 pt-2">
                                <button type="button" onClick={() => setShowOverrideModal(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Volver</button>
                                <button type="submit" disabled={isOverriding || overrideReason.trim().length < 10} className="flex items-center gap-2 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50">
                                    {isOverriding && <Loader2 size={14} className="animate-spin" />} Confirmar cancelación
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {showNewModal && canManageOperations && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4 backdrop-blur-sm">
                    <motion.div initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
                            <div>
                                <h2 id="new-operation-title" className="text-lg font-bold text-slate-800">Nueva operación</h2>
                                <p className="mt-0.5 text-xs text-slate-400">Alta básica con el contrato frontend vigente.</p>
                            </div>
                            <button type="button" aria-label="Cerrar nueva operación" onClick={() => setShowNewModal(false)} className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-600"><X size={17} /></button>
                        </div>
                        <form onSubmit={handleCreate} className="space-y-4 p-6">
                            <div>
                                <label htmlFor="operation-reference" className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate-500">Referencia</label>
                                <input id="operation-reference" required autoFocus type="text" value={newOpRef} onChange={(event) => setNewOpRef(event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20" placeholder="Ej. OP-9001" />
                            </div>
                            <div>
                                <label htmlFor="operation-client" className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-slate-500">Cliente</label>
                                <input id="operation-client" type="text" value={newOpClient} onChange={(event) => setNewOpClient(event.target.value)} className="w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20" placeholder="Nombre del cliente (opcional)" />
                            </div>
                            {createError && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-xs font-semibold text-red-700">{createError}</div>}
                            <div className="flex justify-end gap-3 pt-2">
                                <button type="button" onClick={() => setShowNewModal(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isCreating || !newOpRef.trim()} className="flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-white shadow-sm shadow-primary/20 disabled:opacity-50">
                                    {isCreating && <Loader2 size={14} className="animate-spin" />} Crear operación
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            <AssignmentDrawer
                isOpen={canManageOperations && showAssignmentDrawer}
                onClose={() => setShowAssignmentDrawer(false)}
                operation={activeOp}
                onAssigned={() => {
                    setShowAssignmentDrawer(false);
                    setWorkspaceRefreshKey((value) => value + 1);
                    void fetchOps();
                }}
            />
        </div>
    );
};

export default OperationsPage;
