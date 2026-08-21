import type { FinanceCurrency, InvoiceStatus } from '@/types/finance';

export function money(value: number | null | undefined, currency: FinanceCurrency | string = 'MXN'): string {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency, maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

export function shortDate(value?: string | null): string {
    if (!value) return 'Sin fecha';
    const date = new Date(/^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00` : value);
    return Number.isNaN(date.getTime()) ? value : new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium' }).format(date);
}

export const STATUS_LABEL: Record<InvoiceStatus, string> = { draft: 'Borrador', open: 'Abierta', paid: 'Pagada', overdue: 'Vencida', void: 'Anulada' };
export const STATUS_STYLE: Record<InvoiceStatus, string> = {
    draft: 'bg-slate-100 text-slate-600', open: 'bg-sky-50 text-sky-700', paid: 'bg-emerald-50 text-emerald-700',
    overdue: 'bg-rose-50 text-rose-700', void: 'bg-slate-100 text-slate-400',
};
