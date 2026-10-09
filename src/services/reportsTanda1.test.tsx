import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { SourceTextModule, SyntheticModule } from 'node:vm';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { setImmediate as nextTurn } from 'node:timers/promises';
import * as React from 'react';
import * as jsxRuntime from 'react/jsx-runtime';
import * as icons from 'lucide-react';
import { renderToStaticMarkup } from 'react-dom/server';
import ts from 'typescript';
import { createReportsTanda1Service, ReportsTanda1Error, isReportsTanda1 } from './reportsTanda1.service';
import { createReportsLoader, type LegacyReportsData, type ReportsDependencies } from './reportsLoader';
import { OperationalReportsSection } from '../components/reports/OperationalReportsSection';
import { LegacyReportsSection } from '../components/reports/LegacyReportsSection';
import { formatAverageHours } from '../utils/numberFormat';
import type { ReportsTanda1 } from '../types/reports';

// Every test uses injected clients. Block fetch and socket creation as a backstop.
let networkAttempts = 0;
const blocked = () => { networkAttempts++; throw new Error('Network disabled in isolated reports tests'); };
const originalFetch = globalThis.fetch;
globalThis.fetch = async () => blocked();
const restoreNetwork: (() => void)[] = [];
for (const [target, key] of [
    [http, 'request'], [http, 'get'], [https, 'request'], [https, 'get'],
    [net.Socket.prototype, 'connect'],
] as const) {
    const descriptor = Object.getOwnPropertyDescriptor(target, key)!;
    Object.defineProperty(target, key, { ...descriptor, value: blocked });
    restoreNetwork.push(() => Object.defineProperty(target, key, descriptor));
}
after(() => {
    globalThis.fetch = originalFetch;
    restoreNetwork.forEach(restore => restore());
    assert.equal(networkAttempts, 0, 'No test may attempt network access');
});

const tenantA = '00000000-0000-4000-8000-000000000001';
const tenantB = '00000000-0000-4000-8000-000000000002';
const summary: ReportsTanda1 = {
    date_from: '2026-09-10', date_to: '2026-10-08',
    weekly: [
        { week_start: '2026-09-07', operations_created: 1, delivered: 1, closed: 0, billed: 1 },
        { week_start: '2026-09-21', operations_created: 1, delivered: 1, closed: 1, billed: 1 },
        { week_start: '2026-10-05', operations_created: 1, delivered: 1, closed: 0, billed: 0 },
    ],
    volume: { operations: 3, pieces: 10, weight_kg: 60 },
    by_service_type: [{ service_type: 'Road', service_class: 'FTL', operations: 3, pieces: 10, weight_kg: 60 }],
    by_zone: [{ zone: 'MX / NL', country_code: 'MX', state: 'NL', operations: 3, pieces: 10, weight_kg: 60 }],
    by_scope: [{ scope: 'national', operations: 3, pieces: 10, weight_kg: 60 }],
};
const emptySummary: ReportsTanda1 = {
    ...summary, volume: { operations: 0, pieces: 0, weight_kg: 0 },
    weekly: [], by_service_type: [], by_zone: [], by_scope: [],
};
const legacy: LegacyReportsData = {
    modules: [{ name: 'Operaciones', iconName: 'TrendingUp', count: 4, color: 'bg-blue-50 text-blue-600' }],
    finances: {
        revenue_by_month: [11, 22, 33, 44, 55, 66], ar_open_by_month: [1],
        ap_open_by_month: [2], cashflow_by_month: [3], total_revenue_ytd: 231,
        total_expenses_ytd: 41, net_position: 190,
    },
    pipeline: { deals_by_stage: { lead: 1, contacted: 2, proposal: 3, won: 4 }, total_pipeline_value: 350000, conversion_rate: 15.5 },
    inventory: { inventory_total_value: 1250000, blocked_count: 5, low_stock_count: 12, top_skus_by_value: [{ sku: 'SYNTHETIC-SKU', value: 450000 }] },
    operations: { operations_per_month: [1, 2, 3], avg_delivery_time: 71.41666666666667, active_routes_count: 14 },
};

