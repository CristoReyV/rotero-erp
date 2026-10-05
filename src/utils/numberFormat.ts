const hoursFormat = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 1 });

export function formatAverageHours(value: unknown): string {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
        return 'Prom. — h';
    }
    return `Prom. ${hoursFormat.format(value)} h`;
}
