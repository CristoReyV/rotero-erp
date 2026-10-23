import { useEffect, useRef, useState } from 'react';
import {
    getSandboxFiscalContext,
    sandboxFiscalAction,
    type SandboxFiscalContext,
} from '@/services/fiscalSandbox.service';
export function FiscalSandboxPanel(
    { cfdiId, onAvailable }: { cfdiId: string; onAvailable: (available: boolean) => void },
) {
    const [context, setContext] = useState<SandboxFiscalContext | null>(null),
        [busy, setBusy] = useState(false),
        [error, setError] = useState('');
    const [confirm, setConfirm] = useState<'issue' | 'cancel' | null>(null),
        [motive, setMotive] = useState('03'),
        [replacement, setReplacement] = useState('');
    const [applications, setApplications] = useState(''), [paidAt, setPaidAt] = useState('');
    const currentId = useRef(cfdiId);
    currentId.current = cfdiId;
    useEffect(() => {
        let live = true;
        onAvailable(false);
        setContext(null);
        setBusy(false);
        setError('');
        setConfirm(null);
        void getSandboxFiscalContext(cfdiId).then((c) => {
            if (live) {
                setContext(c);
                onAvailable(Boolean(c));
            }
        });
        return () => {
            live = false;
        };
    }, [cfdiId, onAvailable]);
    if (!context || context.cfdi_id !== cfdiId) return null;
    async function run(action: string, options: Record<string, unknown> = {}) {
        if (busy) return;
        setBusy(true);
        setError('');
        setConfirm(null);
        try {
            const result = await sandboxFiscalAction(cfdiId, action, options);
            if (currentId.current !== cfdiId) return;
            if (action === 'xml' || action === 'ack') {
                const blob = result instanceof Blob
                    ? result
                    : new Blob([String(result)], { type: 'application/xml' });
                const url = URL.createObjectURL(blob), a = document.createElement('a');
                a.href = url;
                a.download = action === 'ack' ? 'acuse-sandbox.xml' : 'cfdi-sandbox.xml';
                a.click();
                URL.revokeObjectURL(url);
            }
            setContext(await getSandboxFiscalContext(cfdiId));
        } catch (e) {
            if (currentId.current === cfdiId) {
                setError(e instanceof Error ? e.message : 'No se pudo completar la acción.');
            }
        } finally {
            if (currentId.current === cfdiId) setBusy(false);
        }
    }
    function payment() {
        try {
            // IDs are validated against explicit same-company links on server.
            const rows = applications.trim().split('\n').map((line) => {
                const [invoice_id, amount] = line.trim().split(',');
                if (!/^[0-9a-f-]{36}$/i.test(invoice_id) || !/^\d+(\.\d{1,2})?$/.test(amount)) {
                    throw new Error();
                }
                return { invoice_id, amount };
            });
            if (!paidAt) throw new Error();
            void run('payment', {
                paidAt: paidAt.length === 16 ? paidAt + ':00' : paidAt,
                applications: rows,
            });
        } catch {
            setError('Indica fecha y una aplicación por línea: UUID de factura,importe.');
        }
    }
    const disabled = busy || context.busy;
    const button = 'rounded border px-3 py-2 text-sm disabled:opacity-40';
    return (
        <section
            aria-label='Facturama sandbox'
            className='space-y-3 rounded-xl border border-amber-400 bg-amber-50 p-4'
        >
            <p className='font-bold text-amber-900'>Modo de prueba — sin validez fiscal</p>
            <p className='text-sm'>
                Empresa: {context.company_name} · Emisor de prueba: {context.issuer_rfc}
            </p>
            <p className='text-sm'>
                Estado: {context.status}
                {context.uncertain ? ' · Resultado incierto; consulta antes de continuar.' : ''}
            </p>
            <dl className='grid grid-cols-2 gap-1 text-sm'>
                <dt>Referencia fiscal</dt>
                <dd>{context.draft_summary.serie} / {context.draft_summary.folio}</dd>
                <dt>Receptor de prueba</dt>
                <dd>{context.draft_summary.receiver_rfc}</dd>
                <dt>Total</dt>
                <dd>{context.draft_summary.total} {context.draft_summary.currency}</dd>
                <dt>UUID</dt>
                <dd className='break-all'>{context.uuid || 'Pendiente de evidencia XML'}</dd>
            </dl>
            {error && <p role='alert' className='text-sm text-red-800'>{error}</p>}
            {busy && <p role='status'>Procesando; no vuelvas a enviar.</p>}
            <div className='flex flex-wrap gap-2'>
                <button
                    type='button'
                    className={button}
                    disabled={disabled || !context.actions.prepare || context.status !== 'draft' ||
                        (context.document_type === 'payment' && !context.payment_recorded)}
                    onClick={() => void run('prepare')}
                >
                    Validar y congelar borrador
                </button>
                <button
                    type='button'
                    className={button}
                    disabled={disabled || !context.actions.issue || context.status !== 'ready_for_api' ||
                        context.uncertain}
                    onClick={() => setConfirm('issue')}
                >
                    Emitir en sandbox
                </button>
                <button
                    type='button'
                    className={button}
                    disabled={disabled || !context.actions.read || context.status === 'draft'}
                    onClick={() => void run('status')}
                >
                    Consultar y recuperar resultado
                </button>
                <button
                    type='button'
                    className={button}
                    disabled={disabled || !context.xml_available}
                    onClick={() => void run('xml')}
                >
                    Descargar XML de prueba
                </button>
            </div>
            {context.actions.cancel && context.status === 'stamped' && (
                <div className='space-y-2'>
                    <label className='block text-sm'>
                        Motivo de cancelación{' '}
                        <select
                            aria-label='Motivo de cancelación sandbox'
                            value={motive}
                            onChange={(e) => setMotive(e.target.value)}
                            className='rounded border p-1'
                        >
                            <option value='03'>03 — No se realizó la operación</option>
                            <option value='02'>02 — Error sin relación</option>
                            <option value='01'>01 — Error con sustituto</option>
                            <option value='04'>04 — Factura global</option>
                        </select>
                    </label>
                    {motive === '01' && (
                        <label className='block text-sm'>
                            UUID sustituto<input
                                value={replacement}
                                onChange={(e) => setReplacement(e.target.value)}
                                className='ml-2 rounded border p-1'
                            />
                        </label>
                    )}
                    <button
                        type='button'
                        className={button}
                        disabled={disabled}
                        onClick={() => setConfirm('cancel')}
                    >
                        Solicitar cancelación sandbox
                    </button>
                </div>
            )}
            {context.cancellation_available && (
                <button
                    type='button'
                    className={button}
                    disabled={disabled}
                    onClick={() => void run('ack')}
                >
                    Descargar acuse de prueba
                </button>
            )}
            {confirm && (
                <div
                    role='group'
                    aria-label='Confirmar acción fiscal sandbox'
                    className='rounded border border-amber-600 p-3'
                >
                    <p>
                        Confirmar {confirm === 'issue' ? 'emisión' : 'cancelación'}{' '}
                        únicamente en sandbox para la empresa y referencia indicadas.
                    </p>
                    <div className='mt-2 flex gap-2'>
                        <button
                            type='button'
                            className={button}
                            disabled={disabled}
                            onClick={() =>
                                void run(confirm, {
                                    motive,
                                    replacement: motive === '01' ? replacement : undefined,
                                })}
                        >
                            Confirmar prueba
                        </button>
                        <button type='button' className={button} onClick={() => setConfirm(null)}>
                            Volver al borrador
                        </button>
                    </div>
                </div>
            )}
            {context.actions.payment && context.document_type === 'payment' && !context.payment_recorded &&
                context.status === 'draft' && (
                <details>
                    <summary>Aplicar cobro de prueba y preparar REP 2.0</summary>
                    <p className='text-xs'>
                        Sólo facturas de prueba vinculadas explícitamente a esta empresa. El recibo
                        administrativo tiene referencia independiente del folio fiscal.
                    </p>
                    <label className='block text-sm'>
                        Fecha del pago<input
                            type='datetime-local'
                            value={paidAt}
                            onChange={(e) => setPaidAt(e.target.value)}
                            className='m-1 rounded border p-1'
                        />
                    </label>
                    <label className='block text-sm'>
                        Aplicaciones: UUID de factura,importe<textarea
                            value={applications}
                            onChange={(e) => setApplications(e.target.value)}
                            className='block w-full rounded border p-2'
                        />
                    </label>
                    <button type='button' className={button} disabled={disabled} onClick={payment}>
                        Confirmar aplicaciones de prueba
                    </button>
                </details>
            )}
        </section>
    );
}
