import { useEffect, useState, type FormEvent } from 'react';
import { operationChildCommand } from '@/services/companyWorkflow.service';
import { companyDocumentHistory, type CompanyDocument } from '@/services/companyDocuments.service';
import { downloadCompanyFile } from '@/services/companyDelivery.service';
import { useAuthStore } from '@/store/authStore';
import type { Operation360Data } from '@/types/operations';
import { CompanyOperationFiles } from './CompanyOperationFiles';

export function CompanyEvidence({ data, canManage, onRefresh }: { data: Operation360Data; canManage: boolean; onRefresh: () => Promise<void> }) {
    const tenant = useAuthStore((s) => s.activeTenant);
    const [note, setNote] = useState(''); const [file, setFile] = useState('');
    const [files, setFiles] = useState<CompanyDocument[]>([]); const [busy, setBusy] = useState(false); const [error, setError] = useState('');
    const id = data.operation.db_id;
    useEffect(() => {
        if (!tenant || !id) return; let active = true;
        void companyDocumentHistory(tenant, 'operation', id).then((rows) => { if (active) setFiles(rows.filter((f) => f.status === 'active' && f.access_class === 'operational')); }, () => { if (active) setError('No fue posible consultar archivos operacionales.'); });
        return () => { active = false; };
    }, [tenant, id, data]);
    const save = async (event: FormEvent) => {
        event.preventDefault(); if (!id || busy) return; setBusy(true); setError('');
        try { await operationChildCommand(id, 'evidence.add', { kind: file ? 'file_reference' : 'operational_note', note, file_id: file || null }, data.operation.workflow_revision); setNote(''); setFile(''); await onRefresh(); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar la evidencia.'); }
        finally { setBusy(false); }
    };
    const download = async (fileId: string) => {
        if (!tenant) return;
        try { const { blob, name } = await downloadCompanyFile(tenant, fileId); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = name; a.click(); URL.revokeObjectURL(url); }
        catch { setError('Descarga no autorizada o archivo no disponible.'); }
    };
    return <section className='space-y-4'>
        <h3 className='font-bold'>Evidencias operacionales</h3>
        {canManage && <form onSubmit={(e) => void save(e)} className='space-y-3 rounded border p-4'>
            <label className='block'>Nota operativa<input aria-label='Nota de evidencia' value={note} maxLength={2000} onChange={(e) => setNote(e.target.value)} className='ml-3 rounded border p-2' /></label>
            <label className='block'>Archivo<select aria-label='Archivo de evidencia' value={file} onChange={(e) => setFile(e.target.value)} className='ml-3 rounded border p-2'><option value=''>Sin archivo</option>{files.map((f) => <option key={f.id} value={f.id}>{f.file_name}</option>)}</select></label>
            <button disabled={busy || (!note.trim() && !file)} className='rounded border px-3 py-2'>Guardar evidencia</button>
        </form>}
        {error && <p role='alert'>{error}</p>}
        {data.evidence.map((item) => <article key={item.id} className='rounded border p-3'><p>{item.note || 'Evidencia registrada'}</p>{item.file_ref && <button onClick={() => void download(item.file_ref!)}>Descargar evidencia</button>}</article>)}
        {id && <CompanyOperationFiles operationId={id} onChanged={onRefresh} />}
    </section>;
}
