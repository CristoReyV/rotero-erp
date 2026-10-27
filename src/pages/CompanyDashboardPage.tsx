import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';
import { getOperationsSummary } from '@/services/reports.service';
import { formatAverageHours } from '@/utils/numberFormat';

export default function CompanyDashboardPage() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [data, setData] = useState<{ total: number; transit: number; hours: number } | null>(null);
    const [error, setError] = useState('');
    const allowed = hasCompanyCapability('operations.read');
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        void Promise.all([
            supabase.rpc('rpc_dashboard_overview', {
                p_tenant_id: tenant,
                p_start_date: null,
                p_end_date: null,
            }),
            getOperationsSummary(tenant),
        ]).then(([response, ops]) => {
            if (!active) return;
            if (response.error || response.data?.error) {
                setError('No fue posible cargar el resumen empresarial.');
            } else {setData({
                    total: response.data.kpis.ops_total,
                    transit: response.data.kpis.ops_in_transit,
                    hours: ops.avg_delivery_time,
                });}
        }, () => {
            if (active) setError('No fue posible cargar el resumen empresarial.');
        });
        return () => {
            active = false;
        };
    }, [tenant, allowed]);
    return (
        <div className='space-y-6'>
            <h1 className='text-2xl font-bold'>Resumen empresarial</h1>
            <p className='text-sm text-slate-500'>Sólo operaciones clasificadas del alcance elegido.</p>
            {error && <p role='alert'>{error}</p>}
            {!allowed
                ? <p>Sin capacidad operativa para este alcance.</p>
                : data
                ? (
                    <div className='grid gap-4 md:grid-cols-3'>
                        {[['Operaciones', data.total], ['En tránsito', data.transit], [
                            'Tiempo promedio',
                            formatAverageHours(data.hours),
                        ]].map(([label, value]) => (
                            <div key={String(label)} className='rounded-2xl border bg-surface-card p-5'>
                                <p className='text-sm text-slate-500'>{label}</p>
                                <p className='mt-2 text-xl font-bold'>{value}</p>
                            </div>
                        ))}
                    </div>
                )
                : !error && <p role='status'>Cargando…</p>}
            <div className='flex flex-wrap gap-4'>
                <Link to='/operations'>Operaciones</Link>
                <Link to='/finance'>Finance</Link>
                <Link to='/reports'>Reportes</Link>
            </div>
            <p className='text-sm text-slate-500'>
                Consulta Reportes para ver las métricas disponibles según tus permisos.
            </p>
        </div>
    );
}
