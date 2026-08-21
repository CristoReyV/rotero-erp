import { useCallback, useEffect, useState } from 'react';
import { Download, ExternalLink, File, Loader2 } from 'lucide-react';
import { createDocumentSignedUrl, formatFileSize, listDocumentFiles } from '@/services/documents.service';
import type { DocumentEntityType, DocumentFile, DocumentFileKind, DocumentSourceModule } from '@/types/documents';
import { DocumentUploader } from './DocumentUploader';
import { useAuthStore } from '@/store/authStore';
import { canProductRoleManageDocumentContext } from '@/constants/roles';

export function EntityDocumentsPanel({ tenantId, sourceModule, entityType, entityId, title = 'Archivos', fileKind = 'supporting_file', allowOperationalTransfer = false, onChanged }: {
    tenantId: string; sourceModule: DocumentSourceModule; entityType: DocumentEntityType; entityId: string;
    title?: string; fileKind?: DocumentFileKind; allowOperationalTransfer?: boolean; onChanged?: () => void;
}) {
    const role = useAuthStore((state) => state.getRole());
    const canUpload = canProductRoleManageDocumentContext(role, sourceModule);
    const [items, setItems] = useState<DocumentFile[]>([]); const [loading, setLoading] = useState(true); const [error, setError] = useState<string | null>(null);
    const load = useCallback(async () => { setLoading(true); setError(null); try { setItems((await listDocumentFiles(tenantId, { source_entity_type: entityType, source_entity_id: entityId, limit: 50 })).items); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible consultar archivos.'); } finally { setLoading(false); } }, [entityId, entityType, tenantId]);
    useEffect(() => { void load(); }, [load]);
    const open = async (file: DocumentFile, download: boolean) => { try { const url = await createDocumentSignedUrl(file, download); window.open(url, '_blank', 'noopener,noreferrer'); } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible abrir el archivo.'); } };
    return <section className="space-y-3 rounded-2xl border bg-white p-4"><div><h3 className="text-sm font-bold text-slate-800">{title}</h3><p className="text-[11px] text-slate-400">Archivos privados registrados en Documents 360</p></div>{canUpload && <DocumentUploader tenantId={tenantId} sourceModule={sourceModule} entityType={entityType} entityId={entityId} fileKind={fileKind} allowOperationalTransfer={allowOperationalTransfer} compact onUploaded={async () => { await load(); onChanged?.(); }} />}{error && <p className="rounded-lg bg-red-50 p-2 text-xs text-red-700">{error}</p>}{loading ? <div className="flex justify-center p-4"><Loader2 className="animate-spin text-primary" /></div> : items.length === 0 ? <p className="rounded-xl border border-dashed p-4 text-center text-xs text-slate-400">Sin archivos relacionados.</p> : <div className="divide-y rounded-xl border">{items.map((file) => <div key={file.id} className="flex items-center gap-3 p-3"><File size={16} className="text-primary" /><div className="min-w-0 flex-1"><p className="truncate text-xs font-bold text-slate-700">{file.file_name}</p><p className="text-[10px] text-slate-400">{formatFileSize(file.size_bytes)} · {file.status}</p></div><button onClick={() => void open(file, false)} title="Ver" className="p-1.5 text-slate-500"><ExternalLink size={14} /></button><button onClick={() => void open(file, true)} title="Descargar" className="p-1.5 text-slate-500"><Download size={14} /></button></div>)}</div>}</section>;
}
