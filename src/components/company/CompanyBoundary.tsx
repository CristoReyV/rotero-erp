import { type ReactNode, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { type AuthorizedCompany, useCompanyStore } from '@/store/companyStore';

const validCompanies = (data: unknown): data is AuthorizedCompany[] =>
    Array.isArray(data) &&
    data.every((c) =>
        c && typeof c.id === 'string' && /^[\da-f-]{36}$/i.test(c.id) && typeof c.display_name === 'string' &&
        typeof c.legal_name === 'string' && typeof c.rfc === 'string' &&
        Array.isArray(c.capabilities) && c.capabilities.every((cap: unknown) => typeof cap === 'string')
    );

export function CompanyBoundary({ children }: { children: ReactNode }) {
    const tenant = useAuthStore((state) => state.activeTenant);
    const userId = useAuthStore((state) => state.context?.user_id);
    const { phase, selectedIds, epoch } = useCompanyStore();
    const [revision, setRevision] = useState(0);
    useEffect(() => {
        const store = useCompanyStore.getState();
        if (store.tenantId !== tenant) store.reset(tenant);
        if (!tenant || !userId) return;
        let current = true;
        let requestId = 0;
        const load = async () => {
            const id = ++requestId;
            const { data, error } = await supabase.rpc('rpc_delivery_context', { p_tenant_id: tenant });
            if (!current || id !== requestId) return;
            if (error || data?.error || !validCompanies(data?.companies)) useCompanyStore.getState().fail();
            else if (data.cutover_required !== true) useCompanyStore.getState().deactivate();
            else if (
                !Array.isArray(data.consolidations) ||
                !data.consolidations.every((ids: unknown) =>
                    Array.isArray(ids) && ids.every((id) => typeof id === 'string')
                )
            ) useCompanyStore.getState().fail();
            else useCompanyStore.getState().accept(tenant, data.companies, data.consolidations);
        };
        void load();
        const focus = () => {
            if (document.visibilityState === 'visible') void load();
        };
        window.addEventListener('focus', focus);
        return () => {
            current = false;
            window.removeEventListener('focus', focus);
        };
    }, [tenant, userId, revision]);

    if (phase === 'loading') return <p role='status'>Cargando empresas autorizadas…</p>;
    if (phase === 'inactive') {
        return (
            <p role='status' className='rounded-xl border p-6'>
                El acceso empresarial de esta organización está pendiente de conciliación y habilitación
                administrativa.
            </p>
        );
    }
    if (phase === 'error') {
        return (
            <div role='alert' className='rounded-xl border p-6'>
                <p>No fue posible verificar el acceso empresarial.</p>
                <button
                    className='mt-3 text-primary underline'
                    onClick={() => setRevision((value) => value + 1)}
                >
                    Reintentar
                </button>
            </div>
        );
    }
    if (!selectedIds.length) {
        return (
            <p role='status' className='rounded-xl border p-6'>
                Selecciona una empresa autorizada. Si no aparece ninguna, su asignación explícita está
                pendiente.
            </p>
        );
    }
    // Immediate unmount prevents exit animations/caches from retaining the old company.
    return (
        <div key={epoch} className='h-full'>
            <p className='mb-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900'>
                Los totales incluyen sólo registros con empresa resuelta. Los históricos pendientes de
                conciliación quedan fuera de este alcance.
            </p>
            {children}
        </div>
    );
}

export function CompanySelector() {
    const { companies, selectedIds, select, selectConsolidation, consolidations, mode, phase } =
        useCompanyStore();
    return (
        <label className='min-w-0 text-xs font-semibold'>
            <span className='sr-only'>Empresa</span>
            <select
                aria-label='Empresa'
                value={selectedIds.length
                    ? mode === 'company' ? selectedIds[0] : `consolidated:${selectedIds.join(',')}`
                    : ''}
                disabled={phase !== 'ready'}
                onChange={(event) =>
                    event.target.value.startsWith('consolidated:')
                        ? selectConsolidation(event.target.value.slice(13).split(','))
                        : select(event.target.value)}
                className='max-w-40 rounded-xl border bg-surface p-2 text-slate-600'
            >
                <option value='' disabled>Empresa autorizada</option>
                {companies.map((company) => (
                    <option key={company.id} value={company.id}>{company.display_name}</option>
                ))}
                {consolidations.map((ids) => (
                    <option key={ids.join(',')} value={`consolidated:${ids.join(',')}`}>
                        Consolidado: {ids.map((id) =>
                            companies.find((company) =>
                                company.id === id
                            )?.display_name
                        ).join(' + ')}
                    </option>
                ))}
            </select>
        </label>
    );
}
