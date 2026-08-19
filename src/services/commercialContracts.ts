import type { Customer, LogisticsProvider, Quote, QuoteConversionResult, QuoteStatus } from '@/types/commercial';

const QUOTE_STATUSES: readonly QuoteStatus[] = ['draft', 'review', 'approved', 'rejected', 'converted'];

function asNumber(value: unknown): number {
    const parsed = typeof value === 'number' ? value : Number(value ?? 0);
    return Number.isFinite(parsed) ? parsed : 0;
}

function requireArray(value: unknown): Record<string, unknown>[] {
    if (!Array.isArray(value)) throw new Error('invalid_response');
    return value as Record<string, unknown>[];
}

function asCurrencyTotals(value: unknown): Partial<Record<'MXN' | 'USD', number>> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    const totals = value as Record<string, unknown>;
    return {
        ...(totals.MXN === undefined ? {} : { MXN: asNumber(totals.MXN) }),
        ...(totals.USD === undefined ? {} : { USD: asNumber(totals.USD) }),
    };
}

export function normalizeCustomers(value: unknown): Customer[] {
    return requireArray(value).map((row) => {
        if (typeof row.id !== 'string' || typeof row.display_name !== 'string') throw new Error('invalid_response');
        return {
            ...row,
            deal_count: asNumber(row.deal_count), quote_count: asNumber(row.quote_count),
            operation_count: asNumber(row.operation_count), quoted_totals: asCurrencyTotals(row.quoted_totals),
            operation_sell_totals: asCurrencyTotals(row.operation_sell_totals),
        } as unknown as Customer;
    });
}

export function normalizeProviders(value: unknown): LogisticsProvider[] {
    return requireArray(value).map((row) => {
        if (typeof row.id !== 'string' || typeof row.display_name !== 'string') throw new Error('invalid_response');
        return {
            ...row,
            quote_count: asNumber(row.quote_count), operation_count: asNumber(row.operation_count),
            contracted_cost_totals: asCurrencyTotals(row.contracted_cost_totals),
        } as unknown as LogisticsProvider;
    });
}

export function normalizeQuotes(value: unknown): Quote[] {
    return requireArray(value).map((row) => {
        if (typeof row.id !== 'string' || typeof row.quote_reference !== 'string'
            || !QUOTE_STATUSES.includes(row.quote_status as QuoteStatus)
            || typeof row.quote_payload !== 'object' || row.quote_payload === null) {
            throw new Error('invalid_response');
        }
        const payload = row.quote_payload as Record<string, unknown>;
        return {
            ...row,
            value: asNumber(row.value),
            quote_payload: {
                ...payload,
                provider_cost_amount: payload.provider_cost_amount === undefined ? undefined : asNumber(payload.provider_cost_amount),
                customer_price_amount: payload.customer_price_amount === undefined ? undefined : asNumber(payload.customer_price_amount),
            },
        } as unknown as Quote;
    });
}

export function normalizeIdResult(value: unknown): { id: string } {
    if (!value || typeof value !== 'object' || typeof (value as { id?: unknown }).id !== 'string') throw new Error('invalid_response');
    return value as { id: string };
}

export function normalizeConversionResult(value: unknown): QuoteConversionResult {
    const result = value as Partial<QuoteConversionResult> | null;
    if (!result || typeof result.operation_id !== 'string' || typeof result.operation_reference !== 'string' || typeof result.already_converted !== 'boolean') {
        throw new Error('invalid_response');
    }
    return result as QuoteConversionResult;
}
