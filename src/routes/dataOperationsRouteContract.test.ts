import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { canProductRoleAccessModule, canProductRoleManageModule } from '@/constants/roles';

const router=readFileSync('src/routes/router.tsx','utf8'); const nav=readFileSync('src/constants/nav.ts','utf8'); const palette=readFileSync('src/components/productivity/GlobalCommandPalette.tsx','utf8');
assert.match(router,/path: 'data', element: page\(<DataOperationsPage \/>\)/); assert.match(nav,/path: '\/data'.*module: 'data'/);
assert.equal(canProductRoleAccessModule('admin','data'),true); assert.equal(canProductRoleManageModule('admin','data'),true);
for(const role of ['finance','operator','viewer'] as const){assert.equal(canProductRoleAccessModule(role,'data'),false);assert.equal(canProductRoleManageModule(role,'data'),false);}
const dataRoute=router.indexOf("path: 'data'"); const publicTracking=router.indexOf("path: '/t/:token'"); assert.ok(dataRoute>0&&publicTracking>dataRoute,'Data workspace must remain behind authenticated Admin guard');
for(const route of ['/data?view=import&entity=customers','/data?view=import&entity=providers','/data?view=import&entity=operations','/data?view=export']) assert.ok(palette.includes(route),`Palette deep link missing ${route}`);
const financeActions=palette.slice(palette.indexOf('const financeActions'),palette.indexOf('export function')); assert.ok(!financeActions.includes('/data'),'Finance palette must not expose Admin Data workspace');
