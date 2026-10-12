import { useCallback, useEffect, useMemo, useState } from 'react';
import {
    AlertCircle,
    Ban,
    CalendarClock,
    Check,
    CheckCircle2,
    Clipboard,
    ExternalLink,
    KeyRound,
    Loader2,
    MapPin,
    Navigation,
    Radio,
    ShieldCheck,
    Truck,
    UserRound,
} from 'lucide-react';
import { Badge } from '@/components/Badge';
import { computeRouteStats, getTimeRangeStart, listRoutePoints } from '@/services/trackingRoute.service';
import type { Operation } from '@/types/operations';
import type { RoutePoint, RouteStats, RouteTimeRange } from '@/types/tracking';
import { formatOperationDate, getOperationStatus, OPERATION_PROGRESS } from './operationsControl';

interface OperationQuickPanelProps {
    operation: Operation;
    canManageOperations: boolean;
    canViewTracking: boolean;
    canManageTracking: boolean;
    isAdmin: boolean;
    dbHasDriverToken: boolean | null;
    dbHasPublicToken: boolean | null;
    isCheckingTokens: boolean;
    isGeneratingTokens: boolean;
    driverToken: string | null;
    publicToken: string | null;
    copiedStatus: 'driver' | 'public' | null;
    transitionError: string | null;
    isTransitioning: boolean;
    isEnsuringToken: boolean;
    onGenerateTokens: () => void;
    onCopyToken: (type: 'driver' | 'public') => void;
    onAssign: () => void;
    onTransition: (status: string) => void;
    onOverrideCancel: () => void;
}

const WORKFLOW_LABELS: Record<string, string> = {
    draft: 'Borrador',
    planned: 'Planeación',
    assigned: 'Asignación',
    in_transit: 'En tránsito',
    delivered: 'Entrega',
    closed: 'Cierre',
};

function TokenRow({
    label,
    path,
    token,
    exists,
    isChecking,
    copied,
    onCopy,
}: {
    label: string;
    path: '/t/' | '/driver/';
    token: string | null;
    exists: boolean | null;
    isChecking: boolean;
    copied: boolean;
    onCopy: () => void;
}) {
    const stateLabel = isChecking
        ? 'Verificando…'
        : exists === true
            ? 'Activo'
            : exists === false
                ? 'No generado'
                : 'Estado no disponible';

    return (
        <div className="rounded-xl border border-slate-200 bg-slate-50/70 p-3">
            <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                    <p className="text-xs font-bold text-slate-700">{label}</p>
                    <p className="mt-0.5 text-[11px] text-slate-400">{stateLabel}</p>
                </div>
                <span className={`mt-0.5 h-2.5 w-2.5 shrink-0 rounded-full ${exists ? 'bg-emerald-500' : 'bg-slate-300'}`} />
            </div>
            <div className="mt-2 flex items-center gap-2 rounded-lg bg-white px-2.5 py-2 ring-1 ring-slate-200/70">
                <code className="min-w-0 flex-1 truncate text-[10px] text-slate-500">
                    {token ? `${path}${token.slice(0, 8)}…` : exists ? 'Token activo; literal no disponible' : 'Sin enlace disponible'}
                </code>
                <button
                    type="button"
                    onClick={onCopy}
                    disabled={!token}
                    title={token ? `Copiar enlace ${label.toLocaleLowerCase('es-MX')}` : 'El literal solo está disponible al generar o rotar'}
                    className="rounded-md p-1.5 text-slate-400 transition hover:bg-slate-100 hover:text-primary disabled:cursor-not-allowed disabled:opacity-35"
                >
                    {copied ? <Check size={14} className="text-emerald-600" /> : <Clipboard size={14} />}
                </button>
            </div>
        </div>
    );
}

