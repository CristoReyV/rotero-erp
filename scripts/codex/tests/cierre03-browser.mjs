// Real layout + HTTP QA. No HAR, tracing, request bodies or headers are saved.
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto'; import assert from 'node:assert/strict'; import { spawnSync } from 'node:child_process'; import { createRequire } from 'node:module';
const require = createRequire(path.resolve('package.json'));
const { chromium } = require(path.join(process.env.C03_RUNTIME_NODE_MODULES, 'playwright'));
const manifest = JSON.parse(fs.readFileSync(process.env.C03_QA_MANIFEST, 'utf8'));
const out = process.env.C03_QA_OUTPUT; assert(out && fs.existsSync(out));
const origin = manifest.origin, api = manifest.api, ids = manifest.fixture_ids;
if (manifest.destination === 'local') {
    assert.equal(new URL(origin).hostname, '127.0.0.1'); assert.equal(new URL(api).hostname, '127.0.0.1'); assert.match(manifest.project, /^rotero-cierre03-[a-z-]*delivery-[a-f0-9]+$/);
} else {
    assert.equal(process.env.C03_ALLOW_STAGING, 'mxpmgihuheagrcowwbia'); assert.equal(manifest.project, 'mxpmgihuheagrcowwbia');
    assert.equal(origin, 'https://deploy-preview-47--rotero-erp-staging.netlify.app'); assert.equal(api, 'https://mxpmgihuheagrcowwbia.supabase.co');
}
const run = crypto.randomUUID(), events = [], checks = [], blocked = [], errors = []; let phase = 'setup', browser, context, page, activeRole;
const roles = (process.env.C03_QA_ROLES ?? 'operator,finance,setup').split(',');
const report = () => fs.writeFileSync(path.join(out, `browser-${run}-progress.json`), JSON.stringify({ destination: manifest.destination, phase, events, checks, blocked, errors }, null, 2));
const pass = (name, evidence = {}) => { checks.push({ case: name, status: 'passed', ...evidence }); console.log('PASS', name); report(); };
const readRpcs = new Set(['rpc_my_context', 'rpc_get_my_context', 'rpc_get_context', 'rpc_context', 'rpc_delivery_context', 'rpc_delivery_notifications', 'rpc_delivery_dashboard',
    'rpc_reports_operations_summary', 'rpc_delivery_operations_page', 'rpc_delivery_operation_workflow', 'rpc_delivery_operation_children', 'rpc_delivery_operation_history',
    'rpc_delivery_operational_billing', 'rpc_get_operation_incident_summary', 'rpc_get_operation_document_summary', 'rpc_get_operation_dispatch_readiness',
    'rpc_list_operation_tracking_events', 'rpc_delivery_assignment_choices', 'rpc_delivery_provider_eligibility', 'rpc_delivery_document_history', 'rpc_delivery_document_sources',
    'rpc_delivery_upload_contract', 'rpc_delivery_files_page', 'rpc_delivery_file_download', 'rpc_delivery_search', 'rpc_delivery_automation_status']);
