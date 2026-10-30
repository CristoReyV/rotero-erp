import { useEffect, useState, type FormEvent } from 'react';
import { companyDocumentHistory, type CompanyDocument } from '@/services/companyDocuments.service';
import { operationChildCommand } from '@/services/companyWorkflow.service';
import { hasCompanyCapability } from '@/store/companyStore';
import type { Operation360Data, OperationDocument } from '@/types/operations';
import { CompanyOperationFiles } from './CompanyOperationFiles';

function Requirement({ item, data, files, refresh }: { key?: string; item: OperationDocument; data: Operation360Data; files: CompanyDocument[]; refresh: () => Promise<void> }) {
    const [requirement, setRequirement] = useState(item.requirement_level); const [status, setStatus] = useState(item.status);
    const [reference, setReference] = useState(item.document_reference ?? ''); const [file, setFile] = useState(item.file_ref ?? '');
    const [busy, setBusy] = useState(false); const [error, setError] = useState('');
    const save = async (event: FormEvent) => {
        event.preventDefault(); if (busy) return; setBusy(true); setError('');
        try { await operationChildCommand(data.operation.db_id, 'document.save', { document_type: item.document_type, requirement_level: requirement, status, document_reference: reference, file_id: file || null }, data.operation.workflow_revision); await refresh(); }
        catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar el requisito.'); }
        finally { setBusy(false); }
    };
    const manage = hasCompanyCapability('operations.evidence.write');
    return <form onSubmit={(e) => void save(e)} className='space-y-3 rounded border p-4'>
        <h4 className='font-bold'>{item.display_label}</h4>
        {manage ? <>
            <label className='block'>Requisito<select value={requirement} onChange={(e) => setRequirement(e.target.value as typeof requirement)} className='ml-2 rounded border p-2'><option value='required'>Requerido</option><option value='optional'>Opcional</option><option value='not_required'>No requerido</option></select></label>
            <label className='block'>Estado<select value={status} onChange={(e) => setStatus(e.target.value as typeof status)} className='ml-2 rounded border p-2'><option value='missing'>Faltante</option><option value='present'>Presente</option></select></label>
            <label className='block'>Referencia<input value={reference} onChange={(e) => setReference(e.target.value)} className='ml-2 rounded border p-2' /></label>
            <label className='block'>Archivo privado<select value={file} onChange={(e) => setFile(e.target.value)} className='ml-2 rounded border p-2'><option value=''>Sin archivo</option>{files.map((f) => <option key={f.id} value={f.id}>{f.file_name}</option>)}</select></label>
            <button disabled={busy} className='rounded border px-3 py-2'>Guardar {item.display_label}</button>
        </> : <p>{item.requirement_level} · {item.status}</p>}
        {error && <p role='alert'>{error}</p>}
    </form>;
}
export function CompanyOperationalDocuments({ data, onRefresh }: { data: Operation360Data; onRefresh: () => Promise<void> }) {
    const [files, setFiles] = useState<CompanyDocument[]>([]); const [error, setError] = useState('');
    const id = data.operation.db_id; const tenant = data.operation.tenant_id;
    useEffect(() => { if (!tenant || !id) return; let active = true; void companyDocumentHistory(tenant, 'operation', id).then((rows) => { if (active) setFiles(rows.filter((f) => f.status === 'active' && f.access_class === 'operational')); }, () => { if (active) setError('No fue posible consultar el expediente.'); }); return () => { active = false; }; }, [tenant, id, data]);
    return <section className='space-y-4'><h3 className='font-bold'>Requisitos documentales</h3>{error && <p role='alert'>{error}</p>}
        <div className='grid gap-3 lg:grid-cols-2'>{data.documents.map((item) => <Requirement key={`${item.document_type}:${data.operation.workflow_revision}`} item={item} data={data} files={files} refresh={onRefresh} />)}</div>
        {id && <CompanyOperationFiles operationId={id} onChanged={onRefresh} />}
    </section>;
}
