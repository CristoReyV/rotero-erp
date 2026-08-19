import assert from 'node:assert/strict';
import { normalizeConversionResult, normalizeCustomers, normalizeIdResult, normalizeProviders, normalizeQuotes } from './commercialContracts';

assert.equal(normalizeCustomers([{ id: 'c1', display_name: 'Cliente', quote_count: '2' }])[0].quote_count, 2);
assert.deepEqual(normalizeProviders([{ id: 'p1', display_name: 'Proveedor', contracted_cost_totals: { MXN: '1200.50', USD: 80 } }])[0].contracted_cost_totals, { MXN: 1200.5, USD: 80 });
assert.deepEqual(normalizeIdResult({ id: 'quote-1' }), { id: 'quote-1' });
assert.deepEqual(normalizeConversionResult({ operation_id: 'op-1', operation_reference: 'OP-001', already_converted: false }), {
    operation_id: 'op-1', operation_reference: 'OP-001', already_converted: false,
});

const quote = normalizeQuotes([{
    id: 'q1', quote_reference: 'COT-001', quote_status: 'draft', value: '1500',
    quote_payload: { operation_scope: 'national', currency: 'MXN', provider_cost_amount: '1000', customer_price_amount: '1500' },
}])[0];
assert.equal(quote.value, 1500);
assert.equal(quote.quote_payload.provider_cost_amount, 1000);
assert.throws(() => normalizeQuotes([{ id: 'q1', quote_status: 'invented', quote_payload: {} }]), /invalid_response/);
assert.throws(() => normalizeConversionResult({ operation_id: 'op-1' }), /invalid_response/);
