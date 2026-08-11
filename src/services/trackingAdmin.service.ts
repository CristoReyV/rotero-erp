import { supabase } from '@/lib/supabase';
import {
    normalizeCreateResult,
    normalizeRevokeResult,
    normalizeTrackingList,
    type RevokeTrackingTokenResult,
    type TrackingCreateResult,
    type TrackingScope,
    type TrackingTokenMetadata,
} from '@/services/trackingContracts';

export type TrackingServiceErrorCode =
    | 'unauthorized'
    | 'invalid_scope'
    | 'invalid_ttl'
    | 'ttl_exceeds_max'
    | 'not_found'
    | 'forbidden'
    | 'conflict'
    | 'internal_error'
    | 'invalid_response';

export class TrackingServiceError extends Error {
    constructor(public readonly code: TrackingServiceErrorCode) {
        super(code);
        this.name = 'TrackingServiceError';
    }
}

function asServiceCode(value: unknown): TrackingServiceErrorCode {
    const known: TrackingServiceErrorCode[] = [
        'unauthorized',
        'invalid_scope',
        'invalid_ttl',
        'ttl_exceeds_max',
        'not_found',
        'forbidden',
        'conflict',
        'internal_error',
    ];
    return typeof value === 'string' && known.includes(value as TrackingServiceErrorCode)
        ? value as TrackingServiceErrorCode
        : 'invalid_response';
}

export function getTrackingErrorMessage(error: unknown): string {
    const code = error instanceof TrackingServiceError ? error.code : 'invalid_response';
    const messages: Record<TrackingServiceErrorCode, string> = {
        unauthorized: 'No tienes permiso para realizar esta acción.',
        invalid_scope: 'El tipo de enlace no es válido.',
        invalid_ttl: 'La vigencia debe ser mayor a cero.',
        ttl_exceeds_max: 'La vigencia supera el máximo permitido.',
        not_found: 'La operación o el enlace ya no está disponible.',
        forbidden: 'La operación no pertenece al tenant activo.',
        conflict: 'Otro usuario actualizó este enlace. Recarga e intenta nuevamente.',
        internal_error: 'No fue posible completar la acción.',
        invalid_response: 'No fue posible obtener una respuesta válida de Tracking.',
    };
    return messages[code];
}

export async function listTrackingTokens(tenantId: string): Promise<TrackingTokenMetadata[]> {
    const { data, error } = await supabase.rpc('rpc_list_tracking_tokens', {
        p_tenant_id: tenantId,
    });

    if (error) throw new TrackingServiceError('invalid_response');
    if (data && !Array.isArray(data) && typeof data === 'object' && 'error' in data) {
        throw new TrackingServiceError(asServiceCode(data.error));
    }

    try {
        return normalizeTrackingList(data ?? []);
    } catch {
        throw new TrackingServiceError('invalid_response');
    }
}

export interface CreateTrackingTokenInput {
    tenantId: string;
    operationId: string;
    scope: TrackingScope;
    ttlHours: number | null;
    forceRotate: boolean;
}

export async function createTrackingToken(input: CreateTrackingTokenInput): Promise<TrackingCreateResult> {
    const { data, error } = await supabase.rpc('rpc_create_tracking_token', {
        p_tenant_id: input.tenantId,
        p_operation_id: input.operationId,
        p_scope: input.scope,
        p_ttl_hours: input.ttlHours,
        p_force_rotate: input.forceRotate,
    });

    if (error) throw new TrackingServiceError('invalid_response');
    if (data?.error) throw new TrackingServiceError(asServiceCode(data.error));

    try {
        return normalizeCreateResult(data);
    } catch {
        throw new TrackingServiceError('invalid_response');
    }
}

export async function revokeTrackingToken(tokenId: string): Promise<RevokeTrackingTokenResult> {
    const { data, error } = await supabase.rpc('rpc_revoke_tracking_token', {
        p_token_id: tokenId,
    });

    if (error || !data || typeof data !== 'object') {
        throw new TrackingServiceError('invalid_response');
    }

    if (data.status === 'internal_error') throw new TrackingServiceError('internal_error');

    try {
        return normalizeRevokeResult(data);
    } catch {
        throw new TrackingServiceError('invalid_response');
    }
}
