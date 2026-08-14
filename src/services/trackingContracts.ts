export type TrackingRole = 'admin' | 'operator' | 'finance' | 'viewer' | null;

export type TrackingScope = 'public:read' | 'driver:write';
export type TrackingDisplayState = 'active' | 'revoked' | 'expired';
export type TrackingFilter = 'all' | TrackingDisplayState | 'public' | 'driver';

export interface TrackingTokenMetadata {
    id: string;
    operationId: string;
    scope: TrackingScope;
    state: string;
    createdAt: string;
    expiresAt: string | null;
    lastUsedAt: string | null;
    referenceCode: string | null;
    routeSummary: string | null;
    clientDisplayName: string | null;
    operationStatus: string | null;
    lastMunicipality: string | null;
    lastEventAt: string | null;
}

export interface CreatedTrackingToken {
    kind: 'created';
    tokenId: string;
    token: string;
    scope: TrackingScope;
    expiresAt: string;
    rotatedPrevious: boolean;
}

export interface ExistingTrackingToken {
    kind: 'existing';
    tokenId: string;
    scope: TrackingScope;
    expiresAt: string | null;
}

export type TrackingCreateResult = CreatedTrackingToken | ExistingTrackingToken;
export type OneTimeTrackingAction = 'create' | 'rotate' | 'revoke';

export interface RevokeTrackingTokenResult {
    success: boolean;
    status: 'revoked' | 'already_revoked' | 'not_found' | 'forbidden' | 'rotated' | 'invalid_state';
}

export interface OneTimeTrackingLink {
    tokenId: string;
    scope: TrackingScope;
    link: string;
    expiresAt: string;
    rotatedPrevious: boolean;
}

const TRACKING_STATES = new Set(['active', 'revoked', 'rotated', 'soft_expired', 'hard_expired', 'expired']);

export const TRACKING_SCOPE_OPTIONS: ReadonlyArray<{
    value: TrackingScope;
    label: string;
    defaultTtlHours: number;
    maxTtlHours: number;
}> = [
    { value: 'public:read', label: 'Seguimiento público', defaultTtlHours: 168, maxTtlHours: 720 },
    { value: 'driver:write', label: 'Operador / chofer', defaultTtlHours: 48, maxTtlHours: 72 },
];

export function canManageTracking(role: TrackingRole): boolean {
    return role === 'admin' || role === 'operator';
}

export function getScopeConfig(scope: TrackingScope) {
    return TRACKING_SCOPE_OPTIONS.find((option) => option.value === scope) ?? TRACKING_SCOPE_OPTIONS[0];
}

function nullableString(value: unknown): string | null {
    return typeof value === 'string' && value.trim() ? value : null;
}

function requiredString(value: unknown, field: string): string {
    if (typeof value !== 'string' || !value.trim()) {
        throw new Error(`invalid_${field}`);
    }
    return value;
}

function isTrackingScope(value: unknown): value is TrackingScope {
    return value === 'public:read' || value === 'driver:write';
}

export function normalizeTrackingList(payload: unknown): TrackingTokenMetadata[] {
    if (!Array.isArray(payload)) {
        throw new Error('invalid_tracking_list');
    }

    return payload.map((item) => {
        if (!item || typeof item !== 'object') throw new Error('invalid_tracking_item');
        const raw = item as Record<string, unknown>;
        const scope = raw.scope;
        const state = requiredString(raw.state, 'state');

        if (!isTrackingScope(scope) || !TRACKING_STATES.has(state)) {
            throw new Error('invalid_tracking_contract');
        }

        return {
            id: requiredString(raw.id, 'id'),
            operationId: requiredString(raw.operation_id, 'operation_id'),
            scope,
            state,
            createdAt: requiredString(raw.created_at, 'created_at'),
            expiresAt: nullableString(raw.expires_at),
            lastUsedAt: nullableString(raw.last_used_at),
            referenceCode: nullableString(raw.reference_code),
            routeSummary: nullableString(raw.route_summary),
            clientDisplayName: nullableString(raw.client_display_name),
            operationStatus: nullableString(raw.operation_status),
            lastMunicipality: nullableString(raw.last_municipality),
            lastEventAt: nullableString(raw.last_event_at),
        };
    });
}