async function evaluatedSource(source: string, dependencies: Record<string, Record<string, unknown>>) {
    const code = ts.transpileModule(source, {
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, jsx: ts.JsxEmit.ReactJSX },
    }).outputText;
    const module = new SourceTextModule(code, {
        initializeImportMeta: meta => { Object.defineProperty(meta, 'env', { value: { VITE_USE_MOCKS: 'false' } }); },
        importModuleDynamically: async () => { throw new Error('Unexpected dynamic dependency'); },
    });
    await module.link(async specifier => {
        const exports = dependencies[specifier];
        assert.ok(exports, 'Unexpected import: ' + specifier);
        const names = Object.keys(exports);
        const mock = new SyntheticModule(names, function() {
            for (const name of names) this.setExport(name, exports[name]);
        });
        return mock;
    });
    await module.evaluate();
    return module.namespace as Record<string, unknown>;
}

const legacySource = readFileSync(new URL('./reports.service.ts', import.meta.url), 'utf8');
const pageSource = readFileSync(new URL('../pages/ReportsPage.tsx', import.meta.url), 'utf8');
// Pin the approved presentation so this regression test survives its own commit.
const baselineCommit = 'b7e51582097dee851016f67c9f917fa926f669b4';
const basePageSource = execFileSync('git', ['--no-optional-locks', 'show', baselineCommit + ':src/pages/ReportsPage.tsx'], {
    cwd: new URL('../../', import.meta.url), encoding: 'utf8', windowsHide: true,
});

async function setup({ failLegacy = false, failTanda1 = false, response = summary, defer = false,
    beforeRpc, responseForTenant }:
    {
        failLegacy?: boolean; failTanda1?: boolean; response?: unknown; defer?: boolean;
        beforeRpc?: (name: string, tenantId: string) => Promise<void>;
        responseForTenant?: (tenantId: string) => unknown;
    } = {}) {
    const calls: { name: string; parameters: unknown; }[] = [];
    const client = {
        async rpc(name: string, parameters: unknown) {
            calls.push({ name, parameters });
            const tenantId = (parameters as { p_tenant_id: string; }).p_tenant_id;
            if (beforeRpc) await beforeRpc(name, tenantId);
            if (defer) await nextTurn();
            if (name === 'rpc_reports_tanda1') {
                return {
                    data: responseForTenant ? responseForTenant(tenantId) : response,
                    error: failTanda1 ? { message: 'synthetic failure' } : null
                };
            }
            if (failLegacy && name === 'rpc_reports_financial_summary') {
                return { data: null, error: new Error('synthetic legacy failure') };
            }
            const values: Record<string, unknown> = {
                rpc_reports_financial_summary: legacy.finances, rpc_reports_pipeline_summary: legacy.pipeline,
                rpc_reports_inventory_summary: legacy.inventory, rpc_reports_operations_summary: legacy.operations,
            };
            assert.ok(name in values, 'Unexpected RPC: ' + name);
            return { data: values[name], error: null };
        },
    };
    // Execute the unchanged legacy wrappers with only their Supabase import mocked.
    const old = await evaluatedSource(legacySource, { '@/lib/supabase': { supabase: client } });
    const deps: ReportsDependencies = {
        getReportModules: old.getReportModules as ReportsDependencies['getReportModules'],
        getFinancialSummary: old.getFinancialSummary as ReportsDependencies['getFinancialSummary'],
        getPipelineSummary: old.getPipelineSummary as ReportsDependencies['getPipelineSummary'],
        getInventorySummary: old.getInventorySummary as ReportsDependencies['getInventorySummary'],
        getOperationsSummary: old.getOperationsSummary as ReportsDependencies['getOperationsSummary'],
        getReportsTanda1: createReportsTanda1Service(client),
    };
    return { calls, client, old, deps, loader: createReportsLoader(deps) };
}

