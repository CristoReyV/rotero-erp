import { useEffect, useRef, useState } from 'react';
import { useAuthStore } from '@/store/authStore';
import { supabase } from '@/lib/supabase';
import {
    getReportModules, getFinancialSummary, getPipelineSummary,
    getInventorySummary, getOperationsSummary,
} from '@/services/reports.service';
import { createReportsLoader, type LegacyReportsData } from '@/services/reportsLoader';
import { createReportsTanda1Service } from '@/services/reportsTanda1.service';
import { LegacyReportsSection } from '@/components/reports/LegacyReportsSection';
import {
    OperationalReportsSection, type OperationalReportsState,
} from '@/components/reports/OperationalReportsSection';

const getReportsTanda1 = createReportsTanda1Service(supabase);

const ReportsPage = () => {
    const activeTenant = useAuthStore(state => state.activeTenant);
    const loader = useRef<ReturnType<typeof createReportsLoader> | null>(null);
    if (!loader.current) {
        loader.current = createReportsLoader({
            getReportModules, getFinancialSummary, getPipelineSummary,
            getInventorySummary, getOperationsSummary, getReportsTanda1,
        });
    }
    const [revision, setRevision] = useState(0);
    const [legacy, setLegacy] = useState<{ tenantId: string; data: LegacyReportsData; } | null>(null);
    const [legacyLoading, setLegacyLoading] = useState({ tenantId: activeTenant, loading: true });
    const [operational, setOperational] = useState<{
        tenantId: string | null; state: OperationalReportsState;
    }>({ tenantId: activeTenant, state: { status: 'loading' } });

    useEffect(() => {
        let active = true;
        if (!activeTenant) {
            loader.current!.clear();
            setLegacy(null);
            setLegacyLoading({ tenantId: null, loading: false });
            setOperational({ tenantId: null, state: { status: 'error' } });
            return;
        }
        setLegacy(previous => previous?.tenantId === activeTenant ? previous : null);
        setLegacyLoading({ tenantId: activeTenant, loading: true });
        setOperational({ tenantId: activeTenant, state: { status: 'loading' } });
        const load = loader.current!.load(activeTenant, revision);
        void load.legacy.then(data => {
            if (active) setLegacy({ tenantId: activeTenant, data });
        }, () => {
            // Preserve the existing metrics/fallback without logging RPC payloads.
        }).finally(() => {
            if (active) setLegacyLoading({ tenantId: activeTenant, loading: false });
        });
        void load.operational.then(data => {
            if (active) setOperational({ tenantId: activeTenant, state: { status: 'ready', data } });
        }, () => {
            if (active) setOperational({ tenantId: activeTenant, state: { status: 'error' } });
        });
        return () => { active = false; };
    }, [activeTenant, revision]);

    // Do not display another tenant's data while its replacement load is pending.
    const legacyData = legacy?.tenantId === activeTenant ? legacy.data : null;
    const isLegacyLoading = legacyLoading.tenantId === activeTenant
        ? legacyLoading.loading : Boolean(activeTenant);
    const operationalState: OperationalReportsState = operational.tenantId === activeTenant
        ? operational.state : { status: activeTenant ? 'loading' : 'error' };

    return <div className="space-y-6">
        <LegacyReportsSection data={legacyData} loading={isLegacyLoading}
            onRefresh={() => setRevision(value => value + 1)} />
        <OperationalReportsSection state={operationalState} />
    </div>;
};

export default ReportsPage;
