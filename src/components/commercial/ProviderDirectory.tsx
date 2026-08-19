import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Building, Edit3, Inbox, Loader2, Mail, Phone, Plus, Search, X } from 'lucide-react';
import { getCommercialErrorMessage, listProviders, upsertProvider } from '@/services/commercial.service';
import type { LogisticsProvider, LogisticsProviderPayload } from '@/types/commercial';
import { formatCommercialCurrency } from '@/utils/commercialCalculations';

const EMPTY_PROVIDER: LogisticsProviderPayload = {
    display_name: '', legal_name: '', tax_id: '', contact_name: '', contact_email: '',
    contact_phone: '', billing_email: '', notes: '', is_active: true,
};

export function ProviderDirectory({ tenantId }: { tenantId: string }) {
    const [items, setItems] = useState<LogisticsProvider[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [search, setSearch] = useState('');
    const [activeFilter, setActiveFilter] = useState<'all' | 'active' | 'inactive'>('all');
    const [selected, setSelected] = useState<LogisticsProvider | null>(null);
    const [editing, setEditing] = useState<LogisticsProvider | null>(null);
    const [form, setForm] = useState<LogisticsProviderPayload>(EMPTY_PROVIDER);
    const [modalOpen, setModalOpen] = useState(false);
    const [saving, setSaving] = useState(false);

    const load = useCallback(async () => {
        setLoading(true); setError(null);
        try {
            const data = await listProviders(tenantId, {
                searchText: search.trim() || undefined,
                active: activeFilter === 'all' ? undefined : activeFilter === 'active',
            });
            setItems(data);
        } catch (loadError) { setError(getCommercialErrorMessage(loadError)); }
        finally { setLoading(false); }
    }, [activeFilter, search, tenantId]);

    useEffect(() => { void load(); }, [load]);

    const openForm = (provider?: LogisticsProvider) => {
        setEditing(provider ?? null);
        setForm(provider ? {
            display_name: provider.display_name, legal_name: provider.legal_name ?? '', tax_id: provider.tax_id ?? '',
            contact_name: provider.contact_name ?? '', contact_email: provider.contact_email ?? '',
            contact_phone: provider.contact_phone ?? '', billing_email: provider.billing_email ?? '',
            notes: provider.notes ?? '', is_active: provider.is_active,
        } : EMPTY_PROVIDER);
        setModalOpen(true);
    };

    const submit = async (event: FormEvent) => {
        event.preventDefault(); setSaving(true); setError(null);
        try {
            const result = await upsertProvider(tenantId, editing?.id ?? null, form);
            setModalOpen(false); setEditing(null); setForm(EMPTY_PROVIDER);
            await load();
            const updated = (await listProviders(tenantId)).find((item) => item.id === result.id);
            if (updated) setSelected(updated);
        } catch (saveError) { setError(getCommercialErrorMessage(saveError)); }
        finally { setSaving(false); }
    };

    return (
        <div className="space-y-4">
            <div className="flex flex-col gap-3 rounded-2xl border bg-white p-4 lg:flex-row lg:items-center">
                <form onSubmit={(event) => { event.preventDefault(); void load(); }} className="flex min-w-0 flex-1 gap-2"><div className="relative min-w-0 flex-1"><Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Buscar proveedor, RFC o contacto" className="w-full rounded-xl border bg-slate-50 py-2.5 pl-9 pr-3 text-sm" /></div><button className="rounded-xl border px-4 text-xs font-bold text-slate-600">Buscar</button></form>
                <div className="flex gap-2"><select value={activeFilter} onChange={(event) => setActiveFilter(event.target.value as typeof activeFilter)} className="rounded-xl border bg-white px-3 py-2.5 text-xs font-semibold"><option value="all">Todos</option><option value="active">Activos</option><option value="inactive">Inactivos</option></select><button onClick={() => openForm()} className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white"><Plus size={15} /> Nuevo proveedor</button></div>
            </div>
            <div className="rounded-xl border border-blue-100 bg-blue-50 p-3 text-xs text-blue-700">Directorio de proveedores externos contratados. No representa flota propia ni crea accesos al ERP.</div>
            {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
            <div className="grid gap-4 xl:grid-cols-[minmax(0,1.25fr)_minmax(320px,.75fr)]">
                <section className="overflow-hidden rounded-2xl border bg-white">{loading ? <div className="flex h-48 items-center justify-center"><Loader2 className="animate-spin text-primary" /></div> : items.length === 0 ? <div className="flex h-48 flex-col items-center justify-center gap-2 text-slate-400"><Inbox /><p className="text-sm">No hay proveedores con estos filtros.</p></div> : <div className="divide-y">{items.map((provider) => <button key={provider.id} onClick={() => setSelected(provider)} className="grid w-full gap-3 p-4 text-left hover:bg-slate-50 md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_auto] md:items-center"><div className="min-w-0"><div className="flex items-center gap-2"><Building size={16} className="text-primary" /><p className="truncate font-bold text-slate-800">{provider.display_name}</p></div><p className="mt-1 truncate text-xs text-slate-400">{provider.legal_name || provider.tax_id || 'Proveedor externo'}</p></div><div className="text-xs text-slate-500"><p>{provider.contact_name || 'Sin contacto'}</p><p className="truncate">{provider.contact_email || provider.contact_phone || 'Sin datos de contacto'}</p></div><div className="text-right"><span className={`rounded-full px-2 py-1 text-[10px] font-bold ${provider.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>{provider.is_active ? 'Activo' : 'Inactivo'}</span><p className="mt-1 text-[11px] text-slate-400">{provider.quote_count} cot. · {provider.operation_count} op.</p></div></button>)}</div>}</section>
                <aside className="rounded-2xl border bg-white p-5">{!selected ? <div className="flex h-40 flex-col items-center justify-center gap-2 text-center text-slate-400"><Building /><p className="text-sm">Selecciona un proveedor para consultar su relación comercial.</p></div> : <div className="space-y-5"><div className="flex items-start justify-between"><div><p className="text-xs font-bold uppercase tracking-wider text-primary">Proveedor contratado</p><h2 className="text-xl font-bold text-slate-800">{selected.display_name}</h2><p className="text-xs text-slate-400">{selected.tax_id || 'RFC no capturado'}</p></div><button onClick={() => openForm(selected)} className="rounded-lg border p-2 text-slate-500"><Edit3 size={15} /></button></div><div className="grid grid-cols-3 gap-2">{[['Cotizaciones', selected.quote_count], ['Operaciones', selected.operation_count]].map(([label, value]) => <div key={label} className="rounded-xl bg-slate-50 p-3 text-center"><p className="text-lg font-bold">{value}</p><p className="text-[10px] text-slate-400">{label}</p></div>)}<div className="rounded-xl bg-slate-50 p-3 text-center"><p className="truncate text-xs font-bold">{formatCurrencyTotals(selected.contracted_cost_totals)}</p><p className="text-[10px] text-slate-400">Costo histórico*</p></div></div><p className="text-[10px] text-slate-400">* Totales separados por moneda; no aplica conversión FX.</p><div className="space-y-2 text-sm text-slate-600">{selected.contact_name && <p className="font-semibold">{selected.contact_name}</p>}{selected.contact_email && <p className="flex gap-2"><Mail size={14} />{selected.contact_email}</p>}{selected.contact_phone && <p className="flex gap-2"><Phone size={14} />{selected.contact_phone}</p>}{selected.notes ? <p className="rounded-xl bg-slate-50 p-3 text-xs leading-relaxed">{selected.notes}</p> : <p className="text-xs text-slate-400">Sin notas de cobertura o capacidad. El esquema actual no tiene catálogos separados de carriles/equipo.</p>}</div></div>}</aside>
            </div>
            {modalOpen && <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/30 p-4 backdrop-blur-sm"><form onSubmit={submit} className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white p-6 shadow-2xl"><div className="mb-5 flex items-center justify-between"><div><h2 className="text-lg font-bold">{editing ? 'Editar proveedor' : 'Nuevo proveedor'}</h2><p className="text-xs text-slate-400">Empresa externa de la red operativa</p></div><button type="button" onClick={() => setModalOpen(false)}><X size={18} /></button></div><div className="grid gap-4 sm:grid-cols-2"><Field label="Nombre comercial *" value={form.display_name} onChange={(value) => setForm({ ...form, display_name: value })} /><Field label="Razón social" value={form.legal_name} onChange={(value) => setForm({ ...form, legal_name: value })} /><Field label="RFC" value={form.tax_id} onChange={(value) => setForm({ ...form, tax_id: value })} /><Field label="Contacto" value={form.contact_name} onChange={(value) => setForm({ ...form, contact_name: value })} /><Field label="Correo" type="email" value={form.contact_email} onChange={(value) => setForm({ ...form, contact_email: value })} /><Field label="Teléfono" value={form.contact_phone} onChange={(value) => setForm({ ...form, contact_phone: value })} /><Field label="Correo de facturación" type="email" value={form.billing_email} onChange={(value) => setForm({ ...form, billing_email: value })} /><label className="flex items-center gap-2 pt-6 text-sm text-slate-600"><input type="checkbox" checked={form.is_active ?? true} onChange={(event) => setForm({ ...form, is_active: event.target.checked })} /> Proveedor activo</label><label className="space-y-1 text-xs font-bold text-slate-500 sm:col-span-2">Notas de servicio, equipo o cobertura<textarea value={form.notes ?? ''} onChange={(event) => setForm({ ...form, notes: event.target.value })} className="min-h-24 w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal" /></label></div><div className="mt-6 flex justify-end gap-2"><button type="button" onClick={() => setModalOpen(false)} className="px-4 py-2 text-sm font-semibold text-slate-500">Cancelar</button><button disabled={saving || !form.display_name.trim()} className="flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">{saving && <Loader2 size={14} className="animate-spin" />} Guardar</button></div></form></div>}
        </div>
    );
}

function Field({ label, value, onChange, type = 'text' }: { label: string; value?: string; onChange: (value: string) => void; type?: string }) {
    return <label className="space-y-1 text-xs font-bold text-slate-500">{label}<input type={type} value={value ?? ''} onChange={(event) => onChange(event.target.value)} className="w-full rounded-xl border bg-slate-50 px-3 py-2.5 text-sm font-normal" /></label>;
}

function formatCurrencyTotals(totals: Partial<Record<'MXN' | 'USD', number>>): string {
    const values = (['MXN', 'USD'] as const)
        .filter((currency) => totals[currency] !== undefined)
        .map((currency) => formatCommercialCurrency(totals[currency] ?? 0, currency));
    return values.length ? values.join(' · ') : 'Sin importes';
}
