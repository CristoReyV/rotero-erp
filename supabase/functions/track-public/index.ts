/**
 * track-public — GET /functions/v1/track-public?token=xxx
 *
 * Returns PublicTrackingView sanitized by rpc_get_public_tracking.
 * Best-effort access logging; failures do not block the main response.
 *
 * NL-18: X-Robots-Tag: noindex, nofollow
 * NL-19: CORS restricted to whitelisted origins
 * NL-E1: Token literal NEVER in logs
 * NL-E3: SQL errors NEVER exposed to client
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { getCorsHeaders, handlePreflight } from "../_shared/cors.ts";
import { CACHE } from "../_shared/security-headers.ts";
import { checkRateLimit, LIMITS } from "../_shared/rate-limit.ts";
import { jsonResponse, errorResponse, sha256 } from "../_shared/response.ts";
import { createSupabaseAdminClient } from "../_shared/supabase-admin.ts";
import { isTrackingCredentialError } from "../_shared/tracking-credential.ts";

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
        // NL-E7: Same response as token not found
        return errorResponse(404, "not_found", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Rate limiting ──
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
    const tokenPrefix = token.substring(0, 8);

    if (!checkRateLimit(`pub:${ip}`, LIMITS.PUBLIC_IP.max, LIMITS.PUBLIC_IP.windowMs)) {
        return errorResponse(429, "rate_limited", {
            ...corsHeaders,
            "Retry-After": "60",
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    if (!checkRateLimit(`pub:${tokenPrefix}`, LIMITS.PUBLIC_TOKEN.max, LIMITS.PUBLIC_TOKEN.windowMs)) {
        return errorResponse(429, "rate_limited", {
            ...corsHeaders,
            "Retry-After": "60",
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Call RPC with server-side admin client ──
    let supabase: ReturnType<typeof createSupabaseAdminClient>;
    try {
        supabase = createSupabaseAdminClient();
    } catch (error) {
        if (!isTrackingCredentialError(error)) {
            console.error("[track-public] Admin client initialization error");
            return errorResponse(500, "internal_error", {
                ...corsHeaders,
                "Cache-Control": CACHE.NO_STORE,
            });
        }
        console.error("[track-public] Tracking credential unavailable");
        return errorResponse(503, "tracking_service_unavailable", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    const { data, error } = await supabase.rpc("rpc_get_public_tracking", {
        p_token: token,
    });

    if (error) {
        // NL-E3: Never expose SQL error to client
        console.error("[track-public] RPC error");
        return errorResponse(500, "internal_error", {
            ...corsHeaders,
            "Cache-Control": CACHE.NO_STORE,
        });
    }

    // ── Map RPC status → HTTP code + Cache-Control ──
    const status = data?.status as string;

    const httpCode: Record<string, number> = {
        success: 200,
        soft_expired: 200,
        not_found: 404,
        revoked: 403,
        hard_expired: 410,
    };

    const cacheControl: Record<string, string> = {
        success: CACHE.PUBLIC_OK,
        soft_expired: CACHE.PUBLIC_EXPIRED,
        not_found: CACHE.NO_STORE,
        revoked: CACHE.NO_STORE,
        hard_expired: CACHE.NO_STORE,
    };

    const code = httpCode[status] || 404;
    const cache = cacheControl[status] || CACHE.NO_STORE;

    // ── Log access ──
    // Must await because Supabase JS client is lazy (no-op without await).
    // Edge runtime terminates after handler returns, so fire-and-forget won't execute.
    const dateStr = new Date().toISOString().slice(0, 10);
    const [tokenHash, ipHash] = await Promise.all([
        sha256(token),
        sha256(ip + dateStr),
    ]);

    // NL-E1: token literal NEVER in the insert — only hash
    // Use Promise.allSettled so a log failure never blocks the response
    await Promise.allSettled([
        supabase.from("tracking_access_log").insert({
            token_hash: tokenHash,
            ip_hash: ipHash,
            user_agent: (req.headers.get("user-agent") || "").substring(0, 200),
            country_code: req.headers.get("cf-ipcountry") || null,
        }),
    ]);

    // ── Return response ──
    return jsonResponse(code, data, {
        ...corsHeaders,
        "Cache-Control": cache,
    });
});
