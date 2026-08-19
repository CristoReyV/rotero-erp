export interface MarginResult {
    amount: number;
    percentage: number | null;
}

export function calculateMargin(providerCost: number, customerPrice: number): MarginResult {
    const cost = Number.isFinite(providerCost) ? providerCost : 0;
    const price = Number.isFinite(customerPrice) ? customerPrice : 0;
    const amount = price - cost;

    return {
        amount,
        percentage: price === 0 ? null : (amount / price) * 100,
    };
}

export function formatCommercialCurrency(value: number, currency = 'MXN'): string {
    return new Intl.NumberFormat('es-MX', {
        style: 'currency',
        currency,
        maximumFractionDigits: 2,
    }).format(Number.isFinite(value) ? value : 0);
}
