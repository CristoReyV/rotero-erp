import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { CheckCircle2, Download, ExternalLink, FileOutput, FileWarning, Loader2, PencilLine } from 'lucide-react';
import { upsertOperationDocument } from '@/services/operations.service';
import { attachOperationDocumentFile, createDocumentSignedUrl, generateDocument, listDocumentFiles, previewGeneratedHtml } from '@/services/documents.service';
import type { DocumentRequirementLevel, Operation360Data, OperationDocument, OperationDocumentStatus } from '@/types/operations';
import { formatOperationDate } from './operationsControl';
import { DocumentUploader } from '@/components/documents/DocumentUploader';
import { EntityDocumentsPanel } from '@/components/documents/EntityDocumentsPanel';
import type { DocumentFile } from '@/types/documents';

function DocumentEditor({ tenantId, document, files, canManage, onRefresh }: { key?: string; tenantId: string; document: OperationDocument; files: DocumentFile[]; canManage: boolean; onRefresh: () => Promise<void> }) {
    const [editing, setEditing] = useState(false); const [saving, setSaving] = useState(false); const [error, setError] = useState<string | null>(null);
    const [selectedFileId, setSelectedFileId] = useState('');
    const [form, setForm] = useState({ requirement: document.requirement_level, status: document.status, reference: document.document_reference || '', url: document.external_url || '', note: document.note || '' });
    useEffect(() => setForm({ requirement: document.requirement_level, status: document.status, reference: document.document_reference || '', url: document.external_url || '', note: document.note || '' }), [document]);
    const submit = async (event: FormEvent) => {
        event.preventDefault(); setSaving(true); setError(null);
        try {
            await upsertOperationDocument(document.operation_id, { document_type: document.document_type, requirement_level: form.requirement, status: form.status, document_reference: form.reference, external_url: form.url, note: form.note });
            await onRefresh(); setEditing(false);
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar el documento.'); }
        finally { setSaving(false); }
    };
    const attachExisting = async () => {
        if (!selectedFileId) return; setSaving(true); setError(null);
        try { await attachOperationDocumentFile(document.operation_id, document.document_type, selectedFileId, form.note || undefined); await onRefresh(); setSelectedFileId(''); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible relacionar el archivo.'); }
        finally { setSaving(false); }
    };
    const missing = document.requirement_level === 'required' && document.status === 'missing';
    const attachedFile = files.find((file) => file.id === document.file_ref);
    const openAttached = async (download: boolean) => { try { if (attachedFile) window.open(await createDocumentSignedUrl(attachedFile, download), '_blank', 'noopener,noreferrer'); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible abrir el archivo.'); } };
    return <article className={`space-y-3 rounded-2xl border p-4 ${missing ? 'border-red-200 bg-red-50/60' : document.status === 'present' ? 'border-emerald-200 bg-emerald-50/40' : 'border-slate-200'}`}>
        <div className="flex flex-wrap items-start justify-between gap-3"><div className="flex gap-2">{document.status === 'present' ? <CheckCircle2 size={17} className="mt-0.5 text-emerald-600" /> : <FileWarning size={17} className={missing ? 'mt-0.5 text-red-600' : 'mt-0.5 text-slate-400'} />}<div><h3 className="text-sm font-bold text-slate-800">{document.display_label}</h3><p className="mt-1 text-xs text-slate-500">{document.requirement_level === 'required' ? 'Requerido' : document.requirement_level === 'not_required' ? 'No requerido' : 'Opcional'} · {document.status === 'present' ? 'Presente' : 'Faltante'}</p>{document.updated_at && <p className="mt-1 text-[11px] text-slate-400">Actualizado {formatOperationDate(document.updated_at)}</p>}</div></div>{canManage && <button onClick={() => setEditing((value) => !value)} className="inline-flex items-center gap-1 rounded-lg bg-white px-3 py-2 text-xs font-bold text-slate-600 ring-1 ring-slate-200"><PencilLine size={13} />Editar datos</button>}</div>
        {!editing && <div className="grid gap-2 text-xs text-slate-600 sm:grid-cols-2"><p>Referencia: <b>{document.document_reference || 'Datos por confirmar'}</b></p><p>Nota: <b>{document.note || 'Sin nota'}</b></p>{document.external_url && <a className="inline-flex items-center gap-1 font-bold text-primary" href={document.external_url} target="_blank" rel="noreferrer">Abrir enlace externo <ExternalLink size={12} /></a>}</div>}
        {attachedFile && <div className="flex flex-wrap items-center gap-2 rounded-xl border bg-white p-3 text-xs"><div className="min-w-0 flex-1"><p className="truncate font-bold text-slate-700">{attachedFile.file_name}</p><p className="text-[10px] text-slate-400">Subido {formatOperationDate(attachedFile.created_at)}{attachedFile.notes ? ` · ${attachedFile.notes}` : ''}</p></div><button type="button" onClick={() => void openAttached(false)} className="inline-flex items-center gap-1 rounded-lg border px-2 py-1.5 font-bold text-slate-600"><ExternalLink size={12} />Ver</button><button type="button" onClick={() => void openAttached(true)} className="inline-flex items-center gap-1 rounded-lg border px-2 py-1.5 font-bold text-slate-600"><Download size={12} />Descargar</button></div>}
        {editing && <form onSubmit={submit} className="grid gap-3 sm:grid-cols-2"><label className="text-xs font-bold text-slate-500">Requisito<select value={form.requirement} onChange={(event) => setForm({ ...form, requirement: event.target.value as DocumentRequirementLevel })} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal"><option value="required">Requerido</option><option value="optional">Opcional</option><option value="not_required">No requerido</option></select></label><label className="text-xs font-bold text-slate-500">Estado<select value={form.status} disabled={form.requirement === 'not_required'} onChange={(event) => setForm({ ...form, status: event.target.value as OperationDocumentStatus })} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal"><option value="missing">Faltante</option><option value="present">Presente</option></select></label>{[['Referencia', 'reference'], ['URL externa', 'url'], ['Nota', 'note']].map(([label, key]) => <label key={key} className="text-xs font-bold text-slate-500">{label}<input type={key === 'url' ? 'url' : 'text'} value={form[key as keyof typeof form]} onChange={(event) => setForm({ ...form, [key]: event.target.value })} className="mt-1 w-full rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-normal" /></label>)}{error && <p className="rounded-lg bg-red-50 p-3 text-xs text-red-700 sm:col-span-2">{error}</p>}<div className="flex justify-end sm:col-span-2"><button disabled={saving} className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-xs font-bold text-white">{saving && <Loader2 size={14} className="animate-spin" />}Guardar datos</button></div></form>}
        {canManage && <div className="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto]"><select value={selectedFileId} onChange={(event) => setSelectedFileId(event.target.value)} className="rounded-lg border bg-white px-3 py-2 text-xs"><option value="">Relacionar un archivo ya registrado…</option>{files.filter((file) => file.status === 'active').map((file) => <option key={file.id} value={file.id}>{file.file_name}</option>)}</select><button type="button" disabled={!selectedFileId || saving} onClick={() => void attachExisting()} className="rounded-lg border bg-white px-3 py-2 text-xs font-bold text-slate-600 disabled:opacity-50">Relacionar</button></div>}
        {canManage && <DocumentUploader tenantId={tenantId} sourceModule="operations" entityType="operation" entityId={document.operation_id} fileKind="supporting_file" compact onUploaded={async (file) => { await attachOperationDocumentFile(document.operation_id, document.document_type, file.id, file.notes ?? undefined); await onRefresh(); }} />}
    </article>;
}

export function OperationDocuments({ data, canManage, onRefresh }: { data: Operation360Data; canManage: boolean; onRefresh: () => Promise<void> }) {
    const [generating, setGenerating] = useState(false); const [error, setError] = useState<string | null>(null);
    const [files, setFiles] = useState<DocumentFile[]>([]);
    const operationId = data.operation.db_id; const tenantId = data.operation.tenant_id;
    const loadFiles = useCallback(async () => {
        if (!operationId || !tenantId) return;
        try { setFiles((await listDocumentFiles(tenantId, { source_entity_type: 'operation', source_entity_id: operationId, limit: 100 })).items); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar el expediente.'); }
    }, [operationId, tenantId]);
    useEffect(() => { void loadFiles(); }, [loadFiles]);
    const refreshAll = async () => { await Promise.all([onRefresh(), loadFiles()]); };
    const createGenerated = async () => {
        if (!operationId || !tenantId) return; setGenerating(true); setError(null);
        try { previewGeneratedHtml(await generateDocument(tenantId, 'operation_document', 'operation', operationId)); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible generar el documento operativo.'); }
        finally { setGenerating(false); }
    };
    if (!operationId || !tenantId) return <p className="rounded-xl border border-dashed p-6 text-sm text-slate-400">La operación no tiene identidad persistida para Documents 360.</p>;
    return <div className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3"><div className={`min-w-64 flex-1 rounded-2xl border p-4 ${data.documentSummary.pod_present ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'}`}><p className="text-sm font-bold text-slate-800">POD: {data.documentSummary.pod_present ? 'Presente' : 'Pendiente'}</p><p className="mt-1 text-xs text-slate-500">La prueba de entrega usa el documento canónico proof_of_delivery y un archivo privado registrado.</p></div>{canManage && <button disabled={generating} onClick={() => void createGenerated()} className="inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-3 text-xs font-bold text-white disabled:opacity-50">{generating ? <Loader2 size={15} className="animate-spin" /> : <FileOutput size={15} />}Generar documento operativo</button>}</div>
        {error && <p className="rounded-lg bg-red-50 p-3 text-xs text-red-700">{error}</p>}
        <div className="grid gap-3 lg:grid-cols-2">{data.documents.map((document) => <DocumentEditor key={document.document_type} tenantId={tenantId} document={document} files={files} canManage={canManage} onRefresh={refreshAll} />)}</div>
        <EntityDocumentsPanel tenantId={tenantId} sourceModule="operations" entityType="operation" entityId={operationId} title="Expediente completo de la operación" onChanged={() => void refreshAll()} />
    </div>;
}
