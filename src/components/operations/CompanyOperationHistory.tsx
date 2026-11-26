import { useEffect, useState } from 'react';
import { deliveryCsv, deliveryPage, type DeliveryPage, type DeliveryRow } from '@/services/companyDelivery.service';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability, useCompanyStore } from '@/store/companyStore';
import { downloadCsvContent } from '@/utils/csv';

function sourceText(value: DeliveryRow[string]) {
    return value == null || value === '' ? 'Sin dato en origen' : String(value);
}

export function CompanyOperationHistory() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const mode = useCompanyStore((state) => state.mode);
    const allowed = mode === 'company' && hasCompanyCapability('operations.read');
    const [search, setSearch] = useState('');
    const [cursor, setCursor] = useState<string | null>(null);
    const [page, setPage] = useState<DeliveryPage | null>(null);
    const [selected, setSelected] = useState<DeliveryRow | null>(null);
    const [loading, setLoading] = useState(false);
    const [exporting, setExporting] = useState(false);
    const [error, setError] = useState('');

    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        setLoading(true);
        setError('');
        setPage(null);
        void deliveryPage(tenant, 'operations_history', search, cursor).then((result) => {
            if (active) setPage(result);
        }, () => {
            if (active) setError('No fue posible consultar el histórico de la empresa.');
        }).finally(() => {
            if (active) setLoading(false);
        });
        return () => {
            active = false;
        };
    }, [tenant, allowed, search, cursor]);

    const exportCsv = async () => {
        if (!tenant || exporting || !hasCompanyCapability('export.operational')) return;
        setExporting(true);
        setError('');
        try {
            const csv = await deliveryCsv(tenant, 'operations_history', search);
            downloadCsvContent(csv, 'historico-operaciones.csv');
        } catch {
            setError('No fue posible exportar el histórico.');
        } finally {
            setExporting(false);
        }
    };

    if (!allowed) return <p role="status">Selecciona una empresa con permiso de lectura para consultar el histórico.</p>;

    return (
        <section className="space-y-4" aria-labelledby="operation-history-heading">
            <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                    <h1 id="operation-history-heading" className="text-2xl font-bold">Histórico de operaciones</h1>
                    <p className="text-sm text-slate-500">Consulta de sólo lectura. Los datos se muestran como constan en el origen.</p>
                </div>
                {hasCompanyCapability('export.operational') && (
                    <button type="button" disabled={exporting} onClick={() => void exportCsv()}
                        className="rounded-xl bg-primary px-4 py-2 text-white disabled:opacity-60">
                        Exportar CSV histórico
                    </button>
                )}
            </div>
            <input aria-label="Buscar en Histórico" className="w-full rounded-xl border p-3" maxLength={160}
                placeholder="Folio, cliente o línea transportista" value={search}
                onChange={(event) => {
                    setSearch(event.target.value);
                    setCursor(null);
                    setSelected(null);
                }} />
            {loading && <p role="status">Cargando histórico…</p>}
            {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
            {page && (
                <>
                    <p className="text-sm">{page.total} folios históricos en esta empresa</p>
                    {page.items.length > 0 && (
                        <div className="overflow-x-auto rounded-xl border bg-surface-card">
                            <table aria-label="Folios históricos" className="w-full text-left text-sm">
                                <thead className="bg-slate-50 text-slate-700">
                                    <tr>
                                        {['Folio', 'Cliente de origen', 'Línea transportista de origen', 'Fecha de Despacho / Cruce']
                                            .map((title) => <th key={title} scope="col" className="p-3">{title}</th>)}
                                    </tr>
                                </thead>
                                <tbody className="divide-y">
                                    {page.items.map((row) => (
                                        <tr key={String(row.id)}>
                                            <td className="p-3"><button type="button" className="font-semibold underline"
                                                onClick={() => setSelected(row)}>{sourceText(row.reference_code)}</button></td>
                                            <td className="p-3">{sourceText(row.source_customer_name)}</td>
                                            <td className="p-3">{sourceText(row.source_carrier_name)}</td>
                                            <td className="p-3 whitespace-pre-wrap">{sourceText(row.source_dispatch_crossing_date)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                    {(cursor || page.next_cursor) && (
                        <div className="flex gap-4">
                            <button type="button" disabled={!cursor} onClick={() => {
                                setCursor(null);
                                setSelected(null);
                            }}>Primera página</button>
                            <button type="button" disabled={!page.next_cursor} onClick={() => {
                                setCursor(page.next_cursor);
                                setSelected(null);
                            }}>Siguiente página</button>
                        </div>
                    )}
                </>
            )}
            {selected && (
                <section aria-labelledby="historical-record-heading" className="space-y-3 rounded-xl border bg-surface-card p-5">
                    <div className="flex flex-wrap items-center justify-between gap-3">
                        <h2 id="historical-record-heading" className="text-lg font-bold">Ficha histórica</h2>
                        <button type="button" className="underline" onClick={() => setSelected(null)}>Cerrar ficha</button>
                    </div>
                    <dl className="grid gap-3 md:grid-cols-2">
                        {[
                            ['Folio WLS', sourceText(selected.reference_code)],
                            ['Estado operativo', 'No acreditado'],
                            ['Cliente de origen', sourceText(selected.source_customer_name)],
                            ['Línea transportista de origen', sourceText(selected.source_carrier_name)],
                            ['Fecha de Despacho / Cruce', sourceText(selected.source_dispatch_crossing_date)],
                            ['Procedencia', `Hoja ${sourceText(selected.source_sheet)}, fila ${sourceText(selected.source_row)}`],
                        ].map(([label, value]) => (
                            <div key={label}><dt className="text-sm font-semibold">{label}</dt>
                                <dd className="whitespace-pre-wrap">{value}</dd></div>
                        ))}
                    </dl>
                </section>
            )}
        </section>
    );
}
