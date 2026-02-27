export interface Pedimento {
    db_id?: string;
    id: string; // for UI display (pedimento_number)
    pedimento_number?: string;
    date: string;
    material: string;
    balance: number;
    status: string;
    discharge: string;
}

export interface DescargoLine {
    id: string;
    pedimento_id: string;
    sku: string;
    lot_code?: string;
    qty: number;
    unit: string;
    inventory_lot_id?: string;
    created_at: string;
}

export interface PedimentoFilters {
    pedimento_number?: string;
}

export interface PedimentoCreatePayload {
    pedimento_number: string;
    aduana?: string;
    regimen?: string;
    tipo_operacion?: string;
    fecha_pago?: string;
    total_value?: number;
    currency?: string;
    status?: string;
}

export interface PedimentoUpdatePatch {
    status?: string;
    fecha_pago?: string;
    fecha_entrada?: string;
    fecha_salida?: string;
    aduana?: string;
    regimen?: string;
    total_value?: number;
    currency?: string;
}

export interface DescargoLineInsertPayload {
    sku: string;
    lot_code?: string;
    qty: number;
    unit?: string;
    inventory_lot_id?: string;
}
