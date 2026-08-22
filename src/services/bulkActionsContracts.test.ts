import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const operations=readFileSync('src/pages/OperationsPage.tsx','utf8'); const documents=readFileSync('src/pages/DocumentsPage.tsx','utf8'); const finance=readFileSync('src/pages/FinancePage.tsx','utf8'); const quotes=readFileSync('src/components/commercial/QuoteWorkspace.tsx','utf8');
for(const source of [operations,documents,finance,quotes]) assert.ok(source.includes('BulkActionBar'),'Each F6 target workspace needs reusable selection actions');
assert.ok(operations.includes("bulkUpdateOperations")&&operations.includes("'set_priority'")&&operations.includes("'add_note'"),'Operations safe bulk mutations missing');
assert.ok(!documents.includes('bulkUpdate')&&documents.includes('Exportar metadatos'),'Documents bulk action must remain metadata export only');
assert.ok(finance.includes('Exportar selección')&&!finance.includes('bulkUpdateOperations'),'Finance bulk action must remain export/summarize only');
const quoteExport=quotes.slice(quotes.indexOf('const exportSelected'),quotes.indexOf('return (')); assert.ok(quoteExport.includes('customer_safe_selected')&&!quoteExport.includes('provider_cost_amount')&&!quoteExport.includes('margin:'),'Quote bulk export must not leak provider cost or margin');
for(const source of [operations,documents,finance,quotes]) assert.ok(source.includes('recordDataAction'),'Bulk exports/actions must be audited');
