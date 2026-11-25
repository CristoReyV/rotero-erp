import { supabase } from '@/lib/supabase';
import { scopedResponse } from '@/store/companyStore';
import { useAuthStore } from '@/store/authStore';
import type { AutomationRule, AutomationRuleUpdate, AutomationEvaluation, AutomationHealth } from '@/types/automation';

async function call<T>(name: string, args: Record<string, unknown>): Promise<T> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc(name, args);
        if (error || data?.error) throw new Error('No fue posible confirmar la automatización para esta empresa.');
        return data;
    });
}
interface Status {
    rules: AutomationRule[];
    runs: Array<{ id: string; evaluated_at: string; outcome: AutomationEvaluation }>;
}
export const companyAutomationStatus = (tenant: string) => call<Status>('rpc_delivery_automation_status', { p_tenant_id: tenant });
export async function companyAutomationHealth(tenant: string): Promise<AutomationHealth> {
    const data = await companyAutomationStatus(tenant); const last = data.runs[0];
    return {
        scheduler_contract_status: 'release_pending', scheduler_enabled: false, jobs: [],
        rules_enabled: data.rules.filter((r) => r.is_enabled).length, last_digest_run: null,
        last_automation_run: last ? {
            id: last.id, run_type: 'manual', started_at: last.evaluated_at, completed_at: last.evaluated_at,
            status: 'completed', candidate_count: last.outcome.candidates, created_count: last.outcome.created,
            updated_count: last.outcome.updated, resolved_count: last.outcome.resolved, escalated_count: last.outcome.escalated, error_code: null,
        } : null,
    };
}
export async function evaluateCompanyAutomations(tenant: string): Promise<AutomationEvaluation> {
    const user = useAuthStore.getState().context?.user_id;
    if (!user) throw new Error('No hay una identidad autorizada.');
    return scopedResponse(async () => {
        const scope = await call<{ id: string }>('rpc_delivery_prepare_automation', {
            p_tenant_id: tenant, p_request_id: crypto.randomUUID(), p_recipient_ids: [user],
        });
        return call<AutomationEvaluation>('rpc_delivery_run_automation', { p_tenant_id: tenant, p_scope_id: scope.id, p_request_id: crypto.randomUUID() });
    });
}
export const updateCompanyAutomation = (tenant: string, rule: string, payload: AutomationRuleUpdate) => call('rpc_delivery_update_automation', {
    p_tenant_id: tenant, p_rule_id: rule, p_payload: payload,
});
