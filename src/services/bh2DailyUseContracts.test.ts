import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createNotificationCenter } from './notificationCenter';
import type { NotificationFeed } from '../types/executive';

const read=(path:string)=>readFileSync(new URL(`../../${path}`,import.meta.url),'utf8');
const migration=read('supabase/migrations/20260902000000_bh2_daily_use_hardening.sql');
const partner=read('src/components/commercial/Partner360Panel.tsx');
const notifications=read('src/components/productivity/NotificationCenter.tsx');
const palette=read('src/components/productivity/GlobalCommandPalette.tsx');
const rates=read('src/services/rates.service.ts');
const saved=read('src/components/productivity/SavedViewsMenu.tsx');

assert.match(migration,/rpc_list_partner_history_page/);
assert.match(migration,/\(d\.created_at,d\.id\)<\(v_at,v_id\)/);
assert.match(migration,/p_cursor->>'tenant_id'.*p_tenant_id::text/s);
assert.match(migration,/private\.bh2_business_date/);
assert.match(migration,/FOR UPDATE/);
assert.doesNotMatch(migration,/SQLERRM/);
assert.match(rates,/p_history_type: historyType/);
assert.match(partner,/Cargar más/);
assert.match(partner,/partnerTab/);
assert.match(partner,/requestId/);
assert.match(notifications,/rpc_list_internal_notifications_page|listInternalNotifications/);
// Notification pagination now belongs to the controller; verify its behavior.
let page = 0;
const center = createNotificationCenter({
    list: async () => ({
        items: (page++ === 0 ? [{ id: 'one' }] : [{ id: 'one' }, { id: 'two' }]),
        unread_count: 1, has_more: true,
        next_cursor: { tenant_id: 'test-tenant', user_id: 'test-user', unread_only: false, first_seen_at: '2026-10-14T00:00:00Z', id: 'one' },
    } as NotificationFeed),
    markRead: async () => { throw new Error('Unexpected automatic write'); },
    dismiss: async () => { throw new Error('Unexpected automatic write'); },
});
center.setScope({ tenantId: 'test-tenant', userId: 'test-user', role: 'admin' });
await center.load();
await center.load(true);
assert.deepEqual(center.getSnapshot().items.map(item => item.id), ['one', 'two']);
center.setScope(null);
assert.match(palette,/searchRequest/);
assert.match(saved,/filters/);
assert.doesNotMatch(saved,/cursor|next_cursor/);
for(const file of ['src/components/commercial/RateWorkspace.tsx','src/components/commercial/QuoteWorkspace.tsx','src/components/commercial/CustomerDirectory.tsx','src/components/commercial/ProviderDirectory.tsx','src/pages/DocumentsPage.tsx'])assert.match(read(file),/useDebouncedValue/);
console.log('BH2 frontend pagination/state contracts passed');
