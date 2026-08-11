/**
 * trackingEdge.service.ts
 *
 * Servicio frontend para consumir las Edge Functions del módulo Tracking.
 * NUNCA hace llamadas a RPC directamente — siempre pasa por Edge Function.
 *
 * Endpoints:
 *   GET  {BASE}/track-public?token=...   → rpc_get_public_tracking (via Edge)
 *   GET  {BASE}/driver-view?token=...    → rpc_get_driver_view     (via Edge)
 *   POST {BASE}/track-driver             → rpc_post_driver_event   (via Edge)
 *
 * NL-E1: El token literal se envía en query/body al Edge, nunca se loguea aquí.
 * NL-E3: Los errores HTTP del Edge se mapean genéricamente; nunca se expone stack.
 */

import type {
    PublicTrackingResponse,
    DriverTrackingResponse,
    DriverEventPayload,
} from '@/types/tracking';
import { supabaseUrl } from '@/lib/supabase';

// ── Config ────────────────────────────────────────────────────────────────────

const BASE_URL = `${supabaseUrl}/functions/v1`;

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

/** Network timeout (ms). Edge Functions cold-start can be ~2s. */
const TIMEOUT_MS = 12_000;

// ── Typed result wrappers ─────────────────────────────────────────────────────

export type EdgeResult<T> =
    | { ok: true; data: T }
    | { ok: false; error: 'network_error' | 'timeout' | 'server_error' };

// ── Internal helpers ──────────────────────────────────────────────────────────

/**
 * Fetch with AbortController timeout.
 * Throws `DOMException` (AbortError) on timeout.
 */
async function fetchWithTimeout(
    url: string,
    options: RequestInit = {},
    timeoutMs = TIMEOUT_MS,
): Promise<Response> {
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), timeoutMs);
    try {
        return await fetch(url, { ...options, signal: controller.signal });
    } finally {
        clearTimeout(id);
    }
}

function isTimeout(err: unknown): boolean {
    return err instanceof DOMException && err.name === 'AbortError';
}

// ── Mock fallback (only when VITE_USE_MOCKS=true) ─────────────────────────────

async function getMockPublicFallback(token: string): Promise<PublicTrackingResponse> {
    const { getMockPublicTracking } = await import('@/mocks/tracking.mock');
    return getMockPublicTracking(token);
}

async function getMockDriverFallback(token: string): Promise<DriverTrackingResponse> {
    const { getMockDriverView } = await import('@/mocks/tracking.mock');
    return getMockDriverView(token);
}

async function postMockDriverFallback(
    body: DriverEventPayload,
): Promise<DriverEventPostResult> {
    const { postMockDriverEvent } = await import('@/mocks/tracking.mock');
    const res = await postMockDriverEvent(body);
    return { http: 200, accepted: res.accepted, reason: res.reason };
}

// ── Public types exported ─────────────────────────────────────────────────────

/** Response shape from POST track-driver (mirrors RPC output). */
export interface DriverEventPostResult {
    http: number;
    accepted: boolean;
    reason?: string;
    eventId?: string;
}

// ── Service functions ─────────────────────────────────────────────────────────

/**
 * GET public tracking view for a given publicToken.
 *
 * Returns:
 *  - `{ status: 'success', data: PublicTrackingView, expired: false }` on live token
 *  - `{ status: 'soft_expired', data: ..., expired: true }` on soft-expired
 *  - `{ status: 'not_found' }` on 404
 *  - `{ status: 'revoked' }` on 403
 *  - `{ status: 'hard_expired' }` on 410
 *
 * Falls back to mock if VITE_USE_MOCKS=true and fetch fails.
 */
export async function fetchPublicTracking(
    token: string,
): Promise<EdgeResult<PublicTrackingResponse>> {
    if (USE_MOCKS) {
        const data = await getMockPublicFallback(token);
        return { ok: true, data };
    }

    try {
        const res = await fetchWithTimeout(
            `${BASE_URL}/track-public?token=${encodeURIComponent(token)}`,
        );

        // Parse JSON regardless of HTTP status (Edge always returns JSON body)
        let body: PublicTrackingResponse;
        try {
            body = await res.json();
        } catch {
            return { ok: false, error: 'server_error' };
        }

        // Map HTTP 403/404/410 to body.status if needed (Edge already sets status field)
        if (res.status === 403 && !body.status) {
            body = { status: 'revoked' } as PublicTrackingResponse;
        }
        if (res.status === 410) {
            body = { status: 'hard_expired' } as PublicTrackingResponse;
        }
        if (res.status >= 500) {
            return { ok: false, error: 'server_error' };
        }

        return { ok: true, data: body };
    } catch (err) {
        if (isTimeout(err)) return { ok: false, error: 'timeout' };

        // Network error — try mock fallback if enabled
        if (USE_MOCKS) {
            const data = await getMockPublicFallback(token);
            return { ok: true, data };
        }
        return { ok: false, error: 'network_error' };
    }
}

/**
 * GET driver view for a given driverToken.
 * Falls back to mock if VITE_USE_MOCKS=true and fetch fails.
 */
export async function fetchDriverView(
    token: string,
): Promise<EdgeResult<DriverTrackingResponse>> {
    if (USE_MOCKS) {
        const data = await getMockDriverFallback(token);
        return { ok: true, data };
    }

    try {
        const res = await fetchWithTimeout(
            `${BASE_URL}/driver-view?token=${encodeURIComponent(token)}`,
        );

        let body: DriverTrackingResponse;
        try {
            body = await res.json();
        } catch {
            return { ok: false, error: 'server_error' };
        }

        if (res.status === 403) {
            // revoked or expired — Edge sends { status: 'revoked' } or { status: 'expired' }
            return { ok: true, data: body };
        }
        if (res.status >= 500) {
            return { ok: false, error: 'server_error' };
        }

        return { ok: true, data: body };
    } catch (err) {
        if (isTimeout(err)) return { ok: false, error: 'timeout' };

        if (USE_MOCKS) {
            const data = await getMockDriverFallback(token);
            return { ok: true, data };
        }
        return { ok: false, error: 'network_error' };
    }
}

/**
 * POST a driver event to the track-driver Edge Function.
 *
 * Returns:
 *  - `{ ok: true, data: { http, accepted, reason?, eventId? } }` on any valid response
 *  - `{ ok: false, error: 'network_error' | 'timeout' | 'server_error' }` on failure
 *
 * Falls back to mock if VITE_USE_MOCKS=true and fetch fails.
 */
export async function postDriverEvent(
    body: DriverEventPayload,
): Promise<EdgeResult<DriverEventPostResult>> {
    if (USE_MOCKS) {
        const data = await postMockDriverFallback(body);
        return { ok: true, data };
    }

    try {
        const res = await fetchWithTimeout(
            `${BASE_URL}/track-driver`,
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            },
        );

        let data: DriverEventPostResult;
        try {
            data = await res.json();
        } catch {
            return { ok: false, error: 'server_error' };
        }

        if (res.status >= 500) return { ok: false, error: 'server_error' };

        // 403 can mean revoked/expired token — let caller handle via data.http
        return { ok: true, data: { ...data, http: res.status } };
    } catch (err) {
        if (isTimeout(err)) return { ok: false, error: 'timeout' };

        if (USE_MOCKS) {
            const data = await postMockDriverFallback(body);
            return { ok: true, data };
        }
        return { ok: false, error: 'network_error' };
    }
}