function RoutePreview({ points }: { points: RoutePoint[] }) {
    const path = useMemo(() => {
        if (points.length < 2) return '';
        const lats = points.map((point) => point.lat);
        const lngs = points.map((point) => point.lng);
        const minLat = Math.min(...lats);
        const maxLat = Math.max(...lats);
        const minLng = Math.min(...lngs);
        const maxLng = Math.max(...lngs);
        const latRange = maxLat - minLat || 1;
        const lngRange = maxLng - minLng || 1;
        return points.map((point, index) => {
            const x = 12 + ((point.lng - minLng) / lngRange) * 176;
            const y = 68 - ((point.lat - minLat) / latRange) * 56;
            return `${index === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
        }).join(' ');
    }, [points]);

    if (!path) return null;

    return (
        <svg viewBox="0 0 200 80" role="img" aria-label="Trazo GPS registrado" className="h-28 w-full rounded-xl bg-slate-950 p-2">
            <path d={path} fill="none" stroke="#38bdf8" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
    );
}

function RouteSection({ operation }: { operation: Operation }) {
    const [showRoute, setShowRoute] = useState(false);
    const [range, setRange] = useState<RouteTimeRange>('all');
    const [points, setPoints] = useState<RoutePoint[]>([]);
    const [stats, setStats] = useState<RouteStats | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(false);

    const loadRoute = useCallback(async (nextRange: RouteTimeRange) => {
        setLoading(true);
        setError(false);
        try {
            const nextPoints = await listRoutePoints(operation.id, getTimeRangeStart(nextRange));
            setPoints(nextPoints);
            setStats(nextPoints.length > 1 ? computeRouteStats(nextPoints) : null);
        } catch {
            setPoints([]);
            setStats(null);
            setError(true);
        } finally {
            setLoading(false);
        }
    }, [operation.id]);

    useEffect(() => {
        setShowRoute(false);
        setRange('all');
        setPoints([]);
        setStats(null);
        setError(false);
    }, [operation.id]);

    const toggleRoute = () => {
        const next = !showRoute;
        setShowRoute(next);
        if (next && points.length === 0) void loadRoute(range);
    };

    const changeRange = (nextRange: RouteTimeRange) => {
        setRange(nextRange);
        void loadRoute(nextRange);
    };

    return (
        <section className="border-t border-slate-100 pt-5">
            <div className="flex items-center justify-between gap-3">
                <div>
                    <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400">Consulta de ruta GPS</h3>
                    <p className="mt-1 text-[11px] text-slate-400">Consulta bajo demanda; no representa GPS externo en tiempo real.</p>
                </div>
                <button type="button" onClick={toggleRoute} className="shrink-0 rounded-lg bg-sky-50 px-3 py-2 text-xs font-bold text-sky-700 hover:bg-sky-100">
                    {showRoute ? 'Ocultar' : 'Consultar'}
                </button>
            </div>

            {showRoute && (
                <div className="mt-4 space-y-3">
                    <div className="flex gap-2">
                        {(['30m', '1h', 'all'] as RouteTimeRange[]).map((item) => (
                            <button
                                key={item}
                                type="button"
                                onClick={() => changeRange(item)}
                                className={`rounded-lg px-2.5 py-1.5 text-[10px] font-bold ${range === item ? 'bg-primary text-white' : 'bg-slate-100 text-slate-500'}`}
                            >
                                {item === 'all' ? 'Todo' : item}
                            </button>
                        ))}
                    </div>
                    {loading ? (
                        <div className="flex h-28 items-center justify-center rounded-xl bg-slate-50 text-xs text-slate-400"><Loader2 size={16} className="mr-2 animate-spin" /> Consultando ruta</div>
                    ) : error ? (
                        <div className="rounded-xl bg-red-50 p-3 text-xs text-red-700">No fue posible consultar la ruta registrada.</div>
                    ) : points.length < 2 ? (
                        <div className="rounded-xl bg-slate-50 p-4 text-center text-xs text-slate-500">Aún no hay puntos suficientes para dibujar una ruta.</div>
                    ) : (
                        <>
                            <RoutePreview points={points} />
                            {stats && (
                                <div className="grid grid-cols-2 gap-2 text-center text-[10px] sm:grid-cols-4">
                                    <span className="rounded-lg bg-slate-50 p-2 text-slate-600"><b className="block text-slate-800">{stats.distanceKm} km</b>Distancia</span>
                                    <span className="rounded-lg bg-slate-50 p-2 text-slate-600"><b className="block text-slate-800">{stats.durationMin} min</b>Duración</span>
                                    <span className="rounded-lg bg-slate-50 p-2 text-slate-600"><b className="block text-slate-800">{stats.avgSpeedKmh} km/h</b>Promedio</span>
                                    <span className="rounded-lg bg-slate-50 p-2 text-slate-600"><b className="block text-slate-800">{stats.pointCount}</b>Puntos</span>
                                </div>
                            )}
                        </>
                    )}
                </div>
            )}
        </section>
    );
}

export function OperationQuickPanel({
    operation,
    canManageOperations,
    canViewTracking,
    canManageTracking,
    isAdmin,
    dbHasDriverToken,
    dbHasPublicToken,
    isCheckingTokens,
    isGeneratingTokens,
    driverToken,
    publicToken,
    copiedStatus,
    transitionError,
    isTransitioning,
    isEnsuringToken,
    onGenerateTokens,
    onCopyToken,
    onAssign,
    onTransition,
    onOverrideCancel,
}: OperationQuickPanelProps) {
    const status = getOperationStatus(operation.status);
    const currentStep = OPERATION_PROGRESS.indexOf(operation.status as typeof OPERATION_PROGRESS[number]);
    const canAssign = ['draft', 'planned', 'assigned'].includes(operation.status) && canManageOperations;
    const canCancel = ['draft', 'planned', 'assigned'].includes(operation.status) && canManageOperations;
    const canOverride = ['in_transit', 'delivered'].includes(operation.status) && isAdmin;
    const showRoute = ['in_transit', 'delivered', 'closed'].includes(operation.status);

    return (
        <aside className="overflow-hidden rounded-2xl border border-tech-border/60 bg-surface-card shadow-sm shadow-slate-200/30">
            <div className="border-b border-slate-100 bg-gradient-to-br from-slate-50 to-white p-5">
                <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                        <p className="text-[10px] font-bold uppercase tracking-widest text-slate-400">Consulta rápida</p>
                        <h2 className="mt-1 truncate text-lg font-bold text-slate-800">{operation.id}</h2>
                        <p className="mt-0.5 truncate text-sm font-medium text-slate-500">{operation.client}</p>
                    </div>
                    <Badge variant={status.variant}>{status.label}</Badge>
                </div>
            </div>

            <div className="space-y-5 p-5">
                <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
                    <div className="rounded-xl bg-slate-50 p-3">
                        <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400"><MapPin size={12} /> Ruta disponible</p>
                        <p className="mt-1.5 text-sm font-semibold text-slate-700">{operation.route || 'Datos por confirmar'}</p>
                        <p className="mt-1 text-xs text-slate-400">{operation.type || 'Sin resumen de ruta'}</p>
                    </div>
                    <div className="rounded-xl bg-slate-50 p-3">
                        <p className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-slate-400"><CalendarClock size={12} /> Salida planeada</p>
                        <p className="mt-1.5 text-sm font-semibold text-slate-700">{formatOperationDate(operation.planned_departure)}</p>
                        <p className="mt-1 text-xs text-slate-400">Prioridad: {operation.priority || 'no disponible'}</p>
                    </div>
                </section>

                <section>
                    <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400">Ejecución contratada</h3>
                    <p className="mt-1 text-[11px] text-slate-400">El contrato actual no expone un proveedor vinculado.</p>
                    <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
                        <div className="rounded-xl border border-slate-100 p-3">
                            <p className="flex items-center gap-2 text-xs font-bold text-slate-600"><ShieldCheck size={14} className="text-primary" /> Proveedor</p>
                            <p className="mt-1 text-xs text-slate-400">Proveedor por confirmar</p>
                        </div>
                        <div className="rounded-xl border border-slate-100 p-3">
                            <p className="flex items-center gap-2 text-xs font-bold text-slate-600"><UserRound size={14} className="text-primary" /> Operador del proveedor</p>
                            <p className="mt-1 text-xs text-slate-400">{operation.driver_name || 'Datos por confirmar'}</p>
                        </div>
                        <div className="rounded-xl border border-slate-100 p-3">
                            <p className="flex items-center gap-2 text-xs font-bold text-slate-600"><Truck size={14} className="text-primary" /> Unidad del proveedor</p>
                            <p className="mt-1 text-xs text-slate-400">{operation.vehicle_ref || 'Datos por confirmar'}</p>
                        </div>
                        <div className="rounded-xl border border-slate-100 p-3">
                            <p className="flex items-center gap-2 text-xs font-bold text-slate-600"><UserRound size={14} className="text-primary" /> Responsable</p>
                            <p className="mt-1 text-xs text-slate-400">Responsable no disponible</p>
                        </div>
                    </div>
                </section>

                <section className="border-t border-slate-100 pt-5">
                    <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400">Avance por estado</h3>
                    {operation.status === 'cancelled' ? (
                        <div className="mt-3 flex items-center gap-2 rounded-xl bg-red-50 p-3 text-xs font-semibold text-red-700"><Ban size={15} /> Operación cancelada</div>
                    ) : currentStep < 0 ? (
                        <div className="mt-3 rounded-xl bg-slate-50 p-3 text-xs text-slate-500">No hay una secuencia disponible para este estado.</div>
                    ) : (
                        <ol className="mt-4 grid grid-cols-3 gap-x-2 gap-y-4 sm:grid-cols-6 lg:grid-cols-3 2xl:grid-cols-6">
                            {OPERATION_PROGRESS.map((step, index) => {
                                const done = index < currentStep;
                                const current = index === currentStep;
                                return (
                                    <li key={step} className="min-w-0 text-center">
                                        <span className={`mx-auto flex h-7 w-7 items-center justify-center rounded-full text-[10px] font-bold ${done ? 'bg-emerald-100 text-emerald-700' : current ? 'bg-primary text-white ring-4 ring-primary/10' : 'bg-slate-100 text-slate-400'}`}>
                                            {done ? <Check size={13} /> : index + 1}
                                        </span>
                                        <span className={`mt-2 block truncate text-[9px] font-semibold ${current ? 'text-primary' : 'text-slate-400'}`}>{WORKFLOW_LABELS[step]}</span>
                                    </li>
                                );
                            })}
                        </ol>
                    )}
                    <p className="mt-3 text-[10px] text-slate-400">Secuencia derivada del estado actual; no representa eventos ni horas de auditoría.</p>
                </section>

                {canViewTracking && <section className="border-t border-slate-100 pt-5">
                    <div className="flex items-center justify-between gap-3">
                        <div>
                            <h3 className="flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-slate-400"><Radio size={13} /> Tracking</h3>
                            <p className="mt-1 text-[11px] text-slate-400">Estado de enlaces para esta operación.</p>
                        </div>
                        {(dbHasDriverToken || dbHasPublicToken) && <KeyRound size={17} className="text-emerald-500" />}
                    </div>
                    <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
                        <TokenRow label="Vista pública" path="/t/" token={publicToken} exists={dbHasPublicToken} isChecking={isCheckingTokens} copied={copiedStatus === 'public'} onCopy={() => onCopyToken('public')} />
                        <TokenRow label="Vista del operador" path="/driver/" token={driverToken} exists={dbHasDriverToken} isChecking={isCheckingTokens} copied={copiedStatus === 'driver'} onCopy={() => onCopyToken('driver')} />
                    </div>
                    {canManageTracking ? (
                        <button
                            type="button"
                            onClick={onGenerateTokens}
                            disabled={isGeneratingTokens || !operation.db_id}
                            className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl bg-slate-900 px-4 py-2.5 text-xs font-bold text-white transition hover:bg-slate-800 disabled:opacity-50"
                        >
                            {isGeneratingTokens ? <Loader2 size={14} className="animate-spin" /> : <ExternalLink size={14} />}
                            {dbHasDriverToken || dbHasPublicToken ? 'Rotar y obtener nuevos enlaces' : 'Generar enlaces de tracking'}
                        </button>
                    ) : (
                        <p className="mt-3 rounded-lg bg-slate-50 p-2.5 text-center text-[11px] text-slate-500">Consulta sin generación o rotación.</p>
                    )}
                </section>}

                {canViewTracking && showRoute && <RouteSection operation={operation} />}

                {transitionError && (
                    <div className="flex items-start gap-2 rounded-xl border border-red-200 bg-red-50 p-3 text-xs font-medium text-red-700">
                        <AlertCircle size={15} className="mt-0.5 shrink-0" /> {transitionError}
                    </div>
                )}

                {canManageOperations && (
                    <section className="border-t border-slate-100 pt-5">
                        <h3 className="text-xs font-bold uppercase tracking-widest text-slate-400">Acciones disponibles</h3>
                        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
                            {canAssign && (
                                <button type="button" onClick={onAssign} className="flex items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-xs font-bold text-white hover:bg-blue-700">
                                    <CalendarClock size={14} /> {operation.status === 'assigned' ? 'Editar asignación' : 'Planificar y asignar'}
                                </button>
                            )}
                            {operation.status === 'assigned' && (
                                <button type="button" onClick={() => onTransition('in_transit')} disabled={isTransitioning} className="flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white hover:bg-primary-dark disabled:opacity-50">
                                    {isTransitioning ? <Loader2 size={14} className="animate-spin" /> : <Navigation size={14} />} {isEnsuringToken ? 'Preparando tracking…' : 'Iniciar ruta'}
                                </button>
                            )}
                            {operation.status === 'delivered' && (
                                <button type="button" onClick={() => onTransition('closed')} disabled={isTransitioning} className="flex items-center justify-center gap-2 rounded-xl bg-emerald-600 px-4 py-2.5 text-xs font-bold text-white hover:bg-emerald-700 disabled:opacity-50">
                                    <CheckCircle2 size={14} /> Cerrar operación
                                </button>
                            )}
                            {canCancel && (
                                <button type="button" onClick={() => onTransition('cancelled')} disabled={isTransitioning} className="flex items-center justify-center gap-2 rounded-xl bg-red-50 px-4 py-2.5 text-xs font-bold text-red-700 hover:bg-red-100 disabled:opacity-50">
                                    <Ban size={14} /> Cancelar operación
                                </button>
                            )}
                            {canOverride && (
                                <button type="button" onClick={onOverrideCancel} className="flex items-center justify-center gap-2 rounded-xl bg-red-600 px-4 py-2.5 text-xs font-bold text-white hover:bg-red-700">
                                    <Ban size={14} /> Cancelación administrativa
                                </button>
                            )}
                        </div>
                    </section>
                )}

                {!canManageOperations && (
                    <div className="flex items-center gap-2 rounded-xl bg-slate-50 p-3 text-xs text-slate-500"><ShieldCheck size={15} /> Vista de solo lectura.</div>
                )}
            </div>
        </aside>
    );
}
