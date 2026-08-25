import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { AlertCircle, FileText, Loader2, RotateCw, Search, ShieldAlert, X } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { Badge } from '@/components/Badge';
import { PageHeader } from '@/components/PageHeader';
import { getCFDIDetail, listCFDIs } from '@/services/billing.service';
import { useAuthStore } from '@/store/authStore';
import { canAccessRoteroModule } from '@/constants/roles';
import type { CFDIFilters, CFDIListRow, CFDIStatus, CFDIWithDetail } from '@/types/billing';
import type { BadgeVariant } from '@/types/common';

type BillingView = 'all' | 'draft' | 'registered' | 'error' | 'cancelled';

const BILLING_VIEWS: { value: BillingView; label: string }[] = [
    { value: 'all', label: 'Todos' },
    { value: 'draft', label: 'Borradores' },
    { value: 'registered', label: 'Registrados' },
    { value: 'error', label: 'Errores' },
    { value: 'cancelled', label: 'Cancelados' },
];

const STATUS_BY_VIEW: Partial<Record<BillingView, CFDIStatus>> = {
    draft: 'draft',
    registered: 'timbrado',
    error: 'error',
    cancelled: 'cancelado',
};

const isBillingView = (value: string | null): value is BillingView =>
    BILLING_VIEWS.some((view) => view.value === value);

const getStatusPresentation = (status: string): { label: string; variant: BadgeVariant } => {
    switch (status.toLowerCase()) {
        case 'timbrado':
            return { label: 'Registrado internamente', variant: 'success' };
        case 'draft':
        case 'borrador':
            return { label: 'Borrador', variant: 'default' };
        case 'pendiente':
            return { label: 'Pendiente interno', variant: 'warning' };
        case 'error':
            return { label: 'Error de registro', variant: 'danger' };
        case 'cancelado':
            return { label: 'Cancelado', variant: 'default' };
        default:
            return { label: 'Estado interno', variant: 'default' };
    }
};

const getErrorMessage = (error: unknown) =>
    error instanceof Error ? error.message : 'No fue posible cargar la información.';

const formatCurrency = (amount: number, currency = 'MXN') => {
    try {
        return new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(amount);
    } catch {
        return `${amount.toLocaleString('es-MX')} ${currency}`;
    }
};

