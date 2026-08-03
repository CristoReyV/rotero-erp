import { CalendarClock, ChevronRight, MapPin, Truck, UserRound } from 'lucide-react';
import { Badge } from '@/components/Badge';
import type { Operation } from '@/types/operations';
import { formatOperationDate, getOperationStatus } from './operationsControl';

interface OperationsTableProps {
    operations: Operation[];
    selectedId: string | null;
    onSelect: (operation: Operation) => void;
}

const AssignmentSummary = ({ operation }: { operation: Operation }) => (
    <div className="space-y-1">
        <p className="flex items-center gap-1.5 text-xs font-medium text-slate-600">
            <UserRound size={12} className="text-slate-400" />
            {operation.driver_name || 'Operador por confirmar'}
        </p>
        <p className="flex items-center gap-1.5 text-[11px] text-slate-400">
            <Truck size={12} /> {operation.vehicle_ref || 'Unidad por confirmar'}
        </p>
    </div>
);

export function OperationsTable({ operations, selectedId, onSelect }: OperationsTableProps) {
    return (
        <div className="overflow-hidden rounded-2xl border border-tech-border/60 bg-surface-card">
            <div className="hidden overflow-x-auto md:block">
                <table className="w-full min-w-[880px] text-left text-sm">
                    <thead className="border-b border-tech-border/50 bg-slate-50/70">
                        <tr className="text-[10px] font-bold uppercase tracking-widest text-slate-400">
                            <th className="px-5 py-3.5">Referencia / cliente</th>
                            <th className="px-5 py-3.5">Ruta disponible</th>
                            <th className="px-5 py-3.5">Estado</th>
                            <th className="px-5 py-3.5">Asignación conocida</th>
                            <th className="px-5 py-3.5">Salida planeada</th>
                            <th className="w-12 px-3 py-3.5"><span className="sr-only">Abrir panel</span></th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-tech-border/40">
                        {operations.map((operation) => {
                            const status = getOperationStatus(operation.status);
                            const selected = selectedId === operation.id;
                            return (
                                <tr
                                    key={operation.id}
                                    onClick={() => onSelect(operation)}
                                    className={`cursor-pointer transition-colors ${selected ? 'bg-primary-50/60' : 'hover:bg-slate-50/70'}`}
                                >
                                    <td className={`border-l-3 px-5 py-4 ${selected ? 'border-l-primary' : 'border-l-transparent'}`}>
                                        <p className="font-bold text-primary">{operation.id}</p>
                                        <p className="mt-0.5 max-w-[220px] truncate text-xs font-medium text-slate-600">{operation.client}</p>
                                    </td>
                                    <td className="px-5 py-4">
                                        <p className="flex items-center gap-1.5 text-xs font-semibold text-slate-600">
                                            <MapPin size={13} className="text-slate-400" /> {operation.route || 'Datos por confirmar'}
                                        </p>
                                        <p className="mt-1 max-w-[220px] truncate text-[11px] text-slate-400">{operation.type || 'Sin resumen de ruta'}</p>
                                    </td>
                                    <td className="px-5 py-4"><Badge variant={status.variant}>{status.label}</Badge></td>
                                    <td className="px-5 py-4"><AssignmentSummary operation={operation} /></td>
                                    <td className="px-5 py-4 text-xs text-slate-500">
                                        <span className="flex items-center gap-1.5"><CalendarClock size={13} /> {formatOperationDate(operation.planned_departure)}</span>
                                    </td>
                                    <td className="px-3 py-4 text-slate-300"><ChevronRight size={17} /></td>
                                </tr>
                            );
                        })}
                    </tbody>
                </table>
            </div>

            <div className="divide-y divide-tech-border/40 md:hidden">
                {operations.map((operation) => {
                    const status = getOperationStatus(operation.status);
                    const selected = selectedId === operation.id;
                    return (
                        <button
                            key={operation.id}
                            type="button"
                            onClick={() => onSelect(operation)}
                            className={`w-full p-4 text-left transition-colors ${selected ? 'bg-primary-50/60' : 'bg-white active:bg-slate-50'}`}
                        >
                            <div className="flex items-start justify-between gap-3">
                                <div className="min-w-0">
                                    <p className="font-bold text-primary">{operation.id}</p>
                                    <p className="mt-0.5 truncate text-sm font-semibold text-slate-700">{operation.client}</p>
                                </div>
                                <Badge variant={status.variant}>{status.label}</Badge>
                            </div>
                            <div className="mt-3 grid gap-2 text-xs text-slate-500">
                                <p className="flex items-center gap-2"><MapPin size={13} /> {operation.route || 'Ruta por confirmar'}</p>
                                <p className="flex items-center gap-2"><UserRound size={13} /> {operation.driver_name || 'Operador del proveedor por confirmar'}</p>
                                <p className="flex items-center gap-2"><CalendarClock size={13} /> {formatOperationDate(operation.planned_departure)}</p>
                            </div>
                        </button>
                    );
                })}
            </div>
        </div>
    );
}
