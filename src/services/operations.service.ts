import { supabase } from '@/lib/supabase';
import type { Operation } from '@/types/operations';
import type { Place } from '@/types/tracking';
import type { BadgeVariant } from '@/types/common';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export interface DbOperation {
    id: string;
    reference_code: string;
    route_summary: string | null;
    client_display_name: string | null;
    destination_city: string | null;
    eta_display: string | null;
    status: string;
    created_at: string;
    eta: string | null;
    origin_place: Place | null;
    destination_place: Place | null;
}

export type OperationInsertPayload = {
    reference_code: string;
    route_summary?: string;
    client_display_name?: string;
    destination_city?: string;
    eta_display?: string;
    status?: string;
    origin_place?: Place;
    destination_place?: Place;
    eta?: string;
};

// Map Db status to badge variant
function mapStatusToVariant(status: string): BadgeVariant {
    switch (status) {
        case 'draft': return 'default';
        case 'planned': return 'warning';
        case 'in_transit': return 'info';
        case 'delivered': return 'success';
        case 'cancelled': return 'danger';
        default: return 'default';
    }
}

// Convert DbOperation to UI Operation
function mapDbOperationToUI(dbOp: DbOperation): Operation {
    return {
        id: dbOp.reference_code, // Use reference_code as visual ID
        db_id: dbOp.id, // Keep the real UUID for RPC calls
        client: dbOp.client_display_name || 'N/A',
        type: dbOp.route_summary || 'N/A',
        status: dbOp.status,
        route: dbOp.destination_city || 'N/A',
        owner: 'Admin', // In the future, this should come from created_by or owner field
        variant: mapStatusToVariant(dbOp.status)
    };
}

export async function listOperations(tenantId: string): Promise<Operation[]> {
    if (USE_MOCKS) {
        const { getMockOperations } = await import('@/mocks/operations.mock');
        return getMockOperations();
    }

    const { data, error } = await supabase.rpc('rpc_list_operations', { p_tenant_id: tenantId });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return (data || []).map((dbOp: any) => mapDbOperationToUI(dbOp));
}

export async function createOperation(tenantId: string, payload: OperationInsertPayload): Promise<{ id: string }> {
    if (USE_MOCKS) {
        // Just simulate a fake ID
        return { id: 'mock-uuid-123' };
    }

    const { data, error } = await supabase.rpc('rpc_create_operation', {
        p_tenant_id: tenantId,
        p_reference_code: payload.reference_code,
        p_route_summary: payload.route_summary,
        p_client_display_name: payload.client_display_name,
        p_destination_city: payload.destination_city,
        p_eta_display: payload.eta_display,
        p_status: payload.status,
        p_origin_place: payload.origin_place,
        p_destination_place: payload.destination_place,
        p_eta: payload.eta
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function getOperation(operationId: string): Promise<Operation | null> {
    if (USE_MOCKS) {
        const { getMockOperations } = await import('@/mocks/operations.mock');
        const list = await getMockOperations();
        return list.find(o => o.db_id === operationId || o.id === operationId) || null;
    }

    const { data, error } = await supabase.rpc('rpc_get_operation', { p_operation_id: operationId });
    if (error) throw error;
    if (data?.error) {
        if (data.error === 'not_found') return null;
        throw new Error(data.error);
    }

    return mapDbOperationToUI(data);
}
