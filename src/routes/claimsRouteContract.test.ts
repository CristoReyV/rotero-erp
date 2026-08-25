import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
const router=readFileSync('src/routes/router.tsx','utf8'),nav=readFileSync('src/constants/nav.ts','utf8'),roles=readFileSync('src/constants/roles.ts','utf8'),modules=readFileSync('src/types/modules.ts','utf8'),palette=readFileSync('src/components/productivity/GlobalCommandPalette.tsx','utf8');
assert.ok(router.includes("allowedRoles={['admin']}")&&router.includes("path: 'claims'")&&router.includes('<ClaimsPage />'),'claims route must be Admin-only');
assert.ok(nav.includes("path: '/claims'")&&nav.includes("module: 'claims'")&&modules.includes("| 'claims'"),'claims navigation/module missing');
assert.ok(roles.includes("'claims',")&&!roles.match(/finance:\s*\[[^\]]*claims/s),'Finance must not receive claims module');
const finance=palette.slice(palette.indexOf('const financeActions'),palette.indexOf('export function GlobalCommandPalette'));assert.ok(!finance.includes('claim'),'Finance palette must have zero claim action');
console.log('F10 Admin route and Finance isolation contract passed');
