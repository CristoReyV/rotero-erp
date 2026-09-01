import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path: string) => readFileSync(path, 'utf8');
const appLayout = read('src/layout/AppLayout.tsx');
const styles = read('src/index.css');
const accounts = read('src/components/finance/AccountsWorkspace.tsx');
const financeDetail = read('src/components/finance/FinanceInvoiceDrawer.tsx');
const savedViews = read('src/components/productivity/SavedViewsMenu.tsx');
const notifications = read('src/components/productivity/NotificationCenter.tsx');
const mobileSheet = read('src/components/MobileSheet.tsx');
const commercial = read('src/pages/CommercialPage.tsx');
const dealDetail = read('src/components/commercial/DealDetailDrawer.tsx');

assert.match(appLayout, /min-w-0 max-w-full/);
assert.match(appLayout, /overflow-x-clip/);
assert.doesNotMatch(styles, /body\s*\{[^}]*overflow-x:\s*(hidden|clip)/s, 'Global body overflow must not mask a broken child layout');
assert.match(styles, /#root[\s\S]*max-width:\s*100%/);
assert.match(styles, /\.dark \.text-slate-500 \{ color: #a8b5c7; \}/);

assert.match(accounts, /data-finance-mobile-cards/);
assert.match(accounts, /data-finance-desktop-table/);
assert.match(accounts, /isMobile \? <div className="divide-y" data-finance-mobile-cards>/);
assert.match(accounts, /: <div className="overflow-x-auto" data-finance-desktop-table>/);
assert.match(accounts, /bg-surface p-3/);
assert.match(accounts, /onToggleSelected\(invoice\.id\)/, 'Mobile finance cards must preserve bulk selection');

for (const source of [savedViews, notifications]) {
    assert.match(source, /MobileSheet/);
    assert.match(source, /!isMobile/);
}
assert.match(mobileSheet, /createPortal/);
assert.match(mobileSheet, /100dvh/);
assert.match(mobileSheet, /safe-area-inset-bottom/);
assert.match(mobileSheet, /aria-modal="true"/);

assert.match(commercial, /data-commercial-mobile-list/);
assert.match(commercial, /data-commercial-board-container/);
assert.match(commercial, /max-w-full snap-x/);
assert.match(commercial, /overflow-x-auto overscroll-x-contain/);
assert.match(commercial, /isMobile \? 'list' : 'board'/);
assert.doesNotMatch(commercial, /window\.innerWidth/);

for (const source of [financeDetail, dealDetail]) {
    assert.match(source, /h-dvh/);
    assert.match(source, /role="dialog"/);
    assert.match(source, /aria-modal="true"/);
}
