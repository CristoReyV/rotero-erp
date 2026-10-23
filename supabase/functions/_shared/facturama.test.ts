import test from 'node:test';
import assert from 'node:assert/strict';
import {
    canonical,
    cents,
    FacturamaSandbox,
    sha256,
    TEST_ISSUER,
    validatePayload,
    verifyCancellationAck,
    verifyXml,
} from './facturama.ts';
import { executeFiscal, type FiscalStore, invoiceFromSource } from './facturama-executor.ts';
const uuid = 'c8cebf7a-8321-4b0a-afbe-122f71de509f';
function invoice() {
    return invoiceFromSource({
        serie: 'QATEST',
        folio: 'QA-100',
        currency: 'MXN',
        subtotal: 100,
        total: 116,
        fiscal_input: { concepts: [{ description: 'Synthetic contracted logistics service', amount: 100 }] },
    }, '2026-10-23T12:00:00');
}
function xml(p = invoice()) {
    return new TextEncoder().encode(
        `<?xml version="1.0"?><cfdi:Comprobante xmlns:cfdi="http://www.sat.gob.mx/cfd/4" Version="4.0" Sello="synthetic" Certificado="synthetic" Fecha="${p.Date}" Folio="${p.Folio}" Serie="${p.Serie}" TipoDeComprobante="I" Moneda="MXN" MetodoPago="PPD" SubTotal="100.00" Total="116.00"><cfdi:Emisor Rfc="EKU9003173C9" Nombre="ESCUELA KEMPER URGATE"/><cfdi:Receptor Rfc="URE180429TM6" Nombre="UNIVERSIDAD ROBOTICA ESPAÑOLA"/><cfdi:Complemento><tfd:TimbreFiscalDigital xmlns:tfd="http://www.sat.gob.mx/TimbreFiscalDigital" Version="1.1" UUID="${uuid}" SelloSAT="synthetic" FechaTimbrado="2026-10-23T12:00:01"/></cfdi:Complemento></cfdi:Comprobante>`,
    );
}
const config = { username: 'synthetic-user', password: 'synthetic-not-a-credential', environment: 'sandbox' };
test('sandbox only; invalid host, environment and missing credentials denied', () => {
    for (
        const c of [
            { ...config, environment: 'production' },
            { ...config, baseUrl: 'https://api.facturama.mx' },
            { ...config, baseUrl: 'https://apisandbox.facturama.mx/' },
            { ...config, username: '' },
        ]
    ) assert.throws(() => new FacturamaSandbox(c));
});
test('cent arithmetic, canonical hash independent of object key order', async () => {
    assert.equal(cents('0.01'), 1n);
    assert.equal(cents(116), 11600n);
    for (const v of ['-1', 'NaN', '1.001', '1e3', null]) assert.throws(() => cents(v));
    assert.equal(await sha256(canonical({ b: 2, a: 1 })), await sha256(canonical({ a: 1, b: 2 })));
});
test('invoice validation rejects amounts, real RFC, arbitrary URL or tax type', () => {
    validatePayload(invoice());
    for (
        const change of [
            (p: any) => p.Issuer.Rfc = 'WLS110325JH8',
            (p: any) => p.Items[0].Total = 100,
            (p: any) => p.Items[0].Taxes[0].Rate = 0.08,
            (p: any) => p.LogoUrl = 'https://example.invalid',
            (p: any) => p.Receiver.Rfc = 'XAXX010101000',
        ]
    ) {
        const p = invoice();
        change(p);
        assert.throws(() => validatePayload(p));
    }
});
test('XML verified by UUID, namespaces, issuer/receiver, frozen identity and totals', () => {
    assert.equal(verifyXml(xml(), invoice(), uuid).uuid, uuid);
    const raw = new TextDecoder().decode(xml());
    for (
        const changed of [
            raw.replace('Total="116.00"', 'Total="117.00"'),
            raw.replace('sat.gob.mx/cfd/4', 'attacker.invalid/cfd/4'),
            raw.replace('EKU9003173C9', 'WLS110325JH8'),
            raw.replace('QA-100', 'QA-200'),
            raw.replace('<cfdi:Emisor', '<cfdi:Emisor Rfc="duplicate"'),
            '<!DOCTYPE x [<!ENTITY a SYSTEM "file:///private">]>' + raw,
        ]
    ) assert.throws(() => verifyXml(new TextEncoder().encode(changed), invoice(), uuid));
    assert.throws(() => verifyXml(xml(), invoice(), '00000000-0000-4000-8000-000000000000'));
});
test('Basic Auth server transport; redirect denied without forwarding credentials', async () => {
    const calls: any[] = [];
    const adapter = new FacturamaSandbox(config, async (url, init) => {
        calls.push({ url, init });
        return new Response(null, { status: 302, headers: { location: 'https://untrusted.invalid' } });
    });
    await assert.rejects(() => adapter.listCsds(), { code: 'redirect_blocked' });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://apisandbox.facturama.mx/api-lite/csds');
    assert.equal(calls[0].init.redirect, 'manual');
    assert.match(calls[0].init.headers.Authorization, /^Basic /);
});
test('mutating HTTP 500, timeout, malformed response remain uncertain', async () => {
    for (
        const transport of [async () => new Response('{}', { status: 500 }), async () => {
            throw new Error('private raw message');
        }, async () => new Response('not json')]
    ) {
        const adapter = new FacturamaSandbox(config, transport);
        await assert.rejects(
            () => adapter.create(invoice()),
            (e: any) => e.uncertain && !e.message.includes('private raw'),
        );
    }
});
test('large response is bounded; forbidden host/path cannot be used', async () => {
    const adapter = new FacturamaSandbox(config, async () => new Response('a'.repeat(3_000_001)));
    await assert.rejects(() => adapter.listCsds(), { code: 'response_too_large' });
    await assert.rejects(() => adapter.request('GET', 'https://api.facturama.mx/Client'), {
        code: 'forbidden_endpoint',
    });
});
function memoryStore() {
    const d: any = {
        tenant_id: 'tenant',
        company_id: 'company',
        provider_payload: invoice(),
        provider_document_id: null,
        fiscal_uuid: null,
    };
    const files = new Map<string, Uint8Array>();
    let busy = false, uncertain = false, stamped = false, token = 0;
    const actions: string[] = [];
    const store: FiscalStore = {
        async worker(_id, _actor, action, data = {}) {
            actions.push(action);
            if (action === 'claim' || action === 'status') {
                if (busy) return { busy: true };
                if (action === 'claim' && (uncertain || stamped)) return { reconcile_required: true };
                busy = true;
                token++;
                uncertain = action === 'claim' || uncertain;
                return { ...d, busy_token: String(token) };
            }
            if (data.busy_token !== String(token)) throw new Error('stale');
            if (action === 'identified') d.provider_document_id = data.provider_document_id;
            if (action === 'verified') {
                stamped = true;
                uncertain = false;
                busy = false;
                d.fiscal_uuid = data.uuid;
            }
            if (action === 'uncertain') {
                uncertain = true;
                busy = false;
            }
            if (action === 'release') busy = false;
            return { saved: true };
        },
        async upload(path, bytes) {
            files.set(path, bytes);
        },
        async download(path) {
            return files.get(path)!;
        },
    };
    return { store, actions, files };
}
test('double activation claims once, verifies XML, stores privately, never sends twice', async () => {
    let posts = 0;
    const m = memoryStore();
    const adapter = new FacturamaSandbox(config, async (_url, init) => {
        if (init?.method === 'POST') {
            posts++;
            await new Promise((r) => setTimeout(r, 15));
            return Response.json({ Id: 'test-id' });
        }
        return Response.json({ ContentEncoding: 'base64', Content: Buffer.from(xml()).toString('base64') });
    });
    const result = await Promise.all([
        executeFiscal(m.store, adapter, 'actor', 'doc', 'issue'),
        executeFiscal(m.store, adapter, 'actor', 'doc', 'issue'),
    ]);
    assert.equal(posts, 1);
    assert.ok(result.some((r: any) => r.status === 'stamped'));
    assert.equal(m.files.size, 1);
    await executeFiscal(m.store, adapter, 'actor', 'doc', 'issue');
    assert.equal(posts, 1);
    assert.ok(m.actions.includes('identified'));
});
test('lost POST result: no blind retry, status reconciles and verifies found XML', async () => {
    let posts = 0;
    const m = memoryStore();
    const p = invoice();
    const adapter = new FacturamaSandbox(config, async (url, init) => {
        if (init?.method === 'POST') {
            posts++;
            throw new Error('timeout');
        }
        if (String(url).includes('?')) return Response.json([{ Id: 'reconciled-id' }]);
        if (String(url).includes('/api-lite/cfdis/')) {
            return Response.json({ Id: 'reconciled-id', Folio: p.Folio, Date: p.Date, Issuer: TEST_ISSUER });
        }
        return Response.json({ ContentEncoding: 'base64', Content: Buffer.from(xml()).toString('base64') });
    });
    await assert.rejects(() => executeFiscal(m.store, adapter, 'actor', 'doc', 'issue'));
    assert.equal(
        (await executeFiscal(m.store, adapter, 'actor', 'doc', 'issue') as any).reconcile_required,
        true,
    );
    assert.equal((await executeFiscal(m.store, adapter, 'actor', 'doc', 'status') as any).status, 'stamped');
    assert.equal(posts, 1);
});
test('successful HTTP with mismatched XML cannot mark stamped', async () => {
    const m = memoryStore();
    const adapter = new FacturamaSandbox(
        config,
        async (_url, init) =>
            init?.method === 'POST' ? Response.json({ Id: 'bad' }) : Response.json({
                ContentEncoding: 'base64',
                Content: Buffer.from('<x/>').toString('base64'),
            }),
    );
    await assert.rejects(() => executeFiscal(m.store, adapter, 'actor', 'doc', 'issue'));
    assert.equal(m.files.size, 0);
    assert.ok(m.actions.includes('uncertain'));
    assert.ok(!m.actions.includes('verified'));
});
test('payment validation: partial, multiple invoices, conservation and duplicate denial', () => {
    const p: any = {
        NameId: '14',
        CfdiType: 'P',
        Serie: 'QAPMT',
        Folio: 'QA-200',
        Date: '2026-10-23T12:00:00',
        ExpeditionPlace: '42501',
        Issuer: TEST_ISSUER,
        Receiver: {
            Rfc: 'URE180429TM6',
            Name: 'UNIVERSIDAD ROBOTICA ESPAÑOLA',
            FiscalRegime: '601',
            TaxZipCode: '86991',
            CfdiUse: 'CP01',
        },
        Complemento: {
            Payments: [{
                Date: '2026-10-23T12:00:00',
                PaymentForm: '03',
                Currency: 'MXN',
                Amount: 58,
                RelatedDocuments: [{
                    Uuid: uuid,
                    Currency: 'MXN',
                    TaxObject: '02',
                    PartialityNumber: 1,
                    PreviousBalanceAmount: 116,
                    AmountPaid: 58,
                    ImpSaldoInsoluto: 58,
                    Taxes: [{ Name: 'IVA', Rate: 0.16, Base: 50, Total: 8, IsRetention: false }],
                }],
            }],
        },
    };
    validatePayload(p);
    p.Complemento.Payments[0].RelatedDocuments.push({ ...p.Complemento.Payments[0].RelatedDocuments[0] });
    assert.throws(() => validatePayload(p));
});
test('cancellation acknowledgement must correlate its XML UUID, not merely HTTP/status', () => {
    const ack = (id: string) =>
        new TextEncoder().encode(
            `<Acuse RfcEmisor="EKU9003173C9"><Folios><UUID>${id}</UUID><EstatusUUID>201</EstatusUUID></Folios></Acuse>`,
        );
    verifyCancellationAck(ack(uuid), uuid);
    assert.throws(() => verifyCancellationAck(ack('0088B8E0-00DE-43D7-A590-8328B803839F'), uuid), {
        code: 'unconfirmed_cancellation_ack',
    });
    assert.throws(() => verifyCancellationAck(new TextEncoder().encode('<not-xml'), uuid));
    assert.throws(() =>
        verifyCancellationAck(
            new TextEncoder().encode(
                new TextDecoder().decode(ack(uuid)).replace('EKU9003173C9', 'WLS110325JH8'),
            ),
            uuid,
        )
    );
});
test('HTTP 400 before a provider ID is a rejection, not an uncertain submission', async () => {
    const m = memoryStore();
    const adapter = new FacturamaSandbox(
        config,
        async () => Response.json({ ModelState: { 'cfdi.Receiver': ['synthetic issue'] } }, { status: 400 }),
    );
    await assert.rejects(
        () => executeFiscal(m.store, adapter, 'actor', 'doc', 'issue'),
        (e: any) => e.httpStatus === 400 && !e.uncertain && e.validationFields.includes('cfdi.Receiver'),
    );
    assert.ok(m.actions.includes('rejected'));
    assert.ok(!m.actions.includes('uncertain'));
});
test('sandbox credentials cannot be serialized with the adapter', () => {
    const adapter = new FacturamaSandbox(config);
    assert.ok(!JSON.stringify(adapter).includes(config.password));
    assert.ok(
        !JSON.stringify(adapter).includes(
            Buffer.from(config.username + ':' + config.password).toString('base64'),
        ),
    );
});
test('canonical provider boundary requires frozen serialization and never returns a final state from HTTP alone', async () => {
    const adapter = new FacturamaSandbox(
        config,
        async (_url, init) =>
            Response.json(init?.method === 'POST' ? { Id: 'canonical-id' } : { Status: 'canceled' }),
    );
    const request: any = {
        requestId: 'request',
        tenantId: 'tenant',
        billingCfdiId: 'cfdi',
        requestType: 'stamp',
        idempotencyKey: 'a'.repeat(64),
        environment: 'sandbox',
        payloadSnapshot: { schema: 'rotero.fiscal-input' },
    };
    await assert.rejects(() => adapter.submit(request), { code: 'frozen_provider_snapshot_required' });
    const result = await adapter.submit({ ...request, providerPayloadSnapshot: invoice() });
    assert.equal(result.outcome, 'processing');
    assert.equal(result.providerDocumentId, 'canonical-id');
    assert.equal(result.fiscalUuid, undefined);
    assert.equal(
        (await adapter.getStatus({ ...request, providerDocumentId: 'canonical-id' })).outcome,
        'processing',
    );
    assert.equal(
        (await adapter.cancel({
            ...request,
            providerDocumentId: 'canonical-id',
            payloadSnapshot: { motive: '03' },
        })).outcome,
        'processing',
    );
});

