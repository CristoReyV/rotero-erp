import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Building2, Edit3, Inbox, Loader2, Mail, Phone, Plus, Search, X } from 'lucide-react';
import { getCommercialErrorMessage, getCustomer360, listCustomers, upsertCustomer } from '@/services/commercial.service';
import type { CommercialCurrency, Customer, Customer360, CustomerPayload } from '@/types/commercial';
import { formatCommercialCurrency } from '@/utils/commercialCalculations';
import { EntityDocumentsPanel } from '@/components/documents/EntityDocumentsPanel';

const EMPTY_FORM: CustomerPayload = {
    display_name: '',
    legal_name: '',
    tax_id: '',
    contact_name: '',
    contact_email: '',
    contact_phone: '',
    billing_email: '',
    notes: '',
    is_active: true,
    preferred_currency: 'MXN',
};

export function CustomerDirectory({ tenantId }: { tenantId: string }) {
    const [items, setItems] = useState<Customer[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [search, setSearch] = useState('');
    const [activeFilter, setActiveFilter] = useState<'all' | 'active' | 'inactive'>('all');
    const [selected, setSelected] = useState<Customer360 | null>(null);
    const [detailLoading, setDetailLoading] = useState(false);
    const [editing, setEditing] = useState<Customer | null>(null);
    const [form, setForm] = useState<CustomerPayload>(EMPTY_FORM);
    const [modalOpen, setModalOpen] = useState(false);
    const [saving, setSaving] = useState(false);

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            setItems(await listCustomers(tenantId, {
                searchText: search.trim() || undefined,
                active: activeFilter === 'all' ? undefined : activeFilter === 'active',
            }));
        } catch (loadError) {
            setError(getCommercialErrorMessage(loadError));
        } finally {
            setLoading(false);
        }
    }, [activeFilter, search, tenantId]);

    useEffect(() => { void load(); }, [load]);

    const openDetail = async (customer: Customer) => {
        setDetailLoading(true);
        setError(null);
        try {
            setSelected(await getCustomer360(customer.id));
        } catch (detailError) {
            setError(getCommercialErrorMessage(detailError));
        } finally {
            setDetailLoading(false);
        }
    };

    const openForm = (customer?: Customer) => {
        setEditing(customer ?? null);
        setForm(customer ? {
            display_name: customer.display_name,
            legal_name: customer.legal_name ?? '',
            tax_id: customer.tax_id ?? '',
            contact_name: customer.contact_name ?? '',
            contact_email: customer.contact_email ?? '',
            contact_phone: customer.contact_phone ?? '',
            billing_email: customer.billing_email ?? '',
            notes: customer.notes ?? '',
            is_active: customer.is_active,
            preferred_currency: customer.preferred_currency,
        } : EMPTY_FORM);
        setModalOpen(true);
    };

    const submit = async (event: FormEvent) => {
        event.preventDefault();
        setSaving(true);
        setError(null);
        try {
            const result = await upsertCustomer(tenantId, editing?.id ?? null, form);
            setEditing(null);
            setForm(EMPTY_FORM);
            setModalOpen(false);
            await load();
            if (selected?.customer.id === result.id) setSelected(await getCustomer360(result.id));
        } catch (saveError) {
            setError(getCommercialErrorMessage(saveError));
        } finally {
            setSaving(false);
        }
    };

    return (
        <div className="space-y-4">
            <div className="flex flex-col gap-3 rounded-2xl border bg-white p-4 lg:flex-row lg:items-center lg:justify-between">
                <form onSubmit={(event) => { event.preventDefault(); void load(); }} className="flex min-w-0 flex-1 gap-2">
                    <div className="relative min-w-0 flex-1">
                        <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                        <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar nombre, RFC o contacto" className="w-full rounded-xl border bg-slate-50 py-2.5 pl-9 pr-3 text-sm outline-none focus:ring-2 focus:ring-primary/15" />
                    </div>
                    <button className="rounded-xl border px-4 text-xs font-bold text-slate-600">Buscar</button>
                </form>
                <div className="flex gap-2">
                    <select value={activeFilter} onChange={(event) => setActiveFilter(event.target.value as typeof activeFilter)} className="rounded-xl border bg-white px-3 py-2.5 text-xs font-semibold text-slate-600">
                        <option value="all">Todos</option><option value="active">Activos</option><option value="inactive">Inactivos</option>
                    </select>
                    <button onClick={() => openForm()} className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><Plus size={15} /> Nuevo cliente</button>
                </div>
            </div>

            {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}

            <div className="grid gap-4 xl:grid-cols-[minmax(0,1.25fr)_minmax(320px,.75fr)]">
                <section className="overflow-hidden rounded-2xl border bg-white">
                    {loading ? <div className="flex h-48 items-center justify-center text-slate-400"><Loader2 className="animate-spin" /></div> : items.length === 0 ? (
                        <div className="flex h-48 flex-col items-center justify-center gap-2 text-slate-400"><Inbox /><p className="text-sm">No hay clientes con estos filtros.</p></div>
                    ) : (
                        <div className="divide-y">
                            {items.map((customer) => (
                                <button key={customer.id} onClick={() => void openDetail(customer)} className="grid w-full gap-3 p-4 text-left hover:bg-slate-50 md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_auto] md:items-center">
                                    <div className="min-w-0"><div className="flex items-center gap-2"><Building2 size={16} className="text-primary" /><p className="truncate font-bold text-slate-800">{customer.display_name}</p></div><p className="mt-1 truncate text-xs text-slate-400">{customer.legal_name || customer.tax_id || 'Sin razón social capturada'}</p></div>
                                    <div className="text-xs text-slate-500"><p className="truncate">{customer.contact_name || 'Sin contacto'}</p><p className="truncate">{customer.contact_email || customer.contact_phone || 'Sin datos de contacto'}</p></div>
                                    <div className="flex items-center justify-between gap-3 md:block md:text-right"><span className={`rounded-full px-2 py-1 text-[10px] font-bold ${customer.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>{customer.is_active ? 'Activo' : 'Inactivo'}</span><p className="mt-1 text-[11px] text-slate-400">{customer.quote_count} cot. · {customer.operation_count} op.</p></div>
                                </button>
                            ))}
                        </div>
                    )}
                </section>

                <aside className="rounded-2xl border bg-white p-5">
                    {detailLoading ? <div className="flex h-40 items-center justify-center"><Loader2 className="animate-spin text-primary" /></div> : !selected ? (
                        <div className="flex h-40 flex-col items-center justify-center gap-2 text-center text-slate-400"><Building2 /><p className="text-sm">Selecciona un cliente para ver su historial 360.</p></div>
                    ) : (
                        <div className="space-y-5">
                            <div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wider text-primary">Cliente 360</p><h2 className="text-xl font-bold text-slate-800">{selected.customer.display_name}</h2><p className="text-xs text-slate-400">{selected.customer.tax_id || 'RFC no capturado'}</p></div><button onClick={() => openForm(selected.customer)} className="rounded-lg border p-2 text-slate-500"><Edit3 size={15} /></button></div>
                            <div className="grid grid-cols-3 gap-2">{[['Deals', selected.summary.deal_count], ['Cotizaciones', selected.summary.quote_count], ['Operaciones', selected.summary.operation_count]].map(([label, value]) => <div key={label} className="rounded-xl bg-slate-50 p-3 text-center"><p className="text-lg font-bold text-slate-800">{value}</p><p className="text-[10px] text-slate-400">{label}</p></div>)}</div>
                            <div className="grid grid-cols-2 gap-2"><div className="rounded-xl border p-3"><p className="text-[10px] uppercase text-slate-400">Total cotizado</p><p className="text-sm font-bold text-slate-700">{formatCurrencyTotals(selected.summary.quoted_totals)}</p></div><div className="rounded-xl border p-3"><p className="text-[10px] uppercase text-slate-400">Venta operada</p><p className="text-sm font-bold text-slate-700">{formatCurrencyTotals(selected.summary.operation_sell_totals)}</p></div></div>
                            <div className="space-y-2 text-sm text-slate-600">{selected.customer.contact_name && <p className="font-semibold">{selected.customer.contact_name}</p>}{selected.customer.contact_email && <p className="flex items-center gap-2"><Mail size={14} />{selected.customer.contact_email}</p>}{selected.customer.contact_phone && <p className="flex items-center gap-2"><Phone size={14} />{selected.customer.contact_phone}</p>}{selected.customer.notes && <p className="rounded-xl bg-slate-50 p-3 text-xs leading-relaxed">{selected.customer.notes}</p>}</div>
                            <div><p className="mb-2 text-xs font-bold uppercase tracking-wider text-slate-400">Actividad reciente</p>{selected.operations.length === 0 && selected.quotes.length === 0 ? <p className="text-xs text-slate-400">Aún no hay cotizaciones u operaciones relacionadas.</p> : <div className="space-y-2">{selected.operations.slice(0, 3).map((operation) => <div key={operation.id} className="rounded-lg border p-2 text-xs"><span className="font-bold text-slate-700">{operation.reference_code}</span><span className="float-right text-slate-400">{operation.status}</span></div>)}</div>}</div>
                        </div>
                    )}
                </aside>
            </div>

            {selected && <EntityDocumentsPanel tenantId={tenantId} sourceModule="commercial" entityType="customer" entityId={selected.customer.id} title="Documentos del cliente" />}
            {modalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/30 p-4 backdrop-blur-sm">
                    <form onSubmit={submit} className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl">
                        <div className="mb-5 flex items-center justify-between"><div><h2 className="text-lg font-bold text-slate-800">{editing ? 'Editar cliente' : 'Nuevo cliente'}</h2><p className="text-xs text-slate-400">Directorio comercial canónico</p></div><button type="button" onClick={() => { setModalOpen(false); setEditing(null); setForm(EMPTY_FORM); }}><X size={18} /></button></div>
                        <div className="grid gap-4 sm:grid-cols-2">
                            <Field label="Nombre comercial *" value={form.display_name} onChange={(value) => setForm({ ...form, display_name: value })} />
                            <Field label="Razón social" value={form.legal_name} onChange={(value) => setForm({ ...form, legal_name: value })} />
                            <Field label="RFC" value={form.tax_id} onChange={(value) => setForm({ ...form, tax_id: value })} />
                            <Field label="Contacto" value={form.contact_name} onChange={(value) => setForm({ ...form, contact_name: value })} />
                            <Field label="Correo" type="email" value={form.contact_email} onChange={(value) => setForm({ ...form, contact_email: value })} />
                            <Field label="Teléfono" value={form.contact_phone} onChange={(value) => setForm({ ...form, contact_phone: value })} />
                            <Field label="Correo de facturación" type="email" value={form.billing_email} onChange={(value) => setForm({ ...form, billing_email: value })} />
                            <label className="space-y-1 text-xs font-bold text-slate-500">Moneda preferida<select value={form.preferred_currency} onChange={(event) => setForm({ ...form, preferred_currency: event.target.value as CommercialCurrency })} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal text-slate-700"><option>MXN</option><option>USD</option></select></label>
                            <label className="space-y-1 text-xs font-bold text-slate-500 sm:col-span-2">Notas<textarea value={form.notes ?? ''} onChange={(event) => setForm({ ...form, notes: event.target.value })} className="min-h-20 w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal text-slate-700" /></label>
                            <label className="flex items-center gap-2 text-sm text-slate-600"><input type="checkbox" checked={form.is_active ?? true} onChange={(event) => setForm({ ...form, is_active: event.target.checked })} /> Cliente activo</label>
                        </div>
                        <div className="mt-6 flex justify-end gap-2"><button type="button" onClick={() => { setModalOpen(false); setEditing(null); setForm(EMPTY_FORM); }} className="rounded-xl px-4 py-2 text-sm font-semibold text-slate-500">Cancelar</button><button disabled={saving || !form.display_name.trim()} className="flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">{saving && <Loader2 size={14} className="animate-spin" />} Guardar</button></div>
                    </form>
                </div>
            )}
        </div>
    );
}

function Field({ label, value, onChange, type = 'text' }: { label: string; value?: string; onChange: (value: string) => void; type?: string }) {
    return <label className="space-y-1 text-xs font-bold text-slate-500">{label}<input type={type} value={value ?? ''} onChange={(event) => onChange(event.target.value)} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal text-slate-700 outline-none focus:ring-2 focus:ring-primary/15" /></label>;
}

function formatCurrencyTotals(totals: Partial<Record<CommercialCurrency, number>>): string {
    const values = (['MXN', 'USD'] as const)
        .filter((currency) => totals[currency] !== undefined)
        .map((currency) => formatCommercialCurrency(totals[currency] ?? 0, currency));
    return values.length ? values.join(' · ') : 'Sin importes';
}
