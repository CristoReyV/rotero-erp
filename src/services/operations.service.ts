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
    driver_id?: string | null;
    vehicle_id?: string | null;
    driver_name?: string | null;
    vehicle_ref?: string | null;
    planned_departure?: string | null;
    priority?: string | null;
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
        case 'assigned': return 'info';
        case 'in_transit': return 'info';
        case 'delivered': return 'success';
        case 'cancelled': return 'danger';
        case 'closed': return 'default';
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
        variant: mapStatusToVariant(dbOp.status),
        driver_id: dbOp.driver_id || undefined,
        vehicle_id: dbOp.vehicle_id || undefined,
        driver_name: dbOp.driver_name || undefined,
        vehicle_ref: dbOp.vehicle_ref || undefined,
        planned_departure: dbOp.planned_departure || undefined,
        priority: dbOp.priority || undefined
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

export type OperationAssignPayload = {
    driver_id: string;
    vehicle_id: string;
    driver_name?: string;
    vehicle_ref?: string;
    planned_departure: string;
    priority?: string;
};

export async function assignOperation(tenantId: string, operationId: string, payload: OperationAssignPayload): Promise<{ success: boolean; error?: string }> {
    if (USE_MOCKS) {
        return { success: true };
    }

    try {
        // Attempt V2 call (persists names and assigned_at)
        const { data: dataV2, error: errorV2 } = await supabase.rpc('rpc_assign_operation_v2', {
            p_tenant_id: tenantId,
            p_operation_id: operationId,
            p_driver_id: payload.driver_id,
            p_driver_name: payload.driver_name || '',
            p_vehicle_id: payload.vehicle_id,
            p_vehicle_ref: payload.vehicle_ref || '',
            p_planned_departure: payload.planned_departure,
            p_priority: payload.priority || 'normal'
        });

        if (!errorV2 && dataV2?.success) return { success: true };

        // If not found (404/PGRST202) -> fallback to V1
        // Or if it's a specific "function not found" error
        if (errorV2 && (errorV2.code === 'PGRST202' || errorV2.message?.includes('not found') || errorV2.message?.includes('does not exist'))) {
            const { data: dataV1, error: errorV1 } = await supabase.rpc('rpc_assign_operation', {
                p_tenant_id: tenantId,
                p_operation_id: operationId,
                p_driver_id: payload.driver_id,
                p_vehicle_id: payload.vehicle_id,
                p_planned_departure: payload.planned_departure,
                p_priority: payload.priority || 'normal'
            });

            if (errorV1) throw errorV1;
            if (dataV1?.error) throw new Error(dataV1.error);
            return { success: true };
        }

        if (errorV2) throw errorV2;
        if (dataV2?.error) throw new Error(dataV2.error);

    } catch (err: any) {
        console.error('Assignation failed:', err);
        throw err;
    }

    return { success: true };
}

export async function updateOperationDetails(operationId: string, patch: any): Promise<{ success: boolean; error?: string }> {
    if (USE_MOCKS) return { success: true };
    const { data, error } = await supabase.rpc('rpc_update_operation_details', {
        p_operation_id: operationId,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { success: true };
}

export async function transitionOperationStatus(operationId: string, toStatus: string): Promise<{ success: boolean; error?: string }> {
    if (USE_MOCKS) return { success: true };
    const { data, error } = await supabase.rpc('rpc_transition_operation_status', {
        p_operation_id: operationId,
        p_to_status: toStatus
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error); // Specifically bubble errors for UI (missing_driver, etc)

    return { success: true };
}

export async function overrideOperationStatus(operationId: string, toStatus: string, reason: string): Promise<{ success: boolean; error?: string }> {
    if (USE_MOCKS) return { success: true };
    const { data, error } = await supabase.rpc('rpc_override_operation_status', {
        p_operation_id: operationId,
        p_to_status: toStatus,
        p_reason: reason
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { success: true };
}

export async function getOperationRequirements(operationId: string): Promise<{
    has_driver_assigned: boolean;
    has_driver_token: boolean;
    has_public_token: boolean;
    has_delivered_event: boolean;
}> {
    if (USE_MOCKS) {
        return {
            has_driver_assigned: true,
            has_driver_token: true,
            has_public_token: true,
            has_delivered_event: true
        };
    }
    const { data, error } = await supabase.rpc('rpc_get_operation_requirements', {
        p_operation_id: operationId
    });

    if (error) throw error;
    return data;
}

/**
 * Frontend safety net: ensure a driver:write tracking token exists for this operation.
 * The DB RPC is now idempotent — if active token exists, it returns it without rotation.
 */
export async function ensureTrackingToken(tenantId: string, operationId: string): Promise<{ existed: boolean; created: boolean; error?: string }> {
    if (USE_MOCKS) return { existed: true, created: false };

    // Fast path: check if token already exists
    const reqs = await getOperationRequirements(operationId);
    if (reqs.has_driver_token) {
        return { existed: true, created: false };
    }

    // Create driver:write token (idempotent — RPC returns existing if active)
    const { data, error } = await supabase.rpc('rpc_create_tracking_token', {
        p_tenant_id: tenantId,
        p_operation_id: operationId,
        p_scope: 'driver:write',
        p_ttl_hours: 48,
        p_force_rotate: false
    });

    if (error) return { existed: false, created: false, error: error.message };
    if (data?.error) return { existed: false, created: false, error: data.error };

    const alreadyExisted = data?.already_existed === true;

    // Also create public:read token (idempotent, non-critical)
    try {
        await supabase.rpc('rpc_create_tracking_token', {
            p_tenant_id: tenantId,
            p_operation_id: operationId,
            p_scope: 'public:read',
            p_force_rotate: false
        });
    } catch {
        // Non-critical
    }

    return { existed: alreadyExisted, created: !alreadyExisted };
}
