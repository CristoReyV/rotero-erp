import { useCallback, useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { ArrowRight, CheckCircle2, Copy, Edit3, FileText, Inbox, Loader2, Plus, Printer, Search, Send, Truck, X, XCircle } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import {
    convertQuoteToOperation, duplicateQuote, getCommercialErrorMessage, listCommercialDeals, listCustomers,
    listProviders, listQuotes, transitionQuoteStatus, upsertQuote,
} from '@/services/commercial.service';
import type { CommercialCurrency, Customer, Deal, LogisticsProvider, OperationScope, Quote, QuoteStatus, QuoteUpsertPayload } from '@/types/commercial';
import { calculateMargin, formatCommercialCurrency } from '@/utils/commercialCalculations';

const STATUS_META: Record<QuoteStatus, { label: string; className: string }> = {
    draft: { label: 'Borrador', className: 'bg-slate-100 text-slate-600' },
    review: { label: 'Enviada', className: 'bg-blue-50 text-blue-700' },
    approved: { label: 'Aceptada', className: 'bg-emerald-50 text-emerald-700' },
    rejected: { label: 'Rechazada', className: 'bg-red-50 text-red-700' },
    converted: { label: 'Convertida', className: 'bg-purple-50 text-purple-700' },
};

interface QuoteFormState {
    opportunity_id: string;
    title: string; customer_id: string; provider_id: string; operation_scope: OperationScope;
    service_type: string; currency: CommercialCurrency; provider_cost_amount: string;
    customer_price_amount: string; requested_date: string; valid_until: string; notes: string;
    origin_municipality: string; origin_state: string; origin_country: 'MX' | 'US';
    destination_municipality: string; destination_state: string; destination_country: 'MX' | 'US';
}

const EMPTY_QUOTE: QuoteFormState = {
    opportunity_id: '', title: '', customer_id: '', provider_id: '', operation_scope: 'national', service_type: '',
    currency: 'MXN', provider_cost_amount: '', customer_price_amount: '', requested_date: '', valid_until: '', notes: '',
    origin_municipality: '', origin_state: '', origin_country: 'MX', destination_municipality: '', destination_state: '', destination_country: 'MX',
};

export function QuoteWorkspace({ tenantId }: { tenantId: string }) {
    const navigate = useNavigate();
    const [quotes, setQuotes] = useState<Quote[]>([]);
    const [customers, setCustomers] = useState<Customer[]>([]);
    const [providers, setProviders] = useState<LogisticsProvider[]>([]);
    const [opportunities, setOpportunities] = useState<Deal[]>([]);
    const [loading, setLoading] = useState(true);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [notice, setNotice] = useState<string | null>(null);
    const [search, setSearch] = useState('');
    const [status, setStatus] = useState<QuoteStatus | 'all'>('all');
    const [selectedId, setSelectedId] = useState<string | null>(null);
    const [modalOpen, setModalOpen] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState<QuoteFormState>(EMPTY_QUOTE);

    const selected = quotes.find((quote) => quote.id === selectedId) ?? quotes[0] ?? null;
    const formMargin = calculateMargin(Number(form.provider_cost_amount), Number(form.customer_price_amount));

    const load = useCallback(async () => {
        setLoading(true); setError(null);
        try {
            const [quoteData, customerData, providerData, dealData] = await Promise.all([
                listQuotes(tenantId, { searchText: search.trim() || undefined, status: status === 'all' ? undefined : status }),
                listCustomers(tenantId, { active: true }),
                listProviders(tenantId, { active: true }),
                listCommercialDeals(tenantId),
            ]);
            setQuotes(quoteData); setCustomers(customerData); setProviders(providerData);
            setOpportunities(dealData.filter((deal) => !deal.quote_reference));
            setSelectedId((current) => quoteData.some((quote) => quote.id === current) ? current : quoteData[0]?.id ?? null);
        } catch (loadError) { setError(getCommercialErrorMessage(loadError)); }
        finally { setLoading(false); }
    }, [search, status, tenantId]);

    useEffect(() => { void load(); }, [load]);

    const openCreate = () => { setEditingId(null); setForm(EMPTY_QUOTE); setModalOpen(true); setError(null); };
    const openEdit = (quote: Quote) => {
        const payload = quote.quote_payload;
        setEditingId(quote.id);
        setForm({
            opportunity_id: '', title: quote.title, customer_id: quote.customer_id, provider_id: payload.provider_id ?? '',
            operation_scope: payload.operation_scope ?? 'national', service_type: payload.service_type ?? '',
            currency: payload.currency ?? 'MXN', provider_cost_amount: payload.provider_cost_amount?.toString() ?? '',
            customer_price_amount: payload.customer_price_amount?.toString() ?? '',
            requested_date: toLocalDateTime(payload.requested_date), valid_until: payload.valid_until?.slice(0, 10) ?? '', notes: payload.notes ?? quote.notes ?? '',
            origin_municipality: payload.origin_place?.municipality ?? '', origin_state: payload.origin_place?.state ?? '', origin_country: payload.origin_place?.countryCode ?? 'MX',
            destination_municipality: payload.destination_place?.municipality ?? '', destination_state: payload.destination_place?.state ?? '', destination_country: payload.destination_place?.countryCode ?? 'MX',
        });
        setModalOpen(true); setError(null);
    };

    const submit = async (event: FormEvent) => {
        event.preventDefault(); setBusy(true); setError(null); setNotice(null);
        const payload: QuoteUpsertPayload = {
            title: form.title.trim(), customer_id: form.customer_id, provider_id: form.provider_id || undefined,
            operation_scope: form.operation_scope, service_type: form.service_type.trim() || undefined,
            currency: form.currency,
            provider_cost_amount: form.provider_cost_amount === '' ? undefined : Number(form.provider_cost_amount),
            customer_price_amount: form.customer_price_amount === '' ? undefined : Number(form.customer_price_amount),
            requested_date: form.requested_date ? new Date(form.requested_date).toISOString() : undefined,
            valid_until: form.valid_until || undefined, notes: form.notes.trim() || undefined,
            origin_place: form.origin_municipality.trim() && form.origin_state.trim() ? { municipality: form.origin_municipality.trim(), state: form.origin_state.trim(), countryCode: form.origin_country } : undefined,
            destination_place: form.destination_municipality.trim() && form.destination_state.trim() ? { municipality: form.destination_municipality.trim(), state: form.destination_state.trim(), countryCode: form.destination_country } : undefined,
        };
        try {
            const result = await upsertQuote(tenantId, editingId ?? (form.opportunity_id || null), payload);
            setModalOpen(false); setEditingId(null); setNotice('Cotización guardada como borrador.');
            await load(); setSelectedId(result.id);
        } catch (saveError) { setError(getCommercialErrorMessage(saveError)); }
        finally { setBusy(false); }
    };

    const changeStatus = async (next: Exclude<QuoteStatus, 'converted'>, message: string) => {
        if (!selected) return;
        setBusy(true); setError(null); setNotice(null);
        try { await transitionQuoteStatus(selected.id, next); await load(); setSelectedId(selected.id); setNotice(message); }
        catch (statusError) { setError(getCommercialErrorMessage(statusError)); }
        finally { setBusy(false); }
    };

    const duplicate = async () => {
        if (!selected) return;
        setBusy(true); setError(null);
        try { const result = await duplicateQuote(selected.id); await load(); setSelectedId(result.id); setNotice('Se creó una copia en borrador.'); }
        catch (duplicateError) { setError(getCommercialErrorMessage(duplicateError)); }
        finally { setBusy(false); }
    };

    const convert = async () => {
        if (!selected || !window.confirm('Se creará una sola operación ligada a esta cotización aceptada. ¿Continuar?')) return;
        setBusy(true); setError(null);
        try {
            const result = await convertQuoteToOperation(selected.id);
            await load(); setSelectedId(selected.id);
            setNotice(result.already_converted ? `La operación ${result.operation_reference} ya existía.` : `Operación ${result.operation_reference} creada correctamente.`);
        } catch (conversionError) { setError(getCommercialErrorMessage(conversionError)); }
        finally { setBusy(false); }
    };

    return (
        <div className="space-y-4">
            <div className="flex flex-col gap-3 rounded-2xl border bg-white p-4 lg:flex-row lg:items-center">
                <form onSubmit={(event) => { event.preventDefault(); void load(); }} className="flex min-w-0 flex-1 gap-2"><div className="relative min-w-0 flex-1"><Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar referencia, cliente, proveedor u oportunidad" className="w-full rounded-xl border bg-slate-50 py-2.5 pl-9 pr-3 text-sm" /></div><button className="rounded-xl border px-4 text-xs font-bold text-slate-600">Buscar</button></form>
                <select value={status} onChange={(event) => setStatus(event.target.value as QuoteStatus | 'all')} className="rounded-xl border bg-white px-3 py-2.5 text-xs font-semibold"><option value="all">Todos los estados</option>{Object.entries(STATUS_META).map(([value, meta]) => <option key={value} value={value}>{meta.label}</option>)}</select>
                <button onClick={openCreate} className="flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><Plus size={15} /> Nueva cotización</button>
            </div>
            {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
            {notice && <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</div>}
            <div className="grid gap-4 xl:grid-cols-[minmax(0,1.05fr)_minmax(380px,.95fr)]">
                <section className="overflow-hidden rounded-2xl border bg-white">{loading ? <div className="flex h-56 items-center justify-center"><Loader2 className="animate-spin text-primary" /></div> : quotes.length === 0 ? <div className="flex h-56 flex-col items-center justify-center gap-2 text-slate-400"><Inbox /><p className="text-sm">No hay cotizaciones con estos filtros.</p><button onClick={openCreate} className="text-xs font-bold text-primary">Crear primera cotización</button></div> : <div className="divide-y">{quotes.map((quote) => { const margin = calculateMargin(quote.quote_payload.provider_cost_amount ?? 0, quote.quote_payload.customer_price_amount ?? 0); return <button key={quote.id} onClick={() => setSelectedId(quote.id)} className={`grid w-full gap-3 p-4 text-left hover:bg-slate-50 md:grid-cols-[minmax(0,1.3fr)_minmax(0,.9fr)_auto] md:items-center ${selected?.id === quote.id ? 'bg-primary-50' : ''}`}><div className="min-w-0"><div className="flex items-center gap-2"><FileText size={15} className="text-primary" /><p className="font-mono text-xs font-bold text-primary">{quote.quote_reference}</p></div><p className="mt-1 truncate font-bold text-slate-800">{quote.title}</p><p className="truncate text-xs text-slate-400">{quote.customer_name} · {quote.provider_name || 'Proveedor por confirmar'}</p></div><div className="text-xs"><p className="text-slate-400">Venta</p><p className="font-bold text-slate-700">{formatCommercialCurrency(quote.quote_payload.customer_price_amount ?? 0, quote.quote_payload.currency)}</p><p className={margin.amount >= 0 ? 'text-emerald-600' : 'text-red-600'}>Margen {margin.percentage === null ? '—' : `${margin.percentage.toFixed(1)}%`}</p></div><span className={`rounded-full px-2 py-1 text-[10px] font-bold ${STATUS_META[quote.quote_status].className}`}>{STATUS_META[quote.quote_status].label}</span></button>; })}</div>}</section>
                <aside className="rounded-2xl border bg-white p-5">{!selected ? <div className="flex h-48 flex-col items-center justify-center gap-2 text-center text-slate-400"><FileText /><p className="text-sm">Selecciona una cotización para revisar economía y seguimiento.</p></div> : <QuoteDetail quote={selected} busy={busy} onEdit={() => openEdit(selected)} onDuplicate={() => void duplicate()} onPrint={() => window.print()} onTransition={(next, message) => void changeStatus(next, message)} onConvert={() => void convert()} onOpenOperation={() => selected.converted_operation_reference && navigate(`/operations?view=all&operation=${encodeURIComponent(selected.converted_operation_reference)}`)} />}</aside>
            </div>
            {selected && <PrintableQuote quote={selected} />}
            {modalOpen && <QuoteModal form={form} setForm={setForm} customers={customers} providers={providers} opportunities={opportunities} editing={Boolean(editingId)} busy={busy} margin={formMargin} onClose={() => setModalOpen(false)} onSubmit={submit} />}
        </div>
    );
}

function QuoteDetail({ quote, busy, onEdit, onDuplicate, onPrint, onTransition, onConvert, onOpenOperation }: { quote: Quote; busy: boolean; onEdit: () => void; onDuplicate: () => void; onPrint: () => void; onTransition: (status: Exclude<QuoteStatus, 'converted'>, message: string) => void; onConvert: () => void; onOpenOperation: () => void }) {
    const payload = quote.quote_payload;
    const margin = calculateMargin(payload.provider_cost_amount ?? 0, payload.customer_price_amount ?? 0);
    const expired = payload.valid_until && new Date(`${payload.valid_until}T23:59:59`) < new Date() && !['approved', 'converted'].includes(quote.quote_status);
    return <div className="space-y-5"><div className="flex items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><p className="font-mono text-xs font-bold text-primary">{quote.quote_reference}</p><span className={`rounded-full px-2 py-1 text-[10px] font-bold ${STATUS_META[quote.quote_status].className}`}>{STATUS_META[quote.quote_status].label}</span>{expired && <span className="rounded-full bg-amber-50 px-2 py-1 text-[10px] font-bold text-amber-700">Vigencia vencida</span>}</div><h2 className="mt-2 text-xl font-bold text-slate-800">{quote.title}</h2><p className="text-sm text-slate-500">{quote.customer_name}</p></div>{busy && <Loader2 className="animate-spin text-primary" />}</div><div className="rounded-2xl bg-slate-900 p-4 text-white"><div className="grid grid-cols-3 gap-3"><Money label="Costo proveedor" value={formatCommercialCurrency(payload.provider_cost_amount ?? 0, payload.currency)} /><Money label="Precio cliente" value={formatCommercialCurrency(payload.customer_price_amount ?? 0, payload.currency)} /><Money label="Margen bruto" value={`${formatCommercialCurrency(margin.amount, payload.currency)}${margin.percentage === null ? '' : ` · ${margin.percentage.toFixed(1)}%`}`} accent={margin.amount >= 0} /></div><p className="mt-3 text-[10px] text-slate-400">Importes en {payload.currency}. Sin conversión FX.</p></div><div className="grid grid-cols-2 gap-3 text-xs"><Info label="Proveedor" value={quote.provider_name || 'Por confirmar'} /><Info label="Servicio" value={payload.service_type || 'Por confirmar'} /><Info label="Origen" value={placeLabel(payload.origin_place)} /><Info label="Destino" value={placeLabel(payload.destination_place)} /><Info label="Alcance" value={payload.operation_scope === 'international' ? 'Internacional' : 'Nacional'} /><Info label="Vigencia" value={payload.valid_until || 'Sin fecha'} /></div>{payload.notes && <div className="rounded-xl bg-slate-50 p-3 text-xs leading-relaxed text-slate-600">{payload.notes}</div>}<div className="flex flex-wrap gap-2"><button disabled={busy} onClick={onDuplicate} className="flex items-center gap-2 rounded-xl border px-3 py-2 text-xs font-bold text-slate-600"><Copy size={14} /> Duplicar</button><button onClick={onPrint} className="flex items-center gap-2 rounded-xl border px-3 py-2 text-xs font-bold text-slate-600"><Printer size={14} /> Imprimir</button>{quote.quote_status === 'draft' && <><button onClick={onEdit} className="flex items-center gap-2 rounded-xl border px-3 py-2 text-xs font-bold text-slate-600"><Edit3 size={14} /> Editar</button><button disabled={busy} onClick={() => onTransition('review', 'Cotización marcada como enviada.')} className="flex items-center gap-2 rounded-xl bg-primary px-3 py-2 text-xs font-bold text-white"><Send size={14} /> Marcar enviada</button></>}{quote.quote_status === 'review' && <><button disabled={busy} onClick={() => onTransition('draft', 'Cotización devuelta a borrador.')} className="rounded-xl border px-3 py-2 text-xs font-bold text-slate-600">Volver a borrador</button><button disabled={busy} onClick={() => onTransition('rejected', 'Cotización marcada como rechazada.')} className="flex items-center gap-2 rounded-xl border border-red-200 px-3 py-2 text-xs font-bold text-red-700"><XCircle size={14} /> Rechazar</button><button disabled={busy} onClick={() => onTransition('approved', 'Cotización aceptada; lista para convertir.')} className="flex items-center gap-2 rounded-xl bg-emerald-600 px-3 py-2 text-xs font-bold text-white"><CheckCircle2 size={14} /> Aceptar</button></>}{quote.quote_status === 'approved' && <button disabled={busy} onClick={onConvert} className="flex items-center gap-2 rounded-xl bg-primary px-3 py-2 text-xs font-bold text-white"><Truck size={14} /> Convertir a operación</button>}{quote.quote_status === 'converted' && quote.converted_operation_reference && <button onClick={onOpenOperation} className="flex items-center gap-2 rounded-xl bg-primary px-3 py-2 text-xs font-bold text-white"><ArrowRight size={14} /> Abrir {quote.converted_operation_reference}</button>}</div></div>;
}

function QuoteModal({ form, setForm, customers, providers, opportunities, editing, busy, margin, onClose, onSubmit }: { form: QuoteFormState; setForm: (form: QuoteFormState) => void; customers: Customer[]; providers: LogisticsProvider[]; opportunities: Deal[]; editing: boolean; busy: boolean; margin: ReturnType<typeof calculateMargin>; onClose: () => void; onSubmit: (event: FormEvent) => void }) {
    const selectOpportunity = (id: string) => {
        const opportunity = opportunities.find((deal) => deal.id === id);
        setForm({ ...form, opportunity_id: id, title: opportunity?.title ?? form.title, customer_id: opportunity?.customer_id ?? form.customer_id, currency: (opportunity?.currency as CommercialCurrency | undefined) ?? form.currency });
    };
    return <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/30 p-4 backdrop-blur-sm"><form onSubmit={onSubmit} className="max-h-[92vh] w-full max-w-4xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl"><div className="mb-5 flex items-center justify-between"><div><h2 className="text-lg font-bold">{editing ? 'Editar cotización' : 'Nueva cotización'}</h2><p className="text-xs text-slate-400">Oportunidad, costo proveedor, precio cliente y ruta</p></div><button type="button" onClick={onClose}><X size={18} /></button></div><div className="grid gap-4 md:grid-cols-2">{!editing && <label className="space-y-1 text-xs font-bold text-slate-500 md:col-span-2">Oportunidad existente (opcional)<select value={form.opportunity_id} onChange={(event) => selectOpportunity(event.target.value)} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal"><option value="">Crear oportunidad con esta cotización</option>{opportunities.map((deal) => <option key={deal.id} value={deal.id}>{deal.title} · {deal.company || 'Sin cliente ligado'}</option>)}</select></label>}<Field label="Oportunidad / concepto *" value={form.title} onChange={(value) => setForm({ ...form, title: value })} /><Select label="Cliente *" value={form.customer_id} onChange={(value) => setForm({ ...form, customer_id: value })}><option value="">Selecciona cliente</option>{customers.map((customer) => <option key={customer.id} value={customer.id}>{customer.display_name}</option>)}</Select><Select label="Proveedor contratado" value={form.provider_id} onChange={(value) => setForm({ ...form, provider_id: value })}><option value="">Por confirmar</option>{providers.map((provider) => <option key={provider.id} value={provider.id}>{provider.display_name}</option>)}</Select><Field label="Tipo de servicio" value={form.service_type} onChange={(value) => setForm({ ...form, service_type: value })} /><Select label="Alcance" value={form.operation_scope} onChange={(value) => setForm({ ...form, operation_scope: value as OperationScope })}><option value="national">Nacional</option><option value="international">Internacional</option></Select><Select label="Moneda" value={form.currency} onChange={(value) => setForm({ ...form, currency: value as CommercialCurrency })}><option>MXN</option><option>USD</option></Select><PlaceFields title="Origen" municipality={form.origin_municipality} state={form.origin_state} country={form.origin_country} onChange={(patch) => setForm({ ...form, ...Object.fromEntries(Object.entries(patch).map(([key, value]) => [`origin_${key}`, value])) } as QuoteFormState)} /><PlaceFields title="Destino" municipality={form.destination_municipality} state={form.destination_state} country={form.destination_country} onChange={(patch) => setForm({ ...form, ...Object.fromEntries(Object.entries(patch).map(([key, value]) => [`destination_${key}`, value])) } as QuoteFormState)} /><Field label="Costo proveedor" type="number" value={form.provider_cost_amount} onChange={(value) => setForm({ ...form, provider_cost_amount: value })} /><Field label="Precio cliente" type="number" value={form.customer_price_amount} onChange={(value) => setForm({ ...form, customer_price_amount: value })} /><Field label="Fecha solicitada" type="datetime-local" value={form.requested_date} onChange={(value) => setForm({ ...form, requested_date: value })} /><Field label="Válida hasta" type="date" value={form.valid_until} onChange={(value) => setForm({ ...form, valid_until: value })} /><div className="rounded-xl bg-slate-900 p-4 text-white md:col-span-2"><div className="grid grid-cols-2 gap-4"><Money label="Margen bruto" value={formatCommercialCurrency(margin.amount, form.currency)} accent={margin.amount >= 0} /><Money label="Margen % sobre venta" value={margin.percentage === null ? '—' : `${margin.percentage.toFixed(2)}%`} accent={margin.amount >= 0} /></div></div><label className="space-y-1 text-xs font-bold text-slate-500 md:col-span-2">Notas<textarea value={form.notes} onChange={(event) => setForm({ ...form, notes: event.target.value })} className="min-h-20 w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal" /></label></div><div className="mt-6 flex justify-end gap-2"><button type="button" onClick={onClose} className="px-4 py-2 text-sm font-semibold text-slate-500">Cancelar</button><button disabled={busy || !form.title.trim() || !form.customer_id} className="flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">{busy && <Loader2 size={14} className="animate-spin" />} Guardar borrador</button></div></form></div>;
}

function PrintableQuote({ quote }: { quote: Quote }) { const payload = quote.quote_payload; return <article className="commercial-print-sheet hidden"><header><p>ROTERO · Cotización logística</p><h1>{quote.quote_reference}</h1><h2>{quote.title}</h2></header><hr /><p><strong>Cliente:</strong> {quote.customer_name}</p><p><strong>Ruta:</strong> {placeLabel(payload.origin_place)} → {placeLabel(payload.destination_place)}</p><p><strong>Servicio:</strong> {payload.service_type || 'Por confirmar'} · {payload.operation_scope === 'international' ? 'Internacional' : 'Nacional'}</p><table><tbody><tr><td>Precio del servicio</td><td>{formatCommercialCurrency(payload.customer_price_amount ?? 0, payload.currency)}</td></tr></tbody></table><p><strong>Vigencia:</strong> {payload.valid_until || 'Sin fecha capturada'}</p>{payload.notes && <p><strong>Notas:</strong> {payload.notes}</p>}<footer>Importes expresados en {payload.currency}. Cotización sujeta a disponibilidad de la red operativa.</footer></article>; }
function Money({ label, value, accent }: { label: string; value: string; accent?: boolean }) { return <div><p className="text-[10px] uppercase tracking-wider text-slate-400">{label}</p><p className={`mt-1 text-sm font-bold ${accent === true ? 'text-emerald-300' : accent === false ? 'text-red-300' : 'text-white'}`}>{value}</p></div>; }
function Info({ label, value }: { label: string; value: string }) { return <div className="rounded-xl border p-3"><p className="text-[10px] uppercase tracking-wider text-slate-400">{label}</p><p className="mt-1 font-semibold text-slate-700">{value}</p></div>; }
function Field({ label, value, onChange, type = 'text' }: { label: string; value: string; onChange: (value: string) => void; type?: string }) { return <label className="space-y-1 text-xs font-bold text-slate-500">{label}<input type={type} min={type === 'number' ? 0 : undefined} step={type === 'number' ? '0.01' : undefined} value={value} onChange={(event) => onChange(event.target.value)} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal" /></label>; }
function Select({ label, value, onChange, children }: { label: string; value: string; onChange: (value: string) => void; children: ReactNode }) { return <label className="space-y-1 text-xs font-bold text-slate-500">{label}<select value={value} onChange={(event) => onChange(event.target.value)} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal">{children}</select></label>; }
function PlaceFields({ title, municipality, state, country, onChange }: { title: string; municipality: string; state: string; country: 'MX' | 'US'; onChange: (patch: { municipality?: string; state?: string; country?: 'MX' | 'US' }) => void }) { return <fieldset className="rounded-xl border p-3"><legend className="px-1 text-xs font-bold text-slate-500">{title}</legend><div className="grid gap-2 sm:grid-cols-[1fr_1fr_auto]"><input placeholder="Municipio / ciudad" value={municipality} onChange={(event) => onChange({ municipality: event.target.value })} className="rounded-lg border bg-slate-50 px-3 py-2 text-sm" /><input placeholder="Estado" value={state} onChange={(event) => onChange({ state: event.target.value })} className="rounded-lg border bg-slate-50 px-3 py-2 text-sm" /><select value={country} onChange={(event) => onChange({ country: event.target.value as 'MX' | 'US' })} className="rounded-lg border bg-slate-50 px-2 py-2 text-sm"><option>MX</option><option>US</option></select></div></fieldset>; }
function placeLabel(place?: { municipality: string; state: string }) { return place ? `${place.municipality}, ${place.state}` : 'Por confirmar'; }
function toLocalDateTime(value?: string) { if (!value) return ''; const date = new Date(value); const offset = date.getTimezoneOffset(); return new Date(date.getTime() - offset * 60_000).toISOString().slice(0, 16); }
