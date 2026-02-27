import type { Operation, TimelineStep } from '@/types/operations';
import { MOCK_TIMELINE } from './timeline.mock';
// TODO: Replace with operations.service.ts → rpc_list_operations
export const MOCK_OPERATIONS: Operation[] = [
    { id: 'OP-8492', client: 'Autopartes de México', type: 'FTL - Seco', status: 'En Tránsito', route: 'Laredo → MTY', owner: 'J. Perez', variant: 'info' },
    { id: 'OP-8493', client: 'Logística Global MX', type: 'LTL - Consolidado', status: 'Aduana', route: 'Manzanillo → CDMX', owner: 'M. Gomez', variant: 'warning' },
    { id: 'OP-8494', client: 'Retail Norte', type: 'FTL - Refrigerado', status: 'Cargando', route: 'QRO → LDO', owner: 'R. Sanchez', variant: 'default' },
    { id: 'OP-8495', client: 'Industrias Pesadas', type: 'Sobredimensionado', status: 'Entregado', route: 'Veracruz → SLP', owner: 'L. Torres', variant: 'success' },
];



// Async wrappers for future service swap (SF-02)
export async function getMockOperations() { return MOCK_OPERATIONS; }
export async function getMockTimeline() { return MOCK_TIMELINE; }
