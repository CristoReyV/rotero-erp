import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { AlertCircle, Ban, Download, FileCheck2, FileText, Loader2, RotateCw, Search, Send, ShieldAlert, X } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { Badge } from '@/components/Badge';
import { SemanticPanel, SEMANTIC_TONE_STYLES } from '@/components/SemanticPanel';
import { PageHeader } from '@/components/PageHeader';
import {
    getCFDIDetail, getFiscalReadiness, listCFDIs, queueFiscalStamp, queueFiscalStatusCheck,
    requestFiscalCancellation, retryFiscalRequest, validateFiscalDocument,
} from '@/services/billing.service';
import { createDocumentSignedUrl, listDocumentFiles } from '@/services/documents.service';
import { getFiscalActionAvailability } from '@/services/fiscalContracts';
import { useAuthStore } from '@/store/authStore';
import { canAccessRoteroModule } from '@/constants/roles';
import type { CFDIFilters, CFDIListRow, CFDIStatus, CFDIWithDetail, FiscalReadiness } from '@/types/billing';
import type { BadgeVariant } from '@/types/common';
import { FISCAL_ERROR_LABELS, FISCAL_STATUS_LABELS, formatFiscalMissingFields, getFiscalAttemptLabel, getFiscalProviderLabel } from '@/utils/presentationLabels';

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
    const [fiscalReadiness, setFiscalReadiness] = useState<FiscalReadiness | null>(null);
    const [fiscalBusy, setFiscalBusy] = useState<string | null>(null);
    const [fiscalError, setFiscalError] = useState<string | null>(null);
    const [cancellationReason, setCancellationReason] = useState('');
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
            const [data, readiness] = await Promise.all([getCFDIDetail(cfdiId), getFiscalReadiness(cfdiId)]);
            if (requestId === detailRequestId.current) {
                setSelectedDetail(data);
                setFiscalReadiness(readiness);
            }
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
        setFiscalReadiness(null);
        setFiscalError(null);
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
        setFiscalReadiness(null);
        setFiscalError(null);
        setCancellationReason('');
        const nextParams=new URLSearchParams(searchParams);nextParams.delete('cfdiId');setSearchParams(nextParams,{replace:true});
    };

    const fiscalActions = fiscalReadiness ? getFiscalActionAvailability(fiscalReadiness) : null;

    const runFiscalAction = async (name: string, action: () => Promise<void>) => {
        if (!selectedCfdiId || fiscalBusy) return;
        setFiscalBusy(name); setFiscalError(null);
        try { await action(); await loadDetail(selectedCfdiId); await loadCFDIs(); }
        catch (actionError) { setFiscalError(getErrorMessage(actionError)); }
        finally { setFiscalBusy(null); }
    };

    const downloadFiscalArtifact = async (kind: 'xml' | 'pdf') => {
        if (!activeTenant || !selectedCfdiId || !fiscalReadiness) return;
        const fileId = kind === 'xml' ? fiscalReadiness.xml_document_file_id : fiscalReadiness.pdf_document_file_id;
        if (!fileId) return;
        setFiscalBusy(`download-${kind}`); setFiscalError(null);
        try {
            const page = await listDocumentFiles(activeTenant, { source_entity_type: 'billing_cfdi', source_entity_id: selectedCfdiId, status: 'active' });
            const file = page.items.find((item) => item.id === fileId);
            if (!file) throw new Error('El artefacto fiscal todavía no está disponible.');
            window.open(await createDocumentSignedUrl(file, true), '_blank', 'noopener,noreferrer');
        } catch (actionError) { setFiscalError(getErrorMessage(actionError)); }
        finally { setFiscalBusy(null); }
    };

    if (!canViewBilling) {
        return (
            <div className="space-y-6">
                <PageHeader
                    title="Facturación y control fiscal"
                    subtitle="Control interno de comprobantes · Registro fiscal interno"
                />
                <SemanticPanel tone="warning" className="rounded-2xl p-8 text-center">
                    <ShieldAlert className={`mx-auto mb-4 ${SEMANTIC_TONE_STYLES.warning.accent}`} size={32} />
                    <h2 className="text-lg font-bold text-slate-800">Acceso limitado temporalmente</h2>
                    <p className="mx-auto mt-2 max-w-xl text-sm leading-relaxed text-slate-600">
                        Tu rol no tiene acceso a la superficie de facturación de ROTERO.
                    </p>
                </SemanticPanel>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            <PageHeader
                title="Facturación y control fiscal"
                subtitle="Control interno de comprobantes · Registro fiscal interno"
            />

            <SemanticPanel tone="info" className="rounded-2xl px-5 py-4">
                <div className="flex items-start gap-3">
                    <FileText className={`mt-0.5 shrink-0 ${SEMANTIC_TONE_STYLES.info.accent}`} size={20} />
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
            </SemanticPanel>

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
                    <aside className="absolute inset-y-0 right-0 w-full min-w-0 max-w-md overflow-y-auto bg-surface-card shadow-2xl">
                        <div className="sticky top-0 z-10 flex min-w-0 items-center justify-between gap-3 border-b border-slate-100 bg-surface-card px-4 py-4 sm:px-6">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Detalle interno</h2>
                                <p className="text-[11px] text-slate-400">Consulta de solo lectura del comprobante</p>
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
                                    <SemanticPanel tone="info" className="p-4 text-xs leading-relaxed text-slate-600">Preparación fiscal independiente del proveedor. Ninguna acción simula timbrado ni confirma comunicación con SAT/PAC.</SemanticPanel>
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
                                            ['Operación', selectedDetail.operation_id || 'Sin relación'],
                                            ['Estado fiscal', fiscalReadiness ? FISCAL_STATUS_LABELS[fiscalReadiness.fiscal_status] : 'No disponible'],
                                            ['CFDI', fiscalReadiness?.validation.cfdi_version || selectedDetail.cfdi_version || 'No registrado'],
                                            ['Proveedor', getFiscalProviderLabel(fiscalReadiness?.provider.code)],
                                            ['Entorno fiscal', fiscalReadiness?.provider.environment === 'production' ? 'Producción' : 'Pruebas'],
                                            ['Último intento', fiscalReadiness?.last_attempt ? `${getFiscalAttemptLabel(fiscalReadiness.last_attempt.status)} · ${formatDate(fiscalReadiness.last_attempt.updated_at)}` : 'Sin intentos'],
                                            ['Error', fiscalReadiness?.safe_error_message || (fiscalReadiness?.safe_error_code ? FISCAL_ERROR_LABELS[fiscalReadiness.safe_error_code] : 'Sin error')],
                                            ['Emisión registrada', formatDate(selectedDetail.issued_at)],
                                            ['Alta interna', formatDate(selectedDetail.created_at)],
                                        ].map(([label, value]) => (
                                            <div key={label} className="py-3">
                                                <dt className="text-[10px] font-semibold uppercase tracking-wider text-slate-400">{label}</dt>
                                                <dd className="mt-1 break-words text-sm font-semibold text-slate-700">{value}</dd>
                                            </div>
                                        ))}
                                    </dl>

                                    {fiscalReadiness && fiscalActions && (
                                        <section className="space-y-3 rounded-xl border border-slate-200 p-4">
                                            <div>
                                                <h3 className="text-sm font-bold text-slate-800">Control fiscal</h3>
                                                <p className="mt-1 text-[11px] text-slate-500">
                                                    {fiscalActions.externalDisabledReason || 'Proveedor habilitado explícitamente para este tenant y entorno.'}
                                                </p>
                                            </div>
                                            {!fiscalReadiness.validation.valid && fiscalReadiness.validation.missing_fields.length > 0 && (
                                                <SemanticPanel tone="warning" className="p-3 text-[11px] text-slate-600">{formatFiscalMissingFields(fiscalReadiness.validation.missing_fields)}</SemanticPanel>
                                            )}
                                            {fiscalError && <p className="rounded-lg bg-red-50 p-3 text-[11px] text-red-700">{fiscalError}</p>}
                                            <div className="grid grid-cols-2 gap-2">
                                                <button type="button" disabled={!fiscalActions.validate || Boolean(fiscalBusy)} onClick={() => void runFiscalAction('validate', () => validateFiscalDocument(selectedCfdiId))} className="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"><FileCheck2 size={14} /> Validar</button>
                                                <button type="button" disabled={!fiscalActions.submit || Boolean(fiscalBusy)} onClick={() => void runFiscalAction('submit', () => queueFiscalStamp(selectedCfdiId))} className="flex items-center justify-center gap-2 rounded-lg bg-primary px-3 py-2 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40"><Send size={14} /> Enviar a timbrar</button>
                                                <button type="button" disabled={!fiscalActions.retry || !fiscalReadiness.last_attempt || Boolean(fiscalBusy)} onClick={() => fiscalReadiness.last_attempt && void runFiscalAction('retry', () => retryFiscalRequest(fiscalReadiness.last_attempt!.request_id))} className="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"><RotateCw size={14} /> Reintentar</button>
                                                <button type="button" disabled={!fiscalActions.refresh || Boolean(fiscalBusy)} onClick={() => void runFiscalAction('refresh', () => queueFiscalStatusCheck(selectedCfdiId))} className="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"><RotateCw size={14} /> Consultar estado</button>
                                            </div>
                                            <label className="block text-[10px] font-semibold uppercase tracking-wider text-slate-400">Motivo de cancelación
                                                <input value={cancellationReason} onChange={(event) => setCancellationReason(event.target.value)} disabled={!fiscalActions.cancel} className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-xs font-normal normal-case tracking-normal disabled:bg-slate-50" />
                                            </label>
                                            <button type="button" disabled={!fiscalActions.cancel || !cancellationReason.trim() || Boolean(fiscalBusy)} onClick={() => void runFiscalAction('cancel', () => requestFiscalCancellation(selectedCfdiId, cancellationReason))} className="flex w-full items-center justify-center gap-2 rounded-lg border border-red-200 px-3 py-2 text-xs font-semibold text-red-700 disabled:cursor-not-allowed disabled:opacity-40"><Ban size={14} /> Cancelar</button>
                                            <div className="grid grid-cols-2 gap-2">
                                                <button type="button" disabled={!fiscalActions.downloadXml || Boolean(fiscalBusy)} onClick={() => void downloadFiscalArtifact('xml')} className="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"><Download size={14} /> Descargar XML</button>
                                                <button type="button" disabled={!fiscalActions.downloadPdf || Boolean(fiscalBusy)} onClick={() => void downloadFiscalArtifact('pdf')} className="flex items-center justify-center gap-2 rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed disabled:opacity-40"><Download size={14} /> Descargar PDF</button>
                                            </div>
                                        </section>
                                    )}
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
