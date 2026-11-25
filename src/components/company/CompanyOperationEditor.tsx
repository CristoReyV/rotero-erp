import { useState, type FormEvent } from 'react';
import { operationCommand } from '@/services/companyWorkflow.service';
import { hasCompanyCapability } from '@/store/companyStore';
import { useAuthStore } from '@/store/authStore';
import type { Operation } from '@/types/operations';

export function CompanyOperationEditor({ operation, onRefresh }: {
    operation: Operation; onRefresh: () => Promise<void>;
}) {
    const role = useAuthStore((state) => state.getRole());
    const [editing, setEditing] = useState(false);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState('');
    const allowed = (role === 'operator' || role === 'admin') && hasCompanyCapability('operations.edit');
    if (!allowed) return null;
    const save = async (event: FormEvent<HTMLFormElement>) => {
        event.preventDefault();
        if (!operation.db_id || busy) return;
        const data = new FormData(event.currentTarget);
        setBusy(true);
        setError('');
        try {
            await operationCommand(operation.db_id, 'edit', {
                route_summary: String(data.get('route')),
                client_display_name: String(data.get('customer')),
                destination_city: String(data.get('destination')),
            }, operation.workflow_revision);
            await onRefresh();
            setEditing(false);
        } catch (error) {
            setError(error instanceof Error ? error.message : 'No se pudo confirmar el cambio.');
        } finally { setBusy(false); }
    };
    return (
        <section className='rounded-xl border p-4'>
            <button onClick={() => setEditing((value) => !value)}>Editar ficha operativa</button>
            {editing && (
                <form onSubmit={(event) => void save(event)} className='mt-3 grid gap-3 sm:grid-cols-3'>
                    {[
                        ['route', 'Ruta', operation.route_summary ?? ''],
                        ['customer', 'Cliente', operation.client_display_name ?? ''],
                        ['destination', 'Ciudad destino', operation.destination_city ?? ''],
                    ].map(([name, label, value]) => (
                        <label key={name} className='text-sm'>
                            {label}
                            <input name={name} defaultValue={value} maxLength={500} className='block w-full rounded border p-2' />
                        </label>
                    ))}
                    {error && <p role='alert'>{error}</p>}
                    <button disabled={busy} type='submit'>Guardar ficha</button>
                </form>
            )}
        </section>
    );
}
