import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const service=readFileSync(new URL('./executive.service.ts',import.meta.url),'utf8');
const dashboard=readFileSync(new URL('../pages/DashboardPage.tsx',import.meta.url),'utf8');
const topbar=readFileSync(new URL('../layout/Topbar.tsx',import.meta.url),'utf8');
const notification=readFileSync(new URL('../components/productivity/NotificationCenter.tsx',import.meta.url),'utf8');
const migration=readFileSync(new URL('../../supabase/migrations/20260825000000_f5_executive_productivity.sql',import.meta.url),'utf8');

for(const rpc of ['rpc_get_executive_dashboard','rpc_list_attention_items','rpc_global_search','rpc_refresh_internal_notifications','rpc_list_internal_notifications','rpc_mark_internal_notifications_read','rpc_dismiss_internal_notification','rpc_list_saved_views','rpc_save_view','rpc_delete_saved_view']){
    assert.ok(service.includes(`'${rpc}'`),`Executive service must consume ${rpc}`);
}
assert.ok(!dashboard.includes('OTIF'), 'Dashboard must not fabricate OTIF');
assert.ok(!dashboard.includes('trend='), 'Dashboard must not fabricate trends');
assert.ok(dashboard.includes("data.commercial&&"), 'Commercial dashboard must be response-gated');
assert.ok(topbar.includes('GlobalCommandPalette')&&topbar.includes('NotificationCenter'),'Topbar must use canonical productivity components');
assert.ok(notification.includes("window.addEventListener('focus'")&&notification.includes('pathname'),'Notifications refresh on focus/navigation');
assert.ok(!notification.includes('setInterval'),'Notification Center must not aggressively poll');
assert.ok(migration.includes("v_role='admin' OR a.module IN ('operations','documents','finance')"),'Finance attention must be backend-filtered');
assert.ok(migration.includes("v_role='admin' AND d.tenant_id=p_tenant_id"),'Commercial search/attention must be Admin-only');
assert.ok(!migration.includes('SQLERRM'),'F5 RPCs must not expose raw SQLERRM');
