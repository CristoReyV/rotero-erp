import { AlertTriangle, Download, Plus, RefreshCw } from 'lucide-react';
import type * as React from 'react';
import { useCallback, useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { ClaimDetail } from '@/components/claims/ClaimDetail';
import { PageHeader } from '@/components/PageHeader';
import { SavedViewsMenu } from '@/components/productivity/SavedViewsMenu';
import { createClaim, exportClaims, getClaimReferenceData, getClaimReporting, listClaims } from '@/services/claims.service';
import { useAuthStore } from '@/store/authStore';
import type { ClaimListItem, ClaimReferenceData, ClaimReporting, ClaimType } from '@/types/claims';
import { downloadCsvContent, serializeCsv } from '@/utils/csv';
import { CLAIM_PRIORITY_LABELS, CLAIM_STATUS_LABELS, CLAIM_TYPE_LABELS } from '@/utils/presentationLabels';

const VIEWS = [['all', 'Todas'], ['open', 'Abiertas'], ['critical', 'Críticas'], ['sla', 'SLA vencido'], ['recurrence', 'Recurrencia']] as const;
const CLAIM_TYPES = Object.keys(CLAIM_TYPE_LABELS) as ClaimType[];
const ROOT_CAUSE_LABELS: Record<string, string> = {
    unknown: 'Por determinar', carrier_delay: 'Retraso del transportista', planning: 'Planeación',
    documentation: 'Documentación', communication: 'Comunicación', provider_execution: 'Ejecución del proveedor', other: 'Otra',
};

export default function ClaimsPage() {
    const tenantId = useAuthStore((state) => state.activeTenant);
    const [params, setParams] = useSearchParams();
    const [items, setItems] = useState<ClaimListItem[]>([]);
    const [refs, setRefs] = useState<ClaimReferenceData | null>(null);
    const [report, setReport] = useState<ClaimReporting | null>(null);
    const [busy, setBusy] = useState(true);
    const [error, setError] = useState('');
    const [creating, setCreating] = useState(false);
    const view = params.get('view') || 'all';
    const query = params.get('q') || '';
    const claimId = params.get('claimId');
    const operationId = params.get('operationId');
    const incidentId = params.get('incidentId');

    const filters = (): Record<string, unknown> => ({
        query,
        ...(view === 'open' ? { status: 'open,triage,investigating,awaiting_customer,awaiting_provider,action_in_progress' } : {}),
        ...(view === 'critical' ? { priority: 'critical' } : {}),
        ...(view === 'sla' ? { sla_breached: true } : {}),
        date_from: params.get('dateFrom') || undefined,
        date_to: params.get('dateTo') || undefined,
    });

    const load = useCallback(async () => {
        if (!tenantId) return;
        setBusy(true);
        try {
            const [start, end] = [new Date(Date.now() - 90 * 86400000), new Date()];
            const [next, reference, reporting] = await Promise.all([
                listClaims(tenantId, filters()),
                getClaimReferenceData(tenantId),
                getClaimReporting(tenantId, start, end),
            ]);
            setItems(next);
            setRefs(reference);
            setReport(reporting);
            setError('');
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible cargar las reclamaciones.');
        } finally {
            setBusy(false);
        }
    }, [tenantId, view, query, params.get('dateFrom'), params.get('dateTo')]);

    useEffect(() => { void load(); }, [load]);

    const patch = (values: Record<string, string | null>) => {
        const next = new URLSearchParams(params);
        Object.entries(values).forEach(([key, value]) => value ? next.set(key, value) : next.delete(key));
        setParams(next, { replace: true });
    };

    const create = async (event: React.FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!tenantId) return;
        const form = new FormData(event.currentTarget);
        setCreating(true);
        try {
            const created = await createClaim(tenantId, {
                operation_id: form.get('operation_id') || null,
                customer_id: form.get('customer_id') || null,
                provider_id: form.get('provider_id') || null,
                claim_type: form.get('claim_type'),
                priority: form.get('priority'),
                subject: form.get('subject'),
                description: form.get('description'),
                source_incident_id: incidentId || null,
            });
            patch({ action: null, operationId: null, incidentId: null, claimId: created.id });
            await load();
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible crear la reclamación.');
        } finally {
            setCreating(false);
        }
    };

    const exportCsv = async () => {
        if (!tenantId) return;
        const rows = await exportClaims(tenantId, filters());
        downloadCsvContent(serializeCsv(rows), `reclamaciones-${new Date().toISOString().slice(0, 10)}.csv`);
    };

    if (!tenantId) return <p>Selecciona una empresa activa.</p>;

    return <div className="min-w-0 max-w-full space-y-5">
        <PageHeader title="Reclamaciones" subtitle="Seguimiento, evidencia, SLA y resolución" actions={<>
            <SavedViewsMenu tenantId={tenantId} module="claims" filters={{ view, q: query, dateFrom: params.get('dateFrom'), dateTo: params.get('dateTo') }} onApply={(saved) => patch({ view: typeof saved.view === 'string' ? saved.view : 'all', q: typeof saved.q === 'string' ? saved.q : null, dateFrom: typeof saved.dateFrom === 'string' ? saved.dateFrom : null, dateTo: typeof saved.dateTo === 'string' ? saved.dateTo : null })} />
            <button onClick={() => void exportCsv()} className="rounded-xl border bg-surface-card p-2" title="Exportar CSV seguro"><Download size={16} /></button>
            <button onClick={() => patch({ action: 'new' })} className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-xs font-black text-white"><Plus size={14} />Nueva reclamación</button>
        </>} />

        <nav className="flex max-w-full gap-1 overflow-x-auto overscroll-x-contain rounded-2xl border bg-surface-card p-1.5">
            {VIEWS.map(([id, label]) => <button key={id} onClick={() => patch({ view: id })} className={`shrink-0 rounded-xl px-4 py-2 text-xs font-bold ${view === id ? 'bg-slate-900 text-white' : 'text-slate-500'}`}>{label}</button>)}
        </nav>

        <div className="grid min-w-0 gap-3 md:grid-cols-[minmax(0,1fr)_auto_auto]">
            <input value={query} onChange={(event) => patch({ q: event.target.value || null })} placeholder="Folio, asunto, operación, cliente o proveedor" className="min-w-0 rounded-xl border bg-surface-card px-4 py-2 text-sm" />
            <input type="date" value={params.get('dateFrom') || ''} onChange={(event) => patch({ dateFrom: event.target.value || null })} className="min-w-0 rounded-xl border px-3 text-sm" />
            <input type="date" value={params.get('dateTo') || ''} onChange={(event) => patch({ dateTo: event.target.value || null })} className="min-w-0 rounded-xl border px-3 text-sm" />
        </div>

        {error && <p className="break-words rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}

        {view === 'recurrence' && report && <section className="grid min-w-0 gap-3 rounded-2xl border bg-surface-card p-4 md:grid-cols-2">
            <div className="min-w-0"><h3 className="text-sm font-black">Causas raíz · 90 días</h3>{report.root_causes.map((item) => <p key={item.root_cause} className="break-words text-xs">{ROOT_CAUSE_LABELS[item.root_cause] ?? 'Causa registrada'}: {item.total}</p>)}</div>
            <div className="min-w-0"><h3 className="text-sm font-black">Recurrencia por proveedor</h3>{report.provider_recurrence.map((item) => <p key={item.provider_id} className="break-words text-xs">{item.provider_name}: {item.total}</p>)}</div>
        </section>}

        <section className="min-w-0 overflow-hidden rounded-2xl border bg-surface-card">
            {busy ? <p className="p-8 text-center text-sm text-slate-400"><RefreshCw className="mx-auto mb-2 animate-spin" />Cargando…</p> : items.length === 0 ? <p className="p-10 text-center text-sm text-slate-400">Sin reclamaciones para estos filtros.</p> : items.map((item) => <button key={item.id} onClick={() => patch({ claimId: item.id })} className="grid w-full min-w-0 gap-2 border-b p-4 text-left last:border-0 active:bg-semantic-neutral-soft sm:hover:bg-semantic-neutral-soft md:grid-cols-[180px_minmax(0,1fr)_150px_120px]">
                <span className="min-w-0"><b className="block truncate text-sm">{item.claim_number}</b><small>{new Date(item.reported_at).toLocaleDateString('es-MX')}</small></span>
                <span className="min-w-0"><b className="block break-words text-sm">{item.subject}</b><small className="block break-words text-slate-400">{item.customer_name || item.provider_name || item.operation_reference}</small></span>
                <span className="text-xs">{CLAIM_STATUS_LABELS[item.status]}<br />{CLAIM_TYPE_LABELS[item.claim_type]}</span>
                <span className={`flex items-center gap-1 text-xs font-black uppercase ${item.priority === 'critical' ? 'text-red-700' : 'text-slate-600'}`}>{(item.sla?.first_response_overdue || item.sla?.resolution_overdue) && <AlertTriangle size={14} />} {CLAIM_PRIORITY_LABELS[item.priority]}</span>
            </button>)}
        </section>

        {params.get('action') === 'new' && refs && <div className="fixed inset-0 z-50 grid place-items-center bg-slate-950/50 p-2 sm:p-4">
            <form onSubmit={(event) => void create(event)} className="max-h-[100dvh] w-full min-w-0 max-w-xl space-y-3 overflow-y-auto rounded-2xl bg-surface-card p-4 sm:p-6">
                <h2 className="text-lg font-black">Nueva reclamación operativa</h2>
                <div className="grid min-w-0 gap-2 md:grid-cols-3">
                    <select name="operation_id" defaultValue={operationId ?? ''} className="min-w-0 rounded-xl border p-2 text-sm"><option value="">Operación (opcional)</option>{refs.operations.map((item) => <option key={item.id} value={item.id}>{item.reference_code}</option>)}</select>
                    <select name="customer_id" defaultValue={refs.operations.find((item) => item.id === operationId)?.customer_id ?? ''} className="min-w-0 rounded-xl border p-2 text-sm"><option value="">Cliente</option>{refs.customers.map((item) => <option key={item.id} value={item.id}>{item.display_name}</option>)}</select>
                    <select name="provider_id" defaultValue={refs.operations.find((item) => item.id === operationId)?.provider_id ?? ''} className="min-w-0 rounded-xl border p-2 text-sm"><option value="">Proveedor</option>{refs.providers.map((item) => <option key={item.id} value={item.id}>{item.display_name}</option>)}</select>
                </div>
                <div className="grid min-w-0 gap-2 md:grid-cols-2">
                    <select name="claim_type" defaultValue="service_quality" className="min-w-0 rounded-xl border p-2 text-sm">{CLAIM_TYPES.map((type) => <option key={type} value={type}>{CLAIM_TYPE_LABELS[type]}</option>)}</select>
                    <select name="priority" defaultValue="medium" className="min-w-0 rounded-xl border p-2 text-sm"><option value="critical">Crítica</option><option value="high">Alta</option><option value="medium">Media</option><option value="low">Baja</option></select>
                </div>
                <input required minLength={3} maxLength={180} name="subject" placeholder="Asunto" className="w-full min-w-0 rounded-xl border p-3 text-sm" />
                <textarea required minLength={3} maxLength={10000} name="description" placeholder="Descripción y contexto" className="h-28 w-full min-w-0 rounded-xl border p-3 text-sm" />
                <p className="text-xs text-slate-400">Debe existir al menos Operación, Cliente o Proveedor. El incidente operativo, si existe, permanece separado.</p>
                <div className="flex flex-wrap justify-end gap-2"><button type="button" onClick={() => patch({ action: null, operationId: null, incidentId: null })} className="rounded-xl border px-4 py-2 text-xs font-black">Cancelar</button><button disabled={creating} className="rounded-xl bg-primary px-4 py-2 text-xs font-black text-white">{creating ? 'Creando…' : 'Crear expediente'}</button></div>
            </form>
        </div>}

        {claimId && <ClaimDetail tenantId={tenantId} claimId={claimId} onClose={() => patch({ claimId: null })} />}
    </div>;
}
