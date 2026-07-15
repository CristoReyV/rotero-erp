import { useCallback, useEffect, useRef, useState } from 'react';
import { AlertCircle, ArrowDownRight, ArrowUpRight, CircleDollarSign, Clock3, Loader2, RotateCw, ShieldAlert, Wallet } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { Badge } from '@/components/Badge';
import { KPICard } from '@/components/KPICard';
import { PageHeader } from '@/components/PageHeader';
import { getFinanceOverview, listFinanceInvoices } from '@/services/finance.service';
import { useAuthStore } from '@/store/authStore';
import type { FinanceInvoice, FinanceOverview, InvoiceDirection, InvoiceStatus } from '@/types/finance';
import type { BadgeVariant } from '@/types/common';

type FinanceView = 'overview' | 'ar' | 'ap' | 'overdue' | 'paid';

const FINANCE_VIEWS: { value: FinanceView; label: string }[] = [
    { value: 'overview', label: 'Resumen' },
    { value: 'ar', label: 'Por cobrar' },
    { value: 'ap', label: 'Por pagar' },
    { value: 'overdue', label: 'Vencidas' },
    { value: 'paid', label: 'Pagadas' },
];

const isFinanceView = (value: string | null): value is FinanceView =>
    FINANCE_VIEWS.some((view) => view.value === value);

const getFilters = (view: FinanceView): { status?: InvoiceStatus; direction?: InvoiceDirection } => {
    switch (view) {
        case 'ar':
            return { direction: 'ar' };
        case 'ap':
            return { direction: 'ap' };
        case 'overdue':
            return { status: 'overdue' };
        case 'paid':
            return { status: 'paid' };
        default:
            return {};
    }
};

const getStatusPresentation = (status: InvoiceStatus): { label: string; variant: BadgeVariant } => {
    switch (status) {
        case 'paid':
            return { label: 'Pagada', variant: 'success' };
        case 'overdue':
            return { label: 'Vencida', variant: 'danger' };
        case 'open':
            return { label: 'Abierta', variant: 'info' };
        case 'draft':
            return { label: 'Borrador interno', variant: 'default' };
        case 'void':
            return { label: 'Anulada', variant: 'default' };
        default:
            return { label: 'Estado interno', variant: 'default' };
    }
};

const formatCurrency = (amount: number, currency = 'MXN') => {
    try {
        return new Intl.NumberFormat('es-MX', { style: 'currency', currency }).format(amount);
    } catch {
        return `${amount.toLocaleString('es-MX')} ${currency}`;
    }
};