async function pageHarness(options: Parameters<typeof setup>[0] = {}) {
    const env = await setup(options);
    const states: unknown[] = [], refs: { current: unknown; }[] = [];
    let stateCursor = 0, refCursor = 0;
    let effect: () => void | (() => void) = () => { };
    let cleanup: void | (() => void);
    let activeTenant: string | null = tenantA;
    let stateWrites = 0;
    const hooks = {
        useState(initial: unknown) {
            const index = stateCursor++;
            if (!(index in states)) states[index] = initial;
            return [states[index], (next: unknown) => {
                stateWrites++;
                states[index] = typeof next === 'function'
                    ? (next as (value: unknown) => unknown)(states[index]) : next;
            }];
        },
        useRef(initial: unknown) {
            const index = refCursor++;
            refs[index] ??= { current: initial };
            return refs[index];
        },
        useEffect(callback: () => void | (() => void)) { effect = callback; },
    };
    const page = await evaluatedSource(pageSource, {
        react: hooks, 'react/jsx-runtime': { ...jsxRuntime },
        '@/store/authStore': { useAuthStore: (select: (value: { activeTenant: string | null; }) => unknown) => select({ activeTenant }) },
        '@/lib/supabase': { supabase: env.client },
        '@/services/reports.service': env.old,
        '@/services/reportsLoader': { createReportsLoader },
        '@/services/reportsTanda1.service': { createReportsTanda1Service },
        '@/components/reports/LegacyReportsSection': { LegacyReportsSection },
        '@/components/reports/OperationalReportsSection': { OperationalReportsSection },
    });
    const Page = page.default as () => React.ReactElement;
    return {
        ...env,
        render() { stateCursor = 0; refCursor = 0; return renderToStaticMarkup(Page()); },
        runEffect() { if (cleanup) cleanup(); cleanup = effect(); },
        close() { if (cleanup) cleanup(); },
        setTenant(value: string | null) { activeTenant = value; },
        stateWriteCount() { return stateWrites; },
        async flush() { for (let i = 0; i < 3; i++) await nextTurn(); },
    };
}

test('four unchanged wrappers plus exactly one Tanda 1 RPC use the same tenant', async () => {
    const env = await setup();
    const load = env.loader.load(tenantA, 0);
    const [old, current] = await Promise.all([load.legacy, load.operational]);
    assert.deepEqual(old.finances, legacy.finances);
    assert.deepEqual(current, summary);
    assert.deepEqual(env.calls, [
        { name: 'rpc_reports_financial_summary', parameters: { p_tenant_id: tenantA, p_period: 'monthly' } },
        { name: 'rpc_reports_pipeline_summary', parameters: { p_tenant_id: tenantA } },
        { name: 'rpc_reports_inventory_summary', parameters: { p_tenant_id: tenantA } },
        { name: 'rpc_reports_operations_summary', parameters: { p_tenant_id: tenantA } },
        { name: 'rpc_reports_tanda1', parameters: { p_tenant_id: tenantA } },
    ]);
});

test('dates are omitted by default, null or explicit values retain SQL parameter names', async () => {
    const env = await setup();
    const get = createReportsTanda1Service(env.client);
    await get(tenantA);
    await get(tenantA, { from: null, to: null });
    await get(tenantA, { from: '2026-09-10', to: '2026-10-08' });
    assert.deepEqual(env.calls.map(call => call.parameters), [
        { p_tenant_id: tenantA },
        { p_tenant_id: tenantA, p_date_from: null, p_date_to: null },
        { p_tenant_id: tenantA, p_date_from: '2026-09-10', p_date_to: '2026-10-08' },
    ]);
});

test('all seven keys and nested fields are validated without numeric coercion', () => {
    assert.equal(isReportsTanda1(summary), true);
    assert.deepEqual(Object.keys(summary).sort(),
        ['date_from', 'date_to', 'weekly', 'volume', 'by_service_type', 'by_zone', 'by_scope'].sort());
    const fractional = { ...summary, volume: { operations: 3, pieces: 10.5, weight_kg: 60.125 } };
    assert.equal(isReportsTanda1(fractional), true);
    assert.equal(typeof fractional.volume.pieces, 'number');
    assert.equal(typeof fractional.volume.weight_kg, 'number');
});

