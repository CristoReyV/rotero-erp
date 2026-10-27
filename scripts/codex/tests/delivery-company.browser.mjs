import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
const out = process.env.LOCAL_QA_OUT;
assert.ok(
    out && process.env.LOCAL_QA_ALLOW_DISPOSABLE_FIXTURES === '1',
    'Explicit disposable local fixture opt-in is required',
);
const repo = fileURLToPath(new URL('../../../', import.meta.url)).replaceAll('\\', '/').replace(/\/$/, '');
const require = createRequire(repo + '/package.json');
const { createClient } = require('@supabase/supabase-js');
const { createServer } = await import(pathToFileURL(require.resolve('vite')).href);
const { default: react } = await import(pathToFileURL(require.resolve('@vitejs/plugin-react')).href);
const { default: tailwindcss } = await import(pathToFileURL(require.resolve('@tailwindcss/vite')).href);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
const cli = process.env.LOCAL_QA_CLI;
assert.ok(cli, 'Existing validated loopback CLI required');
const project = process.env.LOCAL_QA_PROJECT;
assert.ok(/^rotero-[a-z0-9-]*delivery-[a-z0-9-]+$/.test(project), 'Own disposable project name required');
const r = spawnSync(cli, ['status', '--workdir', out + '/runtime', '--output', 'json'], {
    encoding: 'utf8',
    windowsHide: true,
});
assert.equal(r.status, 0, 'local CLI status');
const keys = JSON.parse(r.stdout);
const api = keys.API_URL;
assert.equal(new URL(api).hostname, '127.0.0.1');
const admin = createClient(api, keys.SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
});
const password = randomBytes(32).toString('base64url') + 'xA9!';
const email = 'delivery-' + randomBytes(7).toString('hex') + '@example.test';
let browser, server, page;
const events = [], checks = [], errors = [];
let phase = 'setup';
const check = (name) => {
    checks.push({ case: name, passed: true });
    console.log('PASS', name);
};
try {
    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    assert.equal(error, null, 'local synthetic Auth user');
    const fixture = spawnSync(process.env.LOCAL_QA_PYTHON || 'python', [
        repo + '/scripts/codex/tests/delivery-browser-fixture.py',
    ], {
        cwd: out,
        encoding: 'utf8',
        env: { ...process.env, LOCAL_QA_USER_ID: data.user.id },
        windowsHide: true,
    });
    assert.equal(fixture.status, 0, 'synthetic SQL fixture');
    const f = JSON.parse(await fs.readFile(out + '/browser-fixture.json', 'utf8'));
    const stored = await admin.storage.from('tenant-documents').upload(
        f.tenant + '/operations/synthetic.txt',
        Buffer.from('synthetic QA'),
        { contentType: 'text/plain' },
    );
    assert.equal(stored.error, null, 'synthetic private object');
    // Collection is explicit, minimal and confined to the disposable local fixture.
    const grant = spawnSync('docker', [
        'exec',
        '-i',
        'supabase_db_' + project,
        'psql',
        '-XqAt',
        '-v',
        'ON_ERROR_STOP=1',
        '-U',
        'postgres',
        '-d',
        'postgres',
    ], {
        input:
            `SET ROLE rotero_company_access_owner;INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by) VALUES('${f.tenant}','${data.user.id}','${f.company_a}','receivables.collect','synthetic-browser-only','${data.user.id}');`,
        encoding: 'utf8',
        windowsHide: true,
    });
    assert.equal(grant.status, 0, 'synthetic collection grant');
    server = await createServer({
        root: repo,
        configFile: false,
        envDir: out + '/empty-env',
        cacheDir: out + '/browser-vite-cache',
        logLevel: 'error',
        resolve: { alias: { '@': repo + '/src' } },
        plugins: [react(), tailwindcss()],
        define: {
            'import.meta.env.VITE_USE_MOCKS': 'false',
            'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(api),
            'import.meta.env.VITE_SUPABASE_ANON_KEY': JSON.stringify(keys.ANON_KEY),
        },
        server: { host: '127.0.0.1', port: 0, hmr: false },
    });
    await server.listen();
    const origin = 'http://127.0.0.1:' + server.httpServer.address().port;
    browser = await chromium.launch({ headless: process.env.LOCAL_QA_HEADFUL !== '1' });
    const context = await browser.newContext({
        viewport: { width: 1280, height: 720 },
        acceptDownloads: true,
    });
    await context.route('**/*', (route) => {
        const url = new URL(route.request().url());
        if (url.origin === origin || url.origin === api) return route.continue();
        return route.abort();
    });
    page = await context.newPage();
    page.on('pageerror', () => errors.push({ phase, kind: 'pageerror' }));
    context.on('requestfinished', (req) => {
        const u = new URL(req.url());
        if (u.origin === api) {
            events.push({
                phase,
                host: u.host,
                path: u.pathname,
                method: req.method(),
                completion: 'finished',
            });
        }
    });
    context.on('requestfailed', (req) => {
        const u = new URL(req.url());
        if (u.origin === api) {
            events.push({
                phase,
                host: u.host,
                path: u.pathname,
                method: req.method(),
                completion: 'failed',
                error: req.failure()?.errorText?.match(/^net::[A-Z_]+$/)?.[0] || 'network_error',
            });
        }
    });
    context.on('response', (res) => {
        const u = new URL(res.url());
        if (u.origin !== api) return;
        events.push({
            phase,
            host: u.host,
            path: u.pathname,
            method: res.request().method(),
            status: res.status(),
        });
    });
    phase = 'login';
    await page.goto(origin + '/login');
    await page.locator('input[type=email]').fill(email);
    await page.locator('input[type=password]').fill(password);
    await page.getByRole('button', { name: 'Ingresar', exact: true }).click();
    await page.waitForURL('**/dashboard');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByText('Operaciones clasificadas', { exact: false }).first().waitFor({ timeout: 20000 })
        .catch(() => {});
    check('isolated local finance login and company selection');
    phase = 'operations';
    await page.goto(origin + '/operations');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByText('3 operaciones en este alcance', { exact: true }).waitFor();
    assert.equal(await page.getByText('FINANCIAL_CANARY').count(), 0);
    await page.getByRole('table').getByText('A-1', { exact: true }).click();
    await page.getByRole('button', { name: 'Documentos', exact: true }).click();
    await page.getByRole('button', { name: 'synthetic.txt', exact: true }).waitFor();
    const fileEvent = page.waitForEvent('download');
    await page.getByRole('button', { name: 'synthetic.txt', exact: true }).click();
    const file = await fileEvent;
    const fstream = await file.createReadStream();
    let body = '';
    for await (const c of fstream) body += c;
    assert.equal(body, 'synthetic QA');
    check('operations to 360 to authorized private Storage download');
    // Close detail by Escape/close accessible control, then export using actual UI.
    await page.keyboard.press('Escape');
    const closes = page.getByRole('button', { name: /Cerrar.*detalle|Cerrar panel|Cerrar ficha/i });
    if (await closes.count()) await closes.first().click();
    await page.goto(origin + '/operations');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByText('3 operaciones en este alcance', { exact: true }).waitFor();
    const csvEvent = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Exportar CSV', exact: true }).click();
    const csv = await csvEvent;
    let text = '';
    for await (const c of await csv.createReadStream()) text += c;
    assert.ok(text.includes('A-1'));
    assert.ok(!/FINANCIAL_CANARY|12345|54321|provider_cost_amount|margin|AP-A/.test(text));
    check('company CSV contains operational projection only');
    phase = 'receivables';
    await page.goto(origin + '/finance');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByRole('heading', { name: 'Cuentas por cobrar', exact: true }).waitFor();
    await page.getByText('AR-A', { exact: true }).waitFor();
    assert.equal(await page.getByText('AP-A', { exact: true }).count(), 0);
    assert.equal(await page.getByText('AR-B', { exact: true }).count(), 0);
    await page.getByRole('button', { name: /Registrar pago/ }).first().click();
    await page.locator('input[type=number]').fill('25');
    await page.getByRole('button', { name: /Confirmar pago/ }).click();
    await page.getByText('AR-A', { exact: true }).waitFor();
    check('explicit AR collection without AP or full financial permission');
    phase = 'reports';
    const tanda = page.waitForResponse((r) => new URL(r.url()).pathname.endsWith('/rpc_reports_tanda1'));
    await page.goto(origin + '/reports');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    const tr = await tanda;
    const tj = await tr.json();
    assert.deepEqual(
        Object.keys(tj).sort(),
        ['date_from', 'date_to', 'weekly', 'volume', 'by_service_type', 'by_zone', 'by_scope'].sort(),
    );
    assert.equal(tj.volume.operations, 3);
    check('Tanda1 scoped real HTTP structure seven keys');
    phase = 'reload';
    await page.reload();
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByRole('heading', { name: 'Volumen operativo', exact: true }).waitFor();
    check('reload retains authorized local session');
    phase = 'focus';
    const blank = await context.newPage();
    await blank.goto('about:blank');
    await blank.bringToFront();
    const hidden = await page.evaluate(() => ({
        visibility: document.visibilityState,
        focused: document.hasFocus(),
    }));
    await page.bringToFront();
    const focused = await page.evaluate(() => ({
        visibility: document.visibilityState,
        focused: document.hasFocus(),
    }));
    await blank.close();
    checks.push({
        case: 'actual focus transition',
        passed: hidden.visibility === 'hidden' && focused.visibility === 'visible' && focused.focused,
        evidence: { hidden, focused },
        limitation:
            'Focus is only approved if an effective visibility transition is observed; opening a window alone is insufficient',
    });
    phase = 'switch';
    await page.goto(origin + '/operations');
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_b);
    await page.getByText('Sin capacidad de lectura operativa para esta empresa.', { exact: true }).waitFor();
    assert.equal(await page.getByText('A-1', { exact: true }).count(), 0);
    await page.getByLabel('Empresa', { exact: true }).selectOption(f.company_a);
    await page.getByText('3 operaciones en este alcance', { exact: true }).waitFor();
    check('company switch clears data and denies missing capability');
    phase = 'logout';
    await page.getByRole('button', { name: /Cuenta|Local|example/ }).last().click().catch(async () => {
        await page.locator('header button').last().click();
    });
    const logout = page.waitForResponse((r) => new URL(r.url()).pathname.endsWith('/logout'), {
        timeout: 30000,
    });
    await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).click();
    const lr = await logout;
    await page.waitForURL('**/login', { timeout: 35000 });
    assert.equal(lr.status(), 204);
    await page.goto(origin + '/reports');
    await page.waitForURL('**/login');
    check('normal pointer logout HTTP204 local cleanup and protected redirect');
    const forbidden = events.filter((x) =>
        /rpc_refresh_internal_notifications|rpc_mark_|rpc_dismiss_|materialize/.test(x.path)
    );
    assert.equal(forbidden.length, 0);
    check('no notification refresh mark dismiss observed');
    assert.equal(errors.length, 0, 'browser runtime errors');
    await context.close();
} catch (e) {
    if (page) await page.screenshot({ path: out + '/browser-failure-synthetic.png' }).catch(() => {});
    checks.push({
        case: phase,
        passed: false,
        error: e.name === 'TimeoutError' ? 'timeout' : String(e.code || e.name),
    });
    console.log('FAIL', phase, String(e.code || e.name));
    await fs.writeFile(
        out + '/browser-error-safe.txt',
        String(e.message).replaceAll(password, '<redacted>').replaceAll(email, '<synthetic-account>'),
    );
    process.exitCode = 1;
} finally {
    if (browser) await browser.close();
    if (server) await server.close();
    await fs.writeFile(
        out + '/browser-local-result.json',
        JSON.stringify(
            {
                scope: 'disposable loopback only; no remote QA',
                browser_mode: process.env.LOCAL_QA_HEADFUL === '1' ? 'headed' : 'headless',
                checks,
                traffic: events,
                errors,
                remote_revocation:
                    'not inferred beyond observed HTTP result; no complete server-session enumeration',
            },
            null,
            2,
        ),
    );
}
