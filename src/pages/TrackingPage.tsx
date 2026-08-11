import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import {
    AlertTriangle,
    Copy,
    Link2,
    Loader2,
    MessageCircle,
    Plus,
    QrCode,
    RefreshCw,
    RotateCcw,
    Search,
    Share2,
    ShieldOff,
    X,
} from 'lucide-react';
import { Badge } from '@/components/Badge';
import { PageHeader } from '@/components/PageHeader';
import { listOperations } from '@/services/operations.service';
import {
    createTrackingToken,
    getTrackingErrorMessage,
    listTrackingTokens,
    revokeTrackingToken,
} from '@/services/trackingAdmin.service';
import {
    canManageTracking,
    createOneTimeTrackingLink,
    filterTrackingTokens,
    getScopeConfig,
    getTrackingDisplayState,
    TRACKING_SCOPE_OPTIONS,
    type OneTimeTrackingLink,
    type TrackingFilter,
    type TrackingScope,
    type TrackingTokenMetadata,
} from '@/services/trackingContracts';
import { useAuthStore } from '@/store/authStore';
import type { BadgeVariant } from '@/types/common';
import type { Operation } from '@/types/operations';

const FILTER_OPTIONS: ReadonlyArray<{ value: TrackingFilter; label: string }> = [
    { value: 'all', label: 'Todos' },
    { value: 'active', label: 'Activos' },
    { value: 'revoked', label: 'Revocados' },
    { value: 'expired', label: 'Expirados' },
    { value: 'public', label: 'Públicos' },
    { value: 'driver', label: 'Operador' },
];

const DISPLAY_STATES: Record<string, { label: string; badge: BadgeVariant }> = {
    active: { label: 'Activo', badge: 'success' },
    revoked: { label: 'Revocado', badge: 'danger' },
    expired: { label: 'Expirado', badge: 'warning' },
};

function formatDate(value: string | null): string {
    if (!value) return '—';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '—';
    return new Intl.DateTimeFormat('es-MX', {
        dateStyle: 'medium',
        timeStyle: 'short',
    }).format(date);
}

function scopeLabel(scope: TrackingScope): string {
    return scope === 'driver:write' ? 'Operador / chofer' : 'Público';
}

