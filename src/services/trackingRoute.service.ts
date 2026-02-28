/**
 * trackingRoute.service.ts
 *
 * Service for fetching GPS route points for ERP operations.
 * Calls rpc_list_route_points (authenticated via Supabase).
 */

import { supabase } from '@/lib/supabase';
import type { RoutePoint } from '@/types/tracking';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

// ── Mock data ──────────────────────────────────────────────────────────────────

const MOCK_ROUTE: RoutePoint[] = [
    { lat: 25.6866, lng: -100.3161, recorded_at: '2026-02-28T02:00:00Z', source: 'gps' },
    { lat: 25.5500, lng: -100.3800, recorded_at: '2026-02-28T02:15:00Z', source: 'gps' },
    { lat: 25.4200, lng: -100.4500, recorded_at: '2026-02-28T02:30:00Z', source: 'gps' },
    { lat: 25.2800, lng: -100.5300, recorded_at: '2026-02-28T02:45:00Z', source: 'gps' },
    { lat: 25.1000, lng: -100.6200, recorded_at: '2026-02-28T03:00:00Z', source: 'gps' },
    { lat: 24.8100, lng: -100.7500, recorded_at: '2026-02-28T03:30:00Z', source: 'gps' },
    { lat: 24.5200, lng: -100.8900, recorded_at: '2026-02-28T04:00:00Z', source: 'gps' },
];

// ── Service ────────────────────────────────────────────────────────────────────

/**
 * Fetch route points for an operation (ERP authenticated view).
 * Returns points ordered by recorded_at ASC.
 */
export async function listRoutePoints(
    operationId: string,
    start?: string,
    end?: string,
    limit = 2000,
): Promise<RoutePoint[]> {
    if (USE_MOCKS) return MOCK_ROUTE;

    const { data, error } = await supabase.rpc('rpc_list_route_points', {
        p_operation_id: operationId,
        p_start: start || null,
        p_end: end || null,
        p_limit: limit,
    });

    if (error) {
        console.error('[trackingRoute] Error fetching route points:', error.message);
        return [];
    }

    return (data || []).map((p: Record<string, unknown>) => ({
        lat: p.lat as number,
        lng: p.lng as number,
        recorded_at: p.recorded_at as string,
        accuracy_m: p.accuracy_m as number | undefined,
        source: p.source as 'gps' | 'network',
    }));
}
