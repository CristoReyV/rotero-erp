import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { AlertTriangle, Inbox, Loader2, Plus, RefreshCw, X } from 'lucide-react';
import { motion } from 'motion/react';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { AssignmentDrawer } from '@/components/operations/AssignmentDrawer';
import { OperationQuickPanel } from '@/components/operations/OperationQuickPanel';
import { OperationsFilters } from '@/components/operations/OperationsFilters';
import { OperationsKpiStrip } from '@/components/operations/OperationsKpiStrip';
import { OperationsTable } from '@/components/operations/OperationsTable';
import {
    filterOperations,
    isOperationsView,
    OPERATION_STATUS_META,
    type OperationsView,
} from '@/components/operations/operationsControl';
import { supabase } from '@/lib/supabase';
import {
    createOperation,
    ensureTrackingToken,
    getOperationRequirements,
    listOperations,
    overrideOperationStatus,
    transitionOperationStatus,
} from '@/services/operations.service';
import { useAuthStore } from '@/store/authStore';
import type { Operation } from '@/types/operations';

const OperationsPage = () => {
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const getRole = useAuthStore((state) => state.getRole);
    const role = getRole();
    const isViewer = role === 'viewer';
    const isAdmin = role === 'admin';
    const [searchParams, setSearchParams] = useSearchParams();

    const viewParam = searchParams.get('view');
    const view: OperationsView = isOperationsView(viewParam) ? viewParam : 'active';
    const statusParam = searchParams.get('status') ?? '';
    const status = statusParam in OPERATION_STATUS_META ? statusParam : '';
    const query = searchParams.get('q') ?? '';
    const selectedParam = searchParams.get('operation');

    const [operations, setOperations] = useState<Operation[]>([]);
    const [loading, setLoading] = useState(true);
    const [loadError, setLoadError] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [createError, setCreateError] = useState<string | null>(null);
    const [showNewModal, setShowNewModal] = useState(false);
    const [showAssignmentDrawer, setShowAssignmentDrawer] = useState(false);

    const [isGeneratingTokens, setIsGeneratingTokens] = useState(false);
    const [driverToken, setDriverToken] = useState<string | null>(null);
    const [publicToken, setPublicToken] = useState<string | null>(null);
    const [copiedStatus, setCopiedStatus] = useState<'driver' | 'public' | null>(null);
    const [dbHasDriverToken, setDbHasDriverToken] = useState<boolean | null>(null);
    const [dbHasPublicToken, setDbHasPublicToken] = useState<boolean | null>(null);
    const [isCheckingTokens, setIsCheckingTokens] = useState(false);

    const [newOpRef, setNewOpRef] = useState('');
    const [newOpClient, setNewOpClient] = useState('');
    const [isTransitioning, setIsTransitioning] = useState(false);
    const [transitionError, setTransitionError] = useState<string | null>(null);
    const [isEnsuringToken, setIsEnsuringToken] = useState(false);
    const [showOverrideModal, setShowOverrideModal] = useState(false);
    const [overrideReason, setOverrideReason] = useState('');
    const [isOverriding, setIsOverriding] = useState(false);

    const filteredOperations = useMemo(
        () => filterOperations(operations, view, status, query),
        [operations, query, status, view],
    );
    const activeOp = filteredOperations.find((operation) => operation.id === selectedParam)
        ?? filteredOperations[0]
        ?? null;

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

    useEffect(() => {
        if (loading) return;

        if (activeOp && activeOp.id !== selectedParam) {
            updateParams({ operation: activeOp.id });
        } else if (!activeOp && selectedParam) {
            updateParams({ operation: null });
        }
    }, [activeOp, loading, selectedParam, updateParams]);

    useEffect(() => {
        if (!activeOp?.db_id) {
            setDbHasDriverToken(null);
            setDbHasPublicToken(null);
            setDriverToken(null);
            setPublicToken(null);
            setIsCheckingTokens(false);
            return;
        }

        let cancelled = false;
        setIsCheckingTokens(true);
        setDriverToken(null);
        setPublicToken(null);
        setCopiedStatus(null);
        getOperationRequirements(activeOp.db_id)
            .then((requirements) => {
                if (!cancelled) {
                    setDbHasDriverToken(requirements.has_driver_token);
                    setDbHasPublicToken(requirements.has_public_token);
                }
            })
            .catch(() => {
                if (!cancelled) {
                    setDbHasDriverToken(null);
                    setDbHasPublicToken(null);
                }
            })
            .finally(() => {
                if (!cancelled) setIsCheckingTokens(false);
            });

        return () => {
            cancelled = true;
        };
    }, [activeOp?.db_id]);

    const handleCreate = async (event: FormEvent) => {
        event.preventDefault();
        if (!activeTenant || !newOpRef.trim()) return;

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
        if (!activeTenant || !activeOp?.db_id) return;

        setIsGeneratingTokens(true);
        setTransitionError(null);
        try {
            const [driverResponse, publicResponse] = await Promise.all([
                supabase.rpc('rpc_create_tracking_token', {
                    p_tenant_id: activeTenant,
                    p_operation_id: activeOp.db_id,
                    p_scope: 'driver:write',
                    p_force_rotate: true,
                }),
                supabase.rpc('rpc_create_tracking_token', {
                    p_tenant_id: activeTenant,
                    p_operation_id: activeOp.db_id,
                    p_scope: 'public:read',
                    p_force_rotate: true,
                }),
            ]);

            if (driverResponse.error) throw driverResponse.error;
            if (publicResponse.error) throw publicResponse.error;
            if (driverResponse.data?.error) throw new Error(driverResponse.data.error);
            if (publicResponse.data?.error) throw new Error(publicResponse.data.error);

            setDriverToken(driverResponse.data?.token ?? null);
            setPublicToken(publicResponse.data?.token ?? null);
            setDbHasDriverToken(true);
            setDbHasPublicToken(true);
        } catch (error) {
            console.error('Failed to generate tracking tokens:', error);
            setTransitionError('No fue posible generar los enlaces de tracking.');
        } finally {
            setIsGeneratingTokens(false);
        }
    };

    const handleCopyToken = (type: 'driver' | 'public') => {
        const literal = type === 'driver' ? driverToken : publicToken;
        if (!literal) return;

        const path = type === 'driver' ? '/driver/' : '/t/';
        const url = `${window.location.origin}${path}${literal}`;
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
        if (!activeOp?.db_id) return;

        setIsTransitioning(true);
        setTransitionError(null);
        try {
            if (toStatus === 'in_transit' && activeTenant) {
                setIsEnsuringToken(true);
                const tokenResult = await ensureTrackingToken(activeTenant, activeOp.db_id);
                if (tokenResult.error) throw new Error(`No fue posible preparar el tracking: ${tokenResult.error}`);
            }
            await transitionOperationStatus(activeOp.db_id, toStatus);
            await fetchOps();
        } catch (error) {
            setTransitionError(error instanceof Error ? error.message : 'No fue posible cambiar el estado.');
        } finally {
            setIsTransitioning(false);
            setIsEnsuringToken(false);
        }
    };

    const handleOverrideCancel = async (event: FormEvent) => {
        event.preventDefault();
        if (!activeOp?.db_id || overrideReason.trim().length < 10) return;

        setIsOverriding(true);
        setTransitionError(null);
        try {
            await overrideOperationStatus(activeOp.db_id, 'cancelled', overrideReason.trim());
            setShowOverrideModal(false);
            setOverrideReason('');
            await fetchOps();
        } catch (error) {
            setTransitionError(error instanceof Error ? error.message : 'No fue posible cancelar administrativamente.');
        } finally {
            setIsOverriding(false);
        }
    };

    const clearFilters = () => updateParams({ view: 'active', status: null, q: null, operation: null });

    return (
        <div className="relative space-y-5">
            <PageHeader
                title="Control Center"
                subtitle="Bandeja diaria de operaciones y ejecución logística contratada"
                actions={(
                    <>
                        <button
                            type="button"
                            onClick={() => void fetchOps()}
                            disabled={loading}
                            className="flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-3.5 py-2.5 text-xs font-bold text-slate-600 transition hover:bg-slate-50 disabled:opacity-50"
                        >
                            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                            <span className="hidden sm:inline">Actualizar</span>
                        </button>
                        {!isViewer && (
                            <button
                                type="button"
                                onClick={() => { setCreateError(null); setShowNewModal(true); }}
                                className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white shadow-md shadow-primary/20 transition hover:bg-primary-dark"
                            >
                                <Plus size={15} /> Nueva operación
                            </button>
                        )}
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
                        onViewChange={(nextView) => updateParams({ view: nextView, operation: null })}
                        onStatusChange={(nextStatus) => updateParams({ status: nextStatus || null, operation: null })}
                        onQueryChange={(nextQuery) => updateParams({ q: nextQuery || null, operation: null })}
                        onClear={clearFilters}
                    />

                    {filteredOperations.length === 0 ? (
                        <section className="rounded-2xl border border-dashed border-slate-300 bg-white p-10 text-center">
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
                        <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1.8fr)_minmax(340px,0.9fr)]">
                            <OperationsTable
                                operations={filteredOperations}
                                selectedId={activeOp?.id ?? null}
                                onSelect={(operation) => updateParams({ operation: operation.id })}
                            />
                            {activeOp && (
                                <OperationQuickPanel
                                    operation={activeOp}
                                    isViewer={isViewer}
                                    isAdmin={isAdmin}
                                    dbHasDriverToken={dbHasDriverToken}
                                    dbHasPublicToken={dbHasPublicToken}
                                    isCheckingTokens={isCheckingTokens}
                                    isGeneratingTokens={isGeneratingTokens}
                                    driverToken={driverToken}
                                    publicToken={publicToken}
                                    copiedStatus={copiedStatus}
                                    transitionError={transitionError}
                                    isTransitioning={isTransitioning}
                                    isEnsuringToken={isEnsuringToken}
                                    onGenerateTokens={() => void handleGenerateTokens()}
                                    onCopyToken={handleCopyToken}
                                    onAssign={() => setShowAssignmentDrawer(true)}
                                    onTransition={(nextStatus) => void handleTransition(nextStatus)}
                                    onOverrideCancel={() => { setTransitionError(null); setShowOverrideModal(true); }}
                                />
                            )}
                        </div>
                    )}
                </>
            )}

            {showOverrideModal && activeOp && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4 backdrop-blur-sm">
                    <motion.div initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
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

            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4 backdrop-blur-sm">
                    <motion.div initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Nueva operación</h2>
                                <p className="mt-0.5 text-xs text-slate-400">Alta básica con el contrato frontend vigente.</p>
                            </div>
                            <button type="button" onClick={() => setShowNewModal(false)} className="rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600"><X size={17} /></button>
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
                isOpen={showAssignmentDrawer}
                onClose={() => setShowAssignmentDrawer(false)}
                operation={activeOp}
                onAssigned={() => {
                    setShowAssignmentDrawer(false);
                    void fetchOps();
                }}
            />
        </div>
    );
};

export default OperationsPage;
