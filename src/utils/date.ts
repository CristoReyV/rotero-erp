export type DateFilterRange = 'month' | 'quarter' | 'year' | 'all' | 'this_month' | 'last_7_days' | 'last_30_days' | 'this_year';

export function getDates(range: DateFilterRange): { start?: Date; end?: Date } {
    const now = new Date();
    switch (range) {
        // Finance ranges
        case 'month':
            return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: now };
        case 'quarter':
            const currentQuarter = Math.floor(now.getMonth() / 3);
            return { start: new Date(now.getFullYear(), currentQuarter * 3, 1), end: now };
        case 'year':
            return { start: new Date(now.getFullYear(), 0, 1), end: now };
        case 'all':
            return {};

        // Dashboard ranges
        case 'this_month':
            return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: now };
        case 'last_7_days': {
            const start = new Date(now);
            start.setDate(now.getDate() - 7);
            return { start, end: now };
        }
        case 'last_30_days': {
            const start = new Date(now);
            start.setDate(now.getDate() - 30);
            return { start, end: now };
        }
        case 'this_year':
            return { start: new Date(now.getFullYear(), 0, 1), end: now };

        default:
            return {};
    }
}
