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
const attention = read('src/components/executive/AttentionCenter.tsx');
const recentActivity = read('src/components/executive/RecentActivity.tsx');
const paymentDrawer = read('src/components/finance/PaymentDrawer.tsx');
const operationsTable = read('src/components/operations/OperationsTable.tsx');
const operationReadiness = read('src/components/operations/OperationReadiness.tsx');
const operationDocuments = read('src/components/operations/OperationDocuments.tsx');
const operationExecution = read('src/components/operations/OperationExecution.tsx');
const semanticPanel = read('src/components/SemanticPanel.tsx');
const billing = read('src/pages/BillingPage.tsx');
const finance = read('src/pages/FinancePage.tsx');
const claims = read('src/pages/ClaimsPage.tsx');
const claimDetail = read('src/components/claims/ClaimDetail.tsx');
const documents = read('src/pages/DocumentsPage.tsx');
const nav = read('src/constants/nav.ts');

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

for (const source of [attention, recentActivity]) {
    assert.match(source, /min-w-0 max-w-full overflow-hidden/);
    assert.match(source, /break-words/);
}
assert.match(attention, /active:bg-semantic-neutral-soft/);
assert.match(recentActivity, /overscroll|active:bg-semantic-neutral-soft/);

assert.match(paymentDrawer, /w-full min-w-0 max-w-full/);
assert.match(paymentDrawer, /grid-cols-1[\s\S]*min-\[360px\]:grid-cols-3/);
assert.match(paymentDrawer, /overflow-y-auto overscroll-contain/);

assert.match(operationsTable, /aria-pressed=\{selected\}/);
assert.match(operationsTable, /focus-visible:bg-semantic-neutral-soft/);
assert.doesNotMatch(operationsTable, /active:bg-slate-50/);

for (const tone of ['neutral', 'info', 'success', 'warning', 'danger']) {
    assert.match(semanticPanel, new RegExp(`${tone}:`));
}
assert.match(semanticPanel, /bg-surface-card text-slate-800/);
assert.match(operationReadiness, /SemanticPanel/);
assert.match(operationDocuments, /SemanticPanel/);
assert.match(billing, /SemanticPanel/);
assert.match(finance, /SemanticPanel/);

const renderedUi = [operationReadiness, operationDocuments, operationExecution, billing, claims, claimDetail, documents].join('\n');
for (const internalValue of ['missing_planning_data', 'missing_assignment', 'proof_of_delivery', 'rpc_complete_operation_planning_v2', 'generated_pdf']) {
    assert.doesNotMatch(renderedUi, new RegExp(internalValue), `${internalValue} must not be rendered directly`);
}
assert.match(billing, /formatFiscalMissingFields/);
assert.match(claims, /CLAIM_TYPE_LABELS/);
assert.match(claimDetail, /getClaimEventLabel/);

assert.match(dealDetail, /await moveDeal\(dealId, newStage\)/);
assert.match(dealDetail, /setDeal\(\(current\) => current \? \{ \.\.\.current, stage: newStage \}/);
assert.match(dealDetail, /getDealDetail\(activeTenant, dealId\)/);
assert.match(dealDetail, /await onChanged\(\)/);

assert.match(finance, /title="Finanzas"/);
assert.match(claims, /title="Reclamaciones"/);
assert.match(documents, /title="Documentos"/);
assert.doesNotMatch(nav, /Claims & Customer Service 360|Documents 360|Data Operations 360/);

console.log('MOBILE.1A responsive, semantic, label, and state convergence contracts passed');