test('each missing top-level key is rejected', async () => {
    for (const key of Object.keys(summary)) {
        const bad: Record<string, unknown> = { ...summary };
        delete bad[key];
        const env = await setup({ response: bad });
        await assert.rejects(env.loader.load(tenantA, 0).operational,
            (error: unknown) => error instanceof ReportsTanda1Error && error.kind === 'invalid_response');
    }
});

test('invalid numbers, arrays, dates and nested fields are rejected', () => {
    for (const value of [
        null, undefined, [], JSON.stringify(summary),
        { ...summary, date_from: '2026-02-30' },
        { ...summary, volume: { operations: '3', pieces: 10, weight_kg: 60 } },
        { ...summary, volume: { operations: 3.5, pieces: 10, weight_kg: 60 } },
        { ...summary, volume: { operations: 3, pieces: NaN, weight_kg: 60 } },
        { ...summary, volume: { operations: 3, pieces: 10, weight_kg: Infinity } },
        { ...summary, weekly: [{ ...summary.weekly[0], billed: '1' }] },
        { ...summary, weekly: [{ ...summary.weekly[0], delivered: -1 }] },
        { ...summary, by_zone: [{ ...summary.by_zone[0], state: null }] },
        { ...summary, by_service_type: [{ ...summary.by_service_type[0], service_class: undefined }] },
        { ...summary, by_scope: {} },
    ]) assert.equal(isReportsTanda1(value), false);
});

test('an inverted interval with empty results remains valid', () => {
    assert.equal(isReportsTanda1({ ...emptySummary, date_from: '2026-10-08', date_to: '2026-09-10' }), true);
});

test('unauthorized JSON has a controlled failure', async () => {
    const env = await setup({ response: { error: 'unauthorized' } });
    await assert.rejects(createReportsTanda1Service(env.client)(tenantA),
        (error: unknown) => error instanceof ReportsTanda1Error && error.kind === 'unauthorized');
});

test('the ready section renders period, volume and all grouping keys without money', () => {
    const html = renderToStaticMarkup(<OperationalReportsSection state={{ status: 'ready', data: summary }} />);
    for (const text of ['Resumen operativo', '10/09/2026', '08/10/2026', 'Conteos semanales',
        'Volumen operativo', 'Facturadas (conteo)', 'Entregadas o cerradas',
        'Road', 'FTL', 'MX / NL', 'País', 'Estado', 'Nacional', 'Peso (kg)']) assert.ok(html.includes(text), text);
    assert.equal(html.includes('$'), false);
    assert.equal(html.includes('MXN'), false);
    assert.equal(html.includes('Ingresos'), false);
    assert.equal(html.includes('Incidencias'), false);
    assert.equal(html.includes('Documentos'), false);
});

test('empty tenant has explicit empty groups, zero quantities and no alert', () => {
    const html = renderToStaticMarkup(<OperationalReportsSection state={{ status: 'ready', data: emptySummary }} />);
    assert.ok(html.includes('No hay operaciones en este periodo.'));
    assert.equal(html.match(/Sin agrupaciones en este periodo/g)?.length, 3);
    assert.ok(html.includes('>0</dd>'));
    assert.equal(html.includes('role="alert"'), false);
    assert.equal(html.includes('Road'), false);
});

test('loading and failed section have accessible states without fabricated data', () => {
    const loading = renderToStaticMarkup(<OperationalReportsSection state={{ status: 'loading' }} />);
    const failed = renderToStaticMarkup(<OperationalReportsSection state={{ status: 'error' }} />);
    assert.ok(loading.includes('role="status"'));
    assert.ok(loading.includes('aria-busy="true"'));
    assert.ok(failed.includes('role="alert"'));
    assert.equal(failed.includes('Facturadas'), false);
    assert.equal(failed.includes('Road'), false);
});

