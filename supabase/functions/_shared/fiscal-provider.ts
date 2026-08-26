/**
 * Provider-neutral fiscal boundary for a future authenticated Edge orchestrator.
 * FISCAL.0 deliberately contains no endpoint, transport, credential or provider
 * serialization. Frontend code must call canonical RPCs and never import this file.
 */

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
  providerDocumentId?: string;
  fiscalUuid?: string;
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
 * Registry is intentionally inert until official provider documentation exists.
 * `soft_management` is only a stable candidate identifier, never an adapter.
 */
export function resolveFiscalProviderAdapter(providerCode: string | null): FiscalProviderAdapter {
  if (providerCode === 'soft_management' || providerCode === null) {
    throw new FiscalProviderNotConfiguredError();
  }
  throw new FiscalProviderNotConfiguredError();
}
