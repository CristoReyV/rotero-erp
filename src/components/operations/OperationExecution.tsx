import { useEffect, useState, type FormEvent } from 'react';
import { Loader2, PencilLine, Truck } from 'lucide-react';
import { completeOperationPlanning } from '@/services/operations.service';
import type { Operation360Data, OperationPlanningPayload } from '@/types/operations';
import { formatOperationDate } from './operationsControl';
import { validateOperationalChronology } from './operation360';

const localDate = (value?: string | null) => value ? new Date(new Date(value).getTime() - new Date(value).getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '';
const textFromPlace = (place?: Record<string, unknown> | null) => [place?.municipality, place?.state, place?.label].find((value) => typeof value === 'string' && value.trim()) as string | undefined;
const mergePlace = (place: Record<string, unknown> | null | undefined, municipality: string, countryCode: string) => ({
    ...(place ?? {}), municipality, countryCode: typeof place?.countryCode === 'string' ? place.countryCode : countryCode,
});

export function OperationExecution({ data, canManage, onAssign, onRefresh }: { data: Operation360Data; canManage: boolean; onAssign: () => void; onRefresh: () => Promise<void> }) {
    const op = data.operation;
    const [editing, setEditing] = useState(false);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [form, setForm] = useState({ service: '', route: '', origin: '', destination: '', scope: 'national', start: '', end: '', eta: '', cargo: '', notes: '', providerCost: '', customerPrice: '', currency: 'MXN', boxes: '', documentationReceived: '', documentationNote: '' });

    useEffect(() => setForm({
        service: op.service_type || '', route: op.route_summary || '',
        origin: textFromPlace(op.origin_place as unknown as Record<string, unknown>) || '',
        destination: textFromPlace(op.destination_place as unknown as Record<string, unknown>) || '',
        scope: op.operation_scope || 'national', start: localDate(op.operational_window_start), end: localDate(op.operational_window_end), eta: localDate(op.eta),
        cargo: typeof op.cargo_summary?.description === 'string' ? op.cargo_summary.description : '', notes: op.notes || '',
        providerCost: op.provider_cost_amount?.toString() || '', customerPrice: op.customer_price_amount?.toString() || '',
        currency: op.pricing_currency || 'MXN', boxes: op.boxes_placed_days?.toString() || '', documentationReceived: localDate(op.documentation_received_at), documentationNote: op.documentation_received_note || '',
    }), [op]);

    const update = (key: keyof typeof form, value: string) => setForm((current) => ({ ...current, [key]: value }));
    const submit = async (event: FormEvent) => {
        event.preventDefault();
        if (!op.db_id) return;
        const chronologicalError = validateOperationalChronology(form.start, form.end, form.eta || null);
        if (chronologicalError) return setError(chronologicalError);
        setSaving(true); setError(null);
        const payload: OperationPlanningPayload = {
            service_type: form.service,
            origin_place: mergePlace(op.origin_place as unknown as Record<string, unknown>, form.origin, 'MX'),
            destination_place: mergePlace(op.destination_place as unknown as Record<string, unknown>, form.destination, form.scope === 'international' ? 'US' : 'MX'),
            operational_window_start: new Date(form.start).toISOString(), operational_window_end: new Date(form.end).toISOString(),
            route_summary: form.route, destination_city: form.destination,
            eta: form.eta ? new Date(form.eta).toISOString() : undefined, eta_display: form.eta ? formatOperationDate(new Date(form.eta).toISOString()) : undefined,
            operation_scope: form.scope as 'national' | 'international', execution_type: op.execution_type || 'third_party',
            cargo_summary: { ...(op.cargo_summary ?? {}), description: form.cargo }, notes: form.notes,
            provider_cost_amount: form.providerCost ? Number(form.providerCost) : null, customer_price_amount: form.customerPrice ? Number(form.customerPrice) : null,
            pricing_currency: form.currency as 'MXN' | 'USD', boxes_placed_days: form.boxes ? Number(form.boxes) : null,
            documentation_received_at: form.documentationReceived ? new Date(form.documentationReceived).toISOString() : null, documentation_received_note: form.documentationNote,
            service_catalog_item_id: op.service_catalog_item_id, service_catalog_snapshot: op.service_catalog_snapshot ?? {},
        };
        try { await completeOperationPlanning(op.db_id, payload); await onRefresh(); setEditing(false); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar la planeación.'); }
        finally { setSaving(false); }
    };

    return <div className="space-y-5">
        <div className="flex min-w-0 flex-wrap items-center justify-between gap-3"><div className="min-w-0"><h3 className="font-bold text-slate-800">Planeación operativa</h3><p className="text-xs text-slate-400">Servicio, ruta, ventana, carga y economía operativa.</p></div>{canManage && <button type="button" onClick={() => setEditing((value) => !value)} className="inline-flex items-center gap-2 rounded-xl border border-slate-200 px-3 py-2 text-xs font-bold text-slate-600"><PencilLine size={14} />{editing ? 'Cancelar edición' : 'Editar planeación'}</button>}</div>
        {editing ? <form onSubmit={submit} className="grid gap-3 rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:grid-cols-2 lg:grid-cols-3">
            {[['Servicio','service'],['Ruta','route'],['Origen','origin'],['Destino','destination'],['Carga','cargo'],['Notas','notes'],['Nota recepción documental','documentationNote']].map(([label,key]) => <label key={key} className="text-xs font-bold text-slate-500">{label}<input required={['service','origin','destination'].includes(key)} value={form[key as keyof typeof form]} onChange={(e) => update(key as keyof typeof form, e.target.value)} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal text-slate-700" /></label>)}
            <label className="text-xs font-bold text-slate-500">Alcance<select value={form.scope} onChange={(e) => update('scope', e.target.value)} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal"><option value="national">Nacional</option><option value="international">Internacional</option></select></label>
            {[['Inicio ventana','start'],['Fin ventana','end'],['ETA','eta'],['Recepción documental','documentationReceived']].map(([label,key]) => <label key={key} className="text-xs font-bold text-slate-500">{label}<input required={key === 'start' || key === 'end'} type="datetime-local" value={form[key as keyof typeof form]} onChange={(e) => update(key as keyof typeof form, e.target.value)} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal" /></label>)}
            {[['Costo proveedor','providerCost'],['Venta cliente','customerPrice'],['Días cajas colocadas','boxes']].map(([label,key]) => <label key={key} className="text-xs font-bold text-slate-500">{label}<input min="0" step={key === 'boxes' ? '1' : '0.01'} type="number" value={form[key as keyof typeof form]} onChange={(e) => update(key as keyof typeof form, e.target.value)} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal" /></label>)}
            <label className="text-xs font-bold text-slate-500">Moneda<select value={form.currency} onChange={(e) => update('currency', e.target.value)} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal"><option>MXN</option><option>USD</option></select></label>
            {error && <p className="sm:col-span-2 lg:col-span-3 rounded-lg bg-red-50 p-3 text-xs font-semibold text-red-700">{error}</p>}
            <div className="sm:col-span-2 lg:col-span-3 flex justify-end"><button disabled={saving} className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white">{saving && <Loader2 size={14} className="animate-spin" />}Guardar planeación</button></div>
        </form> : <div className="grid gap-3 rounded-2xl border border-slate-200 p-4 sm:grid-cols-2 lg:grid-cols-4">{[['Servicio',op.service_type],['Ruta',op.route_summary],['Ventana inicio',formatOperationDate(op.operational_window_start ?? undefined)],['Ventana fin',formatOperationDate(op.operational_window_end ?? undefined)],['Carga',form.cargo],['Días cajas',op.boxes_placed_days?.toString()],['Recepción documental',formatOperationDate(op.documentation_received_at ?? undefined)],['Nota documental',op.documentation_received_note],['Snapshot de servicio',Object.keys(op.service_catalog_snapshot ?? {}).length ? 'Conservado' : 'Datos por confirmar']].map(([label,value]) => <div key={label}><p className="text-[10px] font-bold uppercase text-slate-400">{label}</p><p className="mt-1 text-sm font-semibold text-slate-700">{value || 'Datos por confirmar'}</p></div>)}</div>}
        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-5"><div><h3 className="font-bold text-slate-800">Asignación broker-first</h3><p className="text-xs text-slate-400">Proveedor contratado; chofer y unidad externos son snapshots opcionales.</p></div>{canManage && <button type="button" onClick={onAssign} className="inline-flex items-center gap-2 rounded-xl bg-sky-600 px-4 py-2.5 text-xs font-bold text-white"><Truck size={15} />Asignar o cambiar</button>}</div>
        <div className="space-y-2">{data.assignmentHistory.length ? data.assignmentHistory.map((item) => <div key={item.id} className="rounded-xl border border-slate-200 p-3"><div className="flex justify-between gap-3"><p className="text-xs font-bold text-slate-700">{item.change_type === 'reassignment' ? 'Cambio de asignación' : 'Asignación inicial'}</p><span className="text-[11px] text-slate-400">{formatOperationDate(item.changed_at)}</span></div><p className="mt-1 text-xs text-slate-500">{item.new_provider_name_snapshot || item.new_driver_name_snapshot || 'Proveedor por confirmar'}{item.reason ? ` · ${item.reason}` : ''}</p></div>) : <p className="rounded-xl border border-dashed border-slate-300 p-5 text-center text-xs text-slate-400">Sin historial de asignación.</p>}</div>
    </div>;
}
