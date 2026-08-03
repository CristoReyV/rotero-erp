import type { BadgeVariant } from '@/types/common';
import type { Operation } from '@/types/operations';

export type OperationsView = 'active' | 'all' | 'draft' | 'in_transit' | 'delivered' | 'closed';

export const OPERATIONS_VIEWS: { value: OperationsView; label: string }[] = [
    { value: 'active', label: 'Activas' },
    { value: 'all', label: 'Todas' },
    { value: 'draft', label: 'Borradores' },
    { value: 'in_transit', label: 'En tránsito' },
    { value: 'delivered', label: 'Entregadas' },
    { value: 'closed', label: 'Cerradas' },
];

export const OPERATION_STATUS_META: Record<string, { label: string; variant: BadgeVariant }> = {
    draft: { label: 'Borrador', variant: 'default' },
    planned: { label: 'Planeada', variant: 'warning' },
    assigned: { label: 'Asignada', variant: 'info' },
    in_transit: { label: 'En tránsito', variant: 'info' },
    delivered: { label: 'Entregada', variant: 'success' },
    closed: { label: 'Cerrada', variant: 'default' },
    cancelled: { label: 'Cancelada', variant: 'danger' },
};

export const OPERATION_PROGRESS = ['draft', 'planned', 'assigned', 'in_transit', 'delivered', 'closed'] as const;

const INACTIVE_STATUSES = new Set(['delivered', 'closed', 'cancelled']);

export const isOperationsView = (value: string | null): value is OperationsView =>
    OPERATIONS_VIEWS.some((view) => view.value === value);

export const getOperationStatus = (status: string) =>
    OPERATION_STATUS_META[status] ?? { label: status || 'Sin estado', variant: 'default' as BadgeVariant };

export const isActiveOperation = (operation: Operation) => !INACTIVE_STATUSES.has(operation.status);

export function filterOperations(
    operations: Operation[],
    view: OperationsView,
    status: string,
    query: string,
) {
    const normalizedQuery = query.trim().toLocaleLowerCase('es-MX');

    return operations.filter((operation) => {
        const matchesView =
            view === 'all'
            || (view === 'active' && isActiveOperation(operation))
            || operation.status === view;
        const matchesStatus = !status || operation.status === status;
        const searchableValues = [
            operation.id,
            operation.client,
            operation.type,
            operation.route,
            operation.driver_name,
            operation.vehicle_ref,
        ];
        const matchesQuery = !normalizedQuery || searchableValues.some((value) =>
            value?.toLocaleLowerCase('es-MX').includes(normalizedQuery));

        return matchesView && matchesStatus && matchesQuery;
    });
}

export function getOperationsCounts(operations: Operation[]) {
    const count = (status: string) => operations.filter((operation) => operation.status === status).length;

    return {
        active: operations.filter(isActiveOperation).length,
        planned: count('planned'),
        assigned: count('assigned'),
        inTransit: count('in_transit'),
        delivered: count('delivered'),
        closed: count('closed'),
        draft: count('draft'),
    };
}

export function formatOperationDate(value?: string) {
    if (!value) return 'Datos por confirmar';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return 'Datos por confirmar';

    return new Intl.DateTimeFormat('es-MX', {
        dateStyle: 'medium',
        timeStyle: 'short',
    }).format(date);
}
