import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { AlertTriangle, CheckCircle2, Download, FileSpreadsheet, Loader2, RefreshCw, Trash2, Upload } from 'lucide-react';
import { applyImport, deleteImportMapping, listImportMappings, MAX_IMPORT_ROWS, saveImportMapping, validateImport } from '@/services/dataOperations.service';
import { downloadCsvContent, mapCsvRows, parseCsv, sha256Hex, suggestMapping, templateCsv, validationErrorsCsv, type ParsedCsv } from '@/utils/csv';
import { IMPORT_ENTITY_LABELS, IMPORT_FIELDS, type ImportEntity, type ImportMapping, type ImportMode, type ImportValidation, type ImportValidationItem } from '@/types/dataOperations';

const STEPS = ['Entidad', 'Archivo', 'Mapeo', 'Validación', 'Vista previa', 'Confirmación', 'Resultado'];
const MAX_FILE_BYTES = 2 * 1024 * 1024;

export function ImportWizard({ tenantId, initialEntity = 'customers' }: { tenantId: string; initialEntity?: ImportEntity }) {
    const [step, setStep] = useState(0); const [entity, setEntity] = useState<ImportEntity>(initialEntity); const [mode, setMode] = useState<ImportMode>('upsert');
    const [file, setFile] = useState<File | null>(null); const [content, setContent] = useState(''); const [parsed, setParsed] = useState<ParsedCsv | null>(null);
    const [mapping, setMapping] = useState<Record<string, string>>({}); const [mappings, setMappings] = useState<ImportMapping[]>([]); const [validation, setValidation] = useState<ImportValidation | null>(null);
    const [result, setResult] = useState<ImportValidationItem[]>([]); const [confirmed, setConfirmed] = useState(false); const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null);
    const rows = useMemo(() => parsed ? mapCsvRows(parsed, mapping) : [], [mapping, parsed]); const fields = IMPORT_FIELDS[entity];

    useEffect(() => { void listImportMappings(tenantId, entity).then(setMappings).catch(() => setMappings([])); }, [entity, tenantId]);
    const resetFile = () => { setFile(null); setContent(''); setParsed(null); setMapping({}); setValidation(null); setResult([]); setConfirmed(false); };
    const chooseEntity = (value: ImportEntity) => { setEntity(value); resetFile(); };
    const loadFile = async (selected: File) => {
        setError(null); if (selected.size > MAX_FILE_BYTES) { setError('El archivo excede 2 MB. Divide la carga.'); return; }
        try {
            const text = await selected.text(); const next = parseCsv(text);
            if (!next.rows.length || next.rows.length > MAX_IMPORT_ROWS) throw new Error('row_limit');
            setFile(selected); setContent(text); setParsed(next); setMapping(suggestMapping(next.headers, fields)); setStep(2);
        } catch (cause) { setError(cause instanceof Error && cause.message === 'row_limit' ? 'El CSV debe contener entre 1 y 1,000 filas.' : 'No se pudo leer el CSV. Revisa encabezados, comillas y delimitador.'); }
    };
    const validate = async () => {
        const missing = fields.filter((field) => field.required && !mapping[field.key]); if (missing.length) { setError(`Falta mapear: ${missing.map((field) => field.label).join(', ')}.`); return; }
        setStep(3); setBusy(true); setError(null); try { setValidation(await validateImport(tenantId, entity, mode, rows)); setStep(4); } catch (cause) { setStep(2); setError(cause instanceof Error ? cause.message : 'No se pudo validar.'); } finally { setBusy(false); }
    };
    const apply = async (selectedRows = rows, retry = false) => {
        if (!file || !validation) return; setBusy(true); setError(null);
        try {
            const hash = await sha256Hex(content); const key = `${hash}:${entity}:${mode}${retry ? `:retry:${Date.now()}` : ''}`;
            const selectedValidation = retry ? await validateImport(tenantId, entity, mode, selectedRows) : validation;
            const response = await applyImport(tenantId, entity, mode, file.name, key, selectedRows, selectedValidation.summary);
            setResult(response.results); setStep(6);
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No se pudo aplicar la importación.'); } finally { setBusy(false); }
    };
    const retryErrors = () => {
        const rowNumbers = new Set(result.filter((item) => item.status === 'error').map((item) => item.row_number));
        const retryRows = rows.filter((row) => rowNumbers.has(Number(row.row_number))); if (retryRows.length) void apply(retryRows, true);
    };
    const saveMapping = async () => {
        const name = window.prompt('Nombre del mapeo'); if (!name?.trim()) return;
        try { await saveImportMapping(tenantId, entity, name.trim(), mapping); setMappings(await listImportMappings(tenantId, entity)); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No se pudo guardar el mapeo.'); }
    };
    const hasErrors = (validation?.summary.errors ?? 0) > 0; const resultErrors = result.filter((item) => item.status === 'error');

    return <div className="space-y-4">
        <ol className="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">{STEPS.map((label, index) => <li key={label} className={`rounded-xl border px-3 py-2 text-[11px] font-bold ${index === step ? 'border-primary bg-primary/5 text-primary' : index < step ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'bg-white text-slate-400'}`}>{index + 1}. {label}</li>)}</ol>
        {error && <div className="flex gap-2 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700"><AlertTriangle size={17} />{error}</div>}
        {step === 0 && <Card title="¿Qué deseas importar?" subtitle="Solo Admin puede importar. Cotizaciones no se importan: su ciclo comercial requiere acciones de negocio explícitas.">
            <div className="grid gap-3 md:grid-cols-3">{(Object.keys(IMPORT_ENTITY_LABELS) as ImportEntity[]).map((item) => <button key={item} onClick={() => chooseEntity(item)} className={`rounded-2xl border p-5 text-left ${entity === item ? 'border-primary bg-primary/5' : ''}`}><FileSpreadsheet className="mb-3 text-primary" /><strong>{IMPORT_ENTITY_LABELS[item]}</strong><p className="mt-1 text-xs text-slate-500">Crear o actualizar por clave externa y reglas canónicas.</p></button>)}</div>
            <div className="mt-4 flex flex-wrap items-center gap-3"><label className="text-xs font-bold">Modo <select value={mode} onChange={(event) => setMode(event.target.value as ImportMode)} className="ml-2 rounded-xl border px-3 py-2"><option value="upsert">Crear y actualizar</option><option value="create_only">Solo crear</option></select></label><button onClick={() => setStep(1)} className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white">Continuar</button></div>
        </Card>}
        {step === 1 && <Card title={`Archivo de ${IMPORT_ENTITY_LABELS[entity]}`} subtitle="CSV UTF-8, coma o punto y coma. Máximo 2 MB y 1,000 filas.">
            <div className="flex flex-wrap gap-2"><button onClick={() => downloadCsvContent(templateCsv(entity), `plantilla-${entity}.csv`)} className="flex items-center gap-2 rounded-xl border px-4 py-2 text-xs font-bold"><Download size={15} />Descargar plantilla</button><label className="flex cursor-pointer items-center gap-2 rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white"><Upload size={15} />Seleccionar CSV<input type="file" accept=".csv,text/csv" className="hidden" onChange={(event) => { const selected = event.target.files?.[0]; if (selected) void loadFile(selected); }} /></label></div>
        </Card>}
        {step === 2 && parsed && <Card title="Mapeo de columnas" subtitle={`${file?.name} · ${parsed.rows.length} filas · delimitador ${parsed.delimiter === ',' ? 'coma' : 'punto y coma'}`}>
            <div className="grid gap-3 md:grid-cols-2">{fields.map((field) => <label key={field.key} className="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] items-center gap-3 text-xs"><span className="font-semibold text-slate-600">{field.label}{field.required && <b className="text-red-500"> *</b>}</span><select value={mapping[field.key] ?? ''} onChange={(event) => setMapping((current) => ({ ...current, [field.key]: event.target.value }))} className="rounded-xl border px-3 py-2"><option value="">No importar</option>{parsed.headers.map((header) => <option key={header} value={header}>{header}</option>)}</select></label>)}</div>
            <div className="mt-4 flex flex-wrap gap-2"><button onClick={() => setStep(1)} className="rounded-xl border px-4 py-2 text-xs font-bold">Atrás</button><button onClick={() => void saveMapping()} className="rounded-xl border px-4 py-2 text-xs font-bold">Guardar mapeo</button><button disabled={busy} onClick={() => void validate()} className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white">{busy ? 'Validando…' : 'Validar en servidor'}</button></div>
            {!!mappings.length && <div className="mt-4 border-t pt-4"><p className="mb-2 text-xs font-bold text-slate-500">Mapeos guardados</p><div className="flex flex-wrap gap-2">{mappings.map((saved) => <span key={saved.id} className="inline-flex items-center rounded-lg border bg-slate-50 text-xs"><button onClick={() => setMapping(saved.mapping)} className="px-3 py-2 font-semibold">{saved.name}</button><button onClick={() => void deleteImportMapping(tenantId, saved.id).then(() => setMappings((items) => items.filter((item) => item.id !== saved.id)))} className="border-l p-2 text-red-500"><Trash2 size={13} /></button></span>)}</div></div>}
        </Card>}
        {step === 3 && <Card title="Validando" subtitle="La vista previa no escribe datos."><div className="flex items-center gap-3 text-sm text-slate-500"><Loader2 className="animate-spin text-primary" />Validando relaciones, formatos, duplicados y permisos…</div></Card>}
        {step === 4 && validation && <Card title="Vista previa" subtitle="Revisa acciones y errores antes de confirmar.">
            <Summary summary={validation.summary} /><Preview items={validation.results} />
            <div className="mt-4 flex flex-wrap gap-2">{hasErrors && <button onClick={() => downloadCsvContent(validationErrorsCsv(validation.results), `errores-${entity}.csv`)} className="rounded-xl border px-4 py-2 text-xs font-bold">Descargar errores</button>}<button onClick={() => setStep(2)} className="rounded-xl border px-4 py-2 text-xs font-bold">Corregir mapeo</button><button onClick={() => setStep(5)} className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white">Ir a confirmación</button></div>
        </Card>}
        {step === 5 && validation && <Card title="Confirmación explícita" subtitle="Al confirmar se crearán o actualizarán solo las filas válidas. Las operaciones quedan en Planeada y ejecución contratada.">
            <Summary summary={validation.summary} /><label className="mt-4 flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} className="mt-1" />Confirmo que revisé el archivo, el tenant y el resumen. Entiendo que esta acción escribe datos y queda auditada.</label>
            <div className="mt-4 flex gap-2"><button onClick={() => setStep(4)} className="rounded-xl border px-4 py-2 text-xs font-bold">Atrás</button><button disabled={!confirmed || busy} onClick={() => void apply()} className="flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white disabled:opacity-40">{busy && <Loader2 size={14} className="animate-spin" />}Aplicar importación</button></div>
        </Card>}
        {step === 6 && <Card title="Resultado" subtitle="La respuesta no conserva el cuerpo CSV ni campos sensibles en el historial.">
            <div className="flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-700"><CheckCircle2 />Importación procesada: {result.filter((item) => item.status === 'applied').length} creadas, {result.filter((item) => item.status === 'updated').length} actualizadas, {resultErrors.length} con error.</div><Preview items={result} />
            <div className="mt-4 flex flex-wrap gap-2">{!!resultErrors.length && <><button onClick={() => downloadCsvContent(validationErrorsCsv(resultErrors), `errores-${entity}.csv`)} className="rounded-xl border px-4 py-2 text-xs font-bold">Descargar errores</button><button disabled={busy} onClick={retryErrors} className="flex items-center gap-2 rounded-xl border px-4 py-2 text-xs font-bold"><RefreshCw size={14} />Reintentar errores</button></>}<button onClick={() => { resetFile(); setStep(0); }} className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white">Nueva importación</button></div>
        </Card>}
    </div>;
}

function Card({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) { return <section className="rounded-2xl border bg-white p-5"><h2 className="text-lg font-bold text-slate-800">{title}</h2><p className="mb-5 text-xs text-slate-500">{subtitle}</p>{children}</section>; }
function Summary({ summary }: { summary: ImportValidation['summary'] }) { return <div className="mb-4 grid grid-cols-3 gap-2 md:grid-cols-6">{([['Total', summary.total], ['Crear', summary.create], ['Actualizar', summary.update], ['Omitir', summary.skip], ['Errores', summary.errors], ['Avisos', summary.warnings]] as Array<[string, number]>).map(([label, value]) => <div key={label} className="rounded-xl border bg-slate-50 p-3"><p className="text-[10px] font-bold uppercase text-slate-400">{label}</p><p className="text-xl font-black text-slate-700">{value}</p></div>)}</div>; }
function Preview({ items }: { items: ImportValidationItem[] }) { return <div className="mt-3 max-h-80 overflow-auto rounded-xl border"><table className="min-w-full text-left text-xs"><thead className="sticky top-0 bg-slate-50 text-slate-400"><tr><th className="px-3 py-2">Fila</th><th className="px-3 py-2">Clave</th><th className="px-3 py-2">Acción</th><th className="px-3 py-2">Observaciones</th></tr></thead><tbody className="divide-y">{items.map((item, index) => <tr key={`${item.row_number}-${index}`}><td className="px-3 py-2">{item.row_number}</td><td className="px-3 py-2 font-mono">{item.external_key || '—'}</td><td className="px-3 py-2 font-bold">{item.status ?? item.action}</td><td className="px-3 py-2"><span className="text-red-600">{item.errors.map((issue) => issue.message).join(' · ')}</span>{!item.errors.length && <span className="text-amber-600">{item.warnings.map((issue) => issue.message).join(' · ') || 'Sin observaciones'}</span>}</td></tr>)}</tbody></table></div>; }
