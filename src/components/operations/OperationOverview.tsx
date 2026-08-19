import { CalendarClock, MapPin, Package, Route, Truck, UserRound } from 'lucide-react';
import { Badge } from '@/components/Badge';
import type { Operation } from '@/types/operations';
import { formatOperationDate, getOperationStatus } from './operationsControl';
import { getSnapshotText } from './operation360';

const Field = ({ label, value }: { label: string; value?: string | null }) => (
    <div><p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">{label}</p><p className="mt-1 text-sm font-semibold text-slate-700">{value || 'Datos por confirmar'}</p></div>
);

export function OperationOverview({ operation }: { operation: Operation }) {
    const status = getOperationStatus(operation.status);
    const externalDriver = getSnapshotText(operation.external_driver, ['name', 'display_name', 'driver_name']);
    const externalPhone = getSnapshotText(operation.external_driver, ['phone', 'phone_number', 'mobile']);
    const externalVehicle = getSnapshotText(operation.external_vehicle, ['unit_code', 'plate_ref', 'plates', 'vehicle_ref']);
    const cargo = operation.cargo_summary && Object.keys(operation.cargo_summary).length
        ? Object.values(operation.cargo_summary).filter((value) => typeof value === 'string' || typeof value === 'number').slice(0, 3).join(' · ')
        : null;
    return (
        <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Field label="Referencia" value={operation.reference_code || operation.id} />
                <div><p className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Estado</p><div className="mt-1"><Badge variant={status.variant}>{status.label}</Badge></div></div>
                <Field label="Prioridad" value={operation.priority === 'high' ? 'Alta' : operation.priority === 'low' ? 'Baja' : 'Normal'} />
                <Field label="Alcance" value={operation.operation_scope === 'international' ? 'Internacional' : 'Nacional'} />
            </div>
            <div className="grid gap-3 rounded-2xl border border-slate-200 bg-slate-50/60 p-4 sm:grid-cols-2 lg:grid-cols-3">
                <div className="flex gap-3"><UserRound className="mt-0.5 text-primary" size={18} /><Field label="Cliente" value={operation.client_display_name || operation.client} /></div>
                <div className="flex gap-3"><Truck className="mt-0.5 text-primary" size={18} /><Field label="Servicio" value={operation.service_type || operation.type} /></div>
                <div className="flex gap-3"><Route className="mt-0.5 text-primary" size={18} /><Field label="Ruta" value={operation.route_summary || operation.route} /></div>
                <div className="flex gap-3"><MapPin className="mt-0.5 text-primary" size={18} /><Field label="Origen" value={getSnapshotText(operation.origin_place as unknown as Record<string, unknown> | null, ['municipality', 'label', 'name', 'city'])} /></div>
                <div className="flex gap-3"><MapPin className="mt-0.5 text-primary" size={18} /><Field label="Destino" value={getSnapshotText(operation.destination_place as unknown as Record<string, unknown> | null, ['municipality', 'label', 'name', 'city'])} /></div>
                <div className="flex gap-3"><Package className="mt-0.5 text-primary" size={18} /><Field label="Carga" value={cargo} /></div>
            </div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="flex gap-3"><CalendarClock className="mt-0.5 text-slate-400" size={17} /><Field label="Ventana" value={`${formatOperationDate(operation.operational_window_start ?? undefined)} — ${formatOperationDate(operation.operational_window_end ?? undefined)}`} /></div>
                <Field label="Salida planeada" value={formatOperationDate(operation.planned_departure ?? undefined)} />
                <Field label="ETA" value={formatOperationDate(operation.eta ?? undefined)} />
                <Field label="Cotización origen" value={operation.source_deal_id ? 'Vinculada a Comercial' : 'Alta operativa'} />
            </div>
            <div className="rounded-2xl border border-sky-100 bg-sky-50/70 p-4">
                <p className="text-xs font-bold uppercase tracking-wider text-sky-700">Ejecución contratada</p>
                <div className="mt-3 grid gap-3 sm:grid-cols-3">
                    <Field label="Proveedor" value={operation.provider_name} />
                    <Field label="Chofer del proveedor" value={operation.execution_type === 'third_party' ? externalDriver : operation.driver_name} />
                    <Field label="Contacto / unidad" value={operation.execution_type === 'third_party' ? `${externalPhone} · ${externalVehicle}` : operation.vehicle_ref} />
                </div>
                <p className="mt-3 text-[11px] text-sky-700">Para ejecución third-party, el chofer y la unidad son snapshots opcionales del proveedor; no requieren usuario ERP.</p>
            </div>
        </div>
    );
}
