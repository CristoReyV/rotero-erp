import { useEffect, useState } from 'react';
import { type CompanyFile, downloadCompanyFile, operationFiles } from '@/services/companyDelivery.service';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability } from '@/store/companyStore';

export function CompanyOperationFiles(
    { operationId, entityType = 'operation' }: { operationId: string; entityType?: string },
) {
    const tenant = useAuthStore((state) => state.activeTenant);
    const [files, setFiles] = useState<CompanyFile[]>([]);
    const [error, setError] = useState('');
    const allowed = hasCompanyCapability('billing.document.read');
    useEffect(() => {
        if (!tenant || !allowed) return;
        let active = true;
        void operationFiles(tenant, operationId, entityType).then((items) => {
            if (active) setFiles(items);
        }, () => {
            if (active) setError('No fue posible verificar los documentos.');
        });
        return () => {
            active = false;
        };
    }, [tenant, operationId, entityType, allowed]);
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
            setError('Descarga no autorizada o archivo no disponible.');
        }
    };
    return (
        <section className='space-y-3 rounded-xl border p-4'>
            <h3 className='font-bold'>Archivos privados autorizados</h3>
            {!allowed ? <p>Sin capacidad documental para esta empresa.</p> : (
                <>
                    {error && <p role='alert'>{error}</p>}
                    {files.length === 0 && (
                        <p className='text-sm text-slate-500'>No hay archivos clasificados disponibles.</p>
                    )}
                    {files.map((file) => (
                        <button
                            key={file.id}
                            className='block text-sm text-primary underline'
                            onClick={() => void download(file.id)}
                        >
                            {file.file_name}
                        </button>
                    ))}
                </>
            )}
        </section>
    );
}