test('actual page effect keeps old metrics when Tanda 1 fails', async () => {
    const page = await pageHarness({ failTanda1: true });
    page.render(); page.runEffect(); await page.flush();
    const html = page.render();
    assert.ok(html.includes('Métricas Consolidadas (YTD)'));
    assert.ok(html.includes('Prom. 71.4 h'));
    assert.ok(html.includes('No fue posible cargar el resumen operativo.'));
    assert.equal(page.calls.length, 5);
    page.close();
});

test('actual page effect shows Tanda 1 even when a legacy RPC fails', async () => {
    const page = await pageHarness({ failLegacy: true });
    page.render(); page.runEffect(); await page.flush();
    const html = page.render();
    assert.ok(html.includes('Datos insuficientes para reportes'));
    assert.ok(html.includes('Volumen operativo'));
    assert.ok(html.includes('Facturadas (conteo)'));
    assert.equal(html.includes('No fue posible cargar el resumen operativo.'), false);
    assert.equal(page.calls.length, 5);
    page.close();
});

test('incomplete Tanda 1 response activates only its own fallback on the page', async () => {
    const page = await pageHarness({ response: { volume: summary.volume } });
    page.render(); page.runEffect(); await page.flush();
    const html = page.render();
    assert.ok(html.includes('Prom. 71.4 h'));
    assert.ok(html.includes('No fue posible cargar el resumen operativo.'));
    page.close();
});

test('renders and StrictMode-style effect cleanup/replay do not duplicate RPCs', async () => {
    const page = await pageHarness({ defer: true });
    page.render(); page.runEffect();
    page.render(); page.runEffect();
    page.render(); await page.flush();
    for (let i = 0; i < 5; i++) page.render();
    assert.equal(page.calls.length, 5);
    assert.equal(page.calls.filter(call => call.name === 'rpc_reports_tanda1').length, 1);
    assert.ok(page.render().includes('Volumen operativo'));
    page.close();
});

test('manual revision starts a new logical load; only pending requests are deduplicated', async () => {
    const env = await setup({ defer: true });
    const a = env.loader.load(tenantA, 0);
    assert.equal(env.loader.load(tenantA, 0).operational, a.operational);
    assert.equal(env.loader.load(tenantA, 0).legacy, a.legacy);
    await Promise.all([a.legacy, a.operational]);
    const b = env.loader.load(tenantA, 1);
    await Promise.all([b.legacy, b.operational]);
    assert.equal(env.calls.length, 10);
    assert.equal(env.calls.filter(call => call.name === 'rpc_reports_tanda1').length, 2);
});

test('tenant change starts a fresh load and never displays previous tenant data', async () => {
    const page = await pageHarness({ defer: true });
    page.render(); page.runEffect(); await page.flush();
    assert.ok(page.render().includes('Prom. 71.4 h'));
    page.setTenant(tenantB);
    const pending = page.render();
    assert.equal(pending.includes('Prom. 71.4 h'), false);
    assert.equal(pending.includes('Road'), false);
    page.runEffect(); await page.flush();
    assert.equal(page.calls.length, 10);
    assert.equal((page.calls[9].parameters as { p_tenant_id: string; }).p_tenant_id, tenantB);
    page.close();
});

test('legacy success, loading, refresh, fallback and empty SKU markup match the approved base', async () => {
    let cursor = 0;
    let values: unknown[] = [];
    const baseline = await evaluatedSource(basePageSource, {
        react: { default: React, useState: () => [values[cursor++], () => { }], useEffect: () => { } },
        'react/jsx-runtime': { ...jsxRuntime },
        'lucide-react': { ...icons },
        '@/utils/numberFormat': { formatAverageHours },
        '@/store/authStore': { useAuthStore: () => tenantA },
        '@/services/reports.service': Object.fromEntries(
            ['getReportModules', 'getFinancialSummary', 'getPipelineSummary', 'getInventorySummary', 'getOperationsSummary']
                .map(name => [name, () => { throw new Error('Unexpected baseline service call'); }])),
    });
    const Base = baseline.default as React.ComponentType;
    for (const entry of [
        { loading: false, data: legacy },
        { loading: true, data: null },
        { loading: false, data: null },
        { loading: true, data: legacy },
        {
            loading: false, data: {
                ...legacy, modules: [],
                inventory: { ...legacy.inventory, top_skus_by_value: [] },
                finances: { ...legacy.finances, revenue_by_month: [] }
            }
        },
    ]) {
        cursor = 0;
        values = [entry.loading, entry.data?.modules ?? [], entry.data?.finances ?? null,
        entry.data?.pipeline ?? null, entry.data?.inventory ?? null, entry.data?.operations ?? null];
        const previous = renderToStaticMarkup(<Base />);
        const current = renderToStaticMarkup(<LegacyReportsSection data={entry.data}
            loading={entry.loading} onRefresh={() => { }} />);
        assert.equal(current, previous, 'Legacy markup, periods, formats and states are preserved');
    }
});

