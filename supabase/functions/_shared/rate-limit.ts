/**
 * Rate Limiting — In-memory sliding window
 *
 * Best-effort rate limiting for Supabase Edge Functions.
 * Each cold start resets the Map. For production scale,
 * migrate to Upstash Redis (@upstash/ratelimit).
 *
 * Limits aligned with TRACKING_TOKEN_SECURITY_DESIGN.md §4.1:
 * - public GET by IP:           60 req / 1 min
 * - public GET by token prefix: 120 req / 1 min
 * - driver POST by IP:          20 req / 1 hour
 */

const windows = new Map<string, number[]>();

const MAX_ENTRIES = 10_000;

/**
 * Check if a request is within the rate limit.
 * @param key   Unique key for the rate limit bucket (e.g. `pub:${ip}`)
 * @param max   Maximum number of requests allowed in the window
 * @param windowMs Window duration in milliseconds
 * @returns `true` if allowed, `false` if rate limited
 */
export function checkRateLimit(
    key: string,
    max: number,
    windowMs: number,
): boolean {
    const now = Date.now();
    const timestamps = windows.get(key) || [];

    // Remove expired entries
    const valid = timestamps.filter((t) => now - t < windowMs);

    if (valid.length >= max) {
        windows.set(key, valid);
        return false;
    }

    valid.push(now);
    windows.set(key, valid);

    // Prevent memory leak: cleanup stale keys
    if (windows.size > MAX_ENTRIES) {
        for (const [k, v] of windows) {
            if (v.length === 0 || now - v[v.length - 1] > windowMs * 2) {
                windows.delete(k);
            }
        }
    }

    return true;
}

/** Pre-defined limit configurations. */
export const LIMITS = {
    PUBLIC_IP: { max: 60, windowMs: 60_000 },       // 60 req/min
    PUBLIC_TOKEN: { max: 120, windowMs: 60_000 },       // 120 req/min
    DRIVER_IP: { max: 20, windowMs: 3_600_000 },     // 20 req/hour
} as const;
