/**
 * CORS — Tracking Edge Functions
 * NL-19: Restrictive CORS for tracking API endpoints.
 *
 * Dynamic origin validation: only whitelisted origins receive
 * Access-Control-Allow-Origin. All others get no CORS header,
 * which causes the browser to block the response natively.
 */

const ALLOWED_ORIGINS: readonly string[] = [
    // Production
    "https://erp.rotero.mx",
    "https://tracking.rotero.mx",
    "https://roterowlsbeta.netlify.app",
    // Staging
    "https://staging.rotero.mx",
    // Development
    "http://localhost:3000",
    "http://localhost:5173",
];

/**
 * Returns CORS headers for a given request.
 * If the request's Origin is not in the whitelist, `Access-Control-Allow-Origin`
 * is omitted — the browser will block the response by default.
 */
export function getCorsHeaders(req: Request): Record<string, string> {
    const origin = req.headers.get("origin") || "";
    const headers: Record<string, string> = {
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "content-type, x-client-info",
        "Access-Control-Max-Age": "86400",
        "Vary": "Origin",
    };

    if (ALLOWED_ORIGINS.includes(origin)) {
        headers["Access-Control-Allow-Origin"] = origin;
    }

    return headers;
}

/**
 * Handles CORS preflight (OPTIONS) requests.
 * Returns 204 No Content with CORS headers.
 */
export function handlePreflight(req: Request): Response {
    return new Response(null, {
        status: 204,
        headers: getCorsHeaders(req),
    });
}
