import { supabase } from '@/lib/supabase';
import type {
    AutomationEvaluation,
    AutomationHealth,
    AutomationRule,
    AutomationRuleUpdate,
    DailyDigest,
} from '@/types/automation';

function assertResult<T>(data: unknown, error: { message: string } | null): T {
    if (error) throw new Error(error.message);
    if (data && typeof data === 'object' && 'error' in data) {
        throw new Error(String((data as { error: unknown }).error));
    }
    return data as T;
}
export async function listAutomationRules(tenantId: string): Promise<AutomationRule[]> {
    const { data, error } = await supabase.rpc('rpc_list_automation_rules', { p_tenant_id: tenantId });
    return assertResult<{ items: AutomationRule[] }>(data, error).items;
}

export async function updateAutomationRule(
    tenantId: string,
    ruleId: string,
    payload: AutomationRuleUpdate,
): Promise<AutomationRule> {
    const { data, error } = await supabase.rpc('rpc_update_automation_rule', {
        p_tenant_id: tenantId,
        p_rule_id: ruleId,
        p_payload: payload,
    });
    return assertResult<AutomationRule>(data, error);
}

export async function evaluateAutomations(tenantId: string): Promise<AutomationEvaluation> {
    const { data, error } = await supabase.rpc('rpc_evaluate_automations', { p_tenant_id: tenantId });
    return assertResult<AutomationEvaluation>(data, error);
}

export async function getAutomationHealth(tenantId: string): Promise<AutomationHealth> {
    const { data, error } = await supabase.rpc('rpc_get_automation_health', { p_tenant_id: tenantId });
    return assertResult<AutomationHealth>(data, error);
}

export async function getDailyDigest(tenantId: string): Promise<{
    digest: DailyDigest | null;
    business_date: string;
    timezone: string;
}> {
    const { data, error } = await supabase.rpc('rpc_get_daily_digest', { p_tenant_id: tenantId });
    return assertResult(data, error);
}
