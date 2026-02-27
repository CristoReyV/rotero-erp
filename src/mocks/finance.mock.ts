import type { FinanceInvoice, FinanceOverview } from '@/types/finance';

export const MOCK_FINANCE_OVERVIEW: FinanceOverview = {
    total_ar_open: 845000,
    total_ap_open: 210000,
    total_overdue: 45000,
    paid_this_month: 1200000,
    count_open_invoices: 14,
    chart: {
        labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
        values: [150000, 220000, 180000, 240000, 190000, 310000]
    }
};

export const MOCK_FINANCE_INVOICES: FinanceInvoice[] = [
    {
        id: 'mock-inv-1',
        direction: 'ar',
        counterparty_name: 'Logistics MX S.A.',
        reference: 'F-0932',
        amount: 45000,
        currency: 'MXN',
        status: 'open',
        due_date: '2026-03-15',
        created_at: new Date().toISOString()
    },
    {
        id: 'mock-inv-2',
        direction: 'ar',
        counterparty_name: 'Transportes del Norte',
        reference: 'F-0933',
        amount: 85200,
        currency: 'MXN',
        status: 'overdue',
        due_date: '2026-02-10',
        created_at: new Date(Date.now() - 30 * 86400000).toISOString()
    },
    {
        id: 'mock-inv-3',
        direction: 'ap',
        counterparty_name: 'AutoParts Global',
        reference: 'INV-4412',
        amount: 22500,
        currency: 'MXN',
        status: 'paid',
        due_date: '2026-02-25',
        paid_at: new Date().toISOString(),
        created_at: new Date(Date.now() - 15 * 86400000).toISOString()
    }
];

export async function getMockFinanceOverview() { return MOCK_FINANCE_OVERVIEW; }
export async function getMockFinanceInvoices() { return MOCK_FINANCE_INVOICES; }
