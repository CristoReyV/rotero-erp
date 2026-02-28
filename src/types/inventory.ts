export interface InventoryLot {
    id?: string;
    db_id?: string;
    sku: string;
    lot: string;
    description: string;
    warehouse: string;
    date: string;
    stock: number;
    qty_reserved?: number;
    unit: string;
    value: number;
    low?: boolean;
    status?: string;
    pepsPosition?: number;
}

export interface StockAlert {
    sku: string;
    description: string;
    currentStock: number;
    unit: string;
    minStock: number;
    severity: 'danger' | 'warning';
}

export interface InventoryFilters {
    sku?: string;
}

export interface InventoryUpdatePatch {
    qty_reserved?: number;
    status?: string;
    warehouse?: string;
    description?: string;
}

export interface InventoryInsertPayload {
    sku: string;
    lot_code: string;
    qty_on_hand: number;
    warehouse?: string;
    received_at?: string;
    unit_cost?: number;
    currency?: string;
    pedimento_ref?: string;
    description?: string;
    unit?: string;
}
