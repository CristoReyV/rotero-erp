// Run with node --test; PLAYWRIGHT_MODULE_PATH may point to an existing runtime.
// No installation, real credentials, environment files or external network needed.
import assert from 'node:assert/strict';
import { mkdtemp, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { createServer, transformWithEsbuild } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
const root = fileURLToPath(new URL('../../../', import.meta.url));
const entryId = '\0account-menu-entry.tsx';
const backendId = '\0account-menu-backend.ts';

// Only the backend port is replaced. Layout, styles, menus, Auth coordinator,
// route guard and Reports components are the production implementations.
const backend = `
const context = { user_id: 'local-qa', email: 'qa@example.test', memberships: [
    { tenant_id: 'local-tenant', tenant_name: 'Local QA', role: 'finance' }
] };
let session = { user: { id: context.user_id } };
const listeners = new Set();
window.__accountMenuTest = { signOutCalls: 0, controlEvents: [], exports: 0 };
const volume = { operations: 0, pieces: 0, weight_kg: 0 };
const responses = {
    rpc_get_my_context: context,
    rpc_list_internal_notifications_page: { items: [], unread_count: 0, next_cursor: null },
    rpc_reports_financial_summary: { revenue_by_month: [], ar_open_by_month: [],
        ap_open_by_month: [], cashflow_by_month: [], total_revenue_ytd: 0,
        total_expenses_ytd: 0, net_position: 0 },
    rpc_reports_pipeline_summary: { deals_by_stage: {}, total_pipeline_value: 0, conversion_rate: 0 },
    rpc_reports_inventory_summary: { inventory_total_value: 0, blocked_count: 0,
        low_stock_count: 0, top_skus_by_value: [] },
    rpc_reports_operations_summary: { operations_per_month: [], avg_delivery_time: 0, active_routes_count: 0 },
    rpc_reports_tanda1: { date_from: '2026-01-01', date_to: '2026-01-31', volume,
        weekly: [], by_service_type: [], by_zone: [], by_scope: [] }
};
export const supabase = {
    auth: {
        getSession: async () => ({ data: { session }, error: null }),
        onAuthStateChange: callback => {
            listeners.add(callback);
            return { data: { subscription: { unsubscribe: () => listeners.delete(callback) } } };
        },
        signOut: async () => {
            window.__accountMenuTest.signOutCalls++;
            session = null;
            listeners.forEach(callback => callback('SIGNED_OUT', null));
            return { error: null };
        }
    },
    rpc: name => {
        if (!(name in responses)) throw new Error('Unexpected local RPC: ' + name);
        const result = Promise.resolve({ data: responses[name], error: null });
        result.abortSignal = () => result;
        return result;
    }
};
`;

const entry = `
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AppLayout } from '@/layout/AppLayout';
import { AuthGuard } from '@/components/AuthGuard';
import ReportsPage from '@/pages/ReportsPage';
import LoginPage from '@/pages/LoginPage';
import '@/index.css';
createRoot(document.getElementById('root')).render(
    <BrowserRouter><Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<AuthGuard />}><Route element={<AppLayout />}>
            <Route path="/reports" element={<ReportsPage />} />
        </Route></Route>
    </Routes></BrowserRouter>
);
`;

test('account menu receives pointer and keyboard above Reports', { timeout: 120_000 }, async t => {
    const temporary = await mkdtemp(path.join(tmpdir(), 'rotero-account-menu-'));
    const server = await createServer({
        root, configFile: false, envDir: temporary, cacheDir: path.join(temporary, 'vite-cache'),
        logLevel: 'error',
        define: { 'import.meta.env.VITE_USE_MOCKS': 'false' },
        resolve: { alias: { '@': path.join(root, 'src') } },
        plugins: [{
            name: 'local-account-menu-test', enforce: 'pre',
            resolveId(id) {
                if (id === 'virtual:account-menu-entry.tsx') return entryId;
                const source = id.replaceAll('\\', '/');
                if (/\/src\/lib\/supabase(?:\.ts)?$/.test(source)) return backendId;
            },
            async load(id) {
                if (id === entryId) return transformWithEsbuild(entry, 'account-menu-entry.tsx', { loader: 'tsx', jsx: 'automatic' });
                if (id === backendId) return backend;
            },
            configureServer(vite) {
                vite.middlewares.use(async (request, response, next) => {
                    if (!['/reports', '/login'].includes(request.url)) return next();
                    const html = await vite.transformIndexHtml(request.url,
                        '<!doctype html><html><body><div id="root"></div>' +
                        '<script type="module">import "virtual:account-menu-entry.tsx";</script></body></html>');
                    response.setHeader('Content-Type', 'text/html');
                    response.end(html);
                });
            },
        }, react(), tailwindcss()],
        server: { host: '127.0.0.1', port: 0, hmr: false },
    });
    let browser;
    try {
        await server.listen();
        const origin = 'http://127.0.0.1:' + server.httpServer.address().port;
        browser = await chromium.launch({ headless: true });
        for (const width of [1280, 1024]) {
            for (const activation of ['pointer', 'Enter']) {
                await t.test(width + 'px / ' + activation, async () => {
                    const context = await browser.newContext({ viewport: { width, height: width === 1280 ? 720 : 768 } });
                    const external = [];
                    const errors = [];
                    try {
                        await context.route('**/*', route => {
                            if (new URL(route.request().url()).origin === origin) return route.continue();
                            external.push(new URL(route.request().url()).host);
                            return route.abort();
                        });
                        const page = await context.newPage();
                        page.on('pageerror', error => errors.push(error.message));
                        await page.goto(origin + '/reports');
                        try {
                            await page.getByRole('heading', { name: 'Reportes & BI', exact: true }).waitFor({ timeout: 10_000 });
                        } catch (error) {
                            t.diagnostic(JSON.stringify({ errors, external }));
                            throw error;
                        }
                        await page.getByRole('heading', { name: 'Volumen operativo', exact: true }).waitFor();
                        await page.waitForFunction(() =>
                            getComputedStyle(document.querySelector('main > .h-full')).transform === 'none');

                        const exportButton = page.getByRole('button', { name: 'Exportar Suite', exact: true });
                        await exportButton.evaluate(button => button.addEventListener('click', () => {
                            window.__accountMenuTest.exports++;
                        }));
                        await exportButton.click();
                        assert.equal(await page.evaluate(() => window.__accountMenuTest.exports), 1);
                        // Exercise a neighbouring menu without using its mutation controls.
                        const notifications = page.getByRole('button', { name: 'Abrir notificaciones', exact: true });
                        await notifications.click();
                        await page.getByText('Sin notificaciones relevantes.', { exact: true }).waitFor();
                        await notifications.click();

                        await page.locator('header').getByRole('button').filter({ hasText: 'finance' }).click();
                        const logout = page.getByRole('button', { name: 'Cerrar sesión', exact: true });
                        assert.equal(await logout.isVisible(), true);
                        assert.equal(await logout.isEnabled(), true);
                        assert.equal(await exportButton.isVisible(), true, 'Export stays rendered');
                        const geometry = await logout.evaluate(button => {
                            const rect = button.getBoundingClientRect();
                            const points = [0.1, 0.5, 0.9].flatMap(x => [0.2, 0.5, 0.8].map(y =>
                                button.contains(document.elementFromPoint(rect.x + rect.width * x, rect.y + rect.height * y))));
                            return { receivesPointer: points.every(Boolean),
                                withinViewport: rect.x >= 0 && rect.y >= 0 &&
                                    rect.right <= innerWidth && rect.bottom <= innerHeight };
                        });
                        assert.equal(geometry.withinViewport, true, 'Menu stays inside viewport');
                        assert.equal(geometry.receivesPointer, true, 'Menu is not covered or clipped by Reports/overflow');
                        await logout.evaluate(button => button.addEventListener('click', event => {
                            window.__accountMenuTest.controlEvents.push({ trusted: event.isTrusted, detail: event.detail });
                        }, { once: true }));
                        if (process.env.BROWSER_TEST_ARTIFACT_DIR) {
                            await mkdir(process.env.BROWSER_TEST_ARTIFACT_DIR, { recursive: true });
                            await page.screenshot({ path: path.join(process.env.BROWSER_TEST_ARTIFACT_DIR,
                                'menu-' + width + '-' + activation + '.png') });
                        }
                        if (activation === 'pointer') await logout.click({ timeout: 5_000 });
                        else { await logout.focus(); await logout.press('Enter'); }
                        await page.waitForURL(origin + '/login');
                        await page.getByRole('button', { name: 'Ingresar', exact: true }).waitFor();
                        const result = await page.evaluate(() => window.__accountMenuTest);
                        assert.equal(result.signOutCalls, 1, 'Real Auth coordinator called the local SDK double once');
                        assert.equal(result.controlEvents.length, 1);
                        assert.equal(result.controlEvents[0].trusted, true);
                        assert.equal(result.controlEvents[0].detail, activation === 'pointer' ? 1 : 0);
                        assert.equal(await page.getByRole('heading', { name: 'Resumen operativo', exact: true }).isVisible(), false);
                        assert.equal(await page.getByText('Local QA', { exact: true }).isVisible(), false);
                        assert.deepEqual(external, [], 'Local test must not contact external services');
                        assert.deepEqual(errors, []);
                    } finally { await context.close(); }
                });
            }
        }
    } finally {
        await browser?.close();
        await server.close();
    }
});
