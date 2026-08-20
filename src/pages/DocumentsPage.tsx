import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Ban, Download, ExternalLink, FileClock, FileOutput, Files, Loader2, Printer, Search } from 'lucide-react';
import { PageHeader } from '@/components/PageHeader';
import { useAuthStore } from '@/store/authStore';
import {
    cancelGeneratedDocument, createDocumentSignedUrl, formatFileSize, generateDocument,
    listDocumentFiles, listDocumentSourceOptions, listGeneratedDocuments, markDocumentFileStatus,
    markGeneratedDocumentPrinted, previewGeneratedHtml,
} from '@/services/documents.service';
import type { DocumentFile, DocumentFileFilters, DocumentFileKind, DocumentFileStatus, DocumentSourceOption, DocumentTemplateType, GeneratedDocument } from '@/types/documents';
import { canProductRoleManageDocumentContext } from '@/constants/roles';

type View = 'all' | 'operations' | 'commercial' | 'billing' | 'generated' | 'pending';
const VIEWS: Array<{ id: View; label: string }> = [{ id: 'all', label: 'Todos' }, { id: 'operations', label: 'Operaciones' }, { id: 'commercial', label: 'Comercial' }, { id: 'billing', label: 'Facturación' }, { id: 'generated', label: 'Generados' }, { id: 'pending', label: 'Pendientes' }];