test('cancel confirms the exact remote identity, quarantines foreign XML, keeps a recoverable state', async () => {
    const saved: string[] = [], files: string[] = [], methods: string[] = [];
    const store: FiscalStore = {
        async worker(_id, _actor, action, data = {}) {
            saved.push(action);
            if (action === 'cancel') {
                return {
                    busy_token: 'lease',
                    tenant_id: 'tenant',
                    company_id: 'company',
                    provider_payload: invoice(),
                    provider_document_id: 'test-id',
                    fiscal_uuid: uuid,
                    cancellation_options: { motive: '02' },
                };
            }
            assert.equal(data.busy_token, 'lease');
            return { saved: true };
        },
        async upload(path) {
            files.push(path);
        },
        async download() {
            throw new Error('not used');
        },
    };
    const badAck = Buffer.from(
        '<Acuse RfcEmisor="EKU9003173C9"><Folios><UUID>0088B8E0-00DE-43D7-A590-8328B803839F</UUID><EstatusUUID>201</EstatusUUID></Folios></Acuse>',
    ).toString('base64');
    const adapter = new FacturamaSandbox(config, async (url, init) => {
        methods.push(init!.method!);
        if (init?.method === 'DELETE') {
            assert.ok(String(url).endsWith('?motive=02'));
            return Response.json({ Status: 'canceled', Uuid: uuid, AcuseXmlBase64: badAck });
        }
        return Response.json({
            Id: 'test-id',
            Status: 'canceled',
            Issuer: TEST_ISSUER,
            Complement: { TaxStamp: { Uuid: uuid } },
        });
    });
    const result: any = await executeFiscal(store, adapter, 'actor', 'doc', 'cancel', {
        motive: '03',
        recoverAck: true,
    });
    assert.equal(result.remoteCancellation, 'confirmed');
    assert.equal(result.acknowledgement, 'mismatch');
    assert.deepEqual(methods, ['GET', 'DELETE', 'GET']);
    assert.ok(
        saved.includes('cancel_confirmed') && saved.includes('cancel_ack_invalid') &&
            saved.includes('release'),
    );
    assert.ok(!saved.includes('cancelled') && !saved.includes('uncertain'));
    assert.equal(files.length, 1);
    assert.ok(files[0].includes('/unverified-cancellation-'));
});
test('ack recovery does not repeat DELETE while remote cancellation is pending', async () => {
    let deletes = 0;
    const actions: string[] = [];
    const store: FiscalStore = {
        async worker(_id, _actor, action) {
            actions.push(action);
            return action === 'cancel'
                ? {
                    busy_token: 'lease',
                    provider_payload: invoice(),
                    provider_document_id: 'test-id',
                    fiscal_uuid: uuid,
                }
                : { saved: true };
        },
        async upload() {
            throw new Error('not used');
        },
        async download() {
            throw new Error('not used');
        },
    };
    const adapter = new FacturamaSandbox(config, async (_url, init) => {
        if (init?.method === 'DELETE') deletes++;
        return Response.json({
            Id: 'test-id',
            Status: 'active',
            Issuer: TEST_ISSUER,
            Complement: { TaxStamp: { Uuid: uuid } },
        });
    });
    await executeFiscal(store, adapter, 'actor', 'doc', 'cancel', { motive: '03', recoverAck: true });
    assert.equal(deletes, 0);
    assert.ok(actions.includes('release'));
});
