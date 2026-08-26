import { createClient } from "jsr:@supabase/supabase-js@2";
import {
    resolveTrackingCredential,
    TrackingCredentialError,
} from "./tracking-credential.ts";

function normalizeSecret(value: unknown): string | undefined {
    if (typeof value !== "string") return undefined;
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : undefined;
}

export function createSupabaseAdminClient() {
    const supabaseUrl = normalizeSecret(Deno.env.get("SUPABASE_URL"));
    if (!supabaseUrl) {
        throw new TrackingCredentialError();
    }

    const { credential } = resolveTrackingCredential((name) =>
        Deno.env.get(name)
    );

    return createClient(supabaseUrl, credential, {
        auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
        },
    });
}
