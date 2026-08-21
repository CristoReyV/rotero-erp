import { ArrowRight, Banknote, FilePlus2, Search } from 'lucide-react';
import type { FinanceCurrency, FinanceInvoice, InvoiceDirection, InvoiceStatus } from '@/types/finance';
import { money, shortDate, STATUS_LABEL, STATUS_STYLE } from './financeUi';

export interface AccountsWorkspaceProps {
    direction: InvoiceDirection; invoices: FinanceInvoice[]; search: string; status: InvoiceStatus | ''; currency: FinanceCurrency | '';
    onSearch: (value: string) => void; onStatus: (value: InvoiceStatus | '') => void; onCurrency: (value: FinanceCurrency | '') => void;
    onOpen: (invoice: FinanceInvoice) => void; onPay: (invoice: FinanceInvoice) => void; onCreate: () => void;
}

export function AccountsWorkspace({ direction, invoices, search, status, currency, onSearch, onStatus, onCurrency, onOpen, onPay, onCreate }: AccountsWorkspaceProps) {
    const ar = direction === 'ar';
    return <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white">
        <header className="flex flex-col gap-4 border-b border-slate-100 p-5 lg:flex-row lg:items-center lg:justify-between">
            <div><h2 className="font-black text-slate-800">{ar ? 'Cuentas por cobrar' : 'Cuentas por pagar'}</h2><p className="text-xs text-slate-400">{ar ? 'Cobranza, saldos y documentos de clientes.' : 'Obligaciones y pagos a la red de proveedores.'}</p></div>
            <button onClick={onCreate} className="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><FilePlus2 size={15} />Nueva cuenta</button>
        </header>
        <div className="grid gap-3 border-b border-slate-100 bg-slate-50/70 p-4 md:grid-cols-[1fr_170px_120px]">
            <label className="relative"><Search className="absolute left-3 top-2.5 text-slate-400" size={16} /><input value={search} onChange={(e) => onSearch(e.target.value)} placeholder="Contraparte, referencia, operación o UUID fiscal" className="w-full rounded-xl border border-slate-200 bg-white py-2 pl-9 pr-3 text-xs" /></label>
            <select value={status} onChange={(e) => onStatus(e.target.value as InvoiceStatus | '')} className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs"><option value="">Todos los estados</option>{(['draft','open','overdue','paid','void'] as InvoiceStatus[]).map((item) => <option key={item} value={item}>{STATUS_LABEL[item]}</option>)}</select>
            <select value={currency} onChange={(e) => onCurrency(e.target.value as FinanceCurrency | '')} className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs"><option value="">MXN + USD</option><option>MXN</option><option>USD</option></select>
        </div>
        {invoices.length === 0 ? <div className="p-12 text-center text-sm text-slate-400">No hay cuentas para los filtros seleccionados.</div> : <div className="overflow-x-auto"><table className="w-full min-w-[960px] text-left text-xs">
            <thead className="bg-slate-50 text-[10px] font-bold uppercase tracking-wider text-slate-400"><tr><th className="px-5 py-3">Contraparte</th><th className="px-5 py-3">Operación / referencia</th><th className="px-5 py-3">Vence</th><th className="px-5 py-3">Importe</th><th className="px-5 py-3">Pagado</th><th className="px-5 py-3">Saldo</th><th className="px-5 py-3">Estado</th><th className="px-5 py-3"></th></tr></thead>
            <tbody className="divide-y divide-slate-100">{invoices.map((invoice) => { const current = invoice.effective_status ?? invoice.status; const payable = ['open','overdue'].includes(current) && Number(invoice.balance_amount ?? invoice.amount) > 0; return <tr key={invoice.id} className="hover:bg-slate-50/70">
                <td className="px-5 py-4"><p className="font-bold text-slate-700">{invoice.counterparty_name}</p>{invoice.billing_reference && <p className="mt-1 text-[10px] text-indigo-500">Billing · {invoice.billing_reference}</p>}</td>
                <td className="px-5 py-4"><p className="font-mono text-[11px] text-slate-600">{invoice.operation_reference ?? 'Sin operación'}</p><p className="mt-1 text-[10px] text-slate-400">{invoice.reference ?? 'Sin referencia'}</p></td>
                <td className="px-5 py-4 text-slate-500">{shortDate(invoice.due_date)}</td><td className="px-5 py-4 font-black text-slate-700">{money(invoice.amount, invoice.currency)}</td>
                <td className="px-5 py-4 text-slate-500">{money(invoice.paid_amount, invoice.currency)}</td><td className="px-5 py-4 font-black text-slate-800">{money(invoice.balance_amount ?? invoice.amount, invoice.currency)}</td>
                <td className="px-5 py-4"><span className={`rounded-full px-2.5 py-1 text-[10px] font-bold ${STATUS_STYLE[current]}`}>{STATUS_LABEL[current]}</span></td>
                <td className="px-5 py-4"><div className="flex justify-end gap-1">{payable && <button title="Registrar pago" onClick={() => onPay(invoice)} className="rounded-lg p-2 text-emerald-600 hover:bg-emerald-50"><Banknote size={16} /></button>}<button title="Ver expediente" onClick={() => onOpen(invoice)} className="rounded-lg p-2 text-primary hover:bg-primary/5"><ArrowRight size={16} /></button></div></td>
            </tr>; })}</tbody>
        </table></div>}
    </section>;
}
