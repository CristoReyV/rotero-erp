/**
 * Security Headers — Tracking Edge Functions
 * NL-18: X-Robots-Tag noindex
 * NL-19: Full security header set
 *
 * These headers are applied to EVERY tracking response.
 */

/** Headers applied to all tracking API responses. */
export const SECURITY_HEADERS: Record<string, string> = {
    "X-Robots-Tag": "noindex, nofollow",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
    "Permissions-Policy": "geolocation=(), camera=(), microphone=()",
};

/** Cache-Control presets by response type. */
export const CACHE = {
    /** Public tracking view — 60s + stale-while-revalidate (absorb WhatsApp bursts) */
    PUBLIC_OK: "public, max-age=60, stale-while-revalidate=30",
    /** Soft-expired data — longer cache, data won't change */
    PUBLIC_EXPIRED: "public, max-age=300",
    /** Errors — never cache */
    NO_STORE: "no-store",
} as const;
