import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertTriangle, Ban, Bell, FileOutput, Loader2, RefreshCw, X } from 'lucide-react';
import { getOperation360Data } from '@/services/operations.service';
import type { Operation, Operation360Data } from '@/types/operations';
import { OperationOverview } from './OperationOverview';
import { OperationExecution } from './OperationExecution';
import { OperationTimeline } from './OperationTimeline';
import { OperationIncidents } from './OperationIncidents';
import { OperationDocuments } from './OperationDocuments';
import { OperationEvidence } from './OperationEvidence';
import { OperationCrossings } from './OperationCrossings';
import { OperationEconomics } from './OperationEconomics';
import { OperationReadiness } from './OperationReadiness';
import { getOperationStatus } from './operationsControl';
import { Badge } from '@/components/Badge';

type Tab = 'overview' | 'execution' | 'timeline' | 'incidents' | 'documents' | 'evidence' | 'crossings' | 'economics';
const BASE_TABS: { value: Tab; label: string }[] = [
    { value: 'overview', label: 'Resumen' }, { value: 'execution', label: 'Ejecución' },
    { value: 'timeline', label: 'Historial' }, { value: 'incidents', label: 'Incidencias' },
    { value: 'documents', label: 'Documentos' }, { value: 'evidence', label: 'Evidencias' },
    { value: 'economics', label: 'Economía' },
];

