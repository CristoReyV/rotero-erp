import React, { useState, useEffect } from 'react';
import { Filter, Plus, FileText, ShieldCheck, MapPin, Clock, Share2, Link as LinkIcon, Loader2, Copy, Check, Calendar, ArrowRightCircle, CheckCircle2, Ban, AlertTriangle, Radio, Navigation } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { Badge } from '@/components/Badge';
import { useAuthStore } from '@/store/authStore';
import { listOperations, createOperation, transitionOperationStatus, overrideOperationStatus, ensureTrackingToken, getOperationRequirements } from '@/services/operations.service';
import { listRoutePoints, computeRouteStats, getTimeRangeStart } from '@/services/trackingRoute.service';
import type { Operation } from '@/types/operations';
import type { RoutePoint, RouteStats, RouteTimeRange } from '@/types/tracking';
import { MOCK_TIMELINE } from '@/mocks/timeline.mock';
import { supabase } from '@/lib/supabase';
import { AssignmentDrawer } from '@/components/operations/AssignmentDrawer';

const getTimelineDotStyle = (step: typeof MOCK_TIMELINE[0]) => {
    if (step.done) return 'bg-emerald-500 ring-4 ring-emerald-500/20';
    if (step.current) return 'bg-primary ring-4 ring-primary/20 animate-pulse-dot';
    return 'bg-slate-200 ring-4 ring-slate-100';
};

const OperationsPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';
    const isAdmin = getRole() === 'admin';

    const [operations, setOperations] = useState<Operation[]>([]);
    const [loading, setLoading] = useState(true);
    const [selected, setSelected] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [showNewModal, setShowNewModal] = useState(false);
    const [showAssignmentDrawer, setShowAssignmentDrawer] = useState(false);

    // Tracking Link Generation State (Demostración)
    const [isGeneratingTokens, setIsGeneratingTokens] = useState(false);
    const [driverToken, setDriverToken] = useState<string | null>(null);
    const [publicToken, setPublicToken] = useState<string | null>(null);
    const [copiedStatus, setCopiedStatus] = useState<'driver' | 'public' | null>(null);

    // Tracking state (Check DB)
    const [dbHasDriverToken, setDbHasDriverToken] = useState<boolean | null>(null);
    const [dbHasPublicToken, setDbHasPublicToken] = useState<boolean | null>(null);
    const [isCheckingTokens, setIsCheckingTokens] = useState(false);

    // Form state basic
    const [newOpRef, setNewOpRef] = useState('');
    const [newOpClient, setNewOpClient] = useState('');

    // Workflow state
    const [isTransitioning, setIsTransitioning] = useState(false);
    const [transitionError, setTransitionError] = useState<string | null>(null);
    const [isEnsuringToken, setIsEnsuringToken] = useState(false);

    // Route v1 + Sprint A state
    const [routePoints, setRoutePoints] = useState<RoutePoint[]>([]);
    const [isLoadingRoute, setIsLoadingRoute] = useState(false);
    const [showRoutePath, setShowRoutePath] = useState(false);
    const [routeTimeRange, setRouteTimeRange] = useState<RouteTimeRange>('all');
    const [routeStats, setRouteStats] = useState<RouteStats | null>(null);

    // Override Modal State
    const [showOverrideModal, setShowOverrideModal] = useState(false);
    const [overrideReason, setOverrideReason] = useState('');
    const [isOverriding, setIsOverriding] = useState(false);

    const activeOp = operations.find((o) => o.id === selected);

    const fetchOps = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await listOperations(activeTenant);
            setOperations(data);
            if (!selected && data.length > 0) {
                setSelected(data[0].id);
            }
        } catch (err) {
            console.error('Failed to load operations:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchOps();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    // Check tracking token status when active operation changes
    useEffect(() => {
        if (!activeOp?.db_id) {
            setDbHasDriverToken(null);
            setDbHasPublicToken(null);
            setDriverToken(null);
            setPublicToken(null);
            return;
        }
        let cancelled = false;
        setIsCheckingTokens(true);
        getOperationRequirements(activeOp.db_id)
            .then(reqs => {
                if (!cancelled) {
                    setDbHasDriverToken(reqs.has_driver_token);
                    setDbHasPublicToken(reqs.has_public_token);
                }
            })
            .catch(() => {
                if (!cancelled) {
                    setDbHasDriverToken(null);
                    setDbHasPublicToken(null);
                }
            })
            .finally(() => { if (!cancelled) setIsCheckingTokens(false); });

        // Clean literals from previous operation
        setDriverToken(null);
        setPublicToken(null);

        return () => { cancelled = true; };
    }, [activeOp?.db_id]);

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !newOpRef) return;
        setIsCreating(true);
        try {
            await createOperation(activeTenant, {
                reference_code: newOpRef,
                client_display_name: newOpClient,
                status: 'planned'
            });
            setShowNewModal(false);
            setNewOpRef('');
            setNewOpClient('');
            await fetchOps();
        } catch (err) {
            console.error(err);
        } finally {
            setIsCreating(false);
        }
    };

    const handleGenerateTokens = async () => {
        if (!activeTenant || !activeOp?.db_id) return;
        setIsGeneratingTokens(true);
        try {
            // Generate both tokens with force_rotate: true to get literals
            const [driverRes, publicRes] = await Promise.all([
                supabase.rpc('rpc_create_tracking_token', {
                    p_tenant_id: activeTenant,
                    p_operation_id: activeOp.db_id,
                    p_scope: 'driver:write',
                    p_force_rotate: true
                }),
                supabase.rpc('rpc_create_tracking_token', {
                    p_tenant_id: activeTenant,
                    p_operation_id: activeOp.db_id,
                    p_scope: 'public:read',
                    p_force_rotate: true
                })
            ]);

            if (driverRes.error) throw driverRes.error;
            if (publicRes.error) throw publicRes.error;

            if (driverRes.data?.token) setDriverToken(driverRes.data.token);
            if (publicRes.data?.token) setPublicToken(publicRes.data.token);

            // Update DB check state
            setDbHasDriverToken(true);
            setDbHasPublicToken(true);

        } catch (err) {
            console.error('Error generating demo tokens:', err);
        } finally {
            setIsGeneratingTokens(false);
        }
    };

    const handleCopyToken = (type: 'driver' | 'public') => {
        const tokenLiteral = type === 'driver' ? driverToken : publicToken;
        if (!tokenLiteral) return;

        const path = type === 'driver' ? '/driver/' : '/t/';
        const origin = window.location.origin;
        const fullUrl = `${origin}${path}${tokenLiteral}`;

        // Fallback approach if navigator.clipboard is unavailable
        try {
            navigator.clipboard.writeText(fullUrl).then(() => {
                setCopiedStatus(type);
                setTimeout(() => setCopiedStatus(null), 2000);
            }).catch(() => {
                // Secondary fallback: prompt or modal
                alert(`URL: ${fullUrl}`);
            });
        } catch {
            alert(`URL: ${fullUrl}`);
        }
    };

    const handleTransition = async (toStatus: string) => {
        if (!activeOp?.db_id) return;
        setIsTransitioning(true);
        setTransitionError(null);
        try {
            // For in_transit: ensure tracking token exists (belt + suspenders with DB auto-provision)
            if (toStatus === 'in_transit' && activeTenant) {
                setIsEnsuringToken(true);
                const tokenResult = await ensureTrackingToken(activeTenant, activeOp.db_id);
                setIsEnsuringToken(false);
                if (tokenResult.error) {
                    setTransitionError(`Error creando token de tracking: ${tokenResult.error}`);
                    setIsTransitioning(false);
                    return;
                }
            }
            await transitionOperationStatus(activeOp.db_id, toStatus);
            await fetchOps();
            setDbHasDriverToken(null); // Reset for fresh check
            setDbHasPublicToken(null);
        } catch (err: any) {
            setTransitionError(err.message || 'Error al cambiar estado');
        } finally {
            setIsTransitioning(false);
            setIsEnsuringToken(false);
        }
    };

    const handleOverrideCancel = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeOp?.db_id || overrideReason.length < 10) return;
        setIsOverriding(true);
        setTransitionError(null);
        try {
            await overrideOperationStatus(activeOp.db_id, 'cancelled', overrideReason);
            setShowOverrideModal(false);
            setOverrideReason('');
            await fetchOps();
        } catch (err: any) {
            setTransitionError(err.message || 'Error en override');
        } finally {
            setIsOverriding(false);
        }
    };

    return (
        <div className="space-y-5 relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Operaciones</h1>
                    <p className="text-sm text-slate-400 mt-0.5">{operations.length} operaciones activas</p>
                </div>
                <div className="flex items-center gap-2">
                    <button className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Filter size={14} /> Filtros
                    </button>
                    {!isViewer && (
                        <button
                            onClick={() => setShowNewModal(true)}
                            className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all"
                        >
                            <Plus size={14} /> Nueva P.O.
                        </button>
                    )}
                </div>
            </div>

            {/* Split view */}
            <div className="grid grid-cols-1 lg:grid-cols-5 gap-5">
                {/* Left – Operations list */}
                <div className="lg:col-span-3 bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden">
                    <div className="overflow-x-auto min-h-[300px]">
                        {loading ? (
                            <div className="flex items-center justify-center h-48">
                                <Loader2 className="animate-spin text-slate-400" size={24} />
                            </div>
                        ) : (
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60">
                                        <th className="px-5 py-3">Referencia</th>
                                        <th className="px-5 py-3">Cliente</th>
                                        <th className="px-5 py-3">Tipo</th>
                                        <th className="px-5 py-3">Estado</th>
                                        <th className="px-5 py-3">Ruta</th>
                                        <th className="px-5 py-3">Resp.</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-tech-border/40">
                                    {operations.map((op) => (
                                        <tr
                                            key={op.id}
                                            onClick={() => {
                                                setSelected(op.id);
                                                setDriverToken(null);
                                                setPublicToken(null);
                                            }}
                                            className={`cursor-pointer transition-all duration-200 ${selected === op.id
                                                ? 'bg-primary-50/60 border-l-3 border-l-primary'
                                                : 'hover:bg-slate-50/80'
                                                }`}
                                        >
                                            <td className="px-5 py-3.5 font-semibold text-primary text-[13px]">{op.id}</td>
                                            <td className="px-5 py-3.5 text-slate-600 text-[13px]">{op.client}</td>
                                            <td className="px-5 py-3.5 text-slate-400 text-xs">{op.type}</td>
                                            <td className="px-5 py-3.5"><Badge variant={op.variant}>{op.status}</Badge></td>
                                            <td className="px-5 py-3.5 text-slate-400 text-xs font-mono">{op.route}</td>
                                            <td className="px-5 py-3.5 text-slate-500 text-xs">{op.owner}</td>
                                        </tr>
                                    ))}
                                    {operations.length === 0 && (
                                        <tr>
                                            <td colSpan={6} className="px-5 py-8 text-center text-slate-400">
                                                No hay operaciones registradas en este tenant.
                                            </td>
                                        </tr>
                                    )}
                                </tbody>
                            </table>
                        )}
                    </div>
                </div>

                {/* Right – Detail panel */}
                <div className="lg:col-span-2">
                    <AnimatePresence mode="wait">
                        {activeOp && (
                            <motion.div
                                key={activeOp.id}
                                initial={{ opacity: 0, x: 20 }}
                                animate={{ opacity: 1, x: 0 }}
                                exit={{ opacity: 0, x: -20 }}
                                transition={{ duration: 0.2 }}
                                className="bg-surface-card rounded-2xl border border-tech-border/60 p-6 space-y-6"
                            >
                                {/* Header */}
                                <div>
                                    <div className="flex items-center gap-3 mb-3">
                                        <h3 className="text-lg font-bold text-slate-800">{activeOp.id}</h3>
                                        <Badge variant={activeOp.variant}>{activeOp.status}</Badge>
                                    </div>
                                    <p className="text-sm text-slate-500">{activeOp.client}</p>
                                    <div className="flex items-center gap-2 mt-2">
                                        <MapPin size={13} className="text-slate-300" />
                                        <span className="text-xs text-slate-400 font-mono">{activeOp.route}</span>
                                    </div>

                                    {transitionError && (
                                        <div className="mt-3 p-3 bg-red-50 text-red-600 border border-red-200 rounded-xl text-xs font-semibold flex items-center gap-2">
                                            <AlertTriangle size={14} className="shrink-0" />
                                            <span>{transitionError}</span>
                                        </div>
                                    )}
                                </div>

                                {/* Demo Tracking Links Section */}
                                <div className="p-5 bg-slate-50 border border-slate-200 rounded-2xl shadow-sm">
                                    <div className="flex items-center justify-between mb-4">
                                        <h4 className="text-sm font-bold text-slate-800 flex items-center gap-2">
                                            <Share2 size={16} className="text-primary" />
                                            Enlaces para demo
                                        </h4>
                                        <div className="flex items-center gap-1.5 animate-pulse bg-emerald-50 px-2.5 py-1 rounded-lg border border-emerald-100">
                                            <Radio size={12} className="text-emerald-500" />
                                            <span className="text-[10px] font-bold text-emerald-600 uppercase tracking-tight">Real-Time Tokens</span>
                                        </div>
                                    </div>

                                    <div className="space-y-3">
                                        {/* Public Tracking Link */}
                                        <div className="bg-white p-3 rounded-xl border border-slate-200 hover:border-primary/20 transition-all shadow-subtle group">
                                            <div className="flex items-center justify-between mb-2">
                                                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Tracking Público</span>
                                                {dbHasPublicToken ? (
                                                    <span className="text-[10px] font-bold text-emerald-500 flex items-center gap-1">
                                                        <CheckCircle2 size={10} /> Link Activo
                                                    </span>
                                                ) : (
                                                    <span className="text-[10px] font-bold text-slate-400">Token pendiente...</span>
                                                )}
                                            </div>
                                            <div className="flex items-center gap-2">
                                                <div className="bg-slate-50 flex-1 truncate text-xs text-slate-500 font-mono py-2 px-3 rounded-lg border border-slate-100">
                                                    {publicToken ? `${window.location.origin}/t/${publicToken.substring(0, 8)}...` : dbHasPublicToken ? '••••••••' : 'N/A'}
                                                </div>
                                                <button
                                                    onClick={() => handleCopyToken('public')}
                                                    disabled={!publicToken}
                                                    className={`p-2 rounded-lg transition-all ${publicToken
                                                        ? 'bg-primary/10 text-primary hover:bg-primary hover:text-white shadow-md'
                                                        : 'bg-slate-100 text-slate-300 cursor-not-allowed'
                                                        }`}
                                                    title={publicToken ? 'Copiar URL Cliente' : 'Genera tokens primero'}
                                                >
                                                    {copiedStatus === 'public' ? <CheckCircle2 size={15} /> : <Copy size={15} />}
                                                </button>
                                            </div>
                                        </div>

                                        {/* Driver Tracking Link */}
                                        <div className="bg-white p-3 rounded-xl border border-slate-200 hover:border-primary/20 transition-all shadow-subtle group">
                                            <div className="flex items-center justify-between mb-2">
                                                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Link Operador (Simulador)</span>
                                                {dbHasDriverToken ? (
                                                    <span className="text-[10px] font-bold text-sky-500 flex items-center gap-1">
                                                        <Navigation size={10} /> Link Activo
                                                    </span>
                                                ) : (
                                                    <span className="text-[10px] font-bold text-slate-400">Token pendiente...</span>
                                                )}
                                            </div>
                                            <div className="flex items-center gap-2">
                                                <div className="bg-slate-50 flex-1 truncate text-xs text-slate-500 font-mono py-2 px-3 rounded-lg border border-slate-100">
                                                    {driverToken ? `${window.location.origin}/driver/${driverToken.substring(0, 8)}...` : dbHasDriverToken ? '••••••••' : 'N/A'}
                                                </div>
                                                <button
                                                    onClick={() => handleCopyToken('driver')}
                                                    disabled={!driverToken}
                                                    className={`p-2 rounded-lg transition-all ${driverToken
                                                        ? 'bg-sky-50 text-sky-600 hover:bg-sky-500 hover:text-white shadow-md'
                                                        : 'bg-slate-100 text-slate-300 cursor-not-allowed'
                                                        }`}
                                                    title={driverToken ? 'Copiar URL Chofer' : 'Genera tokens primero'}
                                                >
                                                    {copiedStatus === 'driver' ? <CheckCircle2 size={15} /> : <Copy size={15} />}
                                                </button>
                                            </div>
                                        </div>

                                        {/* Generation Button (Visible to admins/operators) */}
                                        {!isViewer && (
                                            <button
                                                onClick={handleGenerateTokens}
                                                disabled={isGeneratingTokens}
                                                className="w-full mt-2 py-3 flex items-center justify-center gap-2 gradient-accent text-white rounded-xl text-xs font-bold shadow-lg shadow-accent-red/20 active:scale-95 transition-all disabled:opacity-50"
                                            >
                                                {isGeneratingTokens ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />}
                                                {dbHasPublicToken || dbHasDriverToken ? 'REGENERAR TOKENS (ROTAR)' : 'GENERAR TOKENS DE TRACKING'}
                                            </button>
                                        )}
                                        {isViewer && !publicToken && !driverToken && (
                                            <p className="text-[10px] text-center text-slate-400 italic">
                                                * Los tokens deben ser generados por un administrador.
                                            </p>
                                        )}
                                    </div>
                                </div>

                                {/* Quick info */}
                                <div className="grid grid-cols-2 gap-3">
                                    <div className="p-3.5 bg-surface rounded-xl border border-tech-border/40">
                                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Tipo carga</p>
                                        <p className="text-sm font-bold text-slate-700 mt-1">{activeOp.type}</p>
                                    </div>
                                    <div className="p-3.5 bg-surface rounded-xl border border-tech-border/40">
                                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Responsable</p>
                                        <p className="text-sm font-bold text-slate-700 mt-1">{activeOp.owner}</p>
                                    </div>
                                </div>

                                {/* Tracking Status Indicator */}
                                {activeOp.status === 'assigned' && (
                                    <div className="p-3.5 bg-surface rounded-xl border border-tech-border/40 flex items-center justify-between">
                                        <div className="flex items-center gap-2">
                                            <Radio size={14} className={dbHasDriverToken ? 'text-emerald-500' : 'text-amber-500'} />
                                            <span className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">Tracking</span>
                                        </div>
                                        {dbHasDriverToken === null ? (
                                            <span className="text-[11px] font-medium text-slate-400">Verificando...</span>
                                        ) : dbHasDriverToken ? (
                                            <Badge variant="success">Activo</Badge>
                                        ) : (
                                            <Badge variant="warning">Pendiente — se crea al iniciar ruta</Badge>
                                        )}
                                    </div>
                                )}

                                {/* Route v1 + Sprint A — GPS polyline preview */}
                                {(activeOp.status === 'in_transit' || activeOp.status === 'delivered') && (
                                    <div className="bg-surface rounded-xl border border-tech-border/40 overflow-hidden">
                                        <button
                                            onClick={() => {
                                                setShowRoutePath(!showRoutePath);
                                                if (!showRoutePath && routePoints.length === 0) {
                                                    setIsLoadingRoute(true);
                                                    listRoutePoints(activeOp.id, getTimeRangeStart(routeTimeRange)).then(pts => {
                                                        setRoutePoints(pts);
                                                        setRouteStats(computeRouteStats(pts));
                                                        setIsLoadingRoute(false);
                                                    }).catch(() => setIsLoadingRoute(false));
                                                }
                                            }}
                                            className="w-full p-3.5 flex items-center justify-between hover:bg-slate-50/50 transition-colors"
                                        >
                                            <div className="flex items-center gap-2">
                                                <Navigation size={14} className="text-blue-500" />
                                                <span className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">Ruta GPS</span>
                                            </div>
                                            <Badge variant={routePoints.length > 0 ? 'success' : 'default'}>
                                                {routePoints.length > 0 ? `${routePoints.length} puntos` : 'Ver ruta'}
                                            </Badge>
                                        </button>
                                        {showRoutePath && (
                                            <div className="px-3.5 pb-3.5 space-y-2">
                                                {/* Sprint A: Time range selector */}
                                                <div className="flex gap-1 bg-slate-100 rounded-lg p-0.5">
                                                    {([['30m', '30 min'], ['1h', '1 hora'], ['all', 'Toda']] as const).map(([val, label]) => (
                                                        <button
                                                            key={val}
                                                            onClick={() => {
                                                                setRouteTimeRange(val);
                                                                setIsLoadingRoute(true);
                                                                listRoutePoints(activeOp.id, getTimeRangeStart(val)).then(pts => {
                                                                    setRoutePoints(pts);
                                                                    setRouteStats(computeRouteStats(pts));
                                                                    setIsLoadingRoute(false);
                                                                }).catch(() => setIsLoadingRoute(false));
                                                            }}
                                                            className={`flex-1 py-1 text-[10px] font-bold rounded-md transition-all ${routeTimeRange === val
                                                                ? 'bg-white text-blue-600 shadow-sm'
                                                                : 'text-slate-500 hover:text-slate-700'
                                                                }`}
                                                        >
                                                            {label}
                                                        </button>
                                                    ))}
                                                </div>

                                                {isLoadingRoute ? (
                                                    <div className="flex items-center justify-center py-6 text-slate-400">
                                                        <Loader2 size={16} className="animate-spin mr-2" />
                                                        <span className="text-xs">Cargando ruta...</span>
                                                    </div>
                                                ) : routePoints.length === 0 ? (
                                                    <div className="text-center py-6 text-slate-400">
                                                        <MapPin size={20} className="mx-auto mb-2 opacity-40" />
                                                        <p className="text-xs">Sin ruta registrada aún</p>
                                                    </div>
                                                ) : (
                                                    <>
                                                        <div className="bg-slate-50 rounded-lg p-2 border border-slate-100">
                                                            <svg viewBox="0 0 300 120" className="w-full h-auto">
                                                                {(() => {
                                                                    const lats = routePoints.map(p => p.lat);
                                                                    const lngs = routePoints.map(p => p.lng);
                                                                    const minLat = Math.min(...lats);
                                                                    const maxLat = Math.max(...lats);
                                                                    const minLng = Math.min(...lngs);
                                                                    const maxLng = Math.max(...lngs);
                                                                    const padLat = (maxLat - minLat) * 0.15 || 0.01;
                                                                    const padLng = (maxLng - minLng) * 0.15 || 0.01;
                                                                    const pts = routePoints.map(p => {
                                                                        const x = 15 + ((p.lng - (minLng - padLng)) / ((maxLng + padLng) - (minLng - padLng))) * 270;
                                                                        const y = 105 - ((p.lat - (minLat - padLat)) / ((maxLat + padLat) - (minLat - padLat))) * 90;
                                                                        return `${x},${y}`;
                                                                    });
                                                                    const fCoords = pts[0].split(',');
                                                                    const lCoords = pts[pts.length - 1].split(',');
                                                                    return (
                                                                        <>
                                                                            <polyline
                                                                                points={pts.join(' ')}
                                                                                fill="none"
                                                                                stroke="#3b82f6"
                                                                                strokeWidth="2.5"
                                                                                strokeLinecap="round"
                                                                                strokeLinejoin="round"
                                                                                opacity="0.8"
                                                                            />
                                                                            <circle cx={fCoords[0]} cy={fCoords[1]} r="4" fill="#22c55e" stroke="white" strokeWidth="1.5" />
                                                                            <circle cx={lCoords[0]} cy={lCoords[1]} r="4" fill="#ef4444" stroke="white" strokeWidth="1.5" />
                                                                            <text x={Number(fCoords[0]) + 6} y={Number(fCoords[1]) + 3} fill="#22c55e" fontSize="7" fontWeight="bold">Inicio</text>
                                                                            <text x={Number(lCoords[0]) + 6} y={Number(lCoords[1]) + 3} fill="#ef4444" fontSize="7" fontWeight="bold">Actual</text>
                                                                        </>
                                                                    );
                                                                })()}
                                                            </svg>
                                                        </div>

                                                        {/* Sprint A: Route stats bar */}
                                                        {routeStats && (
                                                            <div className="flex items-center justify-center gap-3 text-[10px] text-slate-500 font-medium">
                                                                <span>📏 {routeStats.distanceKm} km</span>
                                                                <span className="text-slate-300">·</span>
                                                                <span>⏱ {routeStats.durationMin >= 60 ? `${Math.floor(routeStats.durationMin / 60)}h ${routeStats.durationMin % 60}m` : `${routeStats.durationMin}m`}</span>
                                                                <span className="text-slate-300">·</span>
                                                                <span>🚛 {routeStats.avgSpeedKmh} km/h</span>
                                                                <span className="text-slate-300">·</span>
                                                                <span>📍 {routeStats.pointCount} pts</span>
                                                            </div>
                                                        )}
                                                    </>
                                                )}
                                            </div>
                                        )}
                                    </div>
                                )}

                                {/* Timeline */}
                                <div>
                                    <h4 className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-4">Línea de tiempo</h4>
                                    <div className="space-y-0">
                                        {MOCK_TIMELINE.map((step, idx) => (
                                            <div key={idx} className="flex gap-3.5">
                                                {/* Vertical line + dot */}
                                                <div className="flex flex-col items-center">
                                                    <div className={`w-3 h-3 rounded-full shrink-0 ${getTimelineDotStyle(step)}`} />
                                                    {idx < MOCK_TIMELINE.length - 1 && (
                                                        <div className={`w-px flex-1 my-1 ${step.done ? 'bg-emerald-300' : 'bg-slate-200'}`} />
                                                    )}
                                                </div>
                                                {/* Content */}
                                                <div className="pb-5 min-w-0">
                                                    <div className="flex items-center gap-2">
                                                        <p className={`text-[13px] font-semibold ${step.current ? 'text-primary' : step.done ? 'text-slate-700' : 'text-slate-400'}`}>
                                                            {step.event}
                                                        </p>
                                                    </div>
                                                    <p className="text-[11px] text-slate-400 mt-0.5">{step.desc}</p>
                                                    <p className="text-[10px] text-slate-300 mt-1 flex items-center gap-1">
                                                        <Clock size={10} /> {step.time}
                                                    </p>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>

                                {/* Actions */}
                                <div className="flex flex-col gap-2">
                                    <div className="flex flex-wrap gap-2">
                                        {(activeOp.status === 'draft' || activeOp.status === 'planned' || activeOp.status === 'assigned') && !isViewer && (
                                            <button
                                                onClick={() => setShowAssignmentDrawer(true)}
                                                className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-semibold shadow-sm transition-all"
                                            >
                                                <Calendar size={14} /> {activeOp.status === 'assigned' ? 'Editar Asignación' : 'Planificar y Asignar'}
                                            </button>
                                        )}
                                        {activeOp.status === 'assigned' && !isViewer && (
                                            <button
                                                onClick={() => handleTransition('in_transit')}
                                                disabled={isTransitioning}
                                                className="flex-1 flex items-center justify-center gap-2 py-2.5 gradient-primary text-white rounded-xl text-xs font-semibold shadow-md hover:shadow-lg transition-all disabled:opacity-50"
                                            >
                                                {isTransitioning ? <Loader2 size={14} className="animate-spin" /> : <ArrowRightCircle size={14} />}
                                                {isEnsuringToken ? 'Creando token...' : 'Iniciar Ruta'}
                                            </button>
                                        )}
                                        {activeOp.status === 'delivered' && !isViewer && (
                                            <button
                                                onClick={() => handleTransition('closed')}
                                                disabled={isTransitioning}
                                                className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-semibold shadow-md transition-all disabled:opacity-50"
                                            >
                                                {isTransitioning ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle2 size={14} />}
                                                Cerrar Operación
                                            </button>
                                        )}
                                    </div>
                                    <div className="flex flex-wrap gap-2">
                                        <button className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-slate-100 text-slate-700 rounded-xl text-xs font-semibold hover:bg-slate-200 transition-colors shadow-sm">
                                            <FileText size={14} /> Ver Docs
                                        </button>
                                        {(activeOp.status === 'draft' || activeOp.status === 'planned' || activeOp.status === 'assigned') && !isViewer && (
                                            <button
                                                onClick={() => handleTransition('cancelled')}
                                                disabled={isTransitioning}
                                                className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-red-50 hover:bg-red-100 text-red-700 rounded-xl text-xs font-semibold transition-all disabled:opacity-50"
                                            >
                                                <Ban size={14} /> Cancelar Normal
                                            </button>
                                        )}
                                        {(activeOp.status === 'in_transit' || activeOp.status === 'delivered') && isAdmin && (
                                            <button
                                                onClick={() => { setTransitionError(null); setShowOverrideModal(true); }}
                                                className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-red-600 hover:bg-red-700 text-white rounded-xl text-xs font-semibold shadow-sm transition-all"
                                            >
                                                <Ban size={14} /> Override Cancelation
                                            </button>
                                        )}
                                    </div>
                                </div>
                            </motion.div>
                        )}
                    </AnimatePresence>
                </div>
            </div>

            {/* Override Modal */}
            {showOverrideModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-md shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-red-100 bg-red-50 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-red-800 flex items-center gap-2">
                                <AlertTriangle size={18} /> Default Override
                            </h2>
                            <button onClick={() => setShowOverrideModal(false)} className="text-red-400 hover:text-red-600">✕</button>
                        </div>
                        <form onSubmit={handleOverrideCancel} className="p-6 space-y-4">
                            <div>
                                <p className="text-xs text-slate-600 mb-4 bg-slate-50 p-3 rounded-xl border border-slate-200">
                                    Estás a punto de forzar la cancelación de una operación en estado crítico (<span className="font-bold">{activeOp?.status}</span>). Esta acción quedará registrada en el log de auditoría del sistema de manera irreversible.
                                </p>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Razón del Override (Min 10 caracteres)</label>
                                <textarea
                                    required
                                    autoFocus
                                    minLength={10}
                                    maxLength={280}
                                    rows={3}
                                    value={overrideReason}
                                    onChange={(e) => setOverrideReason(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-red-500/20 focus:border-red-500 transition-all resize-none"
                                    placeholder="Explica detalladamente la razón de esta cancelación forzada..."
                                />
                            </div>

                            {transitionError && (
                                <div className="p-3 bg-red-50 text-red-600 border border-red-200 rounded-xl text-xs font-semibold flex items-center gap-2">
                                    <AlertTriangle size={14} className="shrink-0" />
                                    <span>{transitionError}</span>
                                </div>
                            )}

                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button
                                    type="button"
                                    onClick={() => setShowOverrideModal(false)}
                                    className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700"
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={isOverriding || overrideReason.length < 10}
                                    className="px-4 py-2 bg-red-600 text-white text-sm font-semibold rounded-lg shadow-sm disabled:opacity-50 flex items-center gap-2 hover:bg-red-700 transition"
                                >
                                    {isOverriding && <Loader2 size={14} className="animate-spin" />}
                                    Confirmar Override
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Simple Create Modal Overlay */}
            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-md shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Nueva Operación</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Referencia (Ej. OP-9001)</label>
                                <input
                                    required
                                    autoFocus
                                    type="text"
                                    value={newOpRef}
                                    onChange={(e) => setNewOpRef(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                    placeholder="Referencia única"
                                />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Cliente Principal</label>
                                <input
                                    type="text"
                                    value={newOpClient}
                                    onChange={(e) => setNewOpClient(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                    placeholder="Nombre del cliente (opcional)"
                                />
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button
                                    type="button"
                                    onClick={() => setShowNewModal(false)}
                                    className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700"
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={isCreating}
                                    className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg shadow-sm shadow-primary/20 disabled:opacity-50 flex items-center gap-2"
                                >
                                    {isCreating && <Loader2 size={14} className="animate-spin" />}
                                    Crear Operación
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Assignment Drawer */}
            <AssignmentDrawer
                isOpen={showAssignmentDrawer}
                onClose={() => setShowAssignmentDrawer(false)}
                operation={activeOp || null}
                onAssigned={() => {
                    setShowAssignmentDrawer(false);
                    fetchOps(); // Refetch after assigning
                }}
            />
        </div>
    );
};

export default OperationsPage;
