import assert from 'node:assert/strict';
import { FiscalProviderNotConfiguredError, resolveFiscalProviderAdapter } from './fiscal-provider.ts';
import { createTestFiscalAdapter, type FiscalMockScenario } from './fiscal-provider.mock.ts';

const request = {
  requestId: 'request', tenantId: 'tenant', billingCfdiId: 'cfdi', requestType: 'stamp' as const,
  idempotencyKey: 'fingerprint', environment: 'sandbox' as const, payloadSnapshot: Object.freeze({ cfdi_version: '4.0' }),
};
const expected: Record<FiscalMockScenario, string> = {
  'success-stamped': 'stamped', processing: 'processing', 'technical-error': 'technical_error',
  'business-rejection': 'business_rejection', cancelled: 'cancelled', 'artifact-present': 'stamped',
};
for (const [scenario, outcome] of Object.entries(expected) as [FiscalMockScenario, string][]) {
  assert.equal((await createTestFiscalAdapter(scenario, 'test').submit(request)).outcome, outcome);
}
assert.equal((await createTestFiscalAdapter('artifact-present', 'test').getXml(request)).mimeType, 'application/xml');
assert.throws(() => resolveFiscalProviderAdapter('soft_management'), FiscalProviderNotConfiguredError);
assert.throws(() => resolveFiscalProviderAdapter(null), FiscalProviderNotConfiguredError);
console.log('Fiscal provider mock contracts PASS');
