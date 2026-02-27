import { supabase } from '@/lib/supabase';
import type { Pedimento, DescargoLine, PedimentoFilters, PedimentoCreatePayload, PedimentoUpdatePatch, DescargoLineInsertPayload } from '@/types/customs';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export interface DbPedimento {
    id: string;
    pedimento_number: string;
    status: string;
    aduana: string | null;
    regimen: string | null;
    fecha_pago: string | null;
    total_value: number | null;
    currency: string | null;
    created_at: string;
    descargo_method?: string;
}

function mapStatusToUI(status: string): string {
    switch (status) {
        case 'draft':
        case 'in_transit':
            return 'Activo';
        case 'validating':
        case 'released':
            return 'Auditado';
        case 'closed':
            return 'Cerrado';
        case 'blocked':
        default:
            return 'Bloqueado';
    }
}

function mapDbPedimentoToUI(db: DbPedimento): Pedimento {
    return {
        db_id: db.id,
        id: db.pedimento_number, // The UI expects the string number to be id on the table row
        pedimento_number: db.pedimento_number,
        date: new Date(db.created_at).toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: '2-digit' }),
        material: db.regimen || 'Materias Primas Gral', // Mapping DB concept for visual placeholder
        balance: db.total_value ? Number(db.total_value) : 0,
        status: mapStatusToUI(db.status),
        discharge: 'Auto' // We only support PEPS auto
    };
}

export async function listPedimentos(tenantId: string, filters: PedimentoFilters = {}): Promise<Pedimento[]> {
    if (USE_MOCKS) {
        const { getMockPedimentos } = await import('@/mocks/customs.mock');
        return getMockPedimentos();
    }

    const { data, error } = await supabase.rpc('rpc_list_pedimentos', {
        p_tenant_id: tenantId,
        p_filters: filters
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return (data || []).map((dbPed: any) => mapDbPedimentoToUI(dbPed));
}

export async function createPedimento(tenantId: string, payload: PedimentoCreatePayload): Promise<{ id: string }> {
    if (USE_MOCKS) {
        return { id: 'mock-uuid-ped' };
    }

    const { data, error } = await supabase.rpc('rpc_create_pedimento', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updatePedimento(id: string, patch: PedimentoUpdatePatch): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_pedimento', {
        p_id: id,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function listDescargoLines(pedimentoId: string): Promise<DescargoLine[]> {
    if (USE_MOCKS) return [];

    const { data, error } = await supabase.rpc('rpc_list_descargo_lines', {
        p_pedimento_id: pedimentoId
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data || [];
}

export async function addDescargoLine(pedimentoId: string, payload: DescargoLineInsertPayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-descargo-uuid' };

    const { data, error } = await supabase.rpc('rpc_add_descargo_line', {
        p_pedimento_id: pedimentoId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}