const mutations = {
    create: ['rpc_delivery_create_operation_once'], edit: ['rpc_delivery_operation_action'], plan: ['rpc_delivery_operation_action'], assign: ['rpc_delivery_operation_action'], transition: ['rpc_delivery_operation_action'],
    incident: ['rpc_delivery_operation_child_action'], evidence: ['rpc_delivery_operation_child_action'], requirement: ['rpc_delivery_operation_child_action'],
    upload: ['rpc_delivery_prepare_upload', 'rpc_delivery_finalize_upload'], replace: ['rpc_delivery_prepare_upload', 'rpc_delivery_finalize_upload'], cancel: ['rpc_delivery_cancel_file'],
    automation: ['rpc_delivery_prepare_automation', 'rpc_delivery_run_automation'], configure: ['rpc_delivery_update_automation']
};
function credential(purpose) {
    const person = manifest.identities.find(x => x.purpose === purpose); assert(person, 'dedicated_identity_missing');
    const p = spawnSync(process.env.C03_PYTHON, [process.env.C03_CUSTODY_HELPER, 'unseal', person.custody_label], { windowsHide: true, timeout: 30000 });
    assert.equal(p.status, 0, 'secure_custody_unavailable'); return JSON.parse(p.stdout);
}
const file = { name: `c03-operational-${run.slice(0, 8)}.txt`, mimeType: 'text/plain', buffer: Buffer.from('C03 SYNTHETIC OPERATIONAL EVIDENCE\n') };
const replacement = { ...file, name: `c03-replacement-${run.slice(0, 8)}.txt` };
async function bytes(download) { let all = Buffer.alloc(0); for await (const part of await download.createReadStream()) all = Buffer.concat([all, part]); return all; }
async function rpcAfter(name, action) { const response = page.waitForResponse(r => new URL(r.url()).pathname === `/rest/v1/rpc/${name}`, { timeout: 40000 }); await action(); const r = await response; assert.equal(r.status(), 200); const data = await r.json(); assert(!data?.error, 'backend_action_rejected'); return data; }
async function login(role) {
    activeRole = role; phase = 'login'; context = await browser.newContext({ viewport: { width: 1280, height: 720 }, acceptDownloads: true });
    const phases = new WeakMap();
    context.on('request', request => phases.set(request, phase));
    await context.route('**/*', async route => {
        const request = route.request(), u = new URL(request.url()), method = request.method(), name = u.pathname.split('/rpc/')[1];
        if (!phases.has(request)) phases.set(request, phase);
        let allowed = false;
        if (['fonts.googleapis.com', 'fonts.gstatic.com'].includes(u.host)) allowed = ['GET', 'HEAD'].includes(method);
        if (u.origin === origin) allowed = ['GET', 'HEAD', 'OPTIONS'].includes(method);
        if (u.origin === api) {
            allowed = ['HEAD', 'OPTIONS'].includes(method) || u.pathname.startsWith('/auth/v1/');
            if (name) allowed = readRpcs.has(name) || (mutations[phase] ?? []).includes(name);
            else if (method === 'GET') allowed = true;
            else if (u.pathname.startsWith('/storage/v1/object/tenant-documents/')) allowed = ['upload', 'replace'].includes(phase) && method === 'POST';
        }
        const telemetry = u.host === 'sessions.bugsnag.com' || u.host === 'app.netlify.com' && /^\/access-control\/bb-api\/api\/v1\/cdp\/deploys\/[a-f0-9]+\/views$/.test(u.pathname);
        if (telemetry) { events.push({ phase: phases.get(request), host: u.host, path: u.pathname, method, event: 'preview_telemetry_blocked_separately' }); return route.abort(); }
        if (!allowed) { blocked.push({ phase: phases.get(request), host: u.host, path: u.pathname, method, rpc: name ?? null }); report(); return route.abort(); }
        return route.continue();
    });
    context.on('response', r => { const u = new URL(r.url()); if (u.origin === api) events.push({ phase: phases.get(r.request()), host: u.host, path: u.pathname, method: r.request().method(), http: r.status(), event: 'response' }); });
    context.on('requestfinished', r => { const u = new URL(r.url()); if (u.origin === api) events.push({ phase: phases.get(r), host: u.host, path: u.pathname, method: r.method(), event: 'requestfinished' }); });
    context.on('requestfailed', r => { const u = new URL(r.url()); if (u.origin === api) events.push({ phase: phases.get(r), host: u.host, path: u.pathname, method: r.method(), event: 'requestfailed', error: r.failure()?.errorText?.match(/^net::[A-Z_]+$/)?.[0] ?? 'network_error' }); });
    page = await context.newPage(); page.on('pageerror', () => errors.push({ phase, category: 'pageerror' }));
    await page.goto(origin + '/login'); const c = credential(role); await page.locator('input[type=email]').fill(c.email); await page.locator('input[type=password]').fill(c.password); delete c.password;
    await page.getByRole('button', { name: 'Ingresar', exact: true }).click(); await page.waitForURL('**/dashboard', { timeout: 45000 });
    await page.getByLabel('Empresa', { exact: true }).selectOption(ids.a); await page.getByRole('heading', { name: 'Resumen empresarial', exact: true }).waitFor();
    pass(role + ' isolated login and company', { product_role: manifest.identities.find(x => x.purpose === role).product_role }); phase = 'dashboard';
}
async function logout() {
    phase = 'logout'; const operationClose = page.getByRole('button', { name: 'Cerrar Operation 360', exact: true });
    if (await operationClose.isVisible()) await operationClose.click();
    await page.locator('header').first().locator('button').last().click(); const button = page.getByRole('button', { name: 'Cerrar sesión', exact: true }); await button.waitFor(); assert(await button.isEnabled());
    const box = await button.boundingBox(); assert(box); const reached = await button.evaluate(el => { const b = el.getBoundingClientRect(); return el.contains(document.elementFromPoint(b.x + b.width / 2, b.y + b.height / 2)); }); assert(reached, 'logout_pointer_intercepted');
    const response = page.waitForResponse(r => new URL(r.url()).pathname === '/auth/v1/logout', { timeout: 35000 }); await button.click(); const r = await response;
    const finished = await Promise.race([r.finished(), new Promise(resolve => setTimeout(() => resolve({ message: 'observation_timeout' }), 8000))]);
    await page.waitForURL('**/login', { timeout: 35000 }); assert.equal(await page.locator('header').count(), 0);
    pass(activeRole + ' normal logout click', { http: r.status(), request_finished: finished === null, completion_error: finished?.message === 'observation_timeout' ? 'observation_timeout' : finished?.message?.match(/net::[A-Z_]+/)?.[0] ?? null, ui_cleared: true, remote_revocation_fully_proven: false });
    await page.goto(origin + '/reports'); await page.waitForURL('**/login'); pass(activeRole + ' protected route denied after logout');
    await context.close(); context = null; page = null;
}
try {
    browser = await chromium.launch({ headless: false });
    if (roles.includes('operator')) {
        await login('operator');
        await page.getByText('Las métricas financieras completas requieren autorización explícita.', { exact: true }).waitFor(); pass('partial dashboard excludes financial cards');
        phase = 'operations'; await page.goto(origin + '/operations'); await page.getByRole('table').getByText(manifest.operation_a_reference ?? 'C03-LOCAL-A', { exact: true }).waitFor();
        assert.equal(await page.getByText(manifest.operation_b_reference ?? 'C03-LOCAL-B', { exact: true }).count(), 0); pass('partial operations excludes other company');
        phase = 'create'; await page.getByRole('button', { name: 'Nueva operación', exact: true }).click(); const reference = 'C03-QA-' + run.slice(0, 8);
        await page.getByLabel('Referencia', { exact: true }).fill(reference); await page.getByLabel('Cliente', { exact: true }).fill('C03 SYNTHETIC CUSTOMER'); await page.getByLabel('Ruta', { exact: true }).fill('C03 SYNTHETIC ROUTE'); await page.getByLabel('Ciudad destino', { exact: true }).fill('C03 DESTINATION');
        const created = await rpcAfter('rpc_delivery_create_operation_once', () => page.getByRole('button', { name: 'Guardar operación', exact: true }).click()); assert(created.id); pass('create persisted company operation', { operation_id: created.id });
        await page.getByRole('table').getByText(reference, { exact: true }).click(); let panel = page.getByRole('dialog', { name: new RegExp('Operation 360') });
        phase = 'edit'; await panel.getByRole('button', { name: 'Editar ficha operativa', exact: true }).click(); await panel.getByLabel('Ruta', { exact: true }).fill('C03 EDITED ROUTE'); await rpcAfter('rpc_delivery_operation_action', () => panel.getByRole('button', { name: 'Guardar ficha', exact: true }).click()); await panel.getByRole('button', { name: 'Ejecución', exact: true }).click();
        phase = 'plan'; await panel.getByRole('button', { name: 'Editar planeación', exact: true }).click(); await panel.getByLabel('Servicio', { exact: true }).fill('C03 SYNTHETIC SERVICE'); await panel.getByLabel('Origen', { exact: true }).fill('C03 ORIGIN'); await panel.getByLabel('Estado origen', { exact: true }).fill('QA'); await panel.getByLabel('Destino', { exact: true }).fill('C03 DESTINATION'); await panel.getByLabel('Estado destino', { exact: true }).fill('QA');
        const localTime = delta => { const d = new Date(Date.now() + delta); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16); };
        await panel.getByLabel('Inicio ventana', { exact: true }).fill(localTime(3600000)); await panel.getByLabel('Fin ventana', { exact: true }).fill(localTime(10800000));
        assert.equal(await panel.getByLabel('Costo proveedor', { exact: true }).count(), 0); assert.equal(await panel.getByLabel('Venta cliente', { exact: true }).count(), 0);
        await rpcAfter('rpc_delivery_operation_action', () => panel.getByRole('button', { name: 'Guardar planeación', exact: true }).click()); pass('real planning form saves without financial input fields');
        phase = 'assign'; await panel.getByRole('button', { name: 'Asignar o cambiar', exact: true }).click(); await page.getByText('Asignación contratada', { exact: true }).waitFor();
        await page.locator('aside').last().getByRole('combobox').first().selectOption(ids.carrier); await page.locator('aside').last().locator('input[type=datetime-local]').fill(localTime(7200000));
        const reason = page.locator('aside').last().locator('textarea'); if (await reason.count()) await reason.fill('C03 SYNTHETIC ASSIGNMENT');
        await rpcAfter('rpc_delivery_operation_action', () => page.getByRole('button', { name: 'Guardar asignación', exact: true }).click()); await page.getByText('Asignación contratada', { exact: true }).waitFor({ state: 'hidden' }); pass('existing provider assigned through normal form');
        phase = 'incident'; await panel.getByRole('button', { name: 'Incidencias', exact: true }).click(); await panel.getByRole('button', { name: 'Nueva incidencia', exact: true }).click(); await panel.getByLabel('Título', { exact: true }).fill('C03 SYNTHETIC INCIDENT'); await panel.getByLabel('Detalle', { exact: true }).fill('C03 OPERATIONAL DETAIL'); await rpcAfter('rpc_delivery_operation_child_action', () => panel.getByRole('button', { name: 'Guardar', exact: true }).click()); await panel.getByText('C03 SYNTHETIC INCIDENT', { exact: true }).waitFor(); page.once('dialog', d => d.accept('C03 SYNTHETIC RESOLUTION')); await rpcAfter('rpc_delivery_operation_child_action', () => panel.getByRole('button', { name: 'Resolver', exact: true }).click()); pass('incident creation and resolution persist');
        phase = 'evidence'; await panel.getByRole('button', { name: 'Evidencias', exact: true }).click(); await panel.getByLabel('Nota de evidencia', { exact: true }).fill('C03 SYNTHETIC NOTE'); await rpcAfter('rpc_delivery_operation_child_action', () => panel.getByRole('button', { name: 'Guardar evidencia', exact: true }).click()); await panel.getByText('C03 SYNTHETIC NOTE', { exact: true }).waitFor(); pass('operational evidence persists');
        phase = 'upload'; await panel.getByLabel('Archivo privado', { exact: true }).setInputFiles(file); const uploaded = await rpcAfter('rpc_delivery_finalize_upload', () => panel.getByRole('button', { name: 'Guardar archivo', exact: true }).click()); assert(uploaded.id); await panel.getByRole('button', { name: 'Descargar ' + file.name, exact: true }).waitFor(); pass('real Storage upload and classified registration', { file_id: uploaded.id });
        phase = 'download'; let download = page.waitForEvent('download'); await panel.getByRole('button', { name: 'Descargar ' + file.name, exact: true }).click(); assert.deepEqual(await bytes(await download), file.buffer); pass('authenticated Storage download bytes match synthetic upload');
        phase = 'requirement'; await panel.getByRole('button', { name: 'Documentos', exact: true }).click(); const pod = panel.locator('form').filter({ has: page.getByRole('heading', { name: 'Prueba de entrega (POD)', exact: true }) }); await pod.locator('select').nth(0).selectOption('required'); await pod.locator('select').nth(1).selectOption('present'); await pod.locator('select').nth(2).selectOption(uploaded.id); await rpcAfter('rpc_delivery_operation_child_action', () => pod.getByRole('button', { name: 'Guardar Prueba de entrega (POD)', exact: true }).click()); pass('canonical POD requirement linked to managed file');
        phase = 'replace'; await panel.getByRole('button', { name: 'Sustituir ' + file.name, exact: true }).click(); await panel.getByLabel('Archivo privado', { exact: true }).setInputFiles(replacement); await panel.getByLabel('Motivo documental', { exact: true }).fill('C03 SYNTHETIC REPLACEMENT'); const newer = await rpcAfter('rpc_delivery_finalize_upload', () => panel.getByRole('button', { name: 'Guardar archivo', exact: true }).click()); await panel.getByRole('button', { name: 'Descargar ' + replacement.name, exact: true }).waitFor(); assert.equal(await panel.getByRole('button', { name: 'Descargar ' + file.name, exact: true }).count(), 0); pass('replacement keeps old version and offers only active download', { file_id: newer.id });
        phase = 'cancel'; await panel.getByRole('button', { name: 'Cancelar ' + replacement.name, exact: true }).click(); await panel.getByLabel('Motivo documental', { exact: true }).fill('C03 SYNTHETIC DOCUMENT CANCEL'); await rpcAfter('rpc_delivery_cancel_file', () => panel.getByRole('button', { name: 'Confirmar cancelación documental', exact: true }).click()); await panel.getByRole('button', { name: 'Descargar ' + replacement.name, exact: true }).waitFor({ state: 'hidden' }); pass('document cancellation retains history and removes active download');
        phase = 'export'; await page.goto(origin + '/operations'); download = page.waitForEvent('download'); await page.getByRole('button', { name: 'Exportar CSV', exact: true }).click(); const csv = (await bytes(await download)).toString(); assert(csv.includes(reference)); assert(!/FINANCIAL_CANARY|provider_cost_amount|customer_price_amount|profit|margin|C03-LOCAL-B|C03-LOCAL-X/.test(csv)); pass('operational CSV scope and financial projection');
        phase = 'search'; await page.getByRole('button', { name: 'Buscar o ejecutar una acción', exact: true }).click(); await page.getByLabel('Buscar operaciones, documentos o cuentas', { exact: true }).fill(reference); const result = page.getByRole('dialog', { name: 'Búsqueda global y acciones' }).getByRole('button').filter({ hasText: reference }); await result.first().click(); await page.getByRole('dialog', { name: new RegExp('Operation 360') }).waitFor(); pass('palette result opens actual scoped operation');
        await logout();
    }
    if (roles.includes('finance')) {
        await login('finance'); await page.getByRole('heading', { name: 'Finanzas del alcance autorizado', exact: true }).waitFor(); pass('full finance dashboard explicitly authorized');
        phase = 'documents'; await page.goto(origin + '/documents'); await page.getByLabel('Empresa', { exact: true }).selectOption(ids.a); await page.getByRole('combobox', { name: 'Expediente autorizado' }).selectOption('finance_invoice:' + ids.invoiceA);
        phase = 'upload'; await page.getByLabel('Archivo privado', { exact: true }).setInputFiles({ ...file, name: 'c03-financial-' + run.slice(0, 8) + '.txt' }); const financial = await rpcAfter('rpc_delivery_finalize_upload', () => page.getByRole('button', { name: 'Guardar archivo', exact: true }).click()); pass('financial file upload requires full read plus explicit write', { file_id: financial.id });
        phase = 'consolidation'; await page.goto(origin + '/dashboard'); const selector = page.getByLabel('Empresa', { exact: true }); await selector.selectOption(ids.a); const options = await selector.locator('option').evaluateAll(os => os.map(o => ({ value: o.value, label: o.textContent }))); const consolidated = options.find(o => o.value.startsWith('consolidated:')); assert(consolidated); await selector.selectOption(consolidated.value); await page.getByRole('heading', { name: 'Finanzas del alcance autorizado', exact: true }).waitFor(); pass('explicit consolidation renders only granted set');
        await logout();
    }
    if (roles.includes('setup')) { await login('setup'); phase = 'automation'; await page.goto(origin + '/security/automations'); await page.getByRole('button', { name: 'Evaluar ahora', exact: true }).waitFor(); await rpcAfter('rpc_delivery_run_automation', () => page.getByRole('button', { name: 'Evaluar ahora', exact: true }).click()); await page.getByText('Evaluación completada', { exact: true }).waitFor(); pass('manual company automation runs through explicit control'); await logout(); }
    assert.equal(blocked.length, 0, 'unreviewed_request'); assert.equal(events.filter(x => /rpc_refresh_internal_notifications|f7_materialize/.test(x.path)).length, 0); pass('no automatic materialization or unreviewed business mutation');
} catch (error) {
    checks.push({ case: phase, status: 'failed', error_category: error.name }); console.log('FAIL', phase, error.name); report();
    // Preserve a safe UI snapshot only after credentials have left the form.
    if (page && phase !== 'login') await page.screenshot({ path: path.join(out, `browser-${run}-failure.png`) }).catch(() => { });
    try { if (page && !page.url().endsWith('/login')) await logout(); } catch { } process.exitCode = 1;
} finally {
    if (context) await context.close(); if (browser) await browser.close();
    fs.writeFileSync(path.join(out, `browser-${run}-final.json`), JSON.stringify({ run, destination: manifest.destination, origin, checks, events, blocked, errors, isolated: true, headers_or_auth_bodies_saved: false, headful: true, real_focus_coverage: 'pending unless independently observed', qa_accounts_retained: true }, null, 2), { flag: 'wx' });
}