test('page integration has no notification writes or unexpected RPCs or real network', async () => {
    const page = await pageHarness();
    page.render(); page.runEffect(); await page.flush(); page.render();
    assert.equal(page.calls.length, 5);
    assert.equal(page.calls.some(call => /notification|auth|write|insert|update|delete/.test(call.name)), false);
    assert.equal(networkAttempts, 0);
    page.close();
});

test('roles remain admin/finance; no viewer enablement or guard modification', () => {
    const roles = readFileSync(new URL('../constants/roles.ts', import.meta.url), 'utf8');
    const router = readFileSync(new URL('../routes/router.tsx', import.meta.url), 'utf8');
    assert.ok(roles.includes("ROTERO_ENABLED_ROLES = ['admin', 'finance'] as const"));
    assert.ok(router.includes('allowedRoles={ROTERO_ENABLED_ROLES}'));
    assert.ok(router.includes("{ path: 'reports', element: page(<ReportsPage />) }"));
});

test('the production service source remains byte-equivalent to the base after line endings', () => {
    const base = execFileSync('git', ['--no-optional-locks', 'show', baselineCommit + ':src/services/reports.service.ts'], {
        cwd: new URL('../../', import.meta.url), encoding: 'utf8', windowsHide: true,
    });
    assert.equal(legacySource.replaceAll('\r\n', '\n'), base.replaceAll('\r\n', '\n'));
});

function deferred() {
    let resolve!: () => void;
    let reject!: (error: Error) => void;
    const promise = new Promise<void>((success, failure) => { resolve = success; reject = failure; });
    return { promise, resolve, reject };
}

test('simultaneous loads share only matching tenant and date requests', async () => {
    const gate = deferred();
    const env = await setup({ beforeRpc: () => gate.promise });
    const dates = { from: '2026-09-10', to: '2026-10-08' };
    const a = env.loader.load(tenantA, 0, dates);
    const duplicate = env.loader.load(tenantA, 0, { ...dates });
    const b = env.loader.load(tenantB, 0, dates);
    const differentDates = env.loader.load(tenantA, 0, { ...dates, from: '2026-09-11' });
    assert.equal(a.operational, duplicate.operational);
    assert.equal(a.legacy, duplicate.legacy);
    assert.notEqual(a.operational, b.operational);
    assert.notEqual(a.legacy, b.legacy);
    assert.notEqual(a.operational, differentDates.operational);
    assert.notEqual(a.legacy, differentDates.legacy);
    await nextTurn();
    const rpc = env.calls.filter(call => call.name === 'rpc_reports_tanda1');
    assert.deepEqual(rpc.map(call => call.parameters), [
        { p_tenant_id: tenantA, p_date_from: dates.from, p_date_to: dates.to },
        { p_tenant_id: tenantB, p_date_from: dates.from, p_date_to: dates.to },
        { p_tenant_id: tenantA, p_date_from: '2026-09-11', p_date_to: dates.to },
    ]);
    gate.resolve();
    await Promise.all([a.legacy, a.operational, b.legacy, b.operational,
    differentDates.legacy, differentDates.operational]);
});