export default function DocumentsPage() {
    const tenantId = useAuthStore((state) => state.activeTenant); const role = useAuthStore((state) => state.getRole()); const [view, setView] = useState<View>('all');
    const [files, setFiles] = useState<DocumentFile[]>([]); const [generated, setGenerated] = useState<GeneratedDocument[]>([]);
    const [search, setSearch] = useState(''); const [loading, setLoading] = useState(true); const [error, setError] = useState<string | null>(null);
    const [kind, setKind] = useState<DocumentFileKind | ''>(''); const [statusFilter, setStatusFilter] = useState<DocumentFileStatus | ''>('');
    const [dateFrom, setDateFrom] = useState(''); const [dateTo, setDateTo] = useState('');
    const [nextCursor, setNextCursor] = useState<{ created_at: string; id: string } | null>(null);
    const [templateType, setTemplateType] = useState<DocumentTemplateType>('operation_document'); const [sources, setSources] = useState<DocumentSourceOption[]>([]); const [sourceId, setSourceId] = useState(''); const [busy, setBusy] = useState(false);
    const canGenerate = canProductRoleManageDocumentContext(role, templateType === 'commercial_quote' ? 'commercial' : 'operations');

    const load = useCallback(async () => {
        if (!tenantId) return; setLoading(true); setError(null);
        try {
            if (view === 'generated') setGenerated(await listGeneratedDocuments(tenantId, { search, limit: 100 }));
            else {
                const filters: DocumentFileFilters = { search: search || undefined, file_kind: kind || undefined, status: statusFilter || undefined, date_from: dateFrom || undefined, date_to: dateTo || undefined, limit: 50 };
                if (view === 'operations') filters.source_module = 'operations';
                if (view === 'commercial') filters.source_module = 'commercial';
                if (view === 'billing') filters.source_module = 'billing';
                if (view === 'pending') filters.status = 'superseded';
                const page = await listDocumentFiles(tenantId, filters); setFiles(page.items); setNextCursor(page.next_cursor);
            }
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar Documents 360.'); }
        finally { setLoading(false); }
    }, [dateFrom, dateTo, kind, search, statusFilter, tenantId, view]);
    useEffect(() => { void load(); }, [load]);
    useEffect(() => { if (!tenantId || view !== 'generated') return; void listDocumentSourceOptions(tenantId, templateType).then((items) => { setSources(items); setSourceId(items[0]?.id ?? ''); }).catch(() => setSources([])); }, [templateType, tenantId, view]);

    const openFile = async (file: DocumentFile, download: boolean) => { try { window.open(await createDocumentSignedUrl(file, download), '_blank', 'noopener,noreferrer'); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible abrir el archivo.'); } };
    const createGenerated = async () => { if (!tenantId || !sourceId) return; setBusy(true); setError(null); try { await generateDocument(tenantId, templateType, templateType === 'commercial_quote' ? 'quote' : 'operation', sourceId); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible generar el documento.'); } finally { setBusy(false); } };
    const printGenerated = async (document: GeneratedDocument) => { previewGeneratedHtml(document, true); await markGeneratedDocumentPrinted(document.id); await load(); };
    const cancelGenerated = async (document: GeneratedDocument) => { const reason = window.prompt('Motivo de cancelación'); if (!reason) return; await cancelGeneratedDocument(document.id, reason); await load(); };
    const loadMore = async () => {
        if (!tenantId || !nextCursor) return; setLoading(true);
        try {
            const filters: DocumentFileFilters = { search: search || undefined, file_kind: kind || undefined, status: statusFilter || undefined, date_from: dateFrom || undefined, date_to: dateTo || undefined, limit: 50, cursor_created_at: nextCursor.created_at, cursor_id: nextCursor.id };
            if (view === 'operations') filters.source_module = 'operations'; if (view === 'commercial') filters.source_module = 'commercial'; if (view === 'billing') filters.source_module = 'billing'; if (view === 'pending') filters.status = 'superseded';
            const page = await listDocumentFiles(tenantId, filters); setFiles((current) => [...current, ...page.items]); setNextCursor(page.next_cursor);
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar más archivos.'); } finally { setLoading(false); }
    };

    return <div className="space-y-5"><PageHeader title="Documents 360" subtitle="Archivos reales, expediente operativo y documentos generados" /><nav className="flex gap-1 overflow-x-auto rounded-2xl border bg-white p-1.5">{VIEWS.map((item) => <button key={item.id} onClick={() => setView(item.id)} className={`whitespace-nowrap rounded-xl px-4 py-2 text-xs font-bold ${view === item.id ? 'bg-primary text-white' : 'text-slate-500'}`}>{item.label}</button>)}</nav>
        <div className="flex gap-2 rounded-2xl border bg-white p-4"><div className="relative flex-1"><Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" /><input value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void load(); }} placeholder="Buscar archivo, folio o referencia" className="w-full rounded-xl border bg-slate-50 py-2.5 pl-9 pr-3 text-sm" /></div><button onClick={() => void load()} className="rounded-xl border px-4 text-xs font-bold">Buscar</button></div>
        {view !== 'generated' && <div className="grid gap-2 rounded-2xl border bg-white p-4 sm:grid-cols-2 lg:grid-cols-4"><select value={kind} onChange={(event) => setKind(event.target.value as DocumentFileKind | '')} className="rounded-xl border px-3 py-2 text-xs"><option value="">Todas las clases</option><option value="supporting_file">Soporte</option><option value="operation_evidence">Evidencia</option><option value="provider_upload">Proveedor</option><option value="fiscal_xml">XML fiscal</option><option value="fiscal_pdf">PDF fiscal</option><option value="html_snapshot">Snapshot HTML</option></select><select value={statusFilter} disabled={view === 'pending'} onChange={(event) => setStatusFilter(event.target.value as DocumentFileStatus | '')} className="rounded-xl border px-3 py-2 text-xs disabled:bg-slate-50"><option value="">Todos los estados</option><option value="active">Vigente</option><option value="superseded">Sustituido</option><option value="cancelled">Cancelado</option></select><label className="flex items-center gap-2 text-xs text-slate-500">Desde<input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} className="min-w-0 flex-1 rounded-xl border px-2 py-2" /></label><label className="flex items-center gap-2 text-xs text-slate-500">Hasta<input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} className="min-w-0 flex-1 rounded-xl border px-2 py-2" /></label></div>}
        {view === 'pending' && <p className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-700">Muestra archivos sustituidos que requieren revisión o reemplazo; el contrato canónico no define un estado pendiente.</p>}
        {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
        {view === 'generated' && <section className="space-y-3 rounded-2xl border bg-white p-4"><div className="flex items-center gap-2"><FileOutput className="text-primary" /><div><h2 className="font-bold text-slate-800">Generar desde plantilla activa</h2><p className="text-xs text-slate-400">Cada generación crea un snapshot nuevo e inmutable.</p></div></div><div className="grid gap-2 md:grid-cols-[220px_minmax(0,1fr)_auto]"><select value={templateType} onChange={(event) => setTemplateType(event.target.value as DocumentTemplateType)} className="rounded-xl border px-3 py-2 text-sm"><option value="operation_document">Documento operativo</option><option value="operation_summary">Resumen operativo</option>{canProductRoleManageDocumentContext(role, 'commercial') && <option value="commercial_quote">Cotización formal</option>}</select><select value={sourceId} onChange={(event) => setSourceId(event.target.value)} className="rounded-xl border px-3 py-2 text-sm"><option value="">Selecciona origen</option>{sources.map((item) => <option key={item.id} value={item.id}>{item.label} · {item.description}</option>)}</select>{canGenerate && <button disabled={!sourceId || busy} onClick={() => void createGenerated()} className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white disabled:opacity-50">{busy ? 'Generando…' : 'Generar documento'}</button>}</div></section>}
        {loading ? <div className="flex h-48 items-center justify-center"><Loader2 className="animate-spin text-primary" /></div> : view === 'generated' ? <GeneratedTable items={generated} onPreview={(item) => previewGeneratedHtml(item)} onPrint={(item) => void printGenerated(item)} onCancel={(item) => void cancelGenerated(item)} /> : <><FileTable items={files} onOpen={(item) => void openFile(item, false)} onDownload={(item) => void openFile(item, true)} onArchive={async (item) => { await markDocumentFileStatus(item.id, 'superseded'); await load(); }} />{nextCursor && <div className="flex justify-center"><button onClick={() => void loadMore()} className="rounded-xl border bg-white px-5 py-2 text-xs font-bold text-slate-600">Cargar más</button></div>}</>}
    </div>;
}

function FileTable({ items, onOpen, onDownload, onArchive }: { items: DocumentFile[]; onOpen: (file: DocumentFile) => void; onDownload: (file: DocumentFile) => void; onArchive: (file: DocumentFile) => void }) {
    if (!items.length) return <Empty icon={<Files />} text="No hay archivos con estos filtros." />;
    return <div className="overflow-x-auto rounded-2xl border bg-white"><table className="min-w-full text-left text-xs"><thead className="bg-slate-50 text-slate-400"><tr>{['Archivo','Contexto','Clase','Estado','Fecha','Acciones'].map((label) => <th key={label} className="px-4 py-3">{label}</th>)}</tr></thead><tbody className="divide-y">{items.map((file) => <tr key={file.id}><td className="px-4 py-3"><p className="font-bold text-slate-700">{file.file_name}</p><p className="text-[10px] text-slate-400">{formatFileSize(file.size_bytes)} · {file.mime_type}</p></td><td className="px-4 py-3"><p className="font-semibold">{file.entity_reference}</p><p className="text-[10px] text-slate-400">{file.source_module}</p></td><td className="px-4 py-3">{file.file_kind}</td><td className="px-4 py-3">{file.status}</td><td className="px-4 py-3">{new Date(file.created_at).toLocaleDateString('es-MX')}</td><td className="px-4 py-3"><div className="flex gap-1"><button onClick={() => onOpen(file)} className="p-2" title="Ver"><ExternalLink size={14} /></button><button onClick={() => onDownload(file)} className="p-2" title="Descargar"><Download size={14} /></button>{file.can_manage && file.status === 'active' && <button onClick={() => onArchive(file)} className="p-2 text-amber-600" title="Marcar sustituido"><FileClock size={14} /></button>}</div></td></tr>)}</tbody></table></div>;
}

function GeneratedTable({ items, onPreview, onPrint, onCancel }: { items: GeneratedDocument[]; onPreview: (item: GeneratedDocument) => void; onPrint: (item: GeneratedDocument) => void; onCancel: (item: GeneratedDocument) => void }) {
    if (!items.length) return <Empty icon={<FileOutput />} text="No hay documentos generados." />;
    return <div className="grid gap-3 lg:grid-cols-2">{items.map((item) => <article key={item.id} className="rounded-2xl border bg-white p-4"><div className="flex justify-between gap-3"><div><p className="font-mono text-xs font-bold text-primary">{item.document_number || 'Sin folio'}</p><h3 className="font-bold text-slate-800">{item.template_name || item.template_type}</h3><p className="text-xs text-slate-400">{item.entity_reference} · {new Date(item.generated_at).toLocaleString('es-MX')}</p></div><span className="h-fit rounded-full bg-slate-100 px-2 py-1 text-[10px] font-bold">{item.status}</span></div><p className="mt-3 text-xs text-slate-500">Impresiones: {item.print_count}</p><div className="mt-3 flex gap-2"><button onClick={() => onPreview(item)} className="flex items-center gap-1 rounded-lg border px-3 py-2 text-xs font-bold"><ExternalLink size={13} />Vista previa</button><button onClick={() => onPrint(item)} className="flex items-center gap-1 rounded-lg border px-3 py-2 text-xs font-bold"><Printer size={13} />Imprimir</button>{item.can_manage && item.status !== 'cancelled' && <button onClick={() => onCancel(item)} className="flex items-center gap-1 rounded-lg border border-red-200 px-3 py-2 text-xs font-bold text-red-700"><Ban size={13} />Cancelar</button>}</div></article>)}</div>;
}
function Empty({ icon, text }: { icon: ReactNode; text: string }) { return <div className="flex h-48 flex-col items-center justify-center gap-2 rounded-2xl border border-dashed bg-white text-slate-400">{icon}<p className="text-sm">{text}</p></div>; }
