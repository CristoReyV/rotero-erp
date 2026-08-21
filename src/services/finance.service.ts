import { supabase } from '@/lib/supabase';
import type {
    FinanceCreateInvoicePayload, FinanceDueAlert, FinanceExportRow, FinanceInvoice, FinanceInvoiceDetail,
    FinanceInvoiceFilters, FinanceOverview, FinancePayment, FinanceProfitability, FinanceRecordPaymentPayload,
    InvoiceDirection, InvoiceStatus, OperationFinanceSummary, PaymentComplement,
} from '@/types/finance';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';
const ERRORS: Record<string, string> = {
    unauthorized: 'No tienes permiso para este contexto financiero.', invalid_payload: 'Revisa los datos de la cuenta.',
    invalid_filters: 'Revisa los filtros seleccionados.', invalid_customer: 'El cliente no pertenece a la empresa activa.',
    invalid_provider: 'El proveedor no pertenece a la empresa activa.', invalid_operation: 'La operación no pertenece a la empresa activa.',
    invalid_billing_document: 'El documento de Billing no es válido.', operation_currency_mismatch: 'La moneda debe coincidir con la operación.',
    operation_counterparty_mismatch: 'La contraparte no coincide con la operación.', operation_amount_exceeded: 'El importe supera el remanente esperado de la operación.',
    counterparty_required: 'Selecciona o captura una contraparte.', exchange_rate_required_for_usd: 'Captura tipo de cambio y fecha para USD.',
    invoice_not_found: 'La cuenta ya no está disponible.', invoice_not_payable: 'La cuenta no admite pagos en su estado actual.',
    invalid_payment_amount: 'El importe del pago debe ser mayor a cero.', payment_exceeds_balance: 'El pago supera el saldo disponible.',
    invoice_already_settled: 'La cuenta ya está liquidada.', payment_currency_mismatch: 'La moneda del pago debe coincidir con la cuenta.',
    invalid_payment_method: 'Selecciona un método de pago válido.', payment_driven_status: 'El estado pagado se determina exclusivamente por pagos y créditos.',
    void_reason_required: 'Captura el motivo de anulación.', invoice_cannot_be_voided: 'No se puede anular una cuenta con pagos o créditos aplicados.',
    complement_already_exists: 'El pago ya tiene un complemento preparado.', complement_only_for_ar: 'Los complementos aplican únicamente a cuentas por cobrar.',
};

function result<T>(data: unknown, error: { message?: string } | null): T {
    if (error) throw new Error('No fue posible comunicarse con Finance 360.');
    if (data && typeof data === 'object' && 'error' in data) {
        const code = String((data as { error: unknown }).error);
        throw new Error(ERRORS[code] ?? 'No fue posible completar la acción financiera.');
    }
    return data as T;
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await supabase.rpc(name, args);
    return result<T>(data, error);
}

export async function getFinanceOverview(tenantId: string, filters: Record<string, unknown> = {}): Promise<FinanceOverview> {
    if (USE_MOCKS) return (await import('@/mocks/finance.mock')).getMockFinanceOverview();
    return rpc('rpc_finance_overview', { p_tenant_id: tenantId, p_filters: filters });
}

export async function listFinanceInvoices(tenantId: string, filtersOrLimit: FinanceInvoiceFilters | number = {}, status?: InvoiceStatus, direction?: InvoiceDirection): Promise<FinanceInvoice[]> {
    if (USE_MOCKS) {
        let items = await (await import('@/mocks/finance.mock')).getMockFinanceInvoices();
        const filters = typeof filtersOrLimit === 'number' ? { status, direction } : filtersOrLimit;
        if (filters.status) items = items.filter((item) => (item.effective_status ?? item.status) === filters.status);
        if (filters.direction) items = items.filter((item) => item.direction === filters.direction);
        return items;
    }
    const filters = typeof filtersOrLimit === 'number' ? { limit: filtersOrLimit, status, direction } : filtersOrLimit;
    return (await rpc<{ items: FinanceInvoice[] }>('rpc_list_finance_invoices', { p_tenant_id: tenantId, p_filters: filters })).items;
}