test('successful requests are removed from both in-flight maps', async () => {
    const env = await setup();
    const first = env.loader.load(tenantA, 0);
    await Promise.all([first.legacy, first.operational]);
    const second = env.loader.load(tenantA, 0);
    assert.notEqual(first.legacy, second.legacy);
    assert.notEqual(first.operational, second.operational);
    await Promise.all([second.legacy, second.operational]);
    assert.equal(env.calls.length, 10);
});

test('failed requests are removed and do not cache an error for either tenant', async () => {
    const gate = deferred();
    let failing = true;
    const env = await setup({ beforeRpc: () => failing ? gate.promise : Promise.resolve() });
    const first = env.loader.load(tenantA, 0);
    const outcomes = Promise.allSettled([first.legacy, first.operational]);
    gate.reject(new Error('synthetic rejected request'));
    assert.deepEqual((await outcomes).map(outcome => outcome.status), ['rejected', 'rejected']);
    failing = false;
    const retry = env.loader.load(tenantA, 0), other = env.loader.load(tenantB, 0);
    assert.notEqual(retry.legacy, first.legacy);
    assert.notEqual(retry.operational, first.operational);
    assert.notEqual(retry.operational, other.operational);
    await Promise.all([retry.legacy, retry.operational, other.legacy, other.operational]);
    assert.equal(env.calls.length, 15);
});

test('a finished branch is evicted while the independent branch is still pending', async () => {
    for (const slowBranch of ['legacy', 'operational'] as const) {
        const gate = deferred();
        const env = await setup({
            beforeRpc: name =>
                (name === 'rpc_reports_tanda1') === (slowBranch === 'operational')
                    ? gate.promise : Promise.resolve()
        });
        const first = env.loader.load(tenantA, 0);
        const fastBranch = slowBranch === 'legacy' ? 'operational' : 'legacy';
        await first[fastBranch];
        const second = env.loader.load(tenantA, 0);
        assert.equal(second[slowBranch], first[slowBranch]);
        assert.notEqual(second[fastBranch], first[fastBranch]);
        gate.resolve();
        await Promise.all([first.legacy, first.operational, second.legacy, second.operational]);
    }
});

test('clearing pending requests cannot let an old finally remove a newer request', async () => {
    const oldGate = deferred(), freshGate = deferred();
    let started = 0;
    const env = await setup({ beforeRpc: () => (++started <= 5 ? oldGate.promise : freshGate.promise) });
    const old = env.loader.load(tenantA, 0);
    await nextTurn();
    env.loader.clear();
    const fresh = env.loader.load(tenantA, 0);
    await nextTurn();
    assert.notEqual(old.operational, fresh.operational);
    assert.notEqual(old.legacy, fresh.legacy);
    assert.equal(env.loader.load(tenantA, 0).operational, fresh.operational);
    oldGate.resolve();
    await Promise.all([old.legacy, old.operational]);
    assert.equal(env.loader.load(tenantA, 0).operational, fresh.operational);
    assert.equal(env.loader.load(tenantA, 0).legacy, fresh.legacy);
    assert.equal(env.calls.length, 10);
    freshGate.resolve();
    await Promise.all([fresh.legacy, fresh.operational]);
});

test('late tenant A success cannot overwrite tenant B data or loading state', async () => {
    const gateA = deferred();
    const page = await pageHarness({
        beforeRpc: (_name, tenant) => tenant === tenantA ? gateA.promise : Promise.resolve(),
        responseForTenant: tenant => ({ ...summary, by_scope: [{ ...summary.by_scope[0], scope: tenant === tenantA ? 'SYNTHETIC-A' : 'SYNTHETIC-B' }] })
    });
    page.render(); page.runEffect();
    page.setTenant(tenantB); page.render(); page.runEffect(); await page.flush();
    const before = page.render(), writes = page.stateWriteCount();
    assert.ok(before.includes('SYNTHETIC-B'));
    gateA.resolve(); await page.flush();
    assert.equal(page.render(), before);
    assert.equal(page.stateWriteCount(), writes);
    assert.equal(page.render().includes('SYNTHETIC-A'), false);
    page.close();
});

