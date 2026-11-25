import test from 'node:test';
import assert from 'node:assert/strict';
import {
    assertValidatedFiscalRoute,
    dispatchFiscal,
    FISCAL_PROFILES,
    type FiscalOrigin,
    type FiscalSelection,
    selectFiscalRoute,
} from './fiscal-routing.ts';

const fact: FiscalOrigin = {
    billingCfdiId: 'synthetic-canonical-CFDI',
    companyId: 'synthetic-A',
    providerCode: 'facturama',
    environment: 'sandbox',
    credentialProfile: 'facturama_sandbox_lab_v1',
};
const soft: FiscalOrigin = {
    billingCfdiId: 'synthetic-canonical-CFDI',
    companyId: 'synthetic-A',
    providerCode: 'soft_management',
    environment: 'sandbox',
    credentialProfile: 'soft_management_sandbox_v1',
};
const selected = (origin: FiscalOrigin, enabled = true): FiscalSelection => ({ ...origin, enabled });

test('origin wins for historical status/cancel/download after future selection changes', async () => {
    const calls: string[] = [];
    for (const action of ['status', 'cancel', 'fetch_xml', 'fetch_pdf'] as const) {
        await dispatchFiscal({
            action,
            origin: fact,
            selection: selected(soft, false),
            claimStamp: async () => {
                assert.fail('read/cancel must not create a stamp lane');
            },
            transport: async (route) => {
                calls.push(route.providerCode);
            },
        });
        assert.deepEqual(selectFiscalRoute(action, soft, selected(fact)), soft);
    }
    assert.deepEqual(calls, ['facturama', 'facturama', 'facturama', 'facturama']);
});

test('Softmanagement remains available but all transports unvalidated and inactive', async () => {
    let calls = 0;
    for (const environment of ['sandbox', 'production'] as const) {
        const origin = { ...soft, environment, credentialProfile: `soft_management_${environment}_v1` };
        for (const action of ['stamp', 'status', 'cancel', 'fetch_xml', 'fetch_pdf'] as const) {
            await assert.rejects(
                dispatchFiscal({
                    action,
                    origin,
                    selection: selected(origin),
                    claimStamp: async () => {
                        calls++;
                    },
                    transport: async () => {
                        calls++;
                    },
                }),
                /provider_pending_validation/,
            );
        }
    }
    assert.equal(calls, 0);
    assert.equal(FISCAL_PROFILES.soft_management_sandbox_v1.baseUrl, null);
    assert.deepEqual(FISCAL_PROFILES.soft_management_sandbox_v1.actions, []);
});

test('selection is not enablement; company, profile and environment cannot be substituted', async () => {
    const noTransport = async () => {
        assert.fail('transport must stay closed');
    };
    for (
        const selection of [
            null,
            selected(fact, false),
            selected(soft),
            selected({ ...fact, companyId: 'other' }),
        ]
    ) {
        await assert.rejects(
            dispatchFiscal({
                action: 'stamp',
                origin: fact,
                selection,
                claimStamp: noTransport,
                transport: noTransport,
            }),
        );
    }
    assert.throws(
        () => assertValidatedFiscalRoute({ ...fact, environment: 'production' }, 'stamp'),
        /origin_conflict/,
    );
    assert.throws(
        () =>
            assertValidatedFiscalRoute({ ...fact, credentialProfile: 'https://arbitrary.invalid' }, 'status'),
        /origin_conflict/,
    );
    assert.throws(() => selectFiscalRoute('status', null, selected(fact)), /origin_required/);
});

test('stamp claims before transport; timeout retains uncertainty and never falls back', async () => {
    const order: string[] = [];
    await assert.rejects(
        dispatchFiscal({
            action: 'stamp',
            origin: fact,
            selection: selected(fact),
            claimStamp: async () => {
                order.push('claim');
            },
            transport: async (route) => {
                order.push(route.providerCode);
                throw new Error('synthetic_timeout');
            },
        }),
        /synthetic_timeout/,
    );
    assert.deepEqual(order, ['claim', 'facturama']);
    await assert.rejects(
        dispatchFiscal({
            action: 'stamp',
            origin: fact,
            selection: selected(fact),
            claimStamp: async () => {
                throw new Error('fiscal_reconciliation_required');
            },
            transport: async () => {
                assert.fail('no second send');
            },
        }),
        /reconciliation_required/,
    );
});

test('two providers cannot claim the same local operation; real SQL concurrency has its own suite', async () => {
    const lanes = new Set<string>();
    let sent = 0;
    const stamp = () =>
        dispatchFiscal({
            action: 'stamp',
            origin: fact,
            selection: selected(fact),
            claimStamp: async (origin) => {
                if (lanes.has(origin.billingCfdiId)) throw new Error('fiscal_reconciliation_required');
                lanes.add(origin.billingCfdiId);
            },
            transport: async () => {
                sent++;
            },
        });
    const outcomes = await Promise.allSettled([stamp(), stamp()]);
    assert.equal(outcomes.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal(sent, 1);
    // An alternate provider is neither an alternate operation key nor a retry.
    assert.throws(() => selectFiscalRoute('stamp', fact, selected(soft)), /origin_conflict/);
});
