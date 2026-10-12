import type { ReportsTanda1, ReportsTanda1Volume, ReportsTanda1Week } from '@/types/reports';

export interface ReportsTanda1Parameters {
    p_tenant_id: string;
    p_date_from?: string | null;
    p_date_to?: string | null;
}

export interface ReportsTanda1Client {
    rpc(
        name: 'rpc_reports_tanda1',
        parameters: ReportsTanda1Parameters,
    ): PromiseLike<{ data: unknown; error: unknown; }>;
}

export interface ReportsTanda1Dates {
    from?: string | null;
    to?: string | null;
}

export class ReportsTanda1Error extends Error {
    constructor(public readonly kind: 'transport' | 'unauthorized' | 'invalid_response') {
        super('El resumen operativo no está disponible.');
        this.name = 'ReportsTanda1Error';
    }
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value);

const isCount = (value: unknown): value is number =>
    typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

const isQuantity = (value: unknown): value is number =>
    typeof value === 'number' && Number.isFinite(value) && value >= 0;

const isDate = (value: unknown): value is string => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(value + 'T00:00:00Z');
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
};

const isVolume = (value: unknown): value is ReportsTanda1Volume =>
    isRecord(value) && isCount(value.operations) &&
    isQuantity(value.pieces) && isQuantity(value.weight_kg);

const isWeek = (value: unknown): value is ReportsTanda1Week =>
    isRecord(value) && isDate(value.week_start) &&
    isCount(value.operations_created) && isCount(value.delivered) &&
    isCount(value.closed) && isCount(value.billed);

const rootKeys = ['date_from', 'date_to', 'weekly', 'volume', 'by_service_type', 'by_zone', 'by_scope'];

export function isReportsTanda1(value: unknown): value is ReportsTanda1 {
    return isRecord(value) && Object.keys(value).length === rootKeys.length &&
        rootKeys.every(key => Object.prototype.hasOwnProperty.call(value, key)) &&
        isDate(value.date_from) && isDate(value.date_to) &&
        isVolume(value.volume) && Array.isArray(value.weekly) && value.weekly.every(isWeek) &&
        Array.isArray(value.by_service_type) && value.by_service_type.every(row =>
            isVolume(row) && isRecord(row) &&
            typeof row.service_type === 'string' && typeof row.service_class === 'string') &&
        Array.isArray(value.by_zone) && value.by_zone.every(row =>
            isVolume(row) && isRecord(row) && typeof row.zone === 'string' &&
            typeof row.country_code === 'string' && typeof row.state === 'string') &&
        Array.isArray(value.by_scope) && value.by_scope.every(row =>
            isVolume(row) && isRecord(row) && typeof row.scope === 'string');
}

/** Inject the RPC client so isolated tests never initialize Supabase or Auth. */
export function createReportsTanda1Service(client: ReportsTanda1Client) {
    return async (tenantId: string, dates: ReportsTanda1Dates = {}): Promise<ReportsTanda1> => {
        const parameters: ReportsTanda1Parameters = { p_tenant_id: tenantId };
        if (dates.from !== undefined) parameters.p_date_from = dates.from;
        if (dates.to !== undefined) parameters.p_date_to = dates.to;

        const { data, error } = await client.rpc('rpc_reports_tanda1', parameters);
        if (error) throw new ReportsTanda1Error('transport');
        if (isRecord(data) && data.error === 'unauthorized') {
            throw new ReportsTanda1Error('unauthorized');
        }
        if (!isReportsTanda1(data)) throw new ReportsTanda1Error('invalid_response');
        return data;
    };
}
