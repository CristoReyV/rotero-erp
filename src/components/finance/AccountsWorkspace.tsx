import { ArrowRight, Banknote, FilePlus2, Search, SlidersHorizontal } from 'lucide-react';
import { useState } from 'react';
import { MOBILE_MEDIA_QUERY, useMediaQuery } from '@/hooks/useMediaQuery';
import type { FinanceCurrency, FinanceInvoice, InvoiceDirection, InvoiceStatus } from '@/types/finance';
import { money, shortDate, STATUS_LABEL, STATUS_STYLE } from './financeUi';

export interface AccountsWorkspaceProps {
    direction: InvoiceDirection; invoices: FinanceInvoice[]; search: string; status: InvoiceStatus | ''; currency: FinanceCurrency | '';
    onSearch: (value: string) => void; onStatus: (value: InvoiceStatus | '') => void; onCurrency: (value: FinanceCurrency | '') => void;
    onOpen: (invoice: FinanceInvoice) => void; onPay: (invoice: FinanceInvoice) => void; onCreate: () => void;
    selectedIds?: Set<string>; onToggleSelected?: (id: string) => void; onToggleAll?: () => void;
}

export function AccountsWorkspace({ direction, invoices, search, status, currency, onSearch, onStatus, onCurrency, onOpen, onPay, onCreate, selectedIds, onToggleSelected, onToggleAll }: AccountsWorkspaceProps) {
    const ar = direction === 'ar';
    const isMobile = useMediaQuery(MOBILE_MEDIA_QUERY);
    const [mobileFiltersOpen, setMobileFiltersOpen] = useState(false);
    const activeFilterCount = Number(Boolean(status)) + Number(Boolean(currency));
    const filterFields = <>
        <select aria-label="Filtrar cuentas por estado" value={status} onChange={(event) => onStatus(event.target.value as InvoiceStatus | '')} className="min-h-11 w-full rounded-xl border bg-surface-card px-3 text-xs"><option value="">Todos los estados</option>{(['draft', 'open', 'overdue', 'paid', 'void'] as InvoiceStatus[]).map((item) => <option key={item} value={item}>{STATUS_LABEL[item]}</option>)}</select>
        <select aria-label="Filtrar cuentas por moneda" value={currency} onChange={(event) => onCurrency(event.target.value as FinanceCurrency | '')} className="min-h-11 w-full rounded-xl border bg-surface-card px-3 text-xs"><option value="">MXN + USD</option><option>MXN</option><option>USD</option></select>
    </>;

    return <section className="min-w-0 max-w-full overflow-hidden rounded-2xl border bg-surface-card" data-finance-accounts-workspace>
        <header className="flex flex-col gap-3 border-b p-4 sm:p-5 lg:flex-row lg:items-center lg:justify-between">
            <div className="min-w-0"><h2 className="font-black text-slate-800">{ar ? 'Cuentas por cobrar' : 'Cuentas por pagar'}</h2><p className="text-xs leading-relaxed text-slate-500">{ar ? 'Cobranza, saldos y documentos de clientes.' : 'Obligaciones y pagos a la red de proveedores.'}</p></div>
            <button type="button" onClick={onCreate} className="inline-flex min-h-11 items-center justify-center gap-2 self-start rounded-xl bg-primary px-4 text-xs font-bold text-white lg:self-auto"><FilePlus2 size={15} />Nueva cuenta</button>
        </header>

        <div className="border-b bg-surface p-3 sm:p-4">
            {isMobile ? <><div className="flex min-w-0 gap-2">
                <label className="relative min-w-0 flex-1"><span className="sr-only">Buscar cuentas</span><Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input value={search} onChange={(event) => onSearch(event.target.value)} placeholder="Buscar cuenta" className="min-h-11 w-full rounded-xl border bg-surface-card pl-9 pr-3 text-xs" /></label>
                <button type="button" aria-expanded={mobileFiltersOpen} onClick={() => setMobileFiltersOpen((value) => !value)} className="inline-flex min-h-11 shrink-0 items-center gap-2 rounded-xl border bg-surface-card px-3 text-xs font-bold text-slate-600"><SlidersHorizontal size={15} />Filtros{activeFilterCount > 0 && <span className="rounded-full bg-primary px-1.5 py-0.5 text-[9px] text-white">{activeFilterCount}</span>}</button>
            </div>
            {mobileFiltersOpen && <div className="mt-2 grid gap-2">{filterFields}</div>}</> : <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_170px_120px]">
                <label className="relative min-w-0"><span className="sr-only">Buscar cuentas</span><Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input value={search} onChange={(event) => onSearch(event.target.value)} placeholder="Contraparte, referencia, operación o UUID fiscal" className="min-h-11 w-full rounded-xl border bg-surface-card pl-9 pr-3 text-xs" /></label>
                {filterFields}
            </div>}
        </div>

        {invoices.length === 0 ? <div className="p-6 text-center text-sm text-slate-400 sm:p-12">No hay cuentas para los filtros seleccionados.</div> : isMobile ? <div className="divide-y" data-finance-mobile-cards>
                {invoices.map((invoice) => {
                    const current = invoice.effective_status ?? invoice.status;
                    const payable = ['open', 'overdue'].includes(current) && Number(invoice.balance_amount ?? invoice.amount) > 0;
                    return <article key={invoice.id} className="flex min-w-0 items-start gap-1 p-3">
                        {onToggleSelected && <label className="-ml-2 flex h-11 w-10 shrink-0 items-center justify-center"><span className="sr-only">Seleccionar {invoice.counterparty_name}</span><input type="checkbox" checked={selectedIds?.has(invoice.id) ?? false} onChange={() => onToggleSelected(invoice.id)} /></label>}
                        <button type="button" onClick={() => onOpen(invoice)} className="min-w-0 flex-1 py-1 text-left">
                            <span className="flex min-w-0 items-start justify-between gap-2"><strong className="line-clamp-2 min-w-0 text-sm text-slate-800">{invoice.counterparty_name}</strong><span className={`shrink-0 rounded-full px-2 py-1 text-[9px] font-bold ${STATUS_STYLE[current]}`}>{STATUS_LABEL[current]}</span></span>
                            <span className="mt-1 block text-lg font-black leading-tight text-slate-800">{money(invoice.balance_amount ?? invoice.amount, invoice.currency)}</span>
                            <span className="mt-0.5 block text-[10px] font-bold uppercase text-slate-500">Saldo · {invoice.currency}</span>
                            <span className="mt-2 flex min-w-0 items-center justify-between gap-2 text-[11px] text-slate-500"><span className="min-w-0 truncate">{invoice.operation_reference ?? invoice.reference ?? 'Sin referencia'}</span><span className="shrink-0">Vence {shortDate(invoice.due_date)}</span></span>
                        </button>
                        <div className="flex shrink-0 flex-col">
                            {payable && <button type="button" aria-label={`Registrar pago de ${invoice.counterparty_name}`} onClick={() => onPay(invoice)} className="flex h-11 w-11 items-center justify-center rounded-xl text-emerald-600 hover:bg-emerald-50"><Banknote size={17} /></button>}
                            <button type="button" aria-label={`Abrir expediente de ${invoice.counterparty_name}`} onClick={() => onOpen(invoice)} className="flex h-11 w-11 items-center justify-center rounded-xl text-primary hover:bg-primary-50"><ArrowRight size={17} /></button>
                        </div>
                    </article>;
                })}
            </div> : <div className="overflow-x-auto" data-finance-desktop-table><table className="w-full min-w-[960px] text-left text-xs">
                <thead className="bg-surface text-[10px] font-bold uppercase tracking-wider text-slate-400"><tr>{onToggleSelected && <th className="px-3 py-3"><input type="checkbox" aria-label="Seleccionar todas las cuentas" checked={invoices.every((item) => selectedIds?.has(item.id))} onChange={onToggleAll} /></th>}<th className="px-5 py-3">Contraparte</th><th className="px-5 py-3">Operación / referencia</th><th className="px-5 py-3">Vence</th><th className="px-5 py-3">Importe</th><th className="px-5 py-3">Pagado</th><th className="px-5 py-3">Saldo</th><th className="px-5 py-3">Estado</th><th className="px-5 py-3"></th></tr></thead>
                <tbody className="divide-y">{invoices.map((invoice) => { const current = invoice.effective_status ?? invoice.status; const payable = ['open', 'overdue'].includes(current) && Number(invoice.balance_amount ?? invoice.amount) > 0; return <tr key={invoice.id} className="hover:bg-slate-50">
                    {onToggleSelected && <td className="px-3 py-4"><input type="checkbox" aria-label={`Seleccionar ${invoice.counterparty_name}`} checked={selectedIds?.has(invoice.id) ?? false} onChange={() => onToggleSelected(invoice.id)} /></td>}
                    <td className="px-5 py-4"><p className="font-bold text-slate-700">{invoice.counterparty_name}</p>{invoice.billing_reference && <p className="mt-1 text-[10px] text-indigo-500">Billing · {invoice.billing_reference}</p>}</td>
                    <td className="px-5 py-4"><p className="font-mono text-[11px] text-slate-600">{invoice.operation_reference ?? 'Sin operación'}</p><p className="mt-1 text-[10px] text-slate-400">{invoice.reference ?? 'Sin referencia'}</p></td>
                    <td className="px-5 py-4 text-slate-500">{shortDate(invoice.due_date)}</td><td className="px-5 py-4 font-black text-slate-700">{money(invoice.amount, invoice.currency)}</td><td className="px-5 py-4 text-slate-500">{money(invoice.paid_amount, invoice.currency)}</td><td className="px-5 py-4 font-black text-slate-800">{money(invoice.balance_amount ?? invoice.amount, invoice.currency)}</td>
                    <td className="px-5 py-4"><span className={`rounded-full px-2.5 py-1 text-[10px] font-bold ${STATUS_STYLE[current]}`}>{STATUS_LABEL[current]}</span></td>
                    <td className="px-5 py-4"><div className="flex justify-end gap-1">{payable && <button type="button" aria-label={`Registrar pago de ${invoice.counterparty_name}`} onClick={() => onPay(invoice)} className="flex h-11 w-11 items-center justify-center rounded-lg text-emerald-600 hover:bg-emerald-50"><Banknote size={16} /></button>}<button type="button" aria-label={`Ver expediente de ${invoice.counterparty_name}`} onClick={() => onOpen(invoice)} className="flex h-11 w-11 items-center justify-center rounded-lg text-primary hover:bg-primary-50"><ArrowRight size={16} /></button></div></td>
                </tr>; })}</tbody>
            </table></div>}
    </section>;
}
