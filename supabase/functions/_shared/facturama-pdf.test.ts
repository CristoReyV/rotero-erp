import test from 'node:test';
import assert from 'node:assert/strict';
import {
    decodeCancellationPdf,
    FacturamaSandbox,
    FiscalFailure,
    sha256,
    TEST_ISSUER,
    verifyCancellationAck,
} from './facturama.ts';
import { executeFiscal, type FiscalStore } from './facturama-executor.ts';

const config = { username: 'synthetic', password: 'synthetic', environment: 'sandbox', timeoutMs: 5 };
const uuid = '70000000-0000-4000-8000-000000000004';
const pdf = new TextEncoder().encode('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n%%EOF\n');
const response = {
    ContentType: 'pdf',
    ContentEncoding: 'base64',
    ContentLength: pdf.length,
    Content: Buffer.from(pdf).toString('base64'),
};
const remote = {
    Id: 'persisted-provider',
    Status: 'canceled',
    Issuer: TEST_ISSUER,
    Complement: { TaxStamp: { Uuid: uuid } },
};
function fixture(transport: typeof fetch = async () => Response.json(response)) {
    const calls: string[] = [], http: { method: string; url: string }[] = [];
    const state: any = {
        provider_document_id: remote.Id,
        fiscal_uuid: uuid,
        tenant_id: 'tenant',
        company_id: 'company',
        remote_cancel_status: 'canceled',
    };
    const files = new Map<string, Uint8Array>();
    const store: FiscalStore = {
        async worker(_id, _actor, action, data) {
            calls.push(action);
            if (action === 'load') return { ...state };
            if (action === 'observe_cancel') {
                assert.equal(data?.uuid, uuid);
                state.confirmed = true;
                return { status: 'cancelled' };
            }
            if (action === 'pdf_claim') return { ...state, busy_token: 'lease' };
            if (action === 'pdf_save') {
                state.cancellation_pdf_path = data!.path;
                state.hash = data!.sha256;
                return { saved: true };
            }
            if (action === 'pdf_load') return { path: state.cancellation_pdf_path, sha256: state.hash };
            if (action === 'pdf_release') return { saved: true };
            throw Error('Unexpected worker action');
        },
        async upload(path, bytes, type) {
            assert.equal(type, 'application/pdf');
            files.set(path, bytes);
        },
        async download(path) {
            assert.ok(files.has(path));
            return files.get(path)!;
        },
    };
    const adapter = new FacturamaSandbox(config, async (url, init) => {
        http.push({ method: init!.method!, url: String(url) });
        assert.equal(init?.redirect, 'manual');
        if (String(url).endsWith('/api-lite/cfdis/' + remote.Id)) return Response.json(remote);
        return transport(url, init);
    });
    return { store, adapter, calls, http, state, files };
}
test('observed Content/base64 and documented Data/UTF-8 decode only bounded PDF bytes', () => {
    assert.deepEqual(decodeCancellationPdf(response), pdf);
    assert.deepEqual(
        decodeCancellationPdf({
            ContentType: 'application/pdf',
            ContentEncoding: 'UTF-8',
            Data: response.Content,
        }),
        pdf,
    );
    for (
        const data of [
            {},
            { ...response, Content: 'not base64' },
            { ...response, ContentLength: 1 },
            { ...response, ContentType: 'html' },
            { ...response, ContentEncoding: 'binary' },
            { ...response, Data: 'different' },
            { ...response, Content: Buffer.from('<html>not PDF</html>').toString('base64') },
            { ...response, Content: 'A'.repeat(2_666_672) },
            { ...response, Content: Buffer.from('%PDF-1.4\ntruncated').toString('base64') },
        ]
    ) {
        assert.throws(() => decodeCancellationPdf(data), { code: 'invalid_ack_pdf' });
    }
});
test('PDF recovery uses only persisted ID and GET, stores once, and authenticated download verifies hash', async () => {
    const f = fixture();
    const result: any = await executeFiscal(f.store, f.adapter, 'actor', 'doc', 'recover_pdf', {
        url: 'https://evil.test',
        providerId: 'wrong',
    });
    assert.equal(result.pdfAvailable, true);
    assert.deepEqual(f.http.map((x) => x.method), ['GET', 'GET']);
    assert.ok(f.http[1].url.endsWith('/acuse/pdf/issuedLite/persisted-provider'));
    assert.deepEqual(f.calls, ['load', 'observe_cancel', 'pdf_claim', 'pdf_save']);
    assert.equal(f.state.hash, await sha256(pdf));
    assert.equal(f.state.fiscal_uuid, uuid);
    assert.deepEqual(await executeFiscal(f.store, f.adapter, 'actor', 'doc', 'ack_pdf'), pdf);
    await executeFiscal(f.store, f.adapter, 'actor', 'doc', 'recover_pdf');
    assert.equal(f.http.length, 2);
    assert.equal(f.files.size, 1);
    f.files.set(f.state.cancellation_pdf_path, new Uint8Array([0]));
    await assert.rejects(() => executeFiscal(f.store, f.adapter, 'actor', 'doc', 'ack_pdf'), {
        code: 'artifact_integrity_failed',
    });
});
test('PDF errors leave cancellation confirmed, release only the PDF lease, never create fiscal attempts or DELETE', async () => {
    for (
        const transport of [
            async () => Response.json({ ContentType: 'pdf' }),
            async () => new Response('unavailable', { status: 503 }),
            async () => new Response(null, { status: 302, headers: { location: 'https://evil.test' } }),
            async (_url: any, init: any) =>
                new Promise<Response>((_resolve, reject) =>
                    init.signal.addEventListener('abort', () => reject(Error('synthetic timeout')))
                ),
        ] as (typeof fetch)[]
    ) {
        const f = fixture(transport);
        await assert.rejects(
            () => executeFiscal(f.store, f.adapter, 'actor', 'doc', 'recover_pdf'),
            FiscalFailure,
        );
        assert.equal(f.state.confirmed, true);
        assert.equal(f.state.remote_cancel_status, 'canceled');
        assert.deepEqual(f.calls, ['load', 'observe_cancel', 'pdf_claim', 'pdf_release']);
        assert.ok(f.http.every((x) => x.method === 'GET'));
        assert.equal(f.files.size, 0);
    }
});
test('denial and missing persisted identity stop before provider; PDF URL cannot be supplied or mutated', async () => {
    const f = fixture();
    f.store.worker = async () => {
        throw new FiscalFailure('fiscal_forbidden');
    };
    for (const action of ['recover_pdf', 'ack_pdf']) {
        await assert.rejects(() => executeFiscal(f.store, f.adapter, 'denied', 'other-doc', action), {
            code: 'fiscal_forbidden',
        });
    }
    assert.equal(f.http.length, 0);
    const draft = fixture();
    delete draft.state.provider_document_id;
    await assert.rejects(() => executeFiscal(draft.store, draft.adapter, 'actor', 'doc', 'recover_pdf'), {
        code: 'cancellation_not_confirmed',
    });
    assert.equal(draft.http.length, 0);
    await assert.rejects(() => draft.adapter.cancellationPdf('https://evil.test'), {
        code: 'invalid_provider_id',
    });
    await assert.rejects(() => draft.adapter.request('DELETE', '/acuse/pdf/issuedLite/persisted-provider'), {
        code: 'forbidden_endpoint',
    });
});
test('support clarification does not relax fiscal XML or approve an unrelated acknowledgement', () => {
    const bytes = new TextEncoder().encode(
        '<Acuse RfcEmisor="EKU9003173C9"><Folios><UUID>0088b8e0-00de-43d7-a590-8328b803839f</UUID><EstatusUUID>201</EstatusUUID></Folios></Acuse>',
    );
    assert.throws(() => verifyCancellationAck(bytes, uuid), { code: 'unconfirmed_cancellation_ack' });
});

test('uncorrelated remote status cannot finalize or recover a PDF for a different document', async () => {
    const f = fixture();
    f.adapter.detail = async () => ({ ...remote, Id: 'different-persisted-ID' });
    await assert.rejects(() => executeFiscal(f.store, f.adapter, 'actor', 'doc', 'recover_pdf'), {
        code: 'uncorrelated_cancellation_status',
    });
    assert.deepEqual(f.calls, ['load']);
    assert.equal(f.files.size, 0);
});
