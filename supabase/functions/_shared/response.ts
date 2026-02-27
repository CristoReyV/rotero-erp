/**
 * Response helpers — Tracking Edge Functions
 *
 * Merges CORS + Security headers into every response.
 * Ensures consistent JSON format across all endpoints.
 */

import { SECURITY_HEADERS } from "./security-headers.ts";

/**
 * Build a JSON response with security + CORS headers merged.
 */
export function jsonResponse(
    status: number,
    body: unknown,
    extraHeaders: Record<string, string> = {},
): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: {
            "Content-Type": "application/json",
            ...SECURITY_HEADERS,
            ...extraHeaders,
        },
    });
}

/**
 * Build an error JSON response.
 * NL-E7: Generic format, never exposes internals.
 */
export function errorResponse(
    status: number,
    reason: string,
    extraHeaders: Record<string, string> = {},
): Response {
    return jsonResponse(status, { status: reason }, extraHeaders);
}

/**
 * Compute SHA-256 hex hash of a string.
 * Used for token hashing and IP hashing (with daily salt).
 */
export async function sha256(input: string): Promise<string> {
    const data = new TextEncoder().encode(input);
    const hash = await crypto.subtle.digest("SHA-256", data);
    return Array.from(new Uint8Array(hash))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
}
