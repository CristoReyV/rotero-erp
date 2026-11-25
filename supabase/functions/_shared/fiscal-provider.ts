/**
 * Provider-neutral fiscal boundary for a future authenticated Edge orchestrator.
 * Canonical FISCAL.0 input stays provider-neutral. The server registry binds only
 * explicitly configured adapters; frontend code must never import this file.
 */
import { FacturamaSandbox } from './facturama.ts';
import { assertValidatedFiscalRoute, type FiscalOrigin } from './fiscal-routing.ts';

export type FiscalRequestType = 'stamp' | 'status' | 'cancel' | 'fetch_xml' | 'fetch_pdf';
export type FiscalEnvironment = 'sandbox' | 'production';
export type FiscalNormalizedOutcome =
    | 'processing'
    | 'stamped'
    | 'business_rejection'
    | 'technical_error'
    | 'cancelled'
    | 'cancellation_rejected'
    | 'not_found';

export interface FiscalCanonicalRequest {
    requestId: string;
    tenantId: string;
    billingCfdiId: string;
    requestType: FiscalRequestType;
    idempotencyKey: string;
    environment: FiscalEnvironment;
    payloadSnapshot: Readonly<Record<string, unknown>>;
    /** Server-generated, frozen serialization; canonical FISCAL.0 input stays neutral. */
    providerPayloadSnapshot?: Readonly<Record<string, unknown>>;
    providerDocumentId?: string;
    fiscalUuid?: string;
    /** Immutable origin loaded by the server, never selected by browser metadata. */
    origin?: Readonly<FiscalOrigin>;
}

export interface FiscalNormalizedResult {
    outcome: FiscalNormalizedOutcome;
    providerDocumentId?: string;
    fiscalUuid?: string;
    providerCode?: string;
    safeErrorCode?:
        | 'provider_unavailable'
        | 'provider_timeout'
        | 'provider_rejected'
        | 'cancellation_failed'
        | 'artifact_unavailable';
    artifactAvailable?: Readonly<{ xml: boolean; pdf: boolean }>;
}

export interface FiscalArtifact {
    kind: 'xml' | 'pdf';
    bytes: Uint8Array;
    mimeType: 'application/xml' | 'application/pdf';
}

export interface FiscalProviderAdapter {
    readonly providerCode: string;
    submit(request: FiscalCanonicalRequest): Promise<FiscalNormalizedResult>;
    getStatus(request: FiscalCanonicalRequest): Promise<FiscalNormalizedResult>;
    cancel(request: FiscalCanonicalRequest): Promise<FiscalNormalizedResult>;
    getXml(request: FiscalCanonicalRequest): Promise<FiscalArtifact>;
    getPdf(request: FiscalCanonicalRequest): Promise<FiscalArtifact>;
}

export const FISCAL_RUNTIME_SECRET_CONTRACT = [
    'FISCAL_PROVIDER',
    'FISCAL_API_BASE_URL',
    'FISCAL_API_USER',
    'FISCAL_API_SECRET',
    'FISCAL_WEBHOOK_SECRET',
] as const;

export class FiscalProviderNotConfiguredError extends Error {
    readonly code = 'provider_not_configured';
    constructor() {
        super('provider_not_configured');
    }
}

/**
 * Facturama requires explicit server-only sandbox configuration. All other
 * providers remain inert; Softmanagement is preserved without automatic fallback.
 */
export function resolveFiscalProviderAdapter(
    providerCode: string | null,
    sandbox?: { username: string; password: string; environment: string; baseUrl?: string },
): FiscalProviderAdapter {
    if (providerCode === 'facturama' && sandbox) return new FacturamaSandbox(sandbox);
    if (providerCode === 'soft_management' || providerCode === null) {
        throw new FiscalProviderNotConfiguredError();
    }
    throw new FiscalProviderNotConfiguredError();
}

/** Resolve historical operations from their origin, not today's selection. */
export function resolveOriginAdapter(
    origin: FiscalOrigin,
    action: FiscalRequestType,
    sandbox?: { username: string; password: string; environment: string; baseUrl?: string },
): FiscalProviderAdapter {
    assertValidatedFiscalRoute(origin, action);
    return resolveFiscalProviderAdapter(origin.providerCode, sandbox);
}
