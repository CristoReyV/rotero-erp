import { useSearchParams } from 'react-router-dom';
import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { OperationsTable } from '@/components/operations/OperationsTable';
import { Operation360Panel } from '@/components/operations/Operation360Panel';
import { deliveryCsv, type DeliveryPage, deliveryPage } from '@/services/companyDelivery.service';
import { type DbOperation, mapDbOperationToUI } from '@/services/operationsContracts';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';
import { downloadCsvContent } from '@/utils/csv';
import type { Operation } from '@/types/operations';
import { AssignmentDrawer } from '@/components/operations/AssignmentDrawer';
import { getOperation, transitionOperationStatus } from '@/services/operations.service';

export default function CompanyOperationsPage() {
    const [params, setParams] = useSearchParams();
    const deepLink = params.get('operation_id') ?? params.get('operationId');
    const tenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const [search, setSearch] = useState('');
    const [cursor, setCursor] = useState<string | null>(null);
    const [page, setPage] = useState<DeliveryPage | null>(null);
    const [selected, setSelected] = useState<Operation | null>(null);
    const [assigning, setAssigning] = useState<Operation | null>(null);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const [revision, setRevision] = useState(0);
    const createRequest = useRef(crypto.randomUUID());
    const [creating, setCreating] = useState(false);
    const [busy, setBusy] = useState(false);
    const allowed = hasCompanyCapability('operations.read');
    const capture = (role === 'admin' || role === 'operator') && hasCompanyCapability('operations.capture');
    const manage = (role === 'admin' || role === 'operator') &&
        ['operations.edit', 'operations.plan', 'operations.assign', 'operations.transition', 'operations.evidence.write']
            .some(hasCompanyCapability);
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        setLoading(true);
        setPage(null);
        setError('');
        void deliveryPage(tenant, 'operations', search, cursor).then((result) => {
            if (active) setPage(result);
        }, () => {
            if (active) setError('No fue posible cargar las operaciones autorizadas.');
        })
            .finally(() => {
                if (active) setLoading(false);
            });
        return () => {
            active = false;
        };
    }, [tenant, allowed, search, cursor, revision]);
    useEffect(() => {
        if (!tenant || !allowed || !deepLink) return;
        let active = true;
        void getOperation(deepLink).then((operation) => { if (active) setSelected(operation); }, () => { if (active) setError('La operación solicitada no está disponible en este alcance.'); });
        return () => { active = false; };
    }, [tenant, allowed, deepLink]);
    const select = (operation: Operation | null) => {
        setSelected(operation);
        const next = new URLSearchParams(params);
        next.delete('operationId');
        if (operation?.db_id) next.set('operation_id', operation.db_id); else { next.delete('operation_id'); next.delete('tab'); }
        setParams(next, { replace: true });
    };
    const exportCsv = async () => {
        if (!tenant) return;
        try {
            downloadCsvContent(await deliveryCsv(tenant, 'operations', search), 'operaciones-empresa.csv');
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible exportar.');
        }
    };
    const create = async (form: HTMLFormElement) => {
        if (!tenant || busy) return;
        const fields = new FormData(form);
        setBusy(true);
        setError('');
        try {
            const { data, error: failure } = await supabase.rpc('rpc_delivery_create_operation_once', {
                p_request_id: createRequest.current,
                p_tenant_id: tenant,
                p_reference: fields.get('reference'),
                p_route: fields.get('route'),
                p_customer: fields.get('customer'),
                p_destination_city: fields.get('destination'),
            });
            if (failure || data?.error) throw new Error('capture_failed');
            createRequest.current = crypto.randomUUID();
            setCreating(false);
            setCursor(null);
            setRevision((value) => value + 1);
        } catch {
            setError('No se pudo confirmar la operación. Actualiza el listado antes de reintentar.');
        } finally {
            setBusy(false);
        }
    };
    if (!allowed) return <p role='alert'>Sin capacidad de lectura operativa para esta empresa.</p>;
    return (
        <div className='space-y-5'>
            <div className='flex flex-wrap items-center justify-between gap-3'>
                <h1 className='text-2xl font-bold'>Operaciones</h1>
                <div className='flex gap-3'>
                    <button onClick={() => setRevision((value) => value + 1)}>Actualizar</button>
                    {hasCompanyCapability('export.operational') && (
                        <button
                            className='rounded-xl bg-primary px-4 py-2 text-white'
                            onClick={() => void exportCsv()}
                        >
                            Exportar CSV
                        </button>
                    )}
                    {capture && (
                        <button onClick={() => setCreating((value) => !value)}>Nueva operación</button>
                    )}
                </div>
            </div>
            <p className='text-sm text-slate-500'>
                Sólo registros con empresa resuelta. Los históricos pendientes requieren conciliación y no se
                incluyen en estos totales.
            </p>
            <input
                aria-label='Buscar operaciones'
                placeholder='Referencia, ruta, cliente o proveedor'
                value={search}
                onChange={(event) => {
                    setSearch(event.target.value);
                    setCursor(null);
                    setSelected(null);
                }}
                className='w-full rounded-xl border p-3'
            />
            {loading && <p role='status'>Cargando…</p>}
            {error && <p role='alert'>{error}</p>}
            {creating && (
                <form
                    className='space-y-3 rounded-xl border bg-surface-card p-5'
                    onChange={() => { createRequest.current = crypto.randomUUID(); }}
                    onSubmit={(event) => {
                        event.preventDefault();
                        void create(event.currentTarget);
                    }}
                >
                    <h2 className='font-bold'>Nueva operación planeada</h2>
                    <div className='grid gap-3 sm:grid-cols-2'>
                        {[['reference', 'Referencia', true], ['customer', 'Cliente', false], [
                            'route',
                            'Ruta',
                            false,
                        ], ['destination', 'Ciudad destino', false]].map(([name, label, required]) => (
                            <label key={String(name)} className='text-sm'>
                                {label}
                                <input
                                    name={String(name)}
                                    disabled={busy}
                                    required={Boolean(required)}
                                    maxLength={name === 'route' ? 500 : 160}
                                    className='mt-1 block w-full rounded border p-2'
                                />
                            </label>
                        ))}
                    </div>
                    <button
                        type='submit'
                        disabled={busy}
                        className='rounded-xl bg-primary px-4 py-2 text-white'
                    >
                        Guardar operación
                    </button>
                </form>
            )}
            {page && (
                <>
                    <p className='text-sm'>{page.total} operaciones en este alcance</p>
                    <OperationsTable
                        operations={page.items.map((item) => mapDbOperationToUI(item as DbOperation))}
                        selectedId={selected?.id ?? null}
                        onSelect={select}
                    />
                    <div className='flex gap-4'>
                        <button disabled={!cursor} onClick={() => setCursor(null)}>Primera página</button>
                        <button disabled={!page.next_cursor} onClick={() => setCursor(page.next_cursor)}>
                            Siguiente página
                        </button>
                    </div>
                </>
            )}
            {selected && (
                <div key={selected.db_id}>
                    <Operation360Panel
                        operation={selected}
                        canManage={manage}
                        canManageTracking={false}
                        isAdmin={false}
                        refreshKey={revision}
                        initialTab={params.get('tab')}
                        onClose={() => select(null)}
                        onAssign={() => {
                            if (!selected.db_id) return;
                            void getOperation(selected.db_id).then(setAssigning).catch(() => setError('Actualiza la ficha antes de asignar.'));
                        }}
                        onGenerateTokens={async () => undefined}
                        onTransition={async (status, expectedRevision) => {
                            if (!selected.db_id) return;
                            await transitionOperationStatus(selected.db_id, status, expectedRevision);
                            setRevision((value) => value + 1);
                        }}
                        onOverrideCancel={() => undefined}
                        onOperationsRefresh={async () => setRevision((value) => value + 1)}
                    />
                </div>
            )}
            <AssignmentDrawer isOpen={Boolean(assigning)} operation={assigning}
                onClose={() => setAssigning(null)}
                onAssigned={() => { setAssigning(null); setRevision((value) => value + 1); }} />
        </div>
    );
}
