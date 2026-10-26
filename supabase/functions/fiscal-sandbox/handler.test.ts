import test from 'node:test';
import assert from 'node:assert/strict';
import type { SupabaseClient } from '@supabase/supabase-js';
import { ACK_RECOVERY_PENDING_MESSAGE, FacturamaSandbox } from '../_shared/facturama.ts';
import { createFiscalHandler, isFiscalSandboxRuntime, STAGING_SUPABASE_URL } from './handler.ts';

const origin = 'https://rotero-erp-staging.netlify.app';
const id = '70000000-0000-4000-8000-000000000001';
const actor = '70000000-0000-4000-8000-000000000002';
function fixture(authorized = true, identity = true) {
    const calls: { action: string; data: unknown }[] = [];
    let providerCalls = 0, identityCalls = 0;
    const original = Object.freeze({ motive: '02', remote_cancel_status: 'canceled' });
    const admin = {
        async rpc(_name: string, args: Record<string, unknown>) {
            assert.equal(args.p_actor, actor);
            calls.push({ action: String(args.p_action), data: args.p_data });
            return authorized ? { data: original, error: null } : { data: null, error: { code: '42501' } };
        },
    } as unknown as SupabaseClient;
    const handler = createFiscalHandler({
        admin,
        userClient: () =>
            ({
                auth: {
                    async getUser() {
                        identityCalls++;
                        return {
                            data: { user: identity ? { id: actor } : null },
                            error: identity ? null : new Error('synthetic'),
                        };
                    },
                },
            }) as unknown as SupabaseClient,
        adapter: new FacturamaSandbox({
            username: 'synthetic',
            password: 'synthetic',
            environment: 'sandbox',
        }, async () => {
            providerCalls++;
            throw new Error('Provider must not be contacted during recovery');
        }),
    });
    return {
        handler,
        calls,
        original,
        providerCalls: () => providerCalls,
        identityCalls: () => identityCalls,
    };
}
const request = (site = origin, authenticated = true, extra: Record<string, unknown> = {}) =>
    new Request('https://synthetic.invalid/fiscal-sandbox', {
        method: 'POST',
        headers: {
            origin: site,
            'content-type': 'application/json',
            ...(authenticated ? { Authorization: 'Bearer synthetic' } : {}),
        },
        body: JSON.stringify({ cfdiId: id, action: 'cancel', motive: '03', recoverAck: true, ...extra }),
    });

test('exact staging origin supports preflight and read-authorized direct recovery stays blocked', async () => {
    const f = fixture();
    const preflight = await f.handler(
        new Request('https://synthetic.invalid', { method: 'OPTIONS', headers: { origin } }),
    );
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
    const r = await f.handler(request());
    assert.equal(r.status, 409);
    assert.equal(r.headers.get('access-control-allow-origin'), origin);
    assert.deepEqual(await r.json(), {
        error: 'ack_recovery_unavailable',
        uncertain: false,
        validationFields: [],
        message: ACK_RECOVERY_PENDING_MESSAGE,
    });
    assert.deepEqual(f.calls, [{ action: 'load', data: {} }]);
    assert.equal(f.providerCalls(), 0);
    assert.deepEqual(f.original, { motive: '02', remote_cancel_status: 'canceled' });
});
test('lookalike domains, HTTP staging and other Netlify sites never reach identity or worker', async () => {
    for (
        const site of [
            'http://rotero-erp-staging.netlify.app',
            'https://rotero-erp-staging.netlify.app.evil.test',
            'https://rotero-erp-staging.netlify.app/',
            'https://main--rotero-erp-staging.netlify.app',
            'https://other.netlify.app',
            'http://deploy-preview-46--rotero-erp-staging.netlify.app',
            'https://deploy-preview-46--other.netlify.app',
        ]
    ) {
        const f = fixture();
        for (const method of ['POST', 'OPTIONS']) {
            const r = await f.handler(
                method === 'POST'
                    ? request(site)
                    : new Request('https://synthetic.invalid', { method, headers: { origin: site } }),
            );
            assert.equal(r.status, 403, site);
            assert.equal(r.headers.get('access-control-allow-origin'), null);
        }
        assert.equal(f.identityCalls(), 0);
        assert.equal(f.calls.length, 0);
    }
});
test('existing preview and loopback origins remain narrow and authorized', async () => {
    for (
        const site of [
            'https://deploy-preview-46--rotero-erp-staging.netlify.app',
            'http://127.0.0.1:32000',
            'http://localhost:32000',
        ]
    ) {
        const f = fixture();
        const r = await f.handler(request(site));
        assert.equal(r.status, 409);
        assert.equal(r.headers.get('access-control-allow-origin'), site);
        assert.equal(f.providerCalls(), 0);
    }
});
test('CORS permission never substitutes identity or current company capability', async () => {
    const absent = fixture();
    assert.equal((await absent.handler(request(origin, false))).status, 401);
    assert.equal(absent.calls.length, 0);
    const invalid = fixture(true, false);
    assert.equal((await invalid.handler(request())).status, 401);
    assert.equal(invalid.calls.length, 0);
    const denied = fixture(false);
    assert.equal((await denied.handler(request())).status, 403);
    assert.equal(denied.providerCalls(), 0);
});
test('a direct request cannot reinterpret a non-boolean recovery flag as initial cancellation', async () => {
    for (const recoverAck of ['true', 'false', 1, {}]) {
        const f = fixture();
        assert.equal((await f.handler(request(origin, true, { recoverAck }))).status, 400);
        assert.equal(f.calls.length, 0);
        assert.equal(f.providerCalls(), 0);
    }
});
test('runtime configuration remains exclusively enabled sandbox on the exact staging project', () => {
    const valid = { enabled: 'true', environment: 'sandbox', supabaseUrl: STAGING_SUPABASE_URL };
    assert.equal(isFiscalSandboxRuntime(valid), true);
    for (
        const config of [
            { ...valid, enabled: 'false' },
            { ...valid, environment: 'production' },
            { ...valid, supabaseUrl: 'https://other.supabase.co' },
            { ...valid, supabaseUrl: STAGING_SUPABASE_URL + '.evil.test' },
            {},
        ]
    ) {
        assert.equal(isFiscalSandboxRuntime(config), false);
    }
});
