import { supabase } from '@/lib/supabase';
import type {
    FinanceInvoice,
    FinanceOverview,
    FinanceCreateInvoicePayload,
    FinanceRecordPaymentPayload
} from '@/types/finance';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export async function getFinanceOverview(tenantId: string, startDate?: string, endDate?: string): Promise<FinanceOverview> {
    if (USE_MOCKS) {
        const { getMockFinanceOverview } = await import('@/mocks/finance.mock');
        return getMockFinanceOverview();
    }

    const { data, error } = await supabase.rpc('rpc_finance_overview', {
        p_tenant_id: tenantId,
        p_start_date: startDate || null,
        p_end_date: endDate || null
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as FinanceOverview;
}

export async function listFinanceInvoices(
    tenantId: string,
    limit: number = 50,
    status?: string,
    direction?: string,
    startDate?: string,
    endDate?: string
): Promise<FinanceInvoice[]> {
    if (USE_MOCKS) {
        const { getMockFinanceInvoices } = await import('@/mocks/finance.mock');
        let mocks = await getMockFinanceInvoices();
        if (status) mocks = mocks.filter(m => m.status === status);
        if (direction) mocks = mocks.filter(m => m.direction === direction);
        return mocks;
    }

    const { data, error } = await supabase.rpc('rpc_list_finance_invoices', {
        p_tenant_id: tenantId,
        p_limit: limit,
        p_status: status || null,
        p_direction: direction || null,
        p_start_date: startDate || null,
        p_end_date: endDate || null
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return data as FinanceInvoice[];
}

export async function createFinanceInvoice(tenantId: string, payload: FinanceCreateInvoicePayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-new-id' };

    const { data, error } = await supabase.rpc('rpc_create_finance_invoice', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function recordPayment(tenantId: string, payload: FinanceRecordPaymentPayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-pay-id' };

    const { data, error } = await supabase.rpc('rpc_record_payment', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updateFinanceInvoiceStatus(tenantId: string, id: string, status: string): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_finance_invoice_status', {
        p_tenant_id: tenantId,
        p_id: id,
        p_status: status
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}
