/**
 * driver-view — GET /functions/v1/driver-view?token=xxx
 *
 * Returns sanitized DriverView for the driver's mini-web.
 * No access logging (last_used_at is updated by the RPC itself).
 *
 * NL-E1: Token literal NEVER in logs
 * Cache-Control: no-store (real-time driver data)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { getCorsHeaders, handlePreflight } from "../_shared/cors.ts";
import { CACHE } from "../_shared/security-headers.ts";
import { checkRateLimit, LIMITS } from "../_shared/rate-limit.ts";
import { jsonResponse, errorResponse } from "../_shared/response.ts";
import { createSupabaseAdminClient } from "../_shared/supabase-admin.ts";

Deno.serve(async (req: Request) => {
    // ── CORS preflight ──
    if (req.method === "OPTIONS") {
        return handlePreflight(req);
    }

    const corsHeaders = getCorsHeaders(req);

    if (req.method !== "GET") {
        return errorResponse(405, "method_not_allowed", corsHeaders);
    }

    // ── Extract token ──
    const url = new URL(req.url);
    const token = url.searchParams.get("token");

    if (!token || token.length < 30) {
        return errorResponse(404, "not_found", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Rate limiting (same as public: 60 req/min per IP) ──
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";

    if (!checkRateLimit(`drv-view:${ip}`, LIMITS.PUBLIC_IP.max, LIMITS.PUBLIC_IP.windowMs)) {
        return errorResponse(429, "rate_limited", {
            ...corsHeaders,
            "Retry-After": "60",
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Call RPC ──
    let supabase: ReturnType<typeof createSupabaseAdminClient>;
    try {
        supabase = createSupabaseAdminClient();
    } catch {
        console.error("[driver-view] Admin client configuration error");
        return errorResponse(500, "internal_error", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    const { data, error } = await supabase.rpc("rpc_get_driver_view", {
        p_token: token,
    });

    if (error) {
        console.error("[driver-view] RPC error:", error.message);
        return errorResponse(500, "internal_error", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Map status → HTTP code ──
    const status = (data as { status?: string })?.status;
    const httpCode =
        status === "success" ? 200 :
            status === "revoked" ? 403 :
                status === "expired" ? 403 : 404;

    return jsonResponse(httpCode, data, {
        ...corsHeaders,
        "Cache-Control": CACHE.NO_STORE, // Driver data is real-time, never cache
    });
});
