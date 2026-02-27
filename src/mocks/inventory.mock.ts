import type { InventoryLot, StockAlert } from '@/types/inventory';

// TODO: Replace with inventory.service.ts → rpc_list_inventory_lots
export const MOCK_INVENTORY_LOTS: InventoryLot[] = [
    { sku: 'SKU-10294', lot: '#9921', description: 'Widget Industrial A', warehouse: 'Nave-01', date: '12/Oct/23', stock: 450, unit: 'pzas', value: 540000 },
    { sku: 'SKU-44021', lot: '#8832', description: 'Conector Hidráulico', warehouse: 'Nave-02', date: '01/Nov/23', stock: 4, unit: 'pzas', value: 1280, low: true },
    { sku: 'SKU-88210', lot: '#7710', description: 'Solvente Orgánico 5L', warehouse: 'Nave-01', date: '15/Dic/23', stock: 200, unit: 'lts', value: 170000 },
    { sku: 'SKU-33219', lot: '#9955', description: 'Empaque Industrial XL', warehouse: 'Nave-03', date: '05/Oct/23', stock: 120, unit: 'pzas', value: 13800 },
];

// TODO: Replace with inventory.service.ts → rpc_get_stock_alerts
export const MOCK_STOCK_ALERTS: StockAlert[] = [
    { sku: 'SKU-44021', description: 'Conector Hidráulico', currentStock: 4, unit: 'pzas', minStock: 20, severity: 'danger' },
    { sku: 'SKU-10294', description: 'Widget Industrial A — Próximo a caducar', currentStock: 450, unit: 'pzas', minStock: 100, severity: 'warning' },
];

// Async wrappers for future service swap (SF-02)
export async function getMockInventoryLots() { return MOCK_INVENTORY_LOTS; }
export async function getMockStockAlerts() { return MOCK_STOCK_ALERTS; }