export function normalizeCreateResult(payload: unknown): TrackingCreateResult {
    if (!payload || typeof payload !== 'object') throw new Error('invalid_create_result');
    const raw = payload as Record<string, unknown>;
    const scope = raw.scope;

    if (!isTrackingScope(scope)) throw new Error('invalid_create_result');

    const tokenId = requiredString(raw.token_id, 'token_id');
    const expiresAt = nullableString(raw.expires_at);

    if (raw.already_existed === true) {
        return { kind: 'existing', tokenId, scope, expiresAt };
    }

    const token = requiredString(raw.token, 'token');
    if (!expiresAt) throw new Error('invalid_create_result');

    return {
        kind: 'created',
        tokenId,
        token,
        scope,
        expiresAt,
        rotatedPrevious: raw.rotated_previous === true,
    };
}

export function normalizeRevokeResult(payload: unknown): RevokeTrackingTokenResult {
    if (!payload || typeof payload !== 'object') throw new Error('invalid_revoke_result');
    const raw = payload as Record<string, unknown>;
    const status = raw.status;

    if (!['revoked', 'already_revoked', 'not_found', 'forbidden', 'rotated'].includes(status as string)) {
        throw new Error('invalid_revoke_result');
    }

    return {
        success: raw.success === true,
        status: status as RevokeTrackingTokenResult['status'],
    };
}

export function getTrackingDisplayState(
    token: Pick<TrackingTokenMetadata, 'state' | 'expiresAt'>,
    now = new Date(),
): TrackingDisplayState {
    if (token.state === 'revoked' || token.state === 'rotated') return 'revoked';
    if (token.state !== 'active') return 'expired';
    if (token.expiresAt && new Date(token.expiresAt).getTime() <= now.getTime()) return 'expired';
    return 'active';
}

export function filterTrackingTokens(
    tokens: TrackingTokenMetadata[],
    query: string,
    filter: TrackingFilter,
    now = new Date(),
): TrackingTokenMetadata[] {
    const normalizedQuery = query.trim().toLocaleLowerCase('es');

    return tokens.filter((token) => {
        const displayState = getTrackingDisplayState(token, now);
        const matchesFilter = filter === 'all'
            || filter === displayState
            || (filter === 'public' && token.scope === 'public:read')
            || (filter === 'driver' && token.scope === 'driver:write');

        if (!matchesFilter) return false;
        if (!normalizedQuery) return true;

        return [
            token.referenceCode,
            token.operationId,
            token.scope,
            token.state,
            token.routeSummary,
            token.clientDisplayName,
        ].some((value) => value?.toLocaleLowerCase('es').includes(normalizedQuery));
    });
}

export function resolvePublicAppBaseUrl(
    configuredBaseUrl: string | undefined,
    fallbackOrigin: string,
): string {
    const selectedBaseUrl = configuredBaseUrl?.trim() || fallbackOrigin.trim();
    let parsed: URL;

    try {
        parsed = new URL(selectedBaseUrl);
    } catch {
        throw new Error('invalid_public_app_base_url');
    }

    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
        throw new Error('invalid_public_app_base_url');
    }

    return selectedBaseUrl.replace(/\/+$/, '');
}

export function buildTrackingUrl(baseUrl: string, scope: TrackingScope, token: string): string {
    const normalizedBaseUrl = baseUrl.replace(/\/+$/, '');
    const path = scope === 'driver:write' ? '/driver/' : '/t/';
    return `${normalizedBaseUrl}${path}${encodeURIComponent(token)}`;
}

export function createOneTimeTrackingLink(
    result: TrackingCreateResult,
    baseUrl: string,
): OneTimeTrackingLink | null {
    if (result.kind !== 'created') return null;

    return {
        tokenId: result.tokenId,
        scope: result.scope,
        link: buildTrackingUrl(baseUrl, result.scope, result.token),
        expiresAt: result.expiresAt,
        rotatedPrevious: result.rotatedPrevious,
    };
}

export function resolveOneTimeTrackingLinkForAction(
    action: OneTimeTrackingAction,
    result: TrackingCreateResult | null,
    baseUrl: string,
): OneTimeTrackingLink | null {
    if (action === 'revoke' || !result) return null;
    return createOneTimeTrackingLink(result, baseUrl);
}

export function getOneTimeCapabilityUrl(link: OneTimeTrackingLink | null): string | null {
    return link?.link ?? null;
}

export function clearOneTimeTrackingLink(): null {
    return null;
}
