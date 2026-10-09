import type { ReportsTanda1, ReportsTanda1Volume } from '@/types/reports';

export type OperationalReportsState =
    | { status: 'loading'; }
    | { status: 'error'; }
    | { status: 'ready'; data: ReportsTanda1; };

const countFormat = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 0 });
const quantityFormat = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });
const displayDate = (date: string) => date.split('-').reverse().join('/');

function VolumeCells({ volume }: { volume: ReportsTanda1Volume; }) {
    return <>
        <td className="px-4 py-3 text-right">{countFormat.format(volume.operations)}</td>
        <td className="px-4 py-3 text-right">{quantityFormat.format(volume.pieces)}</td>
        <td className="px-4 py-3 text-right">{quantityFormat.format(volume.weight_kg)}</td>
    </>;
}

function GroupingTable({ title, columns, rows }: {
    title: string;
    columns: string[];
    rows: { key: string; labels: string[]; volume: ReportsTanda1Volume; }[];
}) {
    return <div className="rounded-xl border border-tech-border/60 overflow-hidden">
        <h3 className="px-4 py-3 text-sm font-bold text-slate-700">{title}</h3>
        {rows.length === 0
            ? <p className="px-4 pb-4 text-sm text-slate-400">Sin agrupaciones en este periodo.</p>
            : <div className="overflow-x-auto">
                <table className="w-full text-sm text-slate-600">
                    <caption className="sr-only">{title}</caption>
                    <thead className="bg-slate-50 text-xs text-slate-500">
                        <tr>
                            {columns.map(column => <th key={column} scope="col" className="px-4 py-3 text-left">{column}</th>)}
                            {['Operaciones', 'Piezas', 'Peso (kg)'].map(column =>
                                <th key={column} scope="col" className="px-4 py-3 text-right">{column}</th>)}
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-tech-border/40">
                        {rows.map(row => <tr key={row.key}>
                            {row.labels.map((label, index) =>
                                <td key={index} className="px-4 py-3">{label || '—'}</td>)}
                            <VolumeCells volume={row.volume} />
                        </tr>)}
                    </tbody>
                </table>
            </div>}
    </div>;
}

export function OperationalReportsSection({ state }: { state: OperationalReportsState; }) {
    const data = state.status === 'ready' ? state.data : null;
    return <section aria-labelledby="operational-report-title" aria-busy={state.status === 'loading'}
        className="space-y-5 bg-surface-card rounded-2xl border border-tech-border/60 p-5 sm:p-6">
        <header>
            <h2 id="operational-report-title" className="text-xl font-bold text-slate-800">Resumen operativo</h2>
            {data && <p className="mt-1 text-sm text-slate-500">
                Periodo: <time dateTime={data.date_from}>{displayDate(data.date_from)}</time>
                {' — '}<time dateTime={data.date_to}>{displayDate(data.date_to)}</time>
                {' · Límites incluidos'}
            </p>}
        </header>
        {state.status === 'loading' && <p role="status" className="text-sm text-slate-400">Cargando resumen operativo…</p>}
        {state.status === 'error' && <p role="alert" className="text-sm text-slate-500">No fue posible cargar el resumen operativo.</p>}
        {data && <>
            <div>
                <h3 className="mb-3 text-sm font-bold text-slate-700">Volumen operativo</h3>
                <dl className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    {[
                        ['Operaciones', countFormat.format(data.volume.operations)],
                        ['Piezas', quantityFormat.format(data.volume.pieces)],
                        ['Peso (kg)', quantityFormat.format(data.volume.weight_kg)],
                    ].map(([label, value]) => <div key={label} className="p-4 bg-slate-50/50 rounded-xl border border-slate-100">
                        <dt className="text-xs text-slate-500">{label}</dt>
                        <dd className="mt-1 text-xl font-bold text-slate-800">{value}</dd>
                    </div>)}
                </dl>
            </div>
            <div className="rounded-xl border border-tech-border/60 overflow-hidden">
                <h3 className="px-4 py-3 text-sm font-bold text-slate-700">Conteos semanales</h3>
                {data.weekly.length === 0
                    ? <p className="px-4 pb-4 text-sm text-slate-400">No hay operaciones en este periodo.</p>
                    : <div className="overflow-x-auto">
                        <table className="w-full text-sm text-slate-600">
                            <caption className="sr-only">Conteos operativos y facturación por semana</caption>
                            <thead className="bg-slate-50 text-xs text-slate-500">
                                <tr>
                                    {['Semana que inicia', 'Creadas', 'Entregadas o cerradas', 'Cerradas', 'Facturadas (conteo)'].map((label, index) =>
                                        <th key={label} scope="col" className={'px-4 py-3 ' + (index ? 'text-right' : 'text-left')}>{label}</th>)}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border/40">
                                {data.weekly.map(week => <tr key={week.week_start}>
                                    <td className="px-4 py-3"><time dateTime={week.week_start}>{displayDate(week.week_start)}</time></td>
                                    {[week.operations_created, week.delivered, week.closed, week.billed].map((count, index) =>
                                        <td key={index} className="px-4 py-3 text-right">{countFormat.format(count)}</td>)}
                                </tr>)}
                            </tbody>
                        </table>
                    </div>}
            </div>
            <GroupingTable title="Por servicio" columns={['Tipo', 'Clase']}
                rows={data.by_service_type.map(row => ({
                    key: JSON.stringify([row.service_type, row.service_class]), labels: [row.service_type, row.service_class], volume: row,
                }))} />
            <GroupingTable title="Por zona de destino" columns={['Zona', 'País', 'Estado']}
                rows={data.by_zone.map(row => ({
                    key: JSON.stringify([row.country_code, row.state]), labels: [row.zone, row.country_code, row.state], volume: row,
                }))} />
            <GroupingTable title="Por alcance" columns={['Alcance']}
                rows={data.by_scope.map(row => ({
                    key: row.scope, labels: [row.scope === 'national' ? 'Nacional' : row.scope === 'international' ? 'Internacional' : row.scope], volume: row,
                }))} />
        </>}
    </section>;
}
