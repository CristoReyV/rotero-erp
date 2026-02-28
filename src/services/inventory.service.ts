import { supabase } from '@/lib/supabase';
import type { InventoryLot, InventoryFilters, InventoryInsertPayload, InventoryUpdatePatch, StockAlert } from '@/types/inventory';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export interface DbInventoryLot {
    id: string;
    sku: string;
    description: string | null;
    warehouse: string | null;
    lot_code: string | null;
    qty_on_hand: number;
    qty_reserved: number;
    unit_cost: number | null;
    currency: string | null;
    received_at: string;
    pedimento_ref: string | null;
    status: string;
    unit?: string;
    created_at: string;
}

function mapDbInventoryToUI(db: DbInventoryLot, index: number): InventoryLot {
    const stock = Number(db.qty_on_hand);
    const reserved = Number(db.qty_reserved);
    const unit_cost = Number(db.unit_cost || 0);

    return {
        id: db.id,
        db_id: db.id,
        sku: db.sku,
        lot: db.lot_code || 'N/A',
        description: db.description || 'N/A',
        warehouse: db.warehouse || 'N/A',
        date: new Date(db.received_at).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: '2-digit' }),
        stock: stock,
        qty_reserved: reserved,
        unit: db.unit || 'Piezas',
        value: unit_cost * stock,
        low: (stock - reserved) <= 10,
        status: db.status,
        pepsPosition: index + 1
    };
}

export async function listInventoryLots(tenantId: string, filters: InventoryFilters = {}): Promise<InventoryLot[]> {
    if (USE_MOCKS) {
        const { getMockInventoryLots } = await import('@/mocks/inventory.mock');
        return getMockInventoryLots();
    }

    const { data, error } = await supabase.rpc('rpc_list_inventory_lots', {
        p_tenant_id: tenantId,
        p_filters: filters
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return (data || []).map((dbLot: any, i: number) => mapDbInventoryToUI(dbLot, i));
}

export async function createInventoryLot(tenantId: string, payload: InventoryInsertPayload): Promise<{ id: string }> {
    if (USE_MOCKS) {
        return { id: 'mock-uuid-123' };
    }

    const { data, error } = await supabase.rpc('rpc_create_inventory_lot', {
        p_tenant_id: tenantId,
        p_sku: payload.sku,
        p_lot_code: payload.lot_code,
        p_qty_on_hand: payload.qty_on_hand,
        p_warehouse: payload.warehouse,
        p_received_at: payload.received_at || new Date().toISOString(),
        p_currency: payload.currency || 'MXN',
        p_pedimento_ref: payload.pedimento_ref,
        p_description: payload.description,
        p_unit: payload.unit || 'Piezas'
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updateInventoryLot(id: string, patch: InventoryUpdatePatch): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_inventory_lot', {
        p_id: id,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function getStockAlerts(tenantId: string): Promise<StockAlert[]> {
    if (USE_MOCKS) {
        const { getMockStockAlerts } = await import('@/mocks/inventory.mock');
        return getMockStockAlerts();
    }

    const lots = await listInventoryLots(tenantId);

    // Wire alerts
    // “Stock Bajo” = qty_on_hand - qty_reserved <= threshold
    // “Bloqueado” = status blocked
    const threshold = 10;
    const alerts: StockAlert[] = [];

    lots.forEach((lot) => {
        const available = lot.stock - (lot.qty_reserved || 0);
        if (lot.status === 'blocked') {
            alerts.push({
                sku: lot.sku,
                description: `${lot.description} — Bloqueado`,
                currentStock: available,
                unit: lot.unit,
                minStock: threshold,
                severity: 'danger'
            });
        } else if (available <= threshold) {
            alerts.push({
                sku: lot.sku,
                description: lot.description,
                currentStock: available,
                unit: lot.unit,
                minStock: threshold,
                severity: 'warning'
            });
        }
    });

    return alerts;
}