const formatDate = (value?: string) => {
    if (!value) return 'No registrado';
    const normalizedValue = /^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00` : value;
    const date = new Date(normalizedValue);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(date);
};

const BillingPage = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const canViewBilling = canAccessRoteroModule(role, 'billing');

    const requestedView = searchParams.get('view');
    const activeView: BillingView = isBillingView(requestedView) ? requestedView : 'all';
    const query = searchParams.get('q')?.trim() ?? '';

    const [queryInput, setQueryInput] = useState(query);
    const [cfdis, setCfdis] = useState<CFDIListRow[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [selectedCfdiId, setSelectedCfdiId] = useState<string | null>(null);
    const [selectedDetail, setSelectedDetail] = useState<CFDIWithDetail | null>(null);
    const [detailLoading, setDetailLoading] = useState(false);
    const [detailError, setDetailError] = useState<string | null>(null);
    const listRequestId = useRef(0);
    const detailRequestId = useRef(0);

    const filters = useMemo<CFDIFilters>(() => ({
        status: STATUS_BY_VIEW[activeView],
        searchText: query || undefined,
    }), [activeView, query]);

    const loadCFDIs = useCallback(async () => {
        const requestId = ++listRequestId.current;
        if (!canViewBilling || !activeTenant) {
            setCfdis([]);
            setLoading(false);
            setError(null);
            return;
        }

        setLoading(true);
        setError(null);
        try {
            const data = await listCFDIs(activeTenant, filters);
            if (requestId === listRequestId.current) setCfdis(data);
        } catch (loadError) {
            if (requestId === listRequestId.current) {
                setCfdis([]);
                setError(getErrorMessage(loadError));
            }
        } finally {
            if (requestId === listRequestId.current) setLoading(false);
        }
    }, [activeTenant, filters, canViewBilling]);

    const loadDetail = useCallback(async (cfdiId: string) => {
        if (!canViewBilling) return;
        const requestId = ++detailRequestId.current;
        setDetailLoading(true);
        setDetailError(null);
        setSelectedDetail(null);
        try {
            const data = await getCFDIDetail(cfdiId);
            if (requestId === detailRequestId.current) setSelectedDetail(data);
        } catch (loadError) {
            if (requestId === detailRequestId.current) setDetailError(getErrorMessage(loadError));
        } finally {
            if (requestId === detailRequestId.current) setDetailLoading(false);
        }
    }, [canViewBilling]);

    useEffect(() => {
        setQueryInput(query);
    }, [query]);

    useEffect(() => {
        const cfdiId=searchParams.get('cfdiId');
        if(cfdiId&&cfdis.some((item)=>item.db_id===cfdiId)&&selectedCfdiId!==cfdiId){
            setSelectedCfdiId(cfdiId);
            void loadDetail(cfdiId);
        }
    },[cfdis,loadDetail,searchParams,selectedCfdiId]);

    useEffect(() => {
        void loadCFDIs();
        return () => {
            listRequestId.current += 1;
        };
    }, [loadCFDIs]);

    useEffect(() => {
        detailRequestId.current += 1;
        setSelectedCfdiId(null);
        setSelectedDetail(null);
        setDetailError(null);
    }, [activeView, query]);

    const changeView = (view: BillingView) => {
        const nextParams = new URLSearchParams(searchParams);
        nextParams.set('view', view);
        setSearchParams(nextParams);
    };

    const submitSearch = (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        const nextParams = new URLSearchParams(searchParams);
        nextParams.set('view', activeView);
        const nextQuery = queryInput.trim();
        if (nextQuery) nextParams.set('q', nextQuery);
        else nextParams.delete('q');
        setSearchParams(nextParams);
    };

    const openDetail = (cfdiId: string) => {
        setSelectedCfdiId(cfdiId);
        const nextParams=new URLSearchParams(searchParams);nextParams.set('cfdiId',cfdiId);setSearchParams(nextParams,{replace:true});
        void loadDetail(cfdiId);
    };

    const closeDetail = () => {
        detailRequestId.current += 1;
        setSelectedCfdiId(null);
        setSelectedDetail(null);
        setDetailError(null);
        const nextParams=new URLSearchParams(searchParams);nextParams.delete('cfdiId');setSearchParams(nextParams,{replace:true});
    };

    if (!canViewBilling) {
        return (
            <div className="space-y-6">
                <PageHeader
                    title="Billing operativo y control fiscal interno"
                    subtitle="Control interno de comprobantes · Registro fiscal interno"
                />
                <div className="rounded-2xl border border-amber-200 bg-amber-50 p-8 text-center">
                    <ShieldAlert className="mx-auto mb-4 text-amber-600" size={32} />
                    <h2 className="text-lg font-bold text-slate-800">Acceso limitado temporalmente</h2>
                    <p className="mx-auto mt-2 max-w-xl text-sm leading-relaxed text-slate-600">
                        Tu rol no tiene acceso a la superficie de facturación de ROTERO.
                    </p>
                </div>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            <PageHeader
                title="Billing operativo y control fiscal interno"
                subtitle="Control interno de comprobantes · Registro fiscal interno"
            />

            <div className="rounded-2xl border border-blue-200/70 bg-blue-50/70 px-5 py-4">
                <div className="flex items-start gap-3">
                    <FileText className="mt-0.5 shrink-0 text-blue-600" size={20} />
                    <div>
                        <p className="text-sm font-bold text-slate-800">Sin integración SAT/PAC confirmada</p>
                        <p className="mt-1 text-xs leading-relaxed text-slate-600">
                            Los estados e identificadores se muestran como registros internos. Esta pantalla no confirma emisión,
                            validación ni cancelación ante servicios fiscales externos.
                        </p>
                        <p className="mt-2 text-[11px] text-slate-500">
                            Acceso disponible para Administración y Finanzas, conforme al contrato backend vigente.
                        </p>
                    </div>
                </div>
            </div>

            <div className="flex flex-col gap-4 rounded-2xl border border-tech-border/60 bg-surface-card p-4 lg:flex-row lg:items-center lg:justify-between">
                <div className="flex flex-wrap gap-2">
                    {BILLING_VIEWS.map((view) => (
                        <button
                            key={view.value}
                            type="button"
                            onClick={() => changeView(view.value)}
                            className={`rounded-xl px-3.5 py-2 text-xs font-semibold transition-colors ${
                                activeView === view.value
                                    ? 'bg-primary text-white shadow-sm'
                                    : 'bg-slate-50 text-slate-500 hover:bg-primary-50 hover:text-primary'
                            }`}
                        >
                            {view.label}
                        </button>
                    ))}
                </div>

                <form onSubmit={submitSearch} className="flex w-full gap-2 lg:max-w-md">
                    <div className="relative flex-1">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                        <input
                            type="search"
                            value={queryInput}
                            onChange={(event) => setQueryInput(event.target.value)}
                            placeholder="Buscar UUID o folio"
                            className="w-full rounded-xl border border-tech-border/60 bg-white py-2.5 pl-9 pr-3 text-sm outline-none transition focus:border-primary/30 focus:ring-2 focus:ring-primary/15"
                        />
                    </div>
                    <button type="submit" className="rounded-xl bg-primary px-4 py-2 text-xs font-semibold text-white hover:bg-primary-light">
                        Buscar
                    </button>
                </form>
            </div>

            <section className="overflow-hidden rounded-2xl border border-tech-border/60 bg-surface-card">
                <div className="flex items-center justify-between border-b border-tech-border/40 px-5 py-4">
                    <div>
                        <h2 className="font-bold text-slate-800">Comprobantes internos</h2>
                        <p className="mt-0.5 text-[11px] text-slate-400">La búsqueda disponible cubre UUID o folio.</p>
                    </div>
                    {!loading && !error && activeTenant && (
                        <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-500">
                            {cfdis.length} registros
                        </span>
                    )}
                </div>

                {!activeTenant ? (
                    <div className="p-10 text-center text-sm text-slate-500">Selecciona una organización activa para consultar registros.</div>
                ) : loading ? (
                    <div className="flex min-h-56 items-center justify-center gap-2 text-sm text-slate-500">
                        <Loader2 className="animate-spin" size={20} /> Cargando comprobantes…
                    </div>
                ) : error ? (
                    <div className="flex min-h-56 flex-col items-center justify-center p-8 text-center">
                        <AlertCircle className="mb-3 text-red-500" size={28} />
                        <p className="font-semibold text-slate-700">No fue posible cargar los comprobantes</p>
                        <p className="mt-1 max-w-lg text-xs text-slate-500">{error}</p>
                        <button type="button" onClick={() => void loadCFDIs()} className="mt-4 flex items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-50">
                            <RotateCw size={14} /> Reintentar
                        </button>
                    </div>
                ) : cfdis.length === 0 ? (
                    <div className="min-h-56 p-10 text-center">
                        <FileText className="mx-auto mb-3 text-slate-300" size={30} />
                        <p className="font-semibold text-slate-600">Sin registros para esta vista</p>
                        <p className="mt-1 text-xs text-slate-400">Ajusta la vista o la búsqueda por UUID o folio.</p>
                    </div>
                ) : (
                    <div className="divide-y divide-tech-border/40">
                        {cfdis.map((cfdi) => {
                            const status = getStatusPresentation(cfdi.status);
                            return (
                                <button
                                    key={cfdi.db_id}
                                    type="button"
                                    onClick={() => openDetail(cfdi.db_id)}
                                    className="flex w-full items-center gap-4 px-5 py-4 text-left transition-colors hover:bg-primary-50/30"
                                >
                                    <div className="min-w-0 flex-1">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <p className="truncate text-[13px] font-semibold text-slate-800">{cfdi.client || 'Receptor no registrado'}</p>
                                            <Badge variant={status.variant}>{status.label}</Badge>
                                        </div>
                                        <p className="mt-1 truncate font-mono text-[10px] text-slate-400">
                                            UUID almacenado: {cfdi.uuid || 'No registrado'} · Folio: {cfdi.folio || 'Sin folio'}
                                        </p>
                                    </div>
                                    <div className="shrink-0 text-right">
                                        <p className="text-[13px] font-bold text-slate-800">{cfdi.amount}</p>
                                        <p className="mt-0.5 text-[10px] font-semibold text-slate-400">Ver detalle interno</p>
                                    </div>
                                </button>
                            );
                        })}
                    </div>
                )}
            </section>

            {selectedCfdiId && (
                <div className="fixed inset-0 z-50">
                    <button type="button" aria-label="Cerrar detalle" onClick={closeDetail} className="absolute inset-0 bg-slate-900/35 backdrop-blur-sm" />
                    <aside className="absolute inset-y-0 right-0 w-full max-w-md overflow-y-auto bg-white shadow-2xl">
                        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-slate-100 bg-white/95 px-6 py-4 backdrop-blur">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Detalle interno</h2>
                                <p className="text-[11px] text-slate-400">Consulta read-only del comprobante</p>
                            </div>
                            <button type="button" onClick={closeDetail} aria-label="Cerrar" className="rounded-lg bg-slate-50 p-2 text-slate-400 hover:text-slate-600">
                                <X size={18} />
                            </button>
                        </div>

                        <div className="p-6">
                            {detailLoading ? (
                                <div className="flex min-h-64 items-center justify-center gap-2 text-sm text-slate-500">
                                    <Loader2 className="animate-spin" size={20} /> Cargando detalle…
                                </div>
                            ) : detailError ? (
                                <div className="flex min-h-64 flex-col items-center justify-center text-center">
                                    <AlertCircle className="mb-3 text-red-500" size={28} />
                                    <p className="font-semibold text-slate-700">No fue posible cargar el detalle</p>
                                    <p className="mt-1 text-xs text-slate-500">{detailError}</p>
                                    <button type="button" onClick={() => void loadDetail(selectedCfdiId)} className="mt-4 flex items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-50">
                                        <RotateCw size={14} /> Reintentar
                                    </button>
                                </div>
                            ) : selectedDetail ? (
                                <div className="space-y-5">
                                    <div className="rounded-xl border border-blue-100 bg-blue-50/60 p-4 text-xs leading-relaxed text-slate-600">
                                        Identificadores y estados almacenados para control interno. Sin integración SAT/PAC confirmada.
                                    </div>
                                    <dl className="divide-y divide-slate-100 rounded-xl border border-slate-100 px-4">
                                        {[
                                            ['Estado del registro', getStatusPresentation(selectedDetail.status).label],
                                            ['Serie / folio', `${selectedDetail.serie || ''}${selectedDetail.folio || ''}` || 'Sin folio'],
                                            ['Identificador UUID almacenado', selectedDetail.uuid || 'No registrado'],
                                            ['Receptor', selectedDetail.receptor_name || 'No registrado'],
                                            ['RFC receptor', selectedDetail.rfc_receptor || 'No registrado'],
                                            ['RFC emisor', selectedDetail.rfc_emisor || 'No registrado'],
                                            ['Subtotal', formatCurrency(selectedDetail.subtotal || 0, selectedDetail.currency)],
                                            ['Total', formatCurrency(selectedDetail.total || 0, selectedDetail.currency)],
                                            ['Moneda', selectedDetail.currency || 'No registrada'],
                                            ['Emisión registrada', formatDate(selectedDetail.issued_at)],
                                            ['Alta interna', formatDate(selectedDetail.created_at)],
                                        ].map(([label, value]) => (
                                            <div key={label} className="py-3">
                                                <dt className="text-[10px] font-semibold uppercase tracking-wider text-slate-400">{label}</dt>
                                                <dd className="mt-1 break-words text-sm font-semibold text-slate-700">{value}</dd>
                                            </div>
                                        ))}
                                    </dl>
                                </div>
                            ) : null}
                        </div>
                    </aside>
                </div>
            )}
        </div>
    );
};

export default BillingPage;
