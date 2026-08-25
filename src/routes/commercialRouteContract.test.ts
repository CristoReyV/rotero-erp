import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('./router.tsx', import.meta.url), 'utf8');
const adminGuard = source.indexOf("allowedRoles={['admin']}");
const commercialRoute = source.indexOf("{ path: 'commercial', element: page(<CommercialPage />) }");
const publicTrackingRoute = source.indexOf("path: '/t/:token'");
const driverTrackingRoute = source.indexOf("path: '/driver/:token'");

assert.ok(adminGuard >= 0, 'Commercial must remain inside the ROTERO Admin guard');
assert.ok(commercialRoute > adminGuard, 'Commercial route must follow the Admin-only guard');
assert.equal(source.match(/path: 'commercial'/g)?.length, 1, 'Commercial must expose one canonical ERP route');
assert.ok(publicTrackingRoute > commercialRoute, 'Public Tracking route must remain outside the ERP Commercial branch');
assert.ok(driverTrackingRoute > publicTrackingRoute, 'Driver capability route must remain preserved');
