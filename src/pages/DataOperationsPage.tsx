import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { ImportWizard } from '@/components/dataOperations/ImportWizard';
import { ImportHistory } from '@/components/dataOperations/ImportHistory';
import { ExportCenter } from '@/components/dataOperations/ExportCenter';
import { useAuthStore } from '@/store/authStore';
import type { ImportEntity } from '@/types/dataOperations';

type View = 'import' | 'history' | 'export'; const VIEWS: Array<{ id: View; label: string }> = [{ id: 'import', label: 'Importar' }, { id: 'history', label: 'Historial' }, { id: 'export', label: 'Exportar' }];
export default function DataOperationsPage() {
    const tenantId = useAuthStore((state) => state.activeTenant); const [params, setParams] = useSearchParams(); const requested = params.get('view'); const view: View = VIEWS.some((item) => item.id === requested) ? requested as View : 'import'; const requestedEntity = params.get('entity'); const initialEntity: ImportEntity = requestedEntity === 'providers' || requestedEntity === 'operations' ? requestedEntity : 'customers';
    const setView = (next: View) => { const copy = new URLSearchParams(params); copy.set('view', next); setParams(copy, { replace: true }); };
    if (!tenantId) return <p className="rounded-xl border bg-white p-5 text-sm text-slate-500">Selecciona un tenant activo.</p>;
    return <div className="space-y-5"><PageHeader title="Datos e importación" subtitle="Importación CSV segura, exportación paginada e historial auditable" /><nav className="flex gap-1 rounded-2xl border bg-white p-1.5">{VIEWS.map((item) => <button key={item.id} onClick={() => setView(item.id)} className={`rounded-xl px-4 py-2 text-xs font-bold ${view === item.id ? 'bg-primary text-white' : 'text-slate-500'}`}>{item.label}</button>)}</nav>{view === 'import' && <ImportWizard tenantId={tenantId} initialEntity={initialEntity} />}{view === 'history' && <ImportHistory tenantId={tenantId} />}{view === 'export' && <ExportCenter tenantId={tenantId} />}</div>;
}