export function Operation360Panel({ operation, canManage, canManageTracking, isAdmin, refreshKey, initialTab, onTabChange, onClose, onAssign, onGenerateTokens, onTransition, onOverrideCancel, onOperationsRefresh }: {
    operation: Operation; canManage: boolean; canManageTracking: boolean; isAdmin: boolean; refreshKey: number;
    initialTab?: string | null; onTabChange?: (tab: Tab) => void;
    onClose: () => void; onAssign: () => void; onGenerateTokens: () => Promise<void>;
    onTransition: (status: string) => Promise<void>; onOverrideCancel: () => void; onOperationsRefresh: () => Promise<void>;
}) {
    const [tab, setTab] = useState<Tab>('overview');
    const [data, setData] = useState<Operation360Data | null>(null);
    const [loading, setLoading] = useState(true);
    const [actionLoading, setActionLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const tabs = useMemo(() => operation.operation_scope === 'international' ? [...BASE_TABS.slice(0, 6), { value: 'crossings' as Tab, label: 'Cruces' }, BASE_TABS[6]] : BASE_TABS, [operation.operation_scope]);
    useEffect(() => { if (initialTab && tabs.some((item) => item.value === initialTab)) setTab(initialTab as Tab); }, [initialTab, tabs]);
    const load = useCallback(async () => { if (!operation.db_id) return; setLoading(true); setError(null); try { setData(await getOperation360Data(operation.db_id)); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar la operación.'); } finally { setLoading(false); } }, [operation.db_id]);
    useEffect(() => { void load(); }, [load, refreshKey]);
    const refresh = async () => { await Promise.all([load(), onOperationsRefresh()]); };
    const transition = async (status: string) => { setActionLoading(true); setError(null); try { await onTransition(status); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cambiar el estado.'); } finally { setActionLoading(false); } };
    const generate = async () => { setActionLoading(true); setError(null); try { await onGenerateTokens(); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible generar las capabilities.'); } finally { setActionLoading(false); } };
    const nextStatus: Record<string, string | undefined> = { draft: 'planned', planned: 'assigned', assigned: 'in_transit', in_transit: 'delivered', delivered: 'closed' };
    const status = getOperationStatus(data?.operation.status ?? operation.status);

    return <div className="fixed inset-0 z-40 bg-slate-950/45 p-2 backdrop-blur-sm sm:p-4" role="dialog" aria-modal="true" aria-label={`Operación ${operation.id}`}>
        <div className="ml-auto flex h-full w-full max-w-7xl flex-col overflow-hidden rounded-2xl bg-white shadow-2xl">
            <header className="flex min-w-0 flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-4 py-4 sm:px-5"><div className="min-w-0"><div className="flex min-w-0 flex-wrap items-center gap-2"><h2 className="min-w-0 break-words text-xl font-black text-slate-900">Operación · {operation.id}</h2><Badge variant={status.variant}>{status.label}</Badge></div><p className="mt-1 text-xs text-slate-400">Ejecución contratada y expediente operativo centralizado</p></div><div className="flex items-center gap-2"><button onClick={() => void refresh()} className="rounded-lg border border-slate-200 p-2 text-slate-500" title="Actualizar"><RefreshCw size={16} /></button><button onClick={onClose} className="rounded-lg bg-slate-100 p-2 text-slate-600" aria-label="Cerrar operación"><X size={18} /></button></div></header>
            <nav className="flex gap-1 overflow-x-auto border-b border-slate-200 px-4 py-2">{tabs.map((item) => <button key={item.value} onClick={() => { setTab(item.value); onTabChange?.(item.value); }} className={`whitespace-nowrap rounded-lg px-3 py-2 text-xs font-bold ${tab === item.value ? 'bg-primary text-white' : 'text-slate-500 hover:bg-slate-100'}`}>{item.label}</button>)}</nav>
            <main className="flex-1 overflow-y-auto p-4 sm:p-6">
                {loading ? <div className="flex h-full items-center justify-center gap-2 text-sm text-slate-400"><Loader2 className="animate-spin" />Cargando expediente operativo…</div> : error && !data ? <div className="mx-auto max-w-xl rounded-2xl border border-red-200 bg-red-50 p-8 text-center"><AlertTriangle className="mx-auto text-red-500" /><p className="mt-3 text-sm font-semibold text-red-700">{error}</p><button onClick={() => void load()} className="mt-4 rounded-lg bg-red-600 px-4 py-2 text-xs font-bold text-white">Reintentar</button></div> : data && <div className="space-y-5">
                    {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-xs font-semibold text-red-700">{error}</div>}
                    {tab === 'overview' && <><OperationOverview operation={data.operation} /><section className="border-t border-slate-100 pt-5"><h3 className="mb-3 font-bold text-slate-800">Preparación para despacho y cierre</h3><OperationReadiness data={data} canManageTracking={canManageTracking} onGenerateTokens={() => void generate()} /></section>{canManage && <div className="flex flex-wrap gap-2 border-t border-slate-100 pt-5">{nextStatus[data.operation.status] && <button disabled={actionLoading} onClick={() => void transition(nextStatus[data.operation.status]!)} className="rounded-xl bg-primary px-4 py-2.5 text-xs font-bold text-white">Avanzar a {getOperationStatus(nextStatus[data.operation.status]!).label}</button>}{isAdmin && data.operation.status !== 'cancelled' && data.operation.status !== 'closed' && <button onClick={onOverrideCancel} className="inline-flex items-center gap-2 rounded-xl bg-red-50 px-4 py-2.5 text-xs font-bold text-red-700"><Ban size={14} />Cancelación con motivo</button>}</div>}<div className="grid gap-3 border-t border-slate-100 pt-5 md:grid-cols-2"><div className="rounded-xl border border-dashed border-slate-300 p-4"><div className="flex items-center gap-2"><Bell size={16} className="text-slate-500" /><p className="text-xs font-bold text-slate-700">Notificaciones internas</p></div><p className="mt-2 text-xs text-slate-500">Consulta disponible desde la ruta relacionada, sin duplicar registros.</p></div><div className="rounded-xl border border-dashed border-slate-300 p-4"><div className="flex items-center gap-2"><FileOutput size={16} className="text-slate-500" /><p className="text-xs font-bold text-slate-700">Generación documental</p></div><p className="mt-2 text-xs text-slate-500">Los documentos operativos se administran desde el expediente documental.</p></div></div></>}
                    {tab === 'execution' && <OperationExecution data={data} canManage={canManage} onAssign={onAssign} onRefresh={refresh} />}
                    {tab === 'timeline' && <OperationTimeline data={data} />}
                    {tab === 'incidents' && <OperationIncidents data={data} canManage={canManage} isAdmin={isAdmin} onRefresh={refresh} />}
                    {tab === 'documents' && <OperationDocuments data={data} canManage={canManage} onRefresh={refresh} />}
                    {tab === 'evidence' && <OperationEvidence data={data} canManage={canManage} onRefresh={refresh} />}
                    {tab === 'crossings' && <OperationCrossings data={data} canManage={canManage} onRefresh={refresh} />}
                    {tab === 'economics' && <OperationEconomics data={data} />}
                </div>}
            </main>
        </div>
    </div>;
}
