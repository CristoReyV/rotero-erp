import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const palette=readFileSync(new URL('../components/productivity/GlobalCommandPalette.tsx',import.meta.url),'utf8');
const saved=readFileSync(new URL('../components/productivity/SavedViewsMenu.tsx',import.meta.url),'utf8');
const operations=readFileSync(new URL('../pages/OperationsPage.tsx',import.meta.url),'utf8');
const operationPanel=readFileSync(new URL('../components/operations/Operation360Panel.tsx',import.meta.url),'utf8');
const commercial=readFileSync(new URL('../pages/CommercialPage.tsx',import.meta.url),'utf8');
const quotes=readFileSync(new URL('../components/commercial/QuoteWorkspace.tsx',import.meta.url),'utf8');
const documents=readFileSync(new URL('../pages/DocumentsPage.tsx',import.meta.url),'utf8');
const finance=readFileSync(new URL('../pages/FinancePage.tsx',import.meta.url),'utf8');
const customers=readFileSync(new URL('../components/commercial/CustomerDirectory.tsx',import.meta.url),'utf8');
const providers=readFileSync(new URL('../components/commercial/ProviderDirectory.tsx',import.meta.url),'utf8');

for(const key of ['ArrowDown','ArrowUp','Enter','Escape'])assert.ok(palette.includes(`'${key}'`),`Palette requires ${key}`);
assert.ok(palette.includes("metaKey")&&palette.includes("ctrlKey")&&palette.includes("'k'"),'Palette requires Ctrl/Cmd+K');
const financeActions=palette.slice(palette.indexOf('const financeActions'),palette.indexOf('export function'));
assert.ok(!financeActions.includes('/commercial'),'Finance palette must not expose Commercial');
assert.ok(saved.includes('saveView')&&saved.includes('deleteSavedView')&&saved.includes('rename')&&saved.includes('makeDefault'),'Saved views must support CRUD/default');
assert.ok(operations.includes("searchParams.get('operationId')")&&operations.includes("searchParams.get('tab')"),'Operations must consume exact deep links');
assert.ok(operationPanel.includes('initialTab')&&operationPanel.includes('onTabChange'),'Operation 360 tab must reflect URL state');
assert.ok(commercial.includes("params.get('dealId')"),'Commercial must consume deal deep links');
assert.ok(commercial.includes("params.get('customerId')")&&customers.includes('requestedCustomerId'),'Customers must consume exact deep links');
assert.ok(commercial.includes("params.get('providerId')")&&providers.includes('requestedProviderId'),'Providers must consume exact deep links');
assert.ok(customers.includes('createRequested')&&providers.includes('createRequested'),'Commercial create actions must open canonical forms');
assert.ok(quotes.includes("params.get('quoteId')"),'Quotes must consume quote deep links');
assert.ok(documents.includes("params.get('fileId')")&&documents.includes("params.get('entityId')"),'Documents must consume file/entity deep links');
assert.ok(finance.includes("params.get('invoiceId')"),'Finance must consume invoice deep links');
for(const source of [operations,commercial,documents,finance])assert.ok(source.includes('SavedViewsMenu'),'All four F5 modules must expose saved views');
