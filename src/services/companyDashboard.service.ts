import { supabase } from '@/lib/supabase';
import { scopedResponse } from '@/store/companyStore';
import type { ExecutiveDashboard, RecentActivityItem } from '@/types/executive';

export interface CompanyDashboard {
    operations: ExecutiveDashboard['operations'] & { total: number };
    finance?: ExecutiveDashboard['finance'];
    commercial?: ExecutiveDashboard['commercial'];
    documents: ExecutiveDashboard['documents'];
    attention: ExecutiveDashboard['attention'];
    recent_activity: RecentActivityItem[];
    financial_available: boolean;
    commercial_available: boolean;
}
export async function companyDashboard(tenant: string, start: string | null, end: string | null): Promise<CompanyDashboard> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc('rpc_delivery_dashboard', { p_tenant_id: tenant, p_start_date: start, p_end_date: end });
        if (error || data?.error || !data?.operations || !data?.documents || !Array.isArray(data?.attention) || !Array.isArray(data?.recent_activity)) {
            throw new Error('No fue posible verificar el dashboard empresarial.');
        }
        const countKeys = ['total', 'active', 'in_transit', 'delivered', 'closed', 'blocking_incidents', 'dispatch_blockers', 'billing_ready', 'billing_blocked'];
        const countersValid = countKeys.every((key) => Number.isSafeInteger(data.operations[key]) && data.operations[key] >= 0)
            && ['required_missing', 'pod_pending'].every((key) => Number.isSafeInteger(data.documents[key]) && data.documents[key] >= 0);
        if (!countersValid || typeof data.financial_available !== 'boolean' || typeof data.commercial_available !== 'boolean'
            || Boolean(data.finance) !== data.financial_available || Boolean(data.commercial) !== data.commercial_available) {
            throw new Error('El resumen no conserva el contrato empresarial esperado.');
        }
        return data;
    });
}
