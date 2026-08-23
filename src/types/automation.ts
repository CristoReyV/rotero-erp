import type { AttentionSeverity, ProductivityModule } from '@/types/executive';

export type AutomationTargetRole = 'admin' | 'finance' | 'admin_finance';
export type AutomationThresholdUnit = 'hours' | 'days';

export interface AutomationRule {
    id: string;
    code: string;
    name: string;
    module: ProductivityModule;
    is_enabled: boolean;
    target_role: AutomationTargetRole;
    severity: AttentionSeverity;
    threshold_value: number;
    threshold_unit: AutomationThresholdUnit;
    escalation_delay_value: number;
    escalation_delay_unit: AutomationThresholdUnit;
    escalation_severity: AttentionSeverity;
    digest_enabled: boolean;
    updated_at: string;
}
export type AutomationRuleUpdate = Pick<
    AutomationRule,
    | 'is_enabled'
    | 'target_role'
    | 'severity'
    | 'threshold_value'
    | 'threshold_unit'
    | 'escalation_delay_value'
    | 'escalation_delay_unit'
    | 'escalation_severity'
    | 'digest_enabled'
>;

export interface AutomationRunSummary {
    id: string;
    run_type?: 'manual' | 'scheduled' | 'digest';
    started_at: string;
    completed_at: string | null;
    status: 'running' | 'completed' | 'failed';
    rule_count?: number;
    candidate_count: number;
    created_count?: number;
    updated_count: number;
    resolved_count?: number;
    escalated_count?: number;
    error_code: string | null;
}

export interface AutomationHealth {
    scheduler_contract_status: 'ready' | 'release_pending';
    scheduler_enabled: boolean;
    jobs: Array<{ jobname: string; schedule: string; active: boolean }>;
    rules_enabled: number;
    last_automation_run: AutomationRunSummary | null;
    last_digest_run: AutomationRunSummary | null;
}

export interface AutomationEvaluation {
    success: boolean;
    rules_evaluated: number;
    candidates: number;
    created: number;
    updated: number;
    resolved: number;
    escalated: number;
    business_date: string;
    timezone: string;
}

export interface DailyDigestItem {
    id: string;
    module: ProductivityModule;
    rule_code: string;
    priority: AttentionSeverity;
    title: string;
    body: string;
    route: string;
    entity_type: string;
    entity_id: string;
    first_seen_at: string;
    escalation_level: number;
}

export interface DailyDigest {
    id: string;
    business_date: string;
    timezone: string;
    role: 'admin' | 'finance';
    summary: {
        total: number;
        critical: number;
        high: number;
        operations_blocked: number;
        ar_overdue: number;
        ap_overdue: number;
        documents_missing: number;
        quotes_pending: number;
    };
    items: DailyDigestItem[];
    generated_at: string;
    updated_at: string;
}
