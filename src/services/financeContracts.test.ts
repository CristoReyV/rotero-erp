import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync('src/pages/FinancePage.tsx', 'utf8');
const service = readFileSync('src/services/finance.service.ts', 'utf8');
const types = readFileSync('src/types/finance.ts', 'utf8');
const drawer = readFileSync('src/components/finance/FinanceInvoiceDrawer.tsx', 'utf8');
const payment = readFileSync('src/components/finance/PaymentDrawer.tsx', 'utf8');
const create = readFileSync('src/components/finance/InvoiceCreateModal.tsx', 'utf8');

for (const label of ['Resumen', 'Por cobrar', 'Por pagar', 'Pagos', 'Vencimientos', 'Rentabilidad']) assert.match(page, new RegExp(label));
for (const component of ['FinanceOverview', 'ReceivablesWorkspace', 'PayablesWorkspace', 'PaymentActivity', 'DueAlertsPanel', 'ProfitabilityWorkspace']) assert.match(page, new RegExp(component));
for (const rpc of ['rpc_finance_overview', 'rpc_list_finance_invoices', 'rpc_create_finance_invoice', 'rpc_record_payment', 'rpc_void_finance_invoice', 'rpc_finance_profitability', 'rpc_export_finance_ledger']) assert.match(service, new RegExp(rpc));
assert.match(service, /payment_exceeds_balance/);
assert.match(service, /exchange_rate_required_for_usd/);
assert.doesNotMatch(service, /SQLERRM|service_role|SUPABASE_SERVICE/i);
assert.match(types, /FinanceInvoiceDetail/);
assert.match(types, /OperationFinanceSummary/);
assert.match(types, /currency_policy: 'separate'/);
assert.match(drawer, /entityType="finance_invoice"/);
assert.match(drawer, /Abrir en Billing/);
assert.match(payment, /Preparar complemento de pago/);
assert.match(payment, /prepare_complement/);
assert.match(create, /Registro explícito/);
assert.match(create, /over_registration_reason/);
assert.match(create, /operation_id/);
assert.match(create, /getOperationFinanceSummary/);
assert.match(create, /remaining_ar_to_register/);
