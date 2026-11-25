import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import {
    deliveryCsv,
    type DeliveryPage,
    deliveryPage,
    type DeliveryRow,
} from '@/services/companyDelivery.service';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';
import { downloadCsvContent } from '@/utils/csv';

export default function CompanyReceivablesPage() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const [search, setSearch] = useState('');
    const [cursor, setCursor] = useState<string | null>(null);
    const [page, setPage] = useState<DeliveryPage | null>(null);
    const [error, setError] = useState('');
    const [revision, setRevision] = useState(0);
    const [paying, setPaying] = useState<DeliveryRow | null>(null);
    const [amount, setAmount] = useState('');
    const [busy, setBusy] = useState(false);
    const allowed = (role === 'admin' || role === 'finance') && hasCompanyCapability('receivables.read');
    const collect = hasCompanyCapability('receivables.collect');
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        setPage(null);
        setError('');
        void deliveryPage(tenant, 'receivables', search, cursor).then((result) => {
            if (active) setPage(result);
        }, () => {
            if (active) setError('No fue posible consultar las cuentas autorizadas.');
        });
        return () => {
            active = false;
        };
    }, [tenant, allowed, search, cursor, revision]);
    const exportCsv = async () => {
        if (!tenant) return;
        try {
            downloadCsvContent(
                await deliveryCsv(tenant, 'receivables', search),
                'cuentas-por-cobrar-empresa.csv',
            );
        } catch {
            setError('No fue posible exportar las cuentas autorizadas.');
        }
    };
    const pay = async () => {
        if (!paying || !tenant || busy) return;
        setBusy(true);
        setError('');
        try {
            const { data, error: failure } = await supabase.rpc('rpc_delivery_record_receivable_payment', {
                p_tenant_id: tenant,
                p_payload: { invoice_id: paying.id, amount, currency: paying.currency, method: 'transfer' },
            });
            if (failure || data?.error) throw new Error('payment_failed');
            setPaying(null);
            setAmount('');
            setRevision((value) => value + 1);
        } catch {
            setError('No se pudo confirmar el pago. Actualiza el saldo antes de reintentar.');
        } finally {
            setBusy(false);
        }
    };
    if (!allowed) return <p role='alert'>Sin capacidad de cobranza para esta empresa.</p>;
    const money = (value: unknown, currency: unknown) =>
        new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: String(currency),
        }).format(Number(value));
    return (
        <div className='space-y-5'>
            <div className='flex flex-wrap items-center justify-between gap-3'>
                <h1 className='text-2xl font-bold'>Cuentas por cobrar</h1>
                <div className='flex gap-4'>
                    <button onClick={() => setRevision((value) => value + 1)}>Actualizar</button>
                    {hasCompanyCapability('export.receivables') && (
                        <button onClick={() => void exportCsv()}>Exportar CSV</button>
                    )}
                </div>
            </div>
            <p className='text-sm text-slate-500'>
                Importe, pagos y saldo de cuentas clasificadas. No incluye cuentas por pagar ni resultados
                financieros completos.
            </p>
            <input
                aria-label='Buscar cuentas por cobrar'
                value={search}
                onChange={(event) => {
                    setSearch(event.target.value);
                    setCursor(null);
                }}
                placeholder='Referencia o cliente'
                className='w-full rounded-xl border p-3'
            />
            {error && <p role='alert'>{error}</p>}
            {page
                ? (
                    <>
                        <p>{page.total} cuentas en este alcance</p>
                        <div className='overflow-x-auto rounded-xl border bg-surface-card'>
                            <table className='w-full text-left text-sm'>
                                <thead>
                                    <tr>
                                        {[
                                            'Referencia',
                                            'Cliente',
                                            'Importe',
                                            'Pagado',
                                            'Saldo',
                                            'Vencimiento',
                                            '',
                                        ].map((label, i) => <th key={i} className='p-3'>{label}</th>)}
                                    </tr>
                                </thead>
                                <tbody>
                                    {page.items.map((row) => (
                                        <tr key={String(row.id)} className='border-t'>
                                            <td className='p-3'>{row.reference}</td>
                                            <td className='p-3'>{row.counterparty_name}</td>
                                            <td className='p-3'>{money(row.amount, row.currency)}</td>
                                            <td className='p-3'>{money(row.paid_amount, row.currency)}</td>
                                            <td className='p-3'>{money(row.balance_amount, row.currency)}</td>
                                            <td className='p-3'>{row.due_date ?? 'Sin fecha'}</td>
                                            <td className='p-3'>
                                                {collect && Number(row.balance_amount) > 0 && (
                                                    <button
                                                        onClick={() => {
                                                            setPaying(row);
                                                            setAmount('');
                                                        }}
                                                    >
                                                        Registrar pago
                                                    </button>
                                                )}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                        <div className='flex gap-4'>
                            <button disabled={!cursor} onClick={() => setCursor(null)}>Primera página</button>
                            <button disabled={!page.next_cursor} onClick={() => setCursor(page.next_cursor)}>
                                Siguiente página
                            </button>
                        </div>
                    </>
                )
                : !error && <p role='status'>Cargando…</p>}
            {paying && (
                <form
                    className='space-y-3 rounded-xl border bg-surface-card p-5'
                    onSubmit={(event) => {
                        event.preventDefault();
                        void pay();
                    }}
                >
                    <h2 className='font-bold'>Pago de {paying.reference}</h2>
                    <label className='block'>
                        Importe ({paying.currency}){' '}
                        <input
                            required
                            type='number'
                            min='0.01'
                            step='0.01'
                            max={Number(paying.balance_amount)}
                            value={amount}
                            onChange={(event) => setAmount(event.target.value)}
                            className='rounded border p-2'
                        />
                    </label>
                    <p className='text-xs text-slate-500'>
                        Registro de cobranza. La preparación fiscal de un complemento es una acción separada.
                    </p>
                    <button
                        disabled={busy}
                        type='submit'
                        className='rounded-xl bg-primary px-4 py-2 text-white'
                    >
                        Confirmar pago
                    </button>
                    <button type='button' disabled={busy} className='ml-4' onClick={() => setPaying(null)}>
                        Cerrar
                    </button>
                </form>
            )}
        </div>
    );
}
