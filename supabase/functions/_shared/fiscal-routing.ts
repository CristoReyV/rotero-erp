/** Server-only routing. These profiles contain no credentials or browser input. */
export type ProviderCode = 'facturama' | 'soft_management';
export type ProviderEnvironment = 'sandbox' | 'production';
export type ProviderAction = 'stamp' | 'status' | 'cancel' | 'fetch_xml' | 'fetch_pdf';

export interface FiscalOrigin {
    billingCfdiId: string;
    companyId: string;
    providerCode: ProviderCode;
    environment: ProviderEnvironment;
    credentialProfile: string;
}
export interface FiscalSelection {
    companyId: string;
    providerCode: ProviderCode;
    environment: ProviderEnvironment;
    credentialProfile: string;
    enabled: boolean;
}
export const FISCAL_PROFILES = {
    facturama_sandbox_lab_v1: {
        providerCode: 'facturama',
        environment: 'sandbox',
        baseUrl: 'https://apisandbox.facturama.mx',
        credentialNames: ['FACTURAMA_SANDBOX_USER', 'FACTURAMA_SANDBOX_PASSWORD'],
        validation: 'sandbox_only',
        actions: ['stamp', 'status', 'cancel', 'fetch_xml', 'fetch_pdf'],
    },
    soft_management_sandbox_v1: {
        providerCode: 'soft_management',
        environment: 'sandbox',
        baseUrl: null,
        credentialNames: ['SOFTMANAGEMENT_SANDBOX_USER', 'SOFTMANAGEMENT_SANDBOX_PASSWORD'],
        validation: 'pending_validation',
        actions: [],
    },
    soft_management_production_v1: {
        providerCode: 'soft_management',
        environment: 'production',
        baseUrl: null,
        credentialNames: ['SOFTMANAGEMENT_PRODUCTION_USER', 'SOFTMANAGEMENT_PRODUCTION_PASSWORD'],
        validation: 'pending_validation',
        actions: [],
    },
} as const;

export class FiscalRoutingError extends Error {
    constructor(readonly code: string) {
        super(code);
    }
}
/** Only trusted database origin/selection objects enter this server boundary. */
export function selectFiscalRoute(
    action: ProviderAction,
    origin: FiscalOrigin | null,
    selection: FiscalSelection | null,
): FiscalOrigin {
    if (!origin?.billingCfdiId || !origin.companyId) throw new FiscalRoutingError('fiscal_origin_required');
    if (action === 'stamp') {
        if (!selection?.enabled) throw new FiscalRoutingError('company_fiscal_transport_disabled');
        if (
            selection.companyId !== origin.companyId || selection.providerCode !== origin.providerCode ||
            selection.environment !== origin.environment ||
            selection.credentialProfile !== origin.credentialProfile
        ) throw new FiscalRoutingError('fiscal_origin_conflict');
    }
    // Reads and cancellation always use the immutable origin, never the future
    // selection. No provider name, endpoint or credential comes from a request.
    return { ...origin };
}

export function assertValidatedFiscalRoute(origin: FiscalOrigin, action: ProviderAction): void {
    const profile = FISCAL_PROFILES[origin.credentialProfile as keyof typeof FISCAL_PROFILES];
    if (
        !profile || profile.providerCode !== origin.providerCode ||
        profile.environment !== origin.environment
    ) throw new FiscalRoutingError('fiscal_origin_conflict');
    if (!(profile.actions as readonly string[]).includes(action)) {
        throw new FiscalRoutingError('provider_pending_validation');
    }
}

/** The caller's store must acquire the database lane before a stamp transport.
 * Failure/timeout leaves that lane uncertain. There is deliberately no catch,
 * fallback, release, retry, alternate provider or production Facturama route.
 */
export async function dispatchFiscal<T>(input: {
    action: ProviderAction;
    origin: FiscalOrigin | null;
    selection: FiscalSelection | null;
    claimStamp: (origin: FiscalOrigin) => Promise<void>;
    transport: (origin: FiscalOrigin) => Promise<T>;
}): Promise<T> {
    const route = selectFiscalRoute(input.action, input.origin, input.selection);
    assertValidatedFiscalRoute(route, input.action);
    if (input.action === 'stamp') await input.claimStamp(route);
    return input.transport(route);
}
