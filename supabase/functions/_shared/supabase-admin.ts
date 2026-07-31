import { createClient } from "jsr:@supabase/supabase-js@2";

const MODERN_SECRET_NAME = "trackingedge";
const CONFIGURATION_ERROR = "supabase_admin_configuration_error";

type CredentialSource =
    | "modern_named"
    | "modern_local"
    | "legacy_fallback";

function normalizeSecret(value: unknown): string | undefined {
    if (typeof value !== "string") return undefined;
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : undefined;
}

function isModernSecret(value: string): boolean {
    return value.startsWith("sb_secret_");
}

function isPublishableKey(value: string): boolean {
    return value.startsWith("sb_publishable_");
}

function readNamedModernSecret(): string | undefined {
    const rawSecretMap = normalizeSecret(Deno.env.get("SUPABASE_SECRET_KEYS"));
    if (!rawSecretMap) return undefined;

    try {
        const parsed: unknown = JSON.parse(rawSecretMap);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            return undefined;
        }

        return normalizeSecret(
            (parsed as Record<string, unknown>)[MODERN_SECRET_NAME],
        );
    } catch {
        return undefined;
    }
}

function resolveAdminCredential(): {
    credential: string;
    source: CredentialSource;
} {
    const modernNamed = readNamedModernSecret();
    if (modernNamed && isModernSecret(modernNamed)) {
        return { credential: modernNamed, source: "modern_named" };
    }

    const modernLocal = normalizeSecret(Deno.env.get("SUPABASE_SECRET_KEY"));
    if (modernLocal && isModernSecret(modernLocal)) {
        return { credential: modernLocal, source: "modern_local" };
    }

    const legacyFallback = normalizeSecret(
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    );
    if (legacyFallback && !isPublishableKey(legacyFallback)) {
        return { credential: legacyFallback, source: "legacy_fallback" };
    }

    throw new Error(CONFIGURATION_ERROR);
}

export function createSupabaseAdminClient() {
    const supabaseUrl = normalizeSecret(Deno.env.get("SUPABASE_URL"));
    if (!supabaseUrl) {
        throw new Error(CONFIGURATION_ERROR);
    }

    const { credential, source } = resolveAdminCredential();
    console.info(`[supabase-admin] credential_source=${source}`);

    return createClient(supabaseUrl, credential, {
        auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
        },
    });
}
