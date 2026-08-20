import { useEffect, useState, type DragEvent, type FormEvent } from 'react';
import { FileUp, Loader2, UploadCloud } from 'lucide-react';
import { formatFileSize, getDocumentUploadContract, uploadDocumentFile } from '@/services/documents.service';
import type { DocumentEntityType, DocumentFile, DocumentFileKind, DocumentSourceModule, DocumentUploadContract } from '@/types/documents';

export function DocumentUploader({ tenantId, sourceModule, entityType, entityId, fileKind = 'supporting_file', allowOperationalTransfer = false, compact = false, onUploaded }: {
    tenantId: string; sourceModule: DocumentSourceModule; entityType: DocumentEntityType; entityId: string;
    fileKind?: DocumentFileKind; allowOperationalTransfer?: boolean; compact?: boolean;
    onUploaded: (file: DocumentFile) => Promise<void> | void;
}) {
    const [contract, setContract] = useState<DocumentUploadContract | null>(null);
    const [file, setFile] = useState<File | null>(null);
    const [notes, setNotes] = useState('');
    const [operational, setOperational] = useState(false);
    const [busy, setBusy] = useState(false);
    const [phase, setPhase] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [success, setSuccess] = useState<string | null>(null);

    useEffect(() => {
        let active = true;
        void getDocumentUploadContract(tenantId).then((value) => { if (active) setContract(value); })
            .catch((cause) => { if (active) setError(cause instanceof Error ? cause.message : 'No fue posible leer la configuración de Storage.'); });
        return () => { active = false; };
    }, [tenantId]);

    const choose = (next: File | null) => { setFile(next); setError(null); setSuccess(null); };
    const drop = (event: DragEvent<HTMLLabelElement>) => { event.preventDefault(); choose(event.dataTransfer.files[0] ?? null); };
    const submit = async (event: FormEvent) => {
        event.preventDefault(); if (!file) return; setBusy(true); setError(null); setSuccess(null);
        try {
            const uploaded = await uploadDocumentFile({
                tenantId, file, sourceModule, entityType, entityId, fileKind, notes: notes.trim() || undefined,
                metadata: allowOperationalTransfer ? { operationally_relevant: operational } : {},
            }, (next) => setPhase(next === 'validating' ? 'Validando…' : next === 'uploading' ? 'Cargando a Storage…' : 'Registrando…'));
            await onUploaded(uploaded); setFile(null); setNotes(''); setOperational(false);
            setSuccess(`${uploaded.file_name} quedó registrado.`);
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible cargar el archivo.'); }
        finally { setBusy(false); setPhase(''); }
    };

    return <form onSubmit={submit} className={`space-y-3 rounded-2xl border border-dashed border-slate-300 bg-slate-50 ${compact ? 'p-3' : 'p-4'}`}>
        <label onDragOver={(event) => event.preventDefault()} onDrop={drop} className="flex cursor-pointer items-center gap-3 rounded-xl bg-white p-3 ring-1 ring-slate-200 hover:ring-primary/40">
            <UploadCloud className="text-primary" size={20} /><div className="min-w-0 flex-1"><p className="truncate text-xs font-bold text-slate-700">{file?.name ?? 'Arrastra un archivo o selecciónalo'}</p><p className="text-[11px] text-slate-400">{contract ? `Máximo ${formatFileSize(contract.max_file_size)} · PDF, imágenes, XML y texto permitidos` : 'Consultando política de Storage…'}</p></div>
            <input type="file" className="sr-only" onChange={(event) => choose(event.target.files?.[0] ?? null)} accept={contract?.allowed_mime_types.join(',')} />
        </label>
        <div className="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto]"><input value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Notas o clasificación" className="rounded-xl border bg-white px-3 py-2 text-xs" /><button disabled={!file || busy || !contract} className="inline-flex items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2 text-xs font-bold text-white disabled:opacity-50">{busy ? <Loader2 size={14} className="animate-spin" /> : <FileUp size={14} />}{phase || 'Subir archivo'}</button></div>
        {allowOperationalTransfer && <label className="flex items-center gap-2 text-xs text-slate-600"><input type="checkbox" checked={operational} onChange={(event) => setOperational(event.target.checked)} />Relacionar también con la operación al convertir la cotización</label>}
        {error && <p className="rounded-lg bg-red-50 p-2 text-xs text-red-700">{error}</p>}{success && <p className="rounded-lg bg-emerald-50 p-2 text-xs text-emerald-700">{success}</p>}
    </form>;
}
