import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { downloadCompanyFile } from '@/services/companyDelivery.service';
import { cancelCompanyDocument, companyDocumentHistory, uploadCompanyDocument, type CompanyDocument, type DocumentParent } from '@/services/companyDocuments.service';
import { hasCompanyCapability } from '@/store/companyStore';
import { useAuthStore } from '@/store/authStore';

export function CompanyDocumentManager({ entityType, entityId, onChanged }: { key?: string; entityType: DocumentParent; entityId: string; onChanged?: () => Promise<void> }) {
    const tenant = useAuthStore((s) => s.activeTenant);
    const role = useAuthStore((s) => s.getRole());
    const [items, setItems] = useState<CompanyDocument[]>([]);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(true);
    const [busy, setBusy] = useState(false);
    const [file, setFile] = useState<File | null>(null);
    const [reason, setReason] = useState('');
    const [previous, setPrevious] = useState<CompanyDocument | null>(null);
    const [cancelling, setCancelling] = useState<CompanyDocument | null>(null);
    const [classification, setClassification] = useState<'operational' | 'financial'>(entityType === 'operation' ? 'operational' : 'financial');
    const allowed = hasCompanyCapability('billing.document.read');
    const financialWrite = hasCompanyCapability('financial.full.read') && hasCompanyCapability('finance.write') && ['admin', 'finance'].includes(role ?? '');
    const operationalWrite = entityType === 'operation' && hasCompanyCapability('operations.evidence.write') && ['admin', 'operator'].includes(role ?? '');
    const upload = hasCompanyCapability('documents.upload') && (financialWrite || operationalWrite);
    const manage = upload && hasCompanyCapability('documents.manage');
    const load = useCallback(async () => {
        if (!tenant || !allowed) { setLoading(false); return; }
        setLoading(true);
        try { setItems(await companyDocumentHistory(tenant, entityType, entityId)); }
        finally { setLoading(false); }
    }, [tenant, allowed, entityType, entityId]);
    useEffect(() => { let active = true; void load().catch(() => { if (active) setError('No fue posible verificar el expediente.'); }); return () => { active = false; }; }, [load]);
    const save = async (event: FormEvent) => {
        event.preventDefault(); if (!tenant || busy) return;
        setBusy(true); setError('');
        try {
            if (cancelling) await cancelCompanyDocument(tenant, cancelling.id, reason);
            else if (file) await uploadCompanyDocument(tenant, entityType, entityId, file, previous?.access_class ?? (entityType === 'operation' && !operationalWrite ? 'financial' : classification), previous?.id, reason);
            else return;
            setFile(null); setPrevious(null); setCancelling(null); setReason(''); await load(); await onChanged?.();
        } catch (cause) { setError(cause instanceof Error ? cause.message : 'No fue posible guardar el archivo.'); }
        finally { setBusy(false); }
    };
    const download = async (id: string) => {
        if (!tenant) return;
        try {
            const result = await downloadCompanyFile(tenant, id); const url = URL.createObjectURL(result.blob);
            const link = document.createElement('a'); link.href = url; link.download = result.name; link.click(); URL.revokeObjectURL(url);
        } catch { setError('Archivo no disponible o descarga no autorizada.'); }
    };
    if (!allowed) return <p>Sin capacidad documental para esta empresa.</p>;
    return <section className='space-y-4 rounded-xl border p-4'>
        <h3 className='font-bold'>Expediente y versiones</h3>
        {error && <p role='alert'>{error}</p>}
        {upload && <form onSubmit={(event) => void save(event)} className='space-y-3 rounded-xl border p-3'>
            <p>{cancelling ? `Cancelar ${cancelling.file_name}` : previous ? `Sustituir ${previous.file_name}` : 'Agregar archivo privado'}</p>
            {!cancelling && <>
                <input aria-label='Archivo privado' type='file' disabled={busy} onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
                {entityType === 'operation' && financialWrite && operationalWrite && !previous && <label className='block'>Clasificación<select aria-label='Clasificación documental' value={classification} onChange={(e) => setClassification(e.target.value as typeof classification)}>
                    <option value='operational'>Operacional</option><option value='financial'>Financiera restringida</option>
                </select></label>}
            </>}
            <label className='block'>Motivo {previous || cancelling ? '(obligatorio)' : '(opcional)'}<input aria-label='Motivo documental' value={reason} maxLength={1000} required={!!(previous || cancelling)} minLength={previous || cancelling ? 3 : undefined} onChange={(e) => setReason(e.target.value)} className='ml-2 rounded border p-2' /></label>
            <button className='rounded border px-3 py-2' disabled={busy || (!cancelling && !file)}>{busy ? 'Guardando…' : cancelling ? 'Confirmar cancelación documental' : 'Guardar archivo'}</button>
            {(previous || cancelling) && <button type='button' className='ml-3' disabled={busy} onClick={() => { setPrevious(null); setCancelling(null); setReason(''); }}>Volver a alta</button>}
        </form>}
        {loading ? <p role='status'>Consultando expediente…</p> : !items.length ? <p>No hay archivos clasificados disponibles.</p> : items.map((item) => <article key={item.id} className='space-y-2 rounded border p-3'>
            <p>{item.file_name} · {item.status} · {item.access_class === 'financial' ? 'Financiero' : 'Operacional'}</p>
            <p className='text-xs'>{new Date(item.created_at).toLocaleString()} · {item.size_bytes} bytes</p>
            {item.status === 'active' && <div className='flex gap-4'>
                <button onClick={() => void download(item.id)}>Descargar {item.file_name}</button>
                {manage && (item.access_class === 'operational' ? operationalWrite : financialWrite) && <>
                    <button disabled={busy} onClick={() => { setPrevious(item); setCancelling(null); setReason(''); }}>Sustituir {item.file_name}</button>
                    <button disabled={busy} onClick={() => { setCancelling(item); setPrevious(null); setReason(''); }}>Cancelar {item.file_name}</button>
                </>}
            </div>}
            {!!item.events.length && <details><summary>Historial de versiones</summary>{item.events.map((event) => <p className='text-xs' key={event.id}>{event.action} · {new Date(event.created_at).toLocaleString()}</p>)}</details>}
        </article>)}
    </section>;
}
