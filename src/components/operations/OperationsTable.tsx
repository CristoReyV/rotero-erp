import { CalendarClock, ChevronRight, MapPin, Truck, UserRound } from 'lucide-react';
import { Badge } from '@/components/Badge';
import type { Operation } from '@/types/operations';
import { formatOperationDate, getOperationStatus } from './operationsControl';

interface OperationsTableProps {
    operations: Operation[];
    selectedId: string | null;
    onSelect: (operation: Operation) => void;
    selectedBulkIds?: Set<string>;
    onToggleBulk?: (operation: Operation) => void;
    onToggleAll?: () => void;
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

export function OperationsTable({ operations, selectedId, onSelect, selectedBulkIds, onToggleBulk, onToggleAll }: OperationsTableProps) {
    return (
        <div className="overflow-hidden rounded-2xl border border-tech-border/60 bg-surface-card">
            <div className="hidden overflow-x-auto md:block">
                <table className="w-full min-w-[880px] text-left text-sm">
                    <thead className="border-b border-tech-border/50 bg-slate-50/70">
                        <tr className="text-[10px] font-bold uppercase tracking-widest text-slate-400">
                            {onToggleBulk && <th className="w-10 px-3 py-3.5"><input aria-label="Seleccionar todas las operaciones visibles" type="checkbox" checked={operations.length > 0 && operations.every((item) => selectedBulkIds?.has(item.db_id ?? item.id))} onChange={onToggleAll} /></th>}
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
                                    className={`cursor-pointer transition-colors ${selected ? 'bg-primary-50/60' : 'hover:bg-semantic-neutral-soft'}`}
                                >
                                    {onToggleBulk && <td className="px-3 py-4"><input aria-label={`Seleccionar ${operation.id}`} type="checkbox" checked={selectedBulkIds?.has(operation.db_id ?? operation.id) ?? false} onClick={(event) => event.stopPropagation()} onChange={() => onToggleBulk(operation)} /></td>}
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
                            aria-pressed={selected}
                            className={`w-full min-w-0 max-w-full p-3 text-left transition-colors min-[390px]:p-4 ${selected ? 'bg-primary-50 ring-1 ring-inset ring-primary/25' : 'bg-surface-card active:bg-semantic-neutral-soft focus-visible:bg-semantic-neutral-soft focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary/40 sm:hover:bg-semantic-neutral-soft'}`}
                        >
                            <div className="flex min-w-0 items-start justify-between gap-2"><div className="flex min-w-0 flex-1 gap-2">{onToggleBulk && <input aria-label={`Seleccionar ${operation.id}`} type="checkbox" checked={selectedBulkIds?.has(operation.db_id ?? operation.id) ?? false} onClick={(event) => event.stopPropagation()} onChange={() => onToggleBulk(operation)} />}
                                <div className="min-w-0">
                                    <p className="truncate font-bold text-primary">{operation.id}</p>
                                    <p className="mt-0.5 truncate text-sm font-semibold text-slate-700">{operation.client}</p>
                                </div></div>
                                <Badge variant={status.variant}>{status.label}</Badge>
                            </div>
                            <div className="mt-3 grid gap-2 text-xs text-slate-500">
                                <p className="flex min-w-0 items-center gap-2"><MapPin size={13} className="shrink-0" /><span className="min-w-0 truncate">{operation.route || 'Ruta por confirmar'}</span></p>
                                <p className="flex min-w-0 items-center gap-2"><UserRound size={13} className="shrink-0" /><span className="min-w-0 truncate">{operation.provider_name || operation.driver_name || 'Proveedor por confirmar'}</span></p>
                                <p className="flex items-center gap-2"><CalendarClock size={13} /> {formatOperationDate(operation.planned_departure)}</p>
                            </div>
                        </button>
                    );
                })}
            </div>
        </div>
    );
}
