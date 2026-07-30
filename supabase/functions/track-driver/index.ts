/**
 * track-driver — POST /functions/v1/track-driver
 *
 * Driver posts a tracking event. Delegates all validation to
 * rpc_post_driver_event (idempotency, cooldown, singletons, anomaly, etc.)
 *
 * NL-E1: Token literal NEVER in logs
 * NL-E5: Request body NEVER logged in full
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { getCorsHeaders, handlePreflight } from "../_shared/cors.ts";
import { CACHE } from "../_shared/security-headers.ts";
import { checkRateLimit, LIMITS } from "../_shared/rate-limit.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createSupabaseAdminClient } from "../_shared/supabase-admin.ts";

const VALID_ACTIONS = new Set([
    "departure",
    "in_transit",
    "arrival",
    "delivered",
    "incident",
]);

Deno.serve(async (req: Request) => {
    // ── CORS preflight ──
    if (req.method === "OPTIONS") {
        return handlePreflight(req);
    }

    const corsHeaders = getCorsHeaders(req);

    if (req.method !== "POST") {
        return errorResponse(405, "method_not_allowed", corsHeaders);
    }

    // ── Parse body ──
    let body: Record<string, unknown>;
    try {
        body = await req.json();
    } catch {
        return errorResponse(400, "invalid_request", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    const {
        driverToken,
        action,
        location,
        manualPlace,
        incident,
        clientTimestamp,
        offlineQueued,
    } = body as {
        driverToken?: string;
        action?: string;
        location?: { lat?: number; lng?: number; accuracy?: number; source?: string };
        manualPlace?: { municipality?: string; state?: string };
        incident?: { type?: string; note?: string };
        clientTimestamp?: string;
        offlineQueued?: boolean;
    };

    // ── Input validation ──
    if (!driverToken || !action || !clientTimestamp) {
        return errorResponse(400, "missing_fields", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    if (!VALID_ACTIONS.has(action)) {
        return errorResponse(400, "invalid_action", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    if (driverToken.length < 30) {
        // NL-E7: Same as not_found
        return errorResponse(404, "not_found", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Rate limiting (20 req/hour for driver writes) ──
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";

    if (!checkRateLimit(`drv:${ip}`, LIMITS.DRIVER_IP.max, LIMITS.DRIVER_IP.windowMs)) {
        return errorResponse(429, "rate_limited", {
            ...corsHeaders,
            "Retry-After": "300",
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Resolve location fields ──
    const source = location?.source || "none";
    const lat = source === "gps" ? (location?.lat ?? null) : null;
    const lng = source === "gps" ? (location?.lng ?? null) : null;
    const accuracy = source === "gps" ? (location?.accuracy ?? null) : null;
    const municipality = manualPlace?.municipality || null;
    const stateName = manualPlace?.state || null;

    // ── Call RPC ──
    let supabase: ReturnType<typeof createSupabaseAdminClient>;
    try {
        supabase = createSupabaseAdminClient();
    } catch {
        console.error("[track-driver] Admin client configuration error");
        return errorResponse(500, "internal_error", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    const { data, error } = await supabase.rpc("rpc_post_driver_event", {
        p_token: driverToken,
        p_action: action,
        p_source: source,
        p_lat: lat,
        p_lng: lng,
        p_accuracy: accuracy,
        p_municipality: municipality,
        p_state_name: stateName,
        p_country_code: "MX",
        p_incident_type: action === "incident" ? (incident?.type || null) : null,
        p_incident_note: action === "incident" ? (incident?.note || null) : null,
        p_client_timestamp: clientTimestamp,
        p_offline_queued: offlineQueued || false,
    });

    if (error) {
        // NL-E3: Never expose SQL error. NL-E1: never log token material.
        console.error("[track-driver] RPC error:", error.message);
        return errorResponse(500, "internal_error", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── The RPC returns {http, accepted, reason?, eventId?, ...} ──
    const httpCode = (data as { http?: number })?.http || 500;

    return jsonResponse(httpCode, data, {
        ...corsHeaders,
        "Cache-Control": CACHE.NO_STORE,
    });
});
