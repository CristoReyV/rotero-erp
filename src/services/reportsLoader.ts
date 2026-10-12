import type {
    ReportModuleDef, ReportsFinancialSummary, ReportsPipelineSummary,
    ReportsInventorySummary, ReportsOperationsSummary, ReportsTanda1,
} from '@/types/reports';
import type { ReportsTanda1Dates } from '@/services/reportsTanda1.service';

export interface LegacyReportsData {
    modules: ReportModuleDef[];
    finances: ReportsFinancialSummary;
    pipeline: ReportsPipelineSummary;
    inventory: ReportsInventorySummary;
    operations: ReportsOperationsSummary;
}

export interface ReportsDependencies {
    getReportModules: () => Promise<ReportModuleDef[]>;
    getFinancialSummary: (tenantId: string) => Promise<ReportsFinancialSummary>;
    getPipelineSummary: (tenantId: string) => Promise<ReportsPipelineSummary>;
    getInventorySummary: (tenantId: string) => Promise<ReportsInventorySummary>;
    getOperationsSummary: (tenantId: string) => Promise<ReportsOperationsSummary>;
    getReportsTanda1: (tenantId: string, dates?: ReportsTanda1Dates) => Promise<ReportsTanda1>;
}

export interface ReportsLoad {
    legacy: Promise<LegacyReportsData>;
    operational: Promise<ReportsTanda1>;
}

/** Share only requests in flight, scoped to this component's loader. */
export function createReportsLoader(dependencies: ReportsDependencies) {
    const legacyInFlight = new Map<string, Promise<LegacyReportsData>>();
    const operationalInFlight = new Map<string, Promise<ReportsTanda1>>();
    function inFlight<T>(entries: Map<string, Promise<T>>, key: string, start: () => Promise<T>) {
        const existing = entries.get(key);
        if (existing) return existing;
        const pending = Promise.resolve().then(start).finally(() => {
            if (entries.get(key) === pending) entries.delete(key);
        });
        entries.set(key, pending);
        return pending;
    }
    return {
        load(tenantId: string, revision: number, dates: ReportsTanda1Dates = {}): ReportsLoad {
            const requestDates = { from: dates.from, to: dates.to };
            const key = JSON.stringify([tenantId, revision, requestDates.from, requestDates.to]);
            const legacy = inFlight(legacyInFlight, key, async () => {
                const [modules, finances, pipeline, inventory, operations] = await Promise.all([
                    dependencies.getReportModules(),
                    dependencies.getFinancialSummary(tenantId),
                    dependencies.getPipelineSummary(tenantId),
                    dependencies.getInventorySummary(tenantId),
                    dependencies.getOperationsSummary(tenantId),
                ]);
                return { modules, finances, pipeline, inventory, operations };
            });
            const operational = inFlight(operationalInFlight, key,
                () => dependencies.getReportsTanda1(tenantId, requestDates));
            return { legacy, operational };
        },
        clear() {
            legacyInFlight.clear();
            operationalInFlight.clear();
        },
    };
}
