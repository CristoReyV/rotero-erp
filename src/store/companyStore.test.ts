import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import {
    type AuthorizedCompany,
    companyHeaders,
    hasCompanyCapability,
    scopedResponse,
    useCompanyStore,
} from './companyStore';

const a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const company = (id: string, caps: string[] = [], rfc = 'AAA010101AA1'): AuthorizedCompany => ({
    id,
    display_name: id === a ? 'A' : 'B',
    legal_name: 'Synthetic only',
    rfc,
    capabilities: caps,
});
beforeEach(() => useCompanyStore.getState().reset('tenant'));

test('selection requires explicit authorization; access alone grants no capabilities', () => {
    useCompanyStore.getState().accept('tenant', [company(a), company(b)]);
    assert.deepEqual(useCompanyStore.getState().selectedIds, []);
    useCompanyStore.getState().select('unknown');
    assert.deepEqual(companyHeaders(), { 'x-rotero-scope': 'required' });
    useCompanyStore.getState().select(a);
    assert.equal(hasCompanyCapability('financial.full.read'), false);
    assert.deepEqual(companyHeaders(), { 'x-rotero-scope': 'company', 'x-rotero-company-id': a });
});

test('ROTERO preference is applied only to an authorized returned company', () => {
    useCompanyStore.getState().accept('tenant', [company(a, [], 'WLS110325JH8'), company(b)]);
    assert.deepEqual(useCompanyStore.getState().selectedIds, [a]);
    useCompanyStore.getState().accept('tenant', [company(b)]);
    assert.deepEqual(
        useCompanyStore.getState().selectedIds,
        [],
        'revocation does not silently switch companies',
    );
});

test('a sole authorized company can be selected initially; refresh revokes capability and changes epoch', () => {
    useCompanyStore.getState().accept('tenant', [company(a, ['operations.read'])]);
    assert.equal(hasCompanyCapability('operations.read'), true);
    const epoch = useCompanyStore.getState().epoch;
    useCompanyStore.getState().accept('tenant', [company(a, [])]);
    assert.equal(hasCompanyCapability('operations.read'), false);
    assert.ok(useCompanyStore.getState().epoch > epoch);
});

test('consolidation is an explicit authorized set; removing a member clears the whole set', () => {
    const companies = [company(a, ['financial.full.read']), company(b, ['financial.full.read'])];
    useCompanyStore.getState().accept('tenant', companies);
    useCompanyStore.getState().selectConsolidation([a, b]);
    assert.deepEqual(useCompanyStore.getState().selectedIds, []);
    useCompanyStore.getState().accept('tenant', companies, [[b, a]]);
    useCompanyStore.getState().selectConsolidation([b, a]);
    assert.equal(useCompanyStore.getState().mode, 'consolidated');
    assert.equal(companyHeaders()['x-rotero-company-ids'], JSON.stringify([a, b]));
    useCompanyStore.getState().accept('tenant', [companies[0]], []);
    assert.deepEqual(useCompanyStore.getState().selectedIds, []);
    assert.equal(hasCompanyCapability('financial.full.read'), false);
});

test('late network and file promises cannot survive company changes or logout reset', async () => {
    useCompanyStore.getState().accept('tenant', [company(a), company(b)]);
    useCompanyStore.getState().select(a);
    let resolve!: (data: string) => void;
    const late = scopedResponse(() =>
        new Promise<string>((done) => {
            resolve = done;
        })
    );
    useCompanyStore.getState().select(b);
    resolve('OLD-COMPANY');
    await assert.rejects(late, /company_context_changed/);
    const afterLogout = scopedResponse(() =>
        new Promise<string>((done) => {
            resolve = done;
        })
    );
    useCompanyStore.getState().reset();
    resolve('OLD-USER');
    await assert.rejects(afterLogout, /company_context_changed/);
});

test('failed bootstrap and stale tenant responses have no legacy fallback', () => {
    useCompanyStore.getState().accept('wrong-tenant', [company(a, ['financial.full.read'])]);
    assert.deepEqual(useCompanyStore.getState().selectedIds, []);
    useCompanyStore.getState().accept('tenant', [company(a, ['operations.read'])]);
    useCompanyStore.getState().fail();
    assert.equal(useCompanyStore.getState().phase, 'error');
    assert.deepEqual(companyHeaders(), { 'x-rotero-scope': 'required' });
    assert.equal(hasCompanyCapability('operations.read'), false);
});
