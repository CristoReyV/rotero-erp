import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const service=readFileSync(new URL('./automation.service.ts',import.meta.url),'utf8');
const page=readFileSync(new URL('../pages/AutomationsPage.tsx',import.meta.url),'utf8');
const dashboard=readFileSync(new URL('../pages/DashboardPage.tsx',import.meta.url),'utf8');
const digest=readFileSync(new URL('../components/productivity/DailyDigestCard.tsx',import.meta.url),'utf8');
const notifications=readFileSync(new URL('../components/productivity/NotificationCenter.tsx',import.meta.url),'utf8');
const router=readFileSync(new URL('../routes/router.tsx',import.meta.url),'utf8');
const security=readFileSync(new URL('../pages/SecurityPage.tsx',import.meta.url),'utf8');
const migration=readFileSync(new URL('../../supabase/migrations/20260827000000_f7_automations.sql',import.meta.url),'utf8');

for(const rpc of [
    'rpc_list_automation_rules','rpc_update_automation_rule','rpc_evaluate_automations',
    'rpc_get_automation_health','rpc_get_daily_digest',
]){
    assert.ok(service.includes("'" + rpc + "'"),'Automation service must consume ' + rpc);
}
assert.ok(page.includes('Evaluar ahora')&&page.includes('Pendiente de activar en release'),'Admin page must expose truthful health and manual evaluation');
assert.ok(page.includes('escalation_delay_value')&&page.includes('digest_enabled'),'Admin page must use friendly escalation/digest controls');
assert.ok(!page.includes('<textarea')&&!page.includes('JSON.stringify'),'Rule configuration must not expose a raw JSON editor');
assert.ok(router.includes("path: 'automations'")&&router.includes('<AutomationsPage />'),'Automation route must exist');
assert.ok(security.includes('/security/automations')&&security.includes('Automatizaciones'),'Admin navigation must expose Automations');
assert.ok(dashboard.includes('DailyDigestCard'),'Dashboard must integrate the canonical digest');
assert.ok(digest.includes("digest.role === 'admin'"),'Commercial digest totals must be Admin-gated');
for(const label of ['Todo','Crítico','Operaciones','Finanzas','Documentos','Comercial','Automatizadas']){
    assert.ok(notifications.includes(label),'Notification filter missing: ' + label);
}
assert.ok(notifications.includes("role==='admin'"),'Commercial notification filter must be Admin-only');
assert.ok(notifications.includes('item.is_automated')&&notifications.includes('item.escalation_level'),'Notification Center must display automation provenance');
assert.ok(!notifications.includes('setInterval'),'Notification Center must not aggressively poll');
assert.ok(migration.includes("CREATE EXTENSION IF NOT EXISTS pg_cron"),'F7 migration must install verified pg_cron');
assert.ok(migration.includes("'0 * * * *'")&&migration.includes("'15 12 * * *'"),'F7 cron schedules must be hourly/daily');
assert.ok(!migration.match(/http_request|net\.http|vault\.|supabase_functions/i),'F7 scheduler must not call network, Vault, or Edge');
assert.ok(!migration.includes('SQLERRM'),'F7 public contracts must not expose SQLERRM');
