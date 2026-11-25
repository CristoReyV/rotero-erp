import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { companyDashboard, type CompanyDashboard } from '@/services/companyDashboard.service';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';
import { getOperationsSummary } from '@/services/reports.service';
import { formatAverageHours } from '@/utils/numberFormat';

export default function CompanyDashboardPage() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [data, setData] = useState<{ executive: CompanyDashboard; hours: number } | null>(null);
    const [start, setStart] = useState('');
    const [end, setEnd] = useState('');
    const [error, setError] = useState('');
    const allowed = hasCompanyCapability('operations.read');
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        setData(null); setError('');
        void Promise.all([
            companyDashboard(tenant, start ? new Date(start + 'T00:00:00').toISOString() : null, end ? new Date(end + 'T23:59:59').toISOString() : null),
            getOperationsSummary(tenant),
        ]).then(([response, ops]) => {
            if (!active) return;
            setData({ executive: response, hours: ops.avg_delivery_time });
        }, () => {
            if (active) setError('No fue posible cargar el resumen empresarial.');
        });
        return () => {
            active = false;
        };
    }, [tenant, allowed, start, end]);
    return (
        <div className='space-y-6'>
            <h1 className='text-2xl font-bold'>Resumen empresarial</h1>
            <p className='text-sm text-slate-500'>Sólo entidades clasificadas del alcance elegido.</p>
            <div className='flex gap-4'><label>Desde<input aria-label='Dashboard desde' type='date' value={start} onChange={(e) => setStart(e.target.value)} className='ml-2 rounded border p-2' /></label><label>Hasta<input aria-label='Dashboard hasta' type='date' value={end} onChange={(e) => setEnd(e.target.value)} className='ml-2 rounded border p-2' /></label></div>
            {error && <p role='alert'>{error}</p>}
            {!allowed
                ? <p>Sin capacidad operativa para este alcance.</p>
                : data
                    ? (
                        <div className='grid gap-4 md:grid-cols-3'>
                            {[['Operaciones', data.executive.operations.total], ['Activas', data.executive.operations.active], ['En tránsito', data.executive.operations.in_transit], ['Entregadas', data.executive.operations.delivered], ['Cerradas', data.executive.operations.closed], ['Incidencias bloqueantes', data.executive.operations.blocking_incidents], ['Despachos bloqueados', data.executive.operations.dispatch_blockers], ['Listas para facturación', data.executive.operations.billing_ready], ['Facturación bloqueada', data.executive.operations.billing_blocked], ['Documentos requeridos faltantes', data.executive.documents.required_missing], ['Entregas sin POD', data.executive.documents.pod_pending], [
                                'Tiempo promedio histórico (horas)',
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
            {data?.executive.finance && <section className='space-y-3'><h2 className='text-lg font-bold'>Finanzas del alcance autorizado</h2><div className='grid gap-3 md:grid-cols-3'>{Object.entries({ 'Cuentas por cobrar pendientes': data.executive.finance.ar_outstanding, 'Cuentas por cobrar vencidas': data.executive.finance.ar_overdue, 'Cuentas por pagar pendientes': data.executive.finance.ap_outstanding, 'Cuentas por pagar vencidas': data.executive.finance.ap_overdue, 'Cobros del mes': data.executive.finance.collections_month, 'Pagos a proveedores del mes': data.executive.finance.provider_payments_month }).map(([label, value]) => <div key={label} className='rounded border p-4'><p>{label}</p><p>{value.toLocaleString('es-MX', { style: 'currency', currency: 'MXN' })}</p></div>)}</div></section>}
            {data && !data.executive.financial_available && <p>Las métricas financieras completas requieren autorización explícita.</p>}
            {data?.executive.commercial && <section><h2 className='text-lg font-bold'>Cotizaciones autorizadas</h2><p>En revisión: {data.executive.commercial.in_review} · Pendientes de conversión: {data.executive.commercial.pending_conversion} · Conversión: {data.executive.commercial.conversion_rate}%</p></section>}
            {data && <section className='space-y-2'><h2 className='text-lg font-bold'>Atención del alcance</h2>{data.executive.attention.map((item) => <Link key={`${item.kind}:${item.entity_id}`} to={item.route} className='block rounded border p-3'>{item.title} · {item.reference}</Link>)}{!data.executive.attention.length && <p>Sin alertas en el alcance autorizado.</p>}</section>}
            {data && <section className='space-y-2'><h2 className='text-lg font-bold'>Actividad reciente autorizada</h2>{data.executive.recent_activity.map((item) => <Link key={item.id} to={item.route} className='block text-sm'>{item.title} · {new Date(item.occurred_at).toLocaleString()}</Link>)}</section>}
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
