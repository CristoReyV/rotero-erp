import type { CFDIListRow } from '@/types/billing';

export const MOCK_CFDIS: CFDIListRow[] = [
    { db_id: 'mock-1', folio: 'A-4022', client: 'Logistics MX S.A.', uuid: '...8a9f', amount: '$12,500.00', status: 'Timbrado', cp: 'Validado' },
    { db_id: 'mock-2', folio: 'A-4023', client: 'Transportes del Norte', uuid: '...', amount: '$8,450.00', status: 'Pendiente', cp: 'Requiere CP' },
    { db_id: 'mock-3', folio: 'A-4024', client: 'Distribuidora Bajío', uuid: '...b7c2', amount: '$3,200.00', status: 'Error', cp: 'Error RFC' },
    { db_id: 'mock-4', folio: 'A-4025', client: 'Comercializadora Global', uuid: '...f921', amount: '$45,120.00', status: 'Timbrado', cp: 'Validado' },
];

export async function getMockCFDIs() { return MOCK_CFDIS; }
