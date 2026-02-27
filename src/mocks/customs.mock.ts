import type { Pedimento } from '@/types/customs';

// TODO: Replace with customs.service.ts → rpc_list_pedimentos
export const MOCK_PEDIMENTOS: Pedimento[] = [
    { id: '23-40-3921', date: '12/Oct/23', material: 'Steel Raw Material', balance: 450, status: 'Activo', discharge: 'Auto' },
    { id: '23-45-8822', date: '28/Sep/23', material: 'Copper Wiring A4', balance: 1200, status: 'Auditado', discharge: 'Manual' },
    { id: '24-01-1055', date: '05/Jan/24', material: 'Plastic Resins', balance: 8500, status: 'Activo', discharge: 'Auto' },
    { id: '24-02-2210', date: '15/Feb/24', material: 'Electronic Components', balance: 300, status: 'Cerrado', discharge: 'Final' },
];

// Async wrapper for future service swap (SF-02)
export async function getMockPedimentos() { return MOCK_PEDIMENTOS; }