export default function TrackingPage() {
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const canManage = canManageTracking(role);

    const [tokens, setTokens] = useState<TrackingTokenMetadata[]>([]);
    const [operations, setOperations] = useState<Operation[]>([]);
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [query, setQuery] = useState('');
    const [filter, setFilter] = useState<TrackingFilter>('all');
    const [toast, setToast] = useState<string | null>(null);
    const [actionTokenId, setActionTokenId] = useState<string | null>(null);

    const [createOpen, setCreateOpen] = useState(false);
    const [operationId, setOperationId] = useState('');
    const [scope, setScope] = useState<TrackingScope>('public:read');
    const [ttlHours, setTtlHours] = useState(getScopeConfig('public:read').defaultTtlHours);
    const [submitting, setSubmitting] = useState(false);
    const [formError, setFormError] = useState<string | null>(null);
    const [oneTimeLink, setOneTimeLink] = useState<OneTimeTrackingLink | null>(null);

    const showToast = useCallback((message: string) => {
        setToast(message);
        window.setTimeout(() => setToast(null), 2500);
    }, []);

    const loadData = useCallback(async (asRefresh = false) => {
        if (!activeTenant) {
            setTokens([]);
            setOperations([]);
            setError('Selecciona un tenant para consultar Tracking.');
            setLoading(false);
            return;
        }

        if (asRefresh) setRefreshing(true);
        else setLoading(true);
        setError(null);

        try {
            const [tokenRows, operationRows] = await Promise.all([
                listTrackingTokens(activeTenant),
                canManage ? listOperations(activeTenant) : Promise.resolve([]),
            ]);
            setTokens(tokenRows);
            setOperations(operationRows);
        } catch (loadError) {
            setError(getTrackingErrorMessage(loadError));
        } finally {
            setLoading(false);
            setRefreshing(false);
        }
    }, [activeTenant, canManage]);

    useEffect(() => {
        void loadData();
    }, [loadData]);

    useEffect(() => {
        setOneTimeLink(null);
        setCreateOpen(false);
    }, [activeTenant]);

    useEffect(() => {
        setTtlHours(getScopeConfig(scope).defaultTtlHours);
    }, [scope]);

    const filteredTokens = useMemo(
        () => filterTrackingTokens(tokens, query, filter),
        [tokens, query, filter],
    );

    const counts = useMemo(() => tokens.reduce(
        (result, token) => {
            result[getTrackingDisplayState(token)] += 1;
            return result;
        },
        { active: 0, revoked: 0, expired: 0 },
    ), [tokens]);

    const openCreate = () => {
        setOperationId(operations.find((operation) => operation.db_id)?.db_id ?? '');
        setScope('public:read');
        setFormError(null);
        setCreateOpen(true);
    };

    const handleCreate = async (event: FormEvent) => {
        event.preventDefault();
        if (!activeTenant || !operationId) {
            setFormError('Selecciona una operación.');
            return;
        }

        const scopeConfig = getScopeConfig(scope);
        if (!Number.isInteger(ttlHours) || ttlHours <= 0 || ttlHours > scopeConfig.maxTtlHours) {
            setFormError(`La vigencia debe estar entre 1 y ${scopeConfig.maxTtlHours} horas.`);
            return;
        }

        setSubmitting(true);
        setFormError(null);
        try {
            const result = await createTrackingToken({
                tenantId: activeTenant,
                operationId,
                scope,
                ttlHours,
                forceRotate: false,
            });

            if (result.kind === 'existing') {
                setCreateOpen(false);
                showToast('Ya existe un enlace activo. Rótalo si necesitas un literal nuevo.');
            } else {
                setOneTimeLink(createOneTimeTrackingLink(result, window.location.origin));
                setCreateOpen(false);
                showToast('Enlace creado. Guárdalo o compártelo ahora.');
            }
            await loadData(true);
        } catch (createError) {
            setFormError(getTrackingErrorMessage(createError));
        } finally {
            setSubmitting(false);
        }
    };

    const handleRotate = async (token: TrackingTokenMetadata) => {
        if (!activeTenant || !canManage) return;
        if (!window.confirm('El enlace anterior dejará de ser válido. ¿Deseas rotarlo?')) return;

        setActionTokenId(token.id);
        try {
            const result = await createTrackingToken({
                tenantId: activeTenant,
                operationId: token.operationId,
                scope: token.scope,
                ttlHours: getScopeConfig(token.scope).defaultTtlHours,
                forceRotate: true,
            });
            const oneTime = createOneTimeTrackingLink(result, window.location.origin);
            if (!oneTime) throw new Error('invalid_rotate_result');
            setOneTimeLink(oneTime);
            showToast('Enlace rotado. Comparte el nuevo enlace ahora.');
            await loadData(true);
        } catch (rotateError) {
            showToast(getTrackingErrorMessage(rotateError));
        } finally {
            setActionTokenId(null);
        }
    };

    const handleRevoke = async (token: TrackingTokenMetadata) => {
        if (!canManage) return;
        if (!window.confirm('Este enlace dejará de funcionar. ¿Deseas revocarlo?')) return;

        setActionTokenId(token.id);
        try {
            const result = await revokeTrackingToken(token.id);
            if (result.status === 'revoked') showToast('Enlace revocado.');
            else if (result.status === 'already_revoked') showToast('El enlace ya estaba revocado.');
            else showToast('No fue posible revocar este enlace.');
            await loadData(true);
        } catch (revokeError) {
            showToast(getTrackingErrorMessage(revokeError));
        } finally {
            setActionTokenId(null);
        }
    };

    const copyLink = async (link: string) => {
        try {
            if (!navigator.clipboard?.writeText) throw new Error('clipboard_unavailable');
            await navigator.clipboard.writeText(link);
            showToast('Enlace copiado.');
        } catch {
            window.prompt('Copia el enlace:', link);
        }
    };

    const shareLink = async (link: string) => {
        if (navigator.share) {
            try {
                await navigator.share({ title: 'Enlace de seguimiento ROTERO', url: link });
                return;
            } catch {
                return;
            }
        }
        await copyLink(link);
    };

    const shareWhatsApp = (link: string) => {
        const text = encodeURIComponent(`Enlace de seguimiento ROTERO: ${link}`);
        window.open(`https://wa.me/?text=${text}`, '_blank', 'noopener,noreferrer');
    };

    const renderActions = (token: TrackingTokenMetadata) => {
        const state = getTrackingDisplayState(token);
        if (!canManage) return <span className="text-xs text-slate-400">Solo lectura</span>;
        const working = actionTokenId === token.id;

        return (
            <div className="flex flex-wrap items-center justify-end gap-2">
                <button
                    type="button"
                    onClick={() => void handleRotate(token)}
                    disabled={working}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 px-2.5 py-2 text-xs font-semibold text-slate-600 hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 disabled:opacity-50"
                >
                    {working ? <Loader2 size={14} className="animate-spin" /> : <RotateCcw size={14} />}
                    Rotar
                </button>
                {state === 'active' && (
                    <button
                        type="button"
                        onClick={() => void handleRevoke(token)}
                        disabled={working}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-red-100 px-2.5 py-2 text-xs font-semibold text-red-600 hover:bg-red-50 disabled:opacity-50"
                    >
                        <ShieldOff size={14} /> Revocar
                    </button>
                )}
            </div>
        );
    };

    return (
        <div className="h-full flex-1 overflow-y-auto bg-surface font-sans">
            <div className="mx-auto max-w-[1400px] px-4 py-6 sm:px-6 sm:py-8">
                <PageHeader
                    title="Control de Tracking"
                    subtitle="Enlaces reales de seguimiento y acceso del operador"
                    actions={
                        <div className="flex flex-wrap gap-2">
                            <button
                                type="button"
                                onClick={() => void loadData(true)}
                                disabled={loading || refreshing}
                                className="inline-flex items-center gap-2 rounded-xl border border-tech-border bg-white px-4 py-2 text-sm font-semibold text-slate-600 shadow-sm hover:bg-slate-50 disabled:opacity-50"
                            >
                                <RefreshCw size={16} className={refreshing ? 'animate-spin' : ''} />
                                Actualizar
                            </button>
                            {canManage && (
                                <button
                                    type="button"
                                    onClick={openCreate}
                                    disabled={loading}
                                    className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-white shadow-md shadow-primary/20 hover:bg-primary/90 disabled:opacity-50"
                                >
                                    <Plus size={16} /> Nuevo enlace
                                </button>
                            )}
                        </div>
                    }
                />

                <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
                    {(['active', 'revoked', 'expired'] as const).map((state) => (
                        <div key={state} className="rounded-xl border border-tech-border bg-white p-4 shadow-sm">
                            <p className="text-xs font-semibold uppercase tracking-wider text-slate-400">{DISPLAY_STATES[state].label}</p>
                            <p className="mt-1 text-2xl font-bold text-slate-800">{counts[state]}</p>
                        </div>
                    ))}
                </div>

                <div className="mt-4 flex flex-col gap-3 rounded-xl border border-tech-border bg-white p-4 shadow-sm sm:flex-row sm:items-center">
                    <div className="relative flex-1">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                        <input
                            value={query}
                            onChange={(event) => setQuery(event.target.value)}
                            placeholder="Buscar referencia, operación, scope o estado"
                            className="w-full rounded-lg border border-slate-200 bg-slate-50 py-2 pl-10 pr-4 text-sm font-medium outline-none focus:ring-2 focus:ring-primary/20"
                        />
                    </div>
                    <select
                        value={filter}
                        onChange={(event) => setFilter(event.target.value as TrackingFilter)}
                        className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-600 outline-none focus:ring-2 focus:ring-primary/20"
                    >
                        {FILTER_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                </div>

                {error && (
                    <div className="mt-4 flex items-start gap-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
                        <AlertTriangle size={18} className="mt-0.5 shrink-0" />
                        <div className="flex-1">
                            <p className="font-semibold">No fue posible cargar Tracking</p>
                            <p className="mt-0.5">{error}</p>
                        </div>
                        <button type="button" onClick={() => void loadData()} className="font-semibold underline">Reintentar</button>
                    </div>
                )}

                {loading ? (
                    <div className="mt-4 flex min-h-56 items-center justify-center rounded-xl border border-tech-border bg-white">
                        <div className="flex items-center gap-2 text-sm font-semibold text-slate-500">
                            <Loader2 size={18} className="animate-spin" /> Cargando enlaces…
                        </div>
                    </div>
                ) : !error && filteredTokens.length === 0 ? (
                    <div className="mt-4 flex min-h-56 flex-col items-center justify-center rounded-xl border border-dashed border-slate-300 bg-white px-6 text-center">
                        <Link2 size={30} className="text-slate-300" />
                        <p className="mt-3 font-semibold text-slate-700">No hay enlaces de seguimiento.</p>
                        <p className="mt-1 text-sm text-slate-400">Ajusta los filtros o crea el primer enlace para una operación.</p>
                    </div>
                ) : !error && (
                    <>
                        <div className="mt-4 hidden overflow-hidden rounded-xl border border-tech-border bg-white shadow-sm md:block">
                            <div className="overflow-x-auto">
                                <table className="w-full min-w-[980px] text-left">
                                    <thead className="border-b border-tech-border bg-slate-50/80">
                                        <tr>
                                            {['Operación', 'Tipo', 'Estado', 'Creado', 'Expira', 'Último evento', 'Acciones'].map((label) => (
                                                <th key={label} className="px-5 py-4 text-[10px] font-bold uppercase tracking-widest text-slate-400">{label}</th>
                                            ))}
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-tech-border">
                                        {filteredTokens.map((token) => {
                                            const state = getTrackingDisplayState(token);
                                            const stateSpec = DISPLAY_STATES[state];
                                            return (
                                                <tr key={token.id} className="hover:bg-slate-50/60">
                                                    <td className="px-5 py-4">
                                                        <p className="text-sm font-bold text-slate-800">{token.referenceCode ?? 'Sin referencia'}</p>
                                                        <p className="mt-0.5 max-w-56 truncate text-xs text-slate-400">{token.routeSummary ?? token.operationId}</p>
                                                    </td>
                                                    <td className="px-5 py-4 text-sm font-semibold text-slate-600">{scopeLabel(token.scope)}</td>
                                                    <td className="px-5 py-4"><Badge variant={stateSpec.badge}>{stateSpec.label}</Badge></td>
                                                    <td className="px-5 py-4 text-xs font-medium text-slate-500">{formatDate(token.createdAt)}</td>
                                                    <td className="px-5 py-4 text-xs font-medium text-slate-500">{formatDate(token.expiresAt)}</td>
                                                    <td className="px-5 py-4">
                                                        <p className="text-xs font-semibold text-slate-600">{token.lastMunicipality ?? 'Sin datos disponibles'}</p>
                                                        <p className="mt-0.5 text-[11px] text-slate-400">{formatDate(token.lastEventAt)}</p>
                                                    </td>
                                                    <td className="px-5 py-4 text-right">{renderActions(token)}</td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <div className="mt-4 space-y-3 md:hidden">
                            {filteredTokens.map((token) => {
                                const state = getTrackingDisplayState(token);
                                const stateSpec = DISPLAY_STATES[state];
                                return (
                                    <article key={token.id} className="rounded-xl border border-tech-border bg-white p-4 shadow-sm">
                                        <div className="flex items-start justify-between gap-3">
                                            <div className="min-w-0">
                                                <p className="truncate text-sm font-bold text-slate-800">{token.referenceCode ?? 'Sin referencia'}</p>
                                                <p className="mt-0.5 truncate text-xs text-slate-400">{token.routeSummary ?? token.operationId}</p>
                                            </div>
                                            <Badge variant={stateSpec.badge}>{stateSpec.label}</Badge>
                                        </div>
                                        <dl className="mt-4 grid grid-cols-2 gap-3 text-xs">
                                            <div><dt className="text-slate-400">Tipo</dt><dd className="mt-1 font-semibold text-slate-600">{scopeLabel(token.scope)}</dd></div>
                                            <div><dt className="text-slate-400">Expira</dt><dd className="mt-1 font-semibold text-slate-600">{formatDate(token.expiresAt)}</dd></div>
                                            <div className="col-span-2"><dt className="text-slate-400">Último evento</dt><dd className="mt-1 font-semibold text-slate-600">{token.lastMunicipality ?? 'Sin datos disponibles'}</dd></div>
                                        </dl>
                                        <div className="mt-4 border-t border-slate-100 pt-3">{renderActions(token)}</div>
                                    </article>
                                );
                            })}
                        </div>
                    </>
                )}
            </div>

            {createOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-sm">
                    <form onSubmit={handleCreate} className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl sm:p-6">
                        <div className="flex items-start justify-between gap-4">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Nuevo enlace</h2>
                                <p className="mt-1 text-sm text-slate-400">El backend valida operación, tenant, scope y vigencia.</p>
                            </div>
                            <button type="button" onClick={() => setCreateOpen(false)} className="rounded-lg p-2 text-slate-400 hover:bg-slate-100"><X size={18} /></button>
                        </div>
                        <div className="mt-5 space-y-4">
                            <label className="block text-sm font-semibold text-slate-600">
                                Operación
                                <select value={operationId} onChange={(event) => setOperationId(event.target.value)} className="mt-1.5 w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/20">
                                    <option value="">Selecciona una operación</option>
                                    {operations.filter((operation) => operation.db_id).map((operation) => (
                                        <option key={operation.db_id} value={operation.db_id}>{operation.id} · {operation.client}</option>
                                    ))}
                                </select>
                            </label>
                            <label className="block text-sm font-semibold text-slate-600">
                                Tipo de enlace
                                <select value={scope} onChange={(event) => setScope(event.target.value as TrackingScope)} className="mt-1.5 w-full rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/20">
                                    {TRACKING_SCOPE_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                                </select>
                            </label>
                            <label className="block text-sm font-semibold text-slate-600">
                                Vigencia en horas
                                <input type="number" min={1} max={getScopeConfig(scope).maxTtlHours} value={ttlHours} onChange={(event) => setTtlHours(Number(event.target.value))} className="mt-1.5 w-full rounded-lg border border-slate-200 px-3 py-2.5 text-sm outline-none focus:ring-2 focus:ring-primary/20" />
                                <span className="mt-1 block text-xs font-normal text-slate-400">Máximo: {getScopeConfig(scope).maxTtlHours} horas.</span>
                            </label>
                        </div>
                        {formError && <p className="mt-4 rounded-lg bg-red-50 px-3 py-2 text-sm font-medium text-red-700">{formError}</p>}
                        <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                            <button type="button" onClick={() => setCreateOpen(false)} className="rounded-xl border border-slate-200 px-4 py-2.5 text-sm font-semibold text-slate-600 hover:bg-slate-50">Cancelar</button>
                            <button type="submit" disabled={submitting || !operations.length} className="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-white hover:bg-primary/90 disabled:opacity-50">
                                {submitting && <Loader2 size={16} className="animate-spin" />} Crear enlace
                            </button>
                        </div>
                    </form>
                </div>
            )}

            {oneTimeLink && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/50 p-4 backdrop-blur-sm">
                    <div className="w-full max-w-lg rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl sm:p-6">
                        <div className="flex items-start justify-between gap-4">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Enlace listo para compartir</h2>
                                <p className="mt-1 text-sm text-slate-500">Guarda o comparte este enlace ahora. Por seguridad no podrá volver a mostrarse.</p>
                            </div>
                            <button type="button" onClick={() => setOneTimeLink(null)} className="rounded-lg p-2 text-slate-400 hover:bg-slate-100"><X size={18} /></button>
                        </div>
                        <div className="mt-5 rounded-xl border border-blue-100 bg-blue-50 p-4">
                            <p className="text-xs font-semibold uppercase tracking-wider text-blue-500">{scopeLabel(oneTimeLink.scope)}</p>
                            <p className="mt-2 break-all font-mono text-xs text-blue-900">{oneTimeLink.link}</p>
                            <p className="mt-2 text-xs text-blue-600">Expira: {formatDate(oneTimeLink.expiresAt)}</p>
                        </div>
                        <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
                            <button type="button" onClick={() => void copyLink(oneTimeLink.link)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 py-2.5 text-sm font-semibold text-slate-600 hover:bg-slate-50"><Copy size={16} /> Copiar</button>
                            <button type="button" onClick={() => void shareLink(oneTimeLink.link)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 px-3 py-2.5 text-sm font-semibold text-slate-600 hover:bg-slate-50"><Share2 size={16} /> Compartir</button>
                            <button type="button" onClick={() => shareWhatsApp(oneTimeLink.link)} className="inline-flex items-center justify-center gap-2 rounded-xl border border-emerald-200 px-3 py-2.5 text-sm font-semibold text-emerald-700 hover:bg-emerald-50"><MessageCircle size={16} /> WhatsApp</button>
                        </div>
                        <div className="mt-4 flex items-start gap-3 rounded-xl border border-slate-200 bg-slate-50 p-4">
                            <QrCode size={20} className="mt-0.5 shrink-0 text-slate-400" />
                            <div>
                                <p className="text-sm font-semibold text-slate-600">QR no disponible en esta compilación</p>
                                <p className="mt-0.5 text-xs text-slate-400">Se retiró el generador externo para no transmitir el enlace de capacidad a un tercero. Usa Copiar o Compartir.</p>
                            </div>
                        </div>
                        <button type="button" onClick={() => setOneTimeLink(null)} className="mt-5 w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white hover:bg-slate-800">Ya guardé el enlace</button>
                    </div>
                </div>
            )}

            {toast && (
                <div className="fixed bottom-6 left-1/2 z-[60] -translate-x-1/2 rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white shadow-xl">
                    {toast}
                </div>
            )}
        </div>
    );
}
