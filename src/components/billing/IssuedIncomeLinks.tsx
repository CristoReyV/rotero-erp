import { useEffect, useRef, useState, type FormEvent } from 'react';
import { downloadCompanyFile } from '@/services/companyDelivery.service';
import {
    encodeIncomeXml, incomeLinkMessage, linkIssuedIncome, loadIssuedIncomeContext, reviewIssuedIncome,
    type IncomeFolioReview, type IssuedIncomeContext,
} from '@/services/issuedIncomeLinks.service';

interface Review {
    xml: string;
    folios: IncomeFolioReview[];
}

const secondaryButton = 'rounded-lg border border-slate-200 px-3 py-2 text-xs font-semibold disabled:opacity-50';

export function IssuedIncomeLinks({ tenantId, cfdiId }: { tenantId: string; cfdiId: string }) {
    const [context, setContext] = useState<IssuedIncomeContext | null>(null);
    const [loading, setLoading] = useState(true);
    const [refresh, setRefresh] = useState(0);
    const [folioLines, setFolioLines] = useState('');
    const [xmlFile, setXmlFile] = useState<File | null>(null);
    const [review, setReview] = useState<Review | null>(null);
    const [busy, setBusy] = useState(false);
    const inFlight = useRef(false);
    const [error, setError] = useState('');
    const [notice, setNotice] = useState('');

    useEffect(() => {
        let active = true;
        setLoading(true);
        setContext(null);
        setError('');
        void loadIssuedIncomeContext(tenantId, cfdiId)
            .then((result) => { if (active) setContext(result); })
            .catch((failure: Error) => { if (active) setError(failure.message); })
            .finally(() => { if (active) setLoading(false); });
        return () => { active = false; };
    }, [tenantId, cfdiId, refresh]);

    function clearReview() {
        setReview(null);
        setNotice('');
        setError('');
    }

    async function run(action: () => Promise<void>) {
        if (inFlight.current) return;
        inFlight.current = true;
        setBusy(true);
        setError('');
        try {
            await action();
        } catch (failure) {
            setError(failure instanceof Error ? failure.message : 'No fue posible verificar el vínculo.');
        } finally {
            inFlight.current = false;
            setBusy(false);
        }
    }

    function reviewFolios(event: FormEvent<HTMLFormElement>) {
        event.preventDefault();
        if (!context || inFlight.current) return;
        clearReview();
        void run(async () => {
            const folios = [...new Set<string>(folioLines.split(/\r?\n/).filter(Boolean))];
            if (folios.length < 1 || folios.length > 100) {
                throw new Error('Introduce entre 1 y 100 folios distintos, uno por línea.');
            }
            let file: Blob;
            try {
                file = xmlFile ?? (await downloadCompanyFile(tenantId, context.xml_file_id)).blob;
            } catch {
                throw new Error('El XML registrado no se pudo descargar con esta sesión. Selecciona el archivo original si ya cuentas con él.');
            }
            const xml = await encodeIncomeXml(file);
            setReview({ xml, folios: await reviewIssuedIncome(tenantId, cfdiId, folios, xml) });
        });
    }

    const readyIds: string[] = review?.folios.flatMap((folio: IncomeFolioReview) =>
        folio.status === 'ready' ? [folio.operation_id] : [],
    ) ?? [];

    function confirmLinks() {
        if (!review || !readyIds.length || inFlight.current) return;
        void run(async () => {
            const count = await linkIssuedIncome(tenantId, cfdiId, readyIds, review.xml)
                .finally(() => setReview(null));
            setNotice(count === 0 ? 'Los folios ya estaban vinculados.' : `Folios vinculados: ${count}.`);
            setRefresh((previous) => previous + 1);
        });
    }

    return (
        <section aria-label="Vincular factura a folios" className="space-y-3 rounded-xl border border-slate-200 p-4">
            <h3 className="text-sm font-bold text-slate-800">Vincular factura a folios internos</h3>
            {loading && <p role="status" className="text-xs text-slate-600">Verificando la factura y sus vínculos…</p>}
            {error && <p role="alert" className="text-xs text-red-700">{error}</p>}
            {notice && <p role="status" className="text-xs font-semibold text-emerald-800">{notice}</p>}
            {!loading && !context && (
                <button type="button" className={secondaryButton} onClick={() => setRefresh((previous) => previous + 1)}>
                    Volver a consultar factura
                </button>
            )}
            {context && (
                <>
                    <div className="text-xs text-slate-700">
                        <h4 className="font-semibold">Folios vinculados</h4>
                        {context.linked_folios.length ? (
                            <ul className="ml-4 mt-1 list-disc" aria-label="Folios vinculados">
                                {context.linked_folios.map((folio) => <li key={folio}>{folio}</li>)}
                            </ul>
                        ) : <p className="mt-1">Aún no hay folios vinculados a esta factura.</p>}
                    </div>
                    <form onSubmit={reviewFolios}>
                        <fieldset disabled={busy || loading} className="space-y-3">
                            <label className="block space-y-1 text-xs font-semibold text-slate-700">
                                <span>Folios internos, uno por línea</span>
                                <textarea
                                    value={folioLines}
                                    onChange={(event) => { setFolioLines(event.target.value); clearReview(); }}
                                    rows={4}
                                    maxLength={102_400}
                                    required
                                    className="block w-full rounded-lg border border-slate-200 px-3 py-2 font-mono font-normal"
                                />
                            </label>
                            <label className="block space-y-1 text-xs text-slate-600">
                                <span>XML original (opcional si el XML registrado está disponible)</span>
                                <input
                                    type="file"
                                    accept=".xml,application/xml,text/xml"
                                    onChange={(event) => { setXmlFile(event.target.files?.[0] ?? null); clearReview(); }}
                                    className="block max-w-full text-xs"
                                />
                            </label>
                            <button type="submit" className={secondaryButton}>Revisar folios</button>
                        </fieldset>
                    </form>
                    {busy && <p role="status" className="text-xs text-slate-600">Verificando la solicitud…</p>}
                    {review && (
                        <div className="space-y-2 border-t border-slate-100 pt-3">
                            <h4 className="text-xs font-semibold text-slate-700">Resultado de la revisión</h4>
                            <ul className="divide-y divide-slate-100 rounded-lg border border-slate-100">
                                {review.folios.map((folio) => (
                                    <li key={folio.folio} className="px-3 py-2 text-xs">
                                        <span className="block whitespace-pre-wrap break-words font-semibold text-slate-800">{folio.folio}</span>
                                        {folio.status === 'rejected' ? (
                                            <span className="text-red-700">Rechazado. {incomeLinkMessage(folio.reason)}</span>
                                        ) : (
                                            <span className="text-slate-600">
                                                {folio.status === 'ready' ? 'Se vinculará' : 'Ya vinculado a esta factura'}
                                            </span>
                                        )}
                                    </li>
                                ))}
                            </ul>
                            {readyIds.length > 0 && (
                                <button
                                    type="button"
                                    disabled={busy}
                                    onClick={confirmLinks}
                                    className="rounded-lg bg-primary px-3 py-2 text-xs font-semibold text-white disabled:opacity-50"
                                >
                                    {readyIds.length === 1 ? 'Vincular 1 folio' : `Vincular ${readyIds.length} folios`}
                                </button>
                            )}
                        </div>
                    )}
                </>
            )}
        </section>
    );
}
