import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { type CompanyFile, downloadCompanyFile } from '@/services/companyDelivery.service';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';

export default function CompanyDocumentsPage() {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [search, setSearch] = useState('');
    const [cursor, setCursor] = useState<string | null>(null);
    const [data, setData] = useState<
        { items: CompanyFile[]; total: number; next_cursor: string | null } | null
    >(null);
    const [error, setError] = useState('');
    const allowed = hasCompanyCapability('billing.document.read');
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        setData(null);
        setError('');
        void supabase.rpc('rpc_delivery_files_page', {
            p_tenant_id: tenant,
            p_search: search,
            p_after_id: cursor,
            p_limit: 50,
        })
            .then(({ data, error }) => {
                if (!active) return;
                if (error || data?.error || !Array.isArray(data?.items)) {
                    setError('No fue posible verificar el expediente documental.');
                } else setData(data);
            });
        return () => {
            active = false;
        };
    }, [tenant, allowed, search, cursor]);
    const download = async (id: string) => {
        if (!tenant) return;
        try {
            const { blob, name } = await downloadCompanyFile(tenant, id);
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = name;
            link.click();
            URL.revokeObjectURL(url);
        } catch {
            setError('Archivo no disponible o descarga no autorizada.');
        }
    };
    if (!allowed) return <p role='alert'>Sin capacidad documental para esta empresa.</p>;
    return (
        <div className='space-y-5'>
            <h1 className='text-2xl font-bold'>Documentos</h1>
            <input
                aria-label='Buscar documentos'
                value={search}
                onChange={(event) => {
                    setSearch(event.target.value);
                    setCursor(null);
                }}
                placeholder='Nombre del archivo'
                className='w-full rounded-xl border p-3'
            />
            {error && <p role='alert'>{error}</p>}
            {data
                ? (
                    <>
                        <p>{data.total} archivos autorizados en este alcance</p>
                        <div className='divide-y rounded-xl border bg-surface-card'>
                            {data.items.map((file) => (
                                <div key={file.id} className='flex items-center justify-between gap-3 p-4'>
                                    <p className='truncate text-sm'>{file.file_name}</p>
                                    <button
                                        onClick={() =>
                                            void download(file.id)}
                                    >
                                        Descargar
                                    </button>
                                </div>
                            ))}
                        </div>
                        <div className='flex gap-4'>
                            <button disabled={!cursor} onClick={() => setCursor(null)}>Primera página</button>
                            <button disabled={!data.next_cursor} onClick={() => setCursor(data.next_cursor)}>
                                Siguiente página
                            </button>
                        </div>
                    </>
                )
                : !error && <p role='status'>Cargando…</p>}
        </div>
    );
}