test('late tenant A failures cannot overwrite the current tenant B', async () => {
    const gateA = deferred();
    const page = await pageHarness({ beforeRpc: (_name, tenant) => tenant === tenantA ? gateA.promise : Promise.resolve() });
    page.render(); page.runEffect();
    page.setTenant(tenantB); page.render(); page.runEffect(); await page.flush();
    const before = page.render(), writes = page.stateWriteCount();
    gateA.reject(new Error('synthetic former tenant failure')); await page.flush();
    assert.equal(page.render(), before);
    assert.equal(page.stateWriteCount(), writes);
    page.close();
});

test('tenant switch immediately masks both previous sections before its effect runs', async () => {
    const gateB = deferred();
    const page = await pageHarness({ beforeRpc: (_name, tenant) => tenant === tenantB ? gateB.promise : Promise.resolve() });
    page.render(); page.runEffect(); await page.flush();
    assert.ok(page.render().includes('Prom. 71.4 h'));
    page.setTenant(tenantB);
    for (const html of [page.render(), (page.runEffect(), page.render())]) {
        assert.equal(html.includes('Prom. 71.4 h'), false);
        assert.equal(html.includes('Road'), false);
        assert.ok(html.includes('Generando cubo de datos OLAP'));
        assert.ok(html.includes('Cargando resumen operativo'));
    }
    gateB.resolve(); await page.flush(); page.close();
});

test('unmount ignores pending responses and a fresh mount starts fresh requests', async () => {
    const gate = deferred();
    const page = await pageHarness({ beforeRpc: () => gate.promise });
    page.render(); page.runEffect(); page.close();
    const writes = page.stateWriteCount();
    gate.resolve(); await page.flush();
    assert.equal(page.stateWriteCount(), writes);
    const fresh = await pageHarness();
    fresh.render(); fresh.runEffect(); await fresh.flush();
    assert.equal(fresh.calls.length, 5);
    fresh.close();
});

test('logout removes visible data and same-tenant login cannot reuse settled responses', async () => {
    const page = await pageHarness();
    page.render(); page.runEffect(); await page.flush();
    assert.ok(page.render().includes('Prom. 71.4 h'));
    page.setTenant(null);
    assert.equal(page.render().includes('Prom. 71.4 h'), false);
    page.runEffect();
    page.setTenant(tenantA);
    assert.equal(page.render().includes('Prom. 71.4 h'), false);
    assert.equal(page.render().includes('Road'), false);
    page.runEffect(); await page.flush();
    assert.equal(page.calls.length, 10);
    page.close();
});

test('a logout/login cycle cannot reuse a previous session request still in flight', async () => {
    const first = deferred(), second = deferred();
    let started = 0;
    const page = await pageHarness({ beforeRpc: () => (++started <= 5 ? first.promise : second.promise) });
    page.render(); page.runEffect(); await nextTurn();
    page.setTenant(null); page.render(); page.runEffect();
    page.setTenant(tenantA); page.render(); page.runEffect(); await nextTurn();
    assert.equal(page.calls.length, 10);
    const writes = page.stateWriteCount();
    first.resolve(); await page.flush();
    assert.equal(page.stateWriteCount(), writes);
    assert.equal(page.render().includes('Road'), false);
    second.resolve(); await page.flush();
    assert.ok(page.render().includes('Road'));
    page.close();
});

test('extra root keys, malformed dates and non-finite values activate the isolated fallback', async () => {
    for (const response of [
        { ...summary, unexpected: 0 },
        { ...summary, date_from: '2026-9-10' },
        { ...summary, date_to: '08/10/2026' },
        { ...summary, volume: { ...summary.volume, pieces: NaN } },
        { ...summary, by_scope: [{ ...summary.by_scope[0], weight_kg: Infinity }] },
    ]) {
        assert.equal(isReportsTanda1(response), false);
        const page = await pageHarness({ response });
        page.render(); page.runEffect(); await page.flush();
        const html = page.render();
        assert.ok(html.includes('No fue posible cargar el resumen operativo.'));
        assert.ok(html.includes('Prom. 71.4 h'));
        page.close();
    }
});
