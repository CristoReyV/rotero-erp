import type {
  FiscalArtifact,
  FiscalCanonicalRequest,
  FiscalNormalizedResult,
  FiscalProviderAdapter,
} from './fiscal-provider.ts';

export type FiscalMockScenario =
  | 'success-stamped'
  | 'processing'
  | 'technical-error'
  | 'business-rejection'
  | 'cancelled'
  | 'artifact-present';

/** Test-only deterministic adapter. Runtime must be the literal `test`. */
export function createTestFiscalAdapter(scenario: FiscalMockScenario, runtime: 'test'): FiscalProviderAdapter {
  if (runtime !== 'test') throw new Error('mock_adapter_forbidden');
  const result = (): FiscalNormalizedResult => {
    switch (scenario) {
      case 'success-stamped': return { outcome: 'stamped', providerDocumentId: 'test-provider-document', fiscalUuid: '00000000-0000-4000-8000-000000000001' };
      case 'processing': return { outcome: 'processing', providerDocumentId: 'test-provider-document' };
      case 'technical-error': return { outcome: 'technical_error', safeErrorCode: 'provider_timeout' };
      case 'business-rejection': return { outcome: 'business_rejection', safeErrorCode: 'provider_rejected' };
      case 'cancelled': return { outcome: 'cancelled' };
      case 'artifact-present': return { outcome: 'stamped', providerDocumentId: 'test-provider-document', fiscalUuid: '00000000-0000-4000-8000-000000000001', artifactAvailable: { xml: true, pdf: true } };
    }
  };
  const artifact = (kind: 'xml' | 'pdf'): FiscalArtifact => ({
    kind,
    bytes: new Uint8Array(kind === 'xml' ? [60, 120, 47, 62] : [37, 80, 68, 70]),
    mimeType: kind === 'xml' ? 'application/xml' : 'application/pdf',
  });
  return {
    providerCode: 'test_only',
    submit: async (_request: FiscalCanonicalRequest) => result(),
    getStatus: async (_request: FiscalCanonicalRequest) => result(),
    cancel: async (_request: FiscalCanonicalRequest) => result(),
    getXml: async (_request: FiscalCanonicalRequest) => artifact('xml'),
    getPdf: async (_request: FiscalCanonicalRequest) => artifact('pdf'),
  };
}
