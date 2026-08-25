import assert from'node:assert/strict';import{readFileSync}from'node:fs';
const page=readFileSync(new URL('../pages/CommercialPage.tsx',import.meta.url),'utf8');const roles=readFileSync(new URL('../constants/roles.ts',import.meta.url),'utf8');
assert.ok(page.includes("'compliance'")&&page.includes('ComplianceWorkspace')&&page.includes("params.get('partnerId')"),'F9 deep-link consumer missing');
assert.ok(page.includes("requestedPartnerType={params.get('partnerType')}")&&page.includes("requestedTab={params.get('tab')}"),'F9 exact context params missing');
assert.ok(!roles.includes("finance: ['/commercial")&&!roles.includes("finance:['/commercial"),'Finance Commercial access changed');