export async function getFinanceInvoiceDetail(tenantId: string, invoiceId: string): Promise<FinanceInvoiceDetail> {
    return rpc('rpc_get_finance_invoice_detail', { p_tenant_id: tenantId, p_invoice_id: invoiceId });
}

export async function createFinanceInvoice(tenantId: string, payload: FinanceCreateInvoicePayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: crypto.randomUUID() };
    return rpc('rpc_create_finance_invoice', { p_tenant_id: tenantId, p_payload: payload });
}

export async function recordPayment(tenantId: string, payload: FinanceRecordPaymentPayload): Promise<{ id: string; complement_id?: string; remaining_balance: number }> {
    if (USE_MOCKS) return { id: crypto.randomUUID(), remaining_balance: 0 };
    return rpc('rpc_record_payment', { p_tenant_id: tenantId, p_payload: payload });
}

export async function updateFinanceInvoiceStatus(tenantId: string, id: string, status: 'open'): Promise<void> {
    if (USE_MOCKS) return;
    await rpc('rpc_update_finance_invoice_status', { p_tenant_id: tenantId, p_id: id, p_status: status });
}

export async function voidFinanceInvoice(tenantId: string, id: string, reason: string): Promise<void> {
    if (USE_MOCKS) return;
    await rpc('rpc_void_finance_invoice', { p_tenant_id: tenantId, p_id: id, p_reason: reason });
}

export async function listFinancePayments(tenantId: string, filters: Record<string, unknown> = {}): Promise<FinancePayment[]> {
    return (await rpc<{ items: FinancePayment[] }>('rpc_list_finance_payments', { p_tenant_id: tenantId, p_filters: filters })).items;
}

export async function listFinanceDueAlerts(tenantId: string, filters: Record<string, unknown> = {}): Promise<FinanceDueAlert[]> {
    return (await rpc<{ items: FinanceDueAlert[] }>('rpc_list_finance_due_alerts', { p_tenant_id: tenantId, p_filters: filters })).items;
}

export async function getOperationFinanceSummary(tenantId: string, operationId: string): Promise<OperationFinanceSummary> {
    return rpc('rpc_get_operation_finance_summary', { p_tenant_id: tenantId, p_operation_id: operationId });
}

export async function getFinanceProfitability(tenantId: string, filters: Record<string, unknown> = {}): Promise<FinanceProfitability> {
    return rpc('rpc_finance_profitability', { p_tenant_id: tenantId, p_filters: filters });
}

export async function listPaymentComplements(tenantId: string, filters: Record<string, unknown> = {}): Promise<PaymentComplement[]> {
    return (await rpc<{ items: PaymentComplement[] }>('rpc_list_payment_complements', { p_tenant_id: tenantId, p_filters: filters })).items;
}

export async function exportFinanceLedger(tenantId: string, filters: Record<string, unknown> = {}): Promise<FinanceExportRow[]> {
    return rpc('rpc_export_finance_ledger', { p_tenant_id: tenantId, p_filters: filters });
}

function csvCell(value: unknown): string { return `"${String(value ?? '').replaceAll('"', '""')}"`; }
export function financeRowsToCsv(rows: FinanceExportRow[]): string {
    if (rows.length === 0) return '';
    const headers = Object.keys(rows[0]);
    return [headers.map(csvCell).join(','), ...rows.map((row) => headers.map((header) => csvCell(row[header])).join(','))].join('\r\n');
}

export function downloadFinanceCsv(rows: FinanceExportRow[]): void {
    const url = URL.createObjectURL(new Blob([`\uFEFF${financeRowsToCsv(rows)}`], { type: 'text/csv;charset=utf-8' }));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = `rotero-finance-${new Date().toISOString().slice(0, 10)}.csv`; anchor.click();
    URL.revokeObjectURL(url);
}
