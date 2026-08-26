const TRACKING_SECRET_NAME = "trackingedge";

export const TRACKING_CREDENTIAL_ERROR = "tracking_credential_unavailable";

export type TrackingCredentialSource = "trackingedge";

export type EnvironmentReader = (name: string) => string | undefined;

export class TrackingCredentialError extends Error {
    constructor() {
        super(TRACKING_CREDENTIAL_ERROR);
        this.name = "TrackingCredentialError";
    }
}

function normalizeSecret(value: unknown): string | undefined {
    if (typeof value !== "string") return undefined;
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : undefined;
}

function isValidSecretKey(value: string): boolean {
    return value.startsWith("sb_secret_") &&
        value.length >= 24 &&
        !/\s/.test(value);
}

export function resolveTrackingCredential(
    readEnvironment: EnvironmentReader,
): { credential: string; source: TrackingCredentialSource } {
    const rawSecretMap = normalizeSecret(
        readEnvironment("SUPABASE_SECRET_KEYS"),
    );

    if (rawSecretMap) {
        try {
            const parsed: unknown = JSON.parse(rawSecretMap);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
                const credential = normalizeSecret(
                    (parsed as Record<string, unknown>)[TRACKING_SECRET_NAME],
                );
                if (credential && isValidSecretKey(credential)) {
                    return { credential, source: TRACKING_SECRET_NAME };
                }
            }
        } catch {
            // Invalid secret metadata is treated exactly like a missing credential.
        }
    }

    throw new TrackingCredentialError();
}

export function isTrackingCredentialError(
    error: unknown,
): error is TrackingCredentialError {
    return error instanceof TrackingCredentialError ||
        (error instanceof Error && error.message === TRACKING_CREDENTIAL_ERROR);
}
