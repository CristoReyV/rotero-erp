import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FISCAL_ERROR_MESSAGES, getFiscalActionAvailability, normalizeFiscalError, withFiscalMutationGuard } from './fiscalContracts';
import type { FiscalReadiness } from '../types/billing';

const readiness = (fiscal_status: FiscalReadiness['fiscal_status'], configured = true): FiscalReadiness => ({
    cfdi_id: '00000000-0000-4000-8000-000000000001', fiscal_status,
    validation: { valid: true, missing_fields: [], cfdi_version: '4.0' },
    provider: { configured, code: configured ? 'soft_management' : null, environment: 'sandbox' },
    last_attempt: null,
});

assert.equal(getFiscalActionAvailability(readiness('draft')).validate, true);
assert.equal(getFiscalActionAvailability(readiness('ready_for_api')).submit, true);
assert.equal(getFiscalActionAvailability(readiness('ready_for_api', false)).submit, false);
assert.equal(getFiscalActionAvailability(readiness('ready_for_api', false)).externalDisabledReason, 'Proveedor fiscal no configurado');
assert.equal(getFiscalActionAvailability({ ...readiness('api_error'), last_attempt: { request_id: 'request', request_type: 'stamp', status: 'technical_error', attempt_count: 1, updated_at: '2026-08-26T00:00:00Z' } }).retry, true);
assert.equal(getFiscalActionAvailability({ ...readiness('rejected'), last_attempt: { request_id: 'request', request_type: 'stamp', status: 'business_rejected', attempt_count: 1, updated_at: '2026-08-26T00:00:00Z' } }).retry, false);
assert.equal(getFiscalActionAvailability(readiness('stamped')).cancel, true);
assert.equal(getFiscalActionAvailability(readiness('processing')).cancel, false);
assert.equal(getFiscalActionAvailability({ ...readiness('stamped'), xml_document_file_id: 'xml' }).downloadXml, true);
assert.equal(getFiscalActionAvailability(readiness('stamped')).downloadXml, false);
assert.equal(normalizeFiscalError('provider_timeout'), FISCAL_ERROR_MESSAGES.provider_timeout);
assert.equal(normalizeFiscalError('raw-provider-message'), 'No fue posible completar la acción fiscal.');

let release!: () => void;
const first = withFiscalMutationGuard('same-document:stamp', () => new Promise<void>((resolve) => { release = resolve; }));
await assert.rejects(() => withFiscalMutationGuard('same-document:stamp', async () => undefined), /solicitud fiscal en proceso/);
release(); await first;
await withFiscalMutationGuard('same-document:stamp', async () => undefined);

const billingPage = readFileSync(new URL('../pages/BillingPage.tsx', import.meta.url), 'utf8');
const billingService = readFileSync(new URL('./billing.service.ts', import.meta.url), 'utf8');
for (const label of ['Validar', 'Enviar a timbrar', 'Reintentar', 'Consultar estado', 'Cancelar', 'Descargar XML', 'Descargar PDF']) {
    assert.match(billingPage, new RegExp(label));
}
assert.match(billingPage, /Proveedor fiscal no configurado|externalDisabledReason/);
assert.match(billingService, /withFiscalMutationGuard\(`\$\{cfdiId\}:stamp`/);
assert.doesNotMatch(billingService, /FISCAL_API_|soft-management|soft_management/);

console.log('Fiscal frontend contracts PASS');
