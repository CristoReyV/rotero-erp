import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { FiscalSandboxPanel } from '@/components/billing/FiscalSandboxPanel';
import { hasCompanyCapability } from '@/store/companyStore';
import { useAuthStore } from '@/store/authStore';
import BillingPage from './BillingPage';

const available = () => undefined;
export default function CompanyBillingPage() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [items, setItems] = useState<Array<{ id: string; status: string; document_type: string }>>([]);
    const [selected, setSelected] = useState('');
    const [error, setError] = useState('');
    const fiscal = hasCompanyCapability('fiscal.read');
    const financial = hasCompanyCapability('financial.full.read');
    useEffect(() => {
        if (!tenant || !fiscal) return;
        let active = true;
        void supabase.rpc('rpc_delivery_fiscal_documents', { p_tenant_id: tenant }).then(
            ({ data, error }) => {
                if (!active) return;
                if (error || data?.error || !Array.isArray(data?.items)) {
                    setError('No fue posible verificar el laboratorio autorizado.');
                } else setItems(data.items);
            },
        );
        return () => {
            active = false;
        };
    }, [tenant, fiscal]);
    if (financial) return <BillingPage />;
    return (
        <div className='space-y-5'>
            <h1 className='text-2xl font-bold'>Billing</h1>
            {!fiscal ? <p>Sin autorización para lectura financiera completa o laboratorio fiscal.</p> : (
                <>
                    <h2 className='font-bold'>Facturama sandbox</h2>
                    <p className='text-sm text-slate-500'>
                        Laboratorio separado de las lecturas ordinarias. Producción y Softmanagement
                        permanecen inactivos.
                    </p>
                    {error && <p role='alert'>{error}</p>}
                    <label>
                        Documento de prueba{' '}
                        <select
                            aria-label='Documento de prueba'
                            value={selected}
                            onChange={(event) => setSelected(event.target.value)}
                            className='ml-3 rounded border p-2'
                        >
                            <option value=''>Selecciona un documento autorizado</option>
                            {items.map((item, index) => (
                                <option key={item.id} value={item.id}>
                                    {item.document_type} {index + 1} · {item.status}
                                </option>
                            ))}
                        </select>
                    </label>
                    {selected && <FiscalSandboxPanel cfdiId={selected} onAvailable={available} />}
                </>
            )}
        </div>
    );
}
