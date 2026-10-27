import { useEffect, useState } from 'react';
import {
    getFinancialSummary,
    getInventorySummary,
    getOperationsSummary,
    getPipelineSummary,
} from '@/services/reports.service';
import { createReportsTanda1Service } from '@/services/reportsTanda1.service';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';
import { OperationalReportsSection, type OperationalReportsState } from './OperationalReportsSection';
import type {
    ReportsFinancialSummary,
    ReportsInventorySummary,
    ReportsOperationsSummary,
    ReportsPipelineSummary,
} from '@/types/reports';
import { formatAverageHours } from '@/utils/numberFormat';

const tanda1 = createReportsTanda1Service(supabase);
export function CompanyReports() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [ops, setOps] = useState<ReportsOperationsSummary | null>(null);
    const [pipeline, setPipeline] = useState<ReportsPipelineSummary | null>(null);
    const [inventory, setInventory] = useState<ReportsInventorySummary | null>(null);
    const [finances, setFinances] = useState<ReportsFinancialSummary | null>(null);
    const [operational, setOperational] = useState<OperationalReportsState>({ status: 'loading' });
    const [failed, setFailed] = useState<string[]>([]);
    const [revision, setRevision] = useState(0);
    const opAllowed = hasCompanyCapability('operations.read');
    const financialAllowed = hasCompanyCapability('financial.full.read');
    const pipelineAllowed = financialAllowed || hasCompanyCapability('pipeline.read');
    const inventoryAllowed = financialAllowed || hasCompanyCapability('inventory.read');
    useEffect(() => {
        if (!tenant) return;
        let active = true;
        setFailed([]);
        setOps(null);
        setPipeline(null);
        setInventory(null);
        setFinances(null);
        setOperational({ status: 'loading' });
        const failure = (section: string) => {
            if (active) setFailed((previous) => [...previous, section]);
        };
        if (opAllowed) {
            void getOperationsSummary(tenant).then((data) => {
                if (active) setOps(data);
            }, () => failure('Operaciones'));
            void tanda1(tenant).then((data) => {
                if (active) setOperational({ status: 'ready', data });
            }, () => {
                if (active) setOperational({ status: 'error' });
            });
        }
        if (pipelineAllowed) {
            void getPipelineSummary(tenant).then((data) => {
                if (active) setPipeline(data);
            }, () => failure('Pipeline'));
        }
        if (inventoryAllowed) {
            void getInventorySummary(tenant).then((data) => {
                if (active) setInventory(data);
            }, () => failure('Inventario'));
        }
        if (financialAllowed) {
            void getFinancialSummary(tenant).then((data) => {
                if (active) setFinances(data);
            }, () => failure('Finanzas'));
        }
        return () => {
            active = false;
        };
    }, [tenant, opAllowed, pipelineAllowed, inventoryAllowed, financialAllowed, revision]);
    const waiting = (name: string, allowed: boolean, loaded: boolean) =>
        !allowed
            ? 'Sin capacidad para este alcance.'
            : failed.includes(name)
            ? 'No fue posible cargar esta sección.'
            : !loaded
            ? 'Cargando…'
            : null;
    return (
        <div className='space-y-6'>
            <div className='flex justify-between'>
                <h1 className='text-2xl font-bold'>Reportes & BI</h1>
                <button onClick={() => setRevision((value) => value + 1)}>Actualizar</button>
            </div>
            <p className='text-sm text-slate-500'>
                Sólo registros clasificados del alcance elegido. Un permiso pendiente no se representa como un
                resultado cero.
            </p>
            <div className='grid gap-4 md:grid-cols-2'>
                <section className='rounded-2xl border bg-surface-card p-5'>
                    <h2 className='font-bold'>Finanzas</h2>
                    {waiting('Finanzas', financialAllowed, !!finances) ?? (
                        <>
                            <p>Ingresos YTD: {finances!.total_revenue_ytd}</p>
                            <p>Egresos YTD: {finances!.total_expenses_ytd}</p>
                            <p>Posición neta: {finances!.net_position}</p>
                        </>
                    )}
                </section>
                <section className='rounded-2xl border bg-surface-card p-5'>
                    <h2 className='font-bold'>Pipeline</h2>
                    {waiting('Pipeline', pipelineAllowed, !!pipeline) ?? (
                        <>
                            <p>Pipeline activo: {pipeline!.total_pipeline_value}</p>
                            <p>Conversión: {pipeline!.conversion_rate}%</p>
                        </>
                    )}
                </section>
                <section className='rounded-2xl border bg-surface-card p-5'>
                    <h2 className='font-bold'>Inventario</h2>
                    {waiting('Inventario', inventoryAllowed, !!inventory) ?? (
                        <>
                            <p>Lotes detenidos: {inventory!.blocked_count}</p>
                            {financialAllowed
                                ? <p>Valor de inventario: {inventory!.inventory_total_value}</p>
                                : <p>Valoración requiere autorización financiera completa.</p>}
                        </>
                    )}
                </section>
                <section className='rounded-2xl border bg-surface-card p-5'>
                    <h2 className='font-bold'>Operaciones</h2>
                    {waiting('Operaciones', opAllowed, !!ops) ?? (
                        <>
                            <p>Rutas activas: {ops!.active_routes_count}</p>
                            <p>{formatAverageHours(ops!.avg_delivery_time)}</p>
                        </>
                    )}
                </section>
            </div>
            {opAllowed
                ? <OperationalReportsSection state={operational} />
                : <p>Resumen operativo sin autorización para este alcance.</p>}
        </div>
    );
}
