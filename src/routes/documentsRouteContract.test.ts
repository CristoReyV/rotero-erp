import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { canProductRoleAccessModule, canProductRoleManageModule } from '@/constants/roles';

const router = readFileSync('src/routes/router.tsx', 'utf8');
const nav = readFileSync('src/constants/nav.ts', 'utf8');
assert.match(router, /path: 'documents', element: page\(<DocumentsPage \/>\)/);
assert.match(nav, /path: '\/documents'.*module: 'documents'/);
assert.equal(canProductRoleAccessModule('admin', 'documents'), true);
assert.equal(canProductRoleAccessModule('finance', 'documents'), true);
assert.equal(canProductRoleManageModule('finance', 'documents'), true);
assert.equal(canProductRoleAccessModule('operator', 'documents'), true);
assert.equal(canProductRoleManageModule('viewer', 'documents'), false);

const publicTracking = router.indexOf("path: '/t/:token'");
const documents = router.indexOf("path: 'documents'");
assert.ok(documents > 0 && publicTracking > documents, 'Documents must remain inside authenticated ERP routes');
