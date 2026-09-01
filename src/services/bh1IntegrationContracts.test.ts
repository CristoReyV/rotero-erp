import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root=fileURLToPath(new URL('../..',import.meta.url));
const read=(path:string)=>readFileSync(join(root,path),'utf8');
const files=(directory:string):string[]=>readdirSync(directory).flatMap(name=>{const path=join(directory,name);return statSync(path).isDirectory()?files(path):[path]});

const sources=files(join(root,'src')).filter(path=>/\.(ts|tsx)$/.test(path)&&!path.endsWith('.test.ts')).map(path=>readFileSync(path,'utf8')).join('\n');
const migrations=files(join(root,'supabase','migrations')).filter(path=>path.endsWith('.sql')).map(path=>readFileSync(path,'utf8')).join('\n');
const rpcCalls=[...sources.matchAll(/supabase\.rpc\(['"]([a-zA-Z0-9_]+)['"]/g)].map(match=>match[1]);
const missing=[...new Set(rpcCalls)].filter(name=>!new RegExp(`\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${name}\\b`,'i').test(migrations));
assert.deepEqual(missing,[],'Every active frontend RPC wrapper must resolve to a migration-defined function');

const partner=read('src/components/commercial/Partner360Panel.tsx');
const commercial=read('src/pages/CommercialPage.tsx');
const quote=read('src/components/commercial/QuoteWorkspace.tsx');
const rate=read('src/components/commercial/RateWorkspace.tsx');
const finance=read('src/pages/FinancePage.tsx');
const invoice=read('src/components/finance/FinanceInvoiceDrawer.tsx');
const billing=read('src/pages/BillingPage.tsx');
const claims=read('src/pages/ClaimsPage.tsx');
const router=read('src/routes/router.tsx');

assert.match(partner,/action=.*new-quote/);assert.match(partner,/action=.*new-buy-rate/);assert.match(partner,/\$\{entityType\}Id/);
assert.match(commercial,/requestedCustomerId=\{params\.get\('customerId'\)\}/);assert.match(commercial,/requestedProviderId=\{params\.get\('providerId'\)\}/);
assert.match(quote,/customer_id:typeof customerId==='string'/);assert.match(rate,/provider_id:requestedProviderId/);
assert.match(finance,/customer_id:tab==='ar'/);assert.match(finance,/provider_id:tab==='ap'/);assert.match(finance,/suggestedTerms/);
assert.match(invoice,/operations\?operationId=/);assert.match(invoice,/billing\?cfdiId=/);assert.match(billing,/searchParams\.get\('cfdiId'\)/);
assert.match(claims,/source_incident_id:\s*incidentId\s*\|\|\s*null/);assert.match(claims,/defaultValue=\{operationId/);
assert.ok(!read('src/services/claims.service.ts').includes('window.location'),'Services must receive route context explicitly');
assert.match(router,/lazy\(\(\)=>import/);assert.match(router,/Suspense/);

const bh1=read('supabase/migrations/20260831000000_bh1_integration_hardening.sql');
assert.ok(!bh1.includes('SQLERRM'),'BH1 must not expose raw database errors');
for(const role of ['PUBLIC','anon','service_role'])assert.ok(bh1.includes(role),`BH1 ACL must address ${role}`);
console.log(`BH1 frontend/RPC/deep-link contracts passed (${new Set(rpcCalls).size} active RPC names)`);