const formatDate = (value?: string) => {
    if (!value) return 'Sin vencimiento';
    const normalizedValue = /^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00` : value;
    const date = new Date(normalizedValue);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(date);
};

const getErrorMessage = (error: unknown) =>
    error instanceof Error ? error.message : 'No fue posible cargar la información financiera.';

const FinancePage = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    const activeTenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const isAdmin = role === 'admin';

    const requestedView = searchParams.get('view');
    const activeView: FinanceView = isFinanceView(requestedView) ? requestedView : 'overview';

    const [overview, setOverview] = useState<FinanceOverview | null>(null);
    const [invoices, setInvoices] = useState<FinanceInvoice[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const requestId = useRef(0);

    const loadFinance = useCallback(async () => {
        const currentRequestId = ++requestId.current;
        if (!isAdmin || !activeTenant) {
            setOverview(null);
            setInvoices([]);
            setLoading(false);
            setError(null);
            return;
        }

        setLoading(true);
        setError(null);
        try {
            const filters = getFilters(activeView);
            if (activeView === 'overview') {
                const [overviewData, invoiceData] = await Promise.all([
                    getFinanceOverview(activeTenant),
                    listFinanceInvoices(activeTenant, 50),
                ]);
                if (currentRequestId === requestId.current) {
                    setOverview(overviewData);
                    setInvoices(invoiceData);
                }
            } else {
                const invoiceData = await listFinanceInvoices(activeTenant, 50, filters.status, filters.direction);
                if (currentRequestId === requestId.current) {
                    setOverview(null);
                    setInvoices(invoiceData);
                }
            }
        } catch (loadError) {
            if (currentRequestId === requestId.current) {
                setOverview(null);
                setInvoices([]);
                setError(getErrorMessage(loadError));
            }
        } finally {
            if (currentRequestId === requestId.current) setLoading(false);
        }
    }, [activeTenant, activeView, isAdmin]);

    useEffect(() => {
        void loadFinance();
        return () => {
            requestId.current += 1;
        };
    }, [loadFinance]);

    const changeView = (view: FinanceView) => {
        const nextParams = new URLSearchParams(searchParams);
        nextParams.set('view', view);
        nextParams.delete('q');
        setSearchParams(nextParams);
    };

    if (!isAdmin) {
        return (
            <div className="space-y-6">
                <PageHeader title="Finanzas operativas" subtitle="Lectura operativa · Cuentas internas" />
                <div className="rounded-2xl border border-amber-200 bg-amber-50 p-8 text-center">
                    <ShieldAlert className="mx-auto mb-4 text-amber-600" size={32} />
                    <h2 className="text-lg font-bold text-slate-800">Acceso limitado temporalmente</h2>
                    <p className="mx-auto mt-2 max-w-xl text-sm leading-relaxed text-slate-600">
                        Esta vista económica está disponible temporalmente solo para administración.
                        La restricción definitiva debe resolverse en backend/RLS.
                    </p>
                </div>
            </div>
        );
    }

    const activeLabel = FINANCE_VIEWS.find((view) => view.value === activeView)?.label ?? 'Resumen';

    return (
        <div className="space-y-6">
            <PageHeader title="Finanzas operativas" subtitle="Lectura operativa · Cuentas internas" />

            <div className="rounded-2xl border border-amber-200/70 bg-amber-50/70 px-5 py-4">
                <div className="flex items-start gap-3">
                    <Wallet className="mt-0.5 shrink-0 text-amber-600" size={20} />
                    <div>
                        <p className="text-sm font-bold text-slate-800">Pagos y ajustes requieren backend protegido</p>
                        <p className="mt-1 text-xs leading-relaxed text-slate-600">
                            Esta pantalla presenta cuentas internas en modo read-only. No registra pagos, ajustes, complementos,
                            notas, conversiones FX ni exportaciones.
                        </p>
                        <p className="mt-2 text-[11px] text-slate-500">
                            Acceso frontend temporal para administración. La restricción definitiva debe resolverse en backend/RLS.
                        </p>
                    </div>
                </div>
            </div>

            <div className="flex flex-wrap gap-2 rounded-2xl border border-tech-border/60 bg-surface-card p-4">
                {FINANCE_VIEWS.map((view) => (
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

            {activeView === 'overview' && overview && !loading && !error && (
                <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
                    <KPICard title="Por cobrar abierto" value={formatCurrency(overview.total_ar_open)} icon={ArrowUpRight} />
                    <KPICard title="Por pagar abierto" value={formatCurrency(overview.total_ap_open)} icon={ArrowDownRight} />
                    <KPICard title="Por cobrar vencido" value={formatCurrency(overview.total_overdue)} icon={Clock3} />
                    <KPICard title="Pagos registrados este mes" value={formatCurrency(overview.paid_this_month)} icon={CircleDollarSign} />
                </div>
            )}

            <section className="overflow-hidden rounded-2xl border border-tech-border/60 bg-surface-card">
                <div className="flex items-center justify-between border-b border-tech-border/40 px-5 py-4">
                    <div>
                        <h2 className="font-bold text-slate-800">Cuentas internas · {activeLabel}</h2>
                        <p className="mt-0.5 text-[11px] text-slate-400">Máximo 50 registros recientes según los filtros soportados.</p>
                    </div>
                    {!loading && !error && activeTenant && (
                        <div className="text-right">
                            <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-500">
                                {invoices.length} cuentas
                            </span>
                            {activeView === 'overview' && overview && (
                                <p className="mt-1 text-[10px] text-slate-400">{overview.count_open_invoices} abiertas en el resumen</p>
                            )}
                        </div>
                    )}
                </div>

                {!activeTenant ? (
                    <div className="p-10 text-center text-sm text-slate-500">Selecciona una organización activa para consultar cuentas.</div>
                ) : loading ? (
                    <div className="flex min-h-56 items-center justify-center gap-2 text-sm text-slate-500">
                        <Loader2 className="animate-spin" size={20} /> Cargando información financiera…
                    </div>
                ) : error ? (
                    <div className="flex min-h-56 flex-col items-center justify-center p-8 text-center">
                        <AlertCircle className="mb-3 text-red-500" size={28} />
                        <p className="font-semibold text-slate-700">No fue posible cargar las cuentas internas</p>
                        <p className="mt-1 max-w-lg text-xs text-slate-500">{error}</p>
                        <button type="button" onClick={() => void loadFinance()} className="mt-4 flex items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-50">
                            <RotateCw size={14} /> Reintentar
                        </button>
                    </div>
                ) : invoices.length === 0 ? (
                    <div className="min-h-56 p-10 text-center">
                        <Wallet className="mx-auto mb-3 text-slate-300" size={30} />
                        <p className="font-semibold text-slate-600">Sin cuentas para esta vista</p>
                        <p className="mt-1 text-xs text-slate-400">Selecciona otra vista para consultar los registros disponibles.</p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-left text-sm">
                            <thead className="border-b border-tech-border/40 bg-slate-50/60">
                                <tr className="text-[10px] font-semibold uppercase tracking-widest text-slate-500">
                                    <th className="px-5 py-3">Contraparte</th>
                                    <th className="px-5 py-3">Referencia</th>
                                    <th className="px-5 py-3">Dirección</th>
                                    <th className="px-5 py-3">Vencimiento</th>
                                    <th className="px-5 py-3">Importe</th>
                                    <th className="px-5 py-3">Estado</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border/40">
                                {invoices.map((invoice) => {
                                    const status = getStatusPresentation(invoice.status);
                                    return (
                                        <tr key={invoice.id} className="transition-colors hover:bg-primary-50/20">
                                            <td className="px-5 py-4 font-semibold text-slate-800">{invoice.counterparty_name || 'No registrada'}</td>
                                            <td className="px-5 py-4 font-mono text-xs text-slate-500">{invoice.reference || 'Sin referencia'}</td>
                                            <td className="px-5 py-4">
                                                <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold ${
                                                    invoice.direction === 'ar'
                                                        ? 'bg-emerald-50 text-emerald-700'
                                                        : 'bg-rose-50 text-rose-700'
                                                }`}>
                                                    {invoice.direction === 'ar' ? <ArrowUpRight size={12} /> : <ArrowDownRight size={12} />}
                                                    {invoice.direction === 'ar' ? 'Por cobrar' : 'Por pagar'}
                                                </span>
                                            </td>
                                            <td className="px-5 py-4 text-xs text-slate-500">{formatDate(invoice.due_date)}</td>
                                            <td className="px-5 py-4 font-bold text-slate-800">{formatCurrency(invoice.amount, invoice.currency)}</td>
                                            <td className="px-5 py-4"><Badge variant={status.variant}>{status.label}</Badge></td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                )}
            </section>
        </div>
    );
};

export default FinancePage;
