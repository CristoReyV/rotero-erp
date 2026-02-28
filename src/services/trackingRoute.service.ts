/**
 * trackingRoute.service.ts
 *
 * Service for fetching GPS route points for ERP operations.
 * Sprint A: includes computeRouteStats and expanded mocks.
 */

import { supabase } from '@/lib/supabase';
import type { RoutePoint, RouteStats, RouteTimeRange } from '@/types/tracking';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

// ── Haversine (client-side, for stats) ─────────────────────────────────────────

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLng / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ── Mock data (25 pts: Monterrey → Saltillo, ~75km, 1h15m) ────────────────────

const MOCK_ROUTE: RoutePoint[] = [
    { lat: 25.6866, lng: -100.3161, recorded_at: '2026-02-28T14:00:00Z', source: 'gps' },
    { lat: 25.6700, lng: -100.3300, recorded_at: '2026-02-28T14:03:00Z', source: 'gps' },
    { lat: 25.6500, lng: -100.3450, recorded_at: '2026-02-28T14:06:00Z', source: 'gps' },
    { lat: 25.6250, lng: -100.3600, recorded_at: '2026-02-28T14:09:00Z', source: 'gps' },
    { lat: 25.6000, lng: -100.3780, recorded_at: '2026-02-28T14:12:00Z', source: 'gps' },
    { lat: 25.5750, lng: -100.3950, recorded_at: '2026-02-28T14:15:00Z', source: 'gps' },
    { lat: 25.5500, lng: -100.4100, recorded_at: '2026-02-28T14:18:00Z', source: 'gps' },
    { lat: 25.5200, lng: -100.4300, recorded_at: '2026-02-28T14:21:00Z', source: 'gps' },
    // Outlier 1: GPS jump to Cancún (impossible speed)
    { lat: 21.1619, lng: -86.8515, recorded_at: '2026-02-28T14:22:00Z', source: 'gps' },
    { lat: 25.4900, lng: -100.4500, recorded_at: '2026-02-28T14:24:00Z', source: 'gps' },
    { lat: 25.4600, lng: -100.4700, recorded_at: '2026-02-28T14:27:00Z', source: 'gps' },
    { lat: 25.4300, lng: -100.4950, recorded_at: '2026-02-28T14:30:00Z', source: 'gps' },
    { lat: 25.4050, lng: -100.5200, recorded_at: '2026-02-28T14:33:00Z', source: 'gps' },
    { lat: 25.3800, lng: -100.5500, recorded_at: '2026-02-28T14:36:00Z', source: 'gps' },
    { lat: 25.3550, lng: -100.5800, recorded_at: '2026-02-28T14:39:00Z', source: 'gps' },
    { lat: 25.3300, lng: -100.6100, recorded_at: '2026-02-28T14:42:00Z', source: 'gps' },
    // Outlier 2: GPS jump to CDMX (impossible speed)
    { lat: 19.4326, lng: -99.1332, recorded_at: '2026-02-28T14:43:00Z', source: 'gps' },
    { lat: 25.3000, lng: -100.6400, recorded_at: '2026-02-28T14:45:00Z', source: 'gps' },
    { lat: 25.2700, lng: -100.6700, recorded_at: '2026-02-28T14:48:00Z', source: 'gps' },
    { lat: 25.2400, lng: -100.7050, recorded_at: '2026-02-28T14:51:00Z', source: 'gps' },
    { lat: 25.2100, lng: -100.7400, recorded_at: '2026-02-28T14:54:00Z', source: 'gps' },
    { lat: 25.1800, lng: -100.7800, recorded_at: '2026-02-28T14:57:00Z', source: 'gps' },
    { lat: 25.1500, lng: -100.8200, recorded_at: '2026-02-28T15:00:00Z', source: 'gps' },
    { lat: 25.1000, lng: -100.8700, recorded_at: '2026-02-28T15:05:00Z', source: 'gps' },
    { lat: 25.0500, lng: -100.9200, recorded_at: '2026-02-28T15:10:00Z', source: 'gps' },
    { lat: 25.0000, lng: -100.9600, recorded_at: '2026-02-28T15:15:00Z', source: 'gps' },
];

// ── computeRouteStats ──────────────────────────────────────────────────────────

export function computeRouteStats(points: RoutePoint[]): RouteStats {
    if (points.length < 2) {
        return { distanceKm: 0, durationMin: 0, avgSpeedKmh: 0, pointCount: points.length };
    }

    let totalKm = 0;
    for (let i = 1; i < points.length; i++) {
        totalKm += haversineKm(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng);
    }

    const startMs = new Date(points[0].recorded_at).getTime();
    const endMs = new Date(points[points.length - 1].recorded_at).getTime();
    const durationMin = Math.max(1, (endMs - startMs) / 60000);
    const avgSpeedKmh = totalKm / (durationMin / 60);

    return {
        distanceKm: Math.round(totalKm * 10) / 10,
        durationMin: Math.round(durationMin),
        avgSpeedKmh: Math.round(avgSpeedKmh * 10) / 10,
        pointCount: points.length,
    };
}

/** Client-side outlier filter (matches DB logic: speed > 200 km/h = skip) */
export function filterOutliers(points: RoutePoint[]): { clean: RoutePoint[]; removed: number } {
    if (points.length < 2) return { clean: points, removed: 0 };

    const clean: RoutePoint[] = [points[0]];
    let removed = 0;

    for (let i = 1; i < points.length; i++) {
        const prev = clean[clean.length - 1];
        const curr = points[i];
        const distKm = haversineKm(prev.lat, prev.lng, curr.lat, curr.lng);
        const dtHours = Math.max(
            1 / 3600,
            (new Date(curr.recorded_at).getTime() - new Date(prev.recorded_at).getTime()) / 3600000,
        );
        const speedKmh = distKm / dtHours;

        if (speedKmh <= 200) {
            clean.push(curr);
        } else {
            removed++;
        }
    }

    return { clean, removed };
}

// ── Time range helpers ─────────────────────────────────────────────────────────

export function getTimeRangeStart(range: RouteTimeRange): string | undefined {
    if (range === 'all') return undefined;
    const now = new Date();
    if (range === '30m') now.setMinutes(now.getMinutes() - 30);
    if (range === '1h') now.setHours(now.getHours() - 1);
    return now.toISOString();
}

// ── Service ────────────────────────────────────────────────────────────────────

/**
 * Fetch route points for an operation (ERP authenticated view).
 * Sprint A: DB-side outlier filter + downsampling applied.
 */
export async function listRoutePoints(
    operationId: string,
    start?: string,
    end?: string,
    limit = 2000,
): Promise<RoutePoint[]> {
    if (USE_MOCKS) {
        // Simulate client-side filtering for mocks
        let pts = MOCK_ROUTE;
        if (start) {
            const startDate = new Date(start).getTime();
            pts = pts.filter(p => new Date(p.recorded_at).getTime() >= startDate);
        }
        const { clean } = filterOutliers(pts);
        return clean;
    }

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
