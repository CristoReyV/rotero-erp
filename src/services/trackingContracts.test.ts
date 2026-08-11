import assert from 'node:assert/strict';
import {
    buildTrackingUrl,
    canManageTracking,
    clearOneTimeTrackingLink,
    createOneTimeTrackingLink,
    filterTrackingTokens,
    getOneTimeCapabilityUrl,
    getTrackingDisplayState,
    normalizeCreateResult,
    normalizeRevokeResult,
    normalizeTrackingList,
} from './trackingContracts';

const NOW = new Date('2026-08-11T12:00:00Z');

const rows = normalizeTrackingList([
    {
        id: 'token-1',
        operation_id: 'operation-1',
        scope: 'public:read',
        state: 'active',
        created_at: '2026-08-10T12:00:00Z',
        expires_at: '2026-08-12T12:00:00Z',
        last_used_at: null,
        reference_code: 'ROT-001',
        route_summary: 'CDMX → Puebla',
        client_display_name: 'Cliente QA',
        operation_status: 'in_transit',
        last_municipality: 'Puebla',
        last_event_at: '2026-08-11T11:00:00Z',
        token: 'must-not-survive-normalization',
        token_hash: 'must-not-survive-normalization',
    },
    {
        id: 'token-2',
        operation_id: 'operation-2',
        scope: 'driver:write',
        state: 'revoked',
        created_at: '2026-08-01T12:00:00Z',
        expires_at: '2026-08-15T12:00:00Z',
        reference_code: 'ROT-002',
    },
    {
        id: 'token-3',
        operation_id: 'operation-3',
        scope: 'public:read',
        state: 'active',
        created_at: '2026-08-01T12:00:00Z',
        expires_at: '2026-08-10T12:00:00Z',
        reference_code: 'ROT-003',
    },
]);

assert.equal(canManageTracking('admin'), true);
assert.equal(canManageTracking('operator'), true);
assert.equal(canManageTracking('viewer'), false);
assert.equal(canManageTracking(null), false);

assert.equal(getTrackingDisplayState(rows[0], NOW), 'active');
assert.equal(getTrackingDisplayState(rows[1], NOW), 'revoked');
assert.equal(getTrackingDisplayState(rows[2], NOW), 'expired');

assert.equal('token' in rows[0], false);
assert.equal('token_hash' in rows[0], false);
assert.deepEqual(filterTrackingTokens(rows, 'ROT-001', 'all', NOW).map((row) => row.id), ['token-1']);
assert.deepEqual(filterTrackingTokens(rows, '', 'driver', NOW).map((row) => row.id), ['token-2']);
assert.deepEqual(filterTrackingTokens(rows, '', 'expired', NOW).map((row) => row.id), ['token-3']);

const created = normalizeCreateResult({
    token_id: 'created-id',
    token: 'literal-once',
    scope: 'public:read',
    expires_at: '2026-08-12T12:00:00Z',
    rotated_previous: false,
    already_existed: false,
});
assert.equal(created.kind, 'created');

const oneTime = createOneTimeTrackingLink(created, 'https://staging.example/');
assert.deepEqual(oneTime, {
    tokenId: 'created-id',
    scope: 'public:read',
    link: 'https://staging.example/t/literal-once',
    expiresAt: '2026-08-12T12:00:00Z',
    rotatedPrevious: false,
});
assert.equal(oneTime && 'token' in oneTime, false);
assert.equal(getOneTimeCapabilityUrl(oneTime), oneTime?.link);
assert.equal(getOneTimeCapabilityUrl(null), null);
assert.equal(clearOneTimeTrackingLink(), null);

const rotated = normalizeCreateResult({
    token_id: 'rotated-id',
    token: 'rotated-literal',
    scope: 'driver:write',
    expires_at: '2026-08-12T12:00:00Z',
    rotated_previous: true,
    already_existed: false,
});
assert.equal(rotated.kind, 'created');
assert.equal(rotated.kind === 'created' && rotated.rotatedPrevious, true);
assert.equal(buildTrackingUrl('https://staging.example', 'driver:write', 'driver-token'), 'https://staging.example/driver/driver-token');

const existing = normalizeCreateResult({
    token_id: 'existing-id',
    scope: 'public:read',
    expires_at: '2026-08-12T12:00:00Z',
    already_existed: true,
});
assert.equal(existing.kind, 'existing');
assert.equal(createOneTimeTrackingLink(existing, 'https://staging.example'), null);
assert.equal(getOneTimeCapabilityUrl(createOneTimeTrackingLink(existing, 'https://staging.example')), null);

assert.deepEqual(normalizeRevokeResult({ success: true, status: 'revoked' }), { success: true, status: 'revoked' });
assert.deepEqual(normalizeRevokeResult({ success: true, status: 'already_revoked' }), { success: true, status: 'already_revoked' });
