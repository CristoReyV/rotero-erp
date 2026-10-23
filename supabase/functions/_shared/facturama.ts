// Server only. Never import from src/. Transport has one immutable sandbox host.
import { XMLParser, XMLValidator } from 'fast-xml-parser';
import type {
    FiscalArtifact,
    FiscalCanonicalRequest,
    FiscalNormalizedResult,
    FiscalProviderAdapter,
} from './fiscal-provider.ts';

export const SANDBOX = 'https://apisandbox.facturama.mx';
export const TEST_ISSUER = Object.freeze({
    Rfc: 'EKU9003173C9',
    Name: 'ESCUELA KEMPER URGATE',
    FiscalRegime: '601',
});
export class FiscalFailure extends Error {
    constructor(
        readonly code: string,
        readonly httpStatus?: number,
        readonly uncertain = false,
        readonly validationFields: string[] = [],
    ) {
        super(code);
    }
}
export type Json = Record<string, any>;
export function cents(value: unknown): bigint {
    const s = String(value);
    if (!/^\d{1,12}(?:\.\d{1,2})?$/.test(s)) throw new FiscalFailure('invalid_amount');
    const [whole, fraction = ''] = s.split('.');
    return BigInt(whole) * 100n + BigInt(fraction.padEnd(2, '0'));
}
export function money(n: bigint): number {
    return Number(n) / 100;
}
export function canonical(value: unknown): string {
    if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
    if (value && typeof value === 'object') {
        return '{' + Object.keys(value).sort().map((k) =>
            JSON.stringify(k) + ':' + canonical((value as Json)[k])
        ).join(',') + '}';
    }
    if (value === undefined || (typeof value === 'number' && !Number.isFinite(value))) {
        throw new FiscalFailure('invalid_payload');
    }
    return JSON.stringify(value);
}
export async function sha256(value: string | Uint8Array): Promise<string> {
    const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
    return Array.from(
        new Uint8Array(await crypto.subtle.digest('SHA-256', bytes as BufferSource)),
        (n) => n.toString(16).padStart(2, '0'),
    ).join('');
}
export function validatePayload(p: Json): void {
    if (
        !p || p.Issuer?.Rfc !== TEST_ISSUER.Rfc || p.Issuer?.Name !== TEST_ISSUER.Name ||
        p.Issuer?.FiscalRegime !== '601'
    ) throw new FiscalFailure('test_issuer_required');
    if (
        p.Receiver?.Rfc !== 'URE180429TM6' || p.Receiver?.Name !== 'UNIVERSIDAD ROBOTICA ESPAÑOLA' ||
        p.Receiver?.FiscalRegime !== '601' || p.Receiver?.TaxZipCode !== '86991'
    ) throw new FiscalFailure('test_receiver_required');
    if (
        !/^[A-Z0-9-]{1,40}$/.test(p.Folio) || !/^QA[A-Z0-9]{1,8}$/.test(p.Serie) ||
        !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/.test(p.Date) || p.ExpeditionPlace !== '42501'
    ) throw new FiscalFailure('invalid_identity');
    if (
        Object.keys(p).some((k) =>
            ![
                'NameId',
                'Currency',
                'Folio',
                'Serie',
                'CfdiType',
                'PaymentForm',
                'PaymentMethod',
                'ExpeditionPlace',
                'Date',
                'Exportation',
                'Issuer',
                'Receiver',
                'Items',
                'Complemento',
            ].includes(k)
        )
    ) throw new FiscalFailure('unsupported_field');
    if (p.CfdiType === 'I') {
        if (
            p.Currency !== 'MXN' || p.PaymentMethod !== 'PPD' || p.PaymentForm !== '99' ||
            p.Receiver.CfdiUse !== 'G03' || !Array.isArray(p.Items) || !p.Items.length ||
            p.Items.length > 50 || p.Complemento
        ) throw new FiscalFailure('invalid_invoice');
        for (const line of p.Items) {
            if (
                line.Quantity !== 1 || line.TaxObject !== '02' || line.ProductCode !== '78101800' ||
                line.UnitCode !== 'E48' || !Array.isArray(line.Taxes) || line.Taxes.length !== 1
            ) throw new FiscalFailure('unsupported_tax');
            const base = cents(line.Subtotal), tax = line.Taxes[0], vat = (base * 16n + 50n) / 100n;
            if (
                !base || cents(line.UnitPrice) !== base || cents(tax.Base) !== base ||
                cents(tax.Total) !== vat || tax.Rate !== 0.16 || tax.Name !== 'IVA' ||
                tax.IsRetention !== false || cents(line.Total) !== base + vat || line.Discount
            ) throw new FiscalFailure('invalid_totals');
        }
    } else if (p.CfdiType === 'P') {
        if (p.Currency || p.Items || p.PaymentMethod || p.PaymentForm || p.Receiver.CfdiUse !== 'CP01') {
            throw new FiscalFailure('invalid_payment');
        }
        const payments = p.Complemento?.Payments;
        if (!Array.isArray(payments) || payments.length !== 1) throw new FiscalFailure('invalid_payment');
        const payment = payments[0], seen = new Set<string>();
        let sum = 0n;
        if (
            payment.Currency !== 'MXN' || payment.PaymentForm !== '03' ||
            !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/.test(payment.Date) ||
            !Array.isArray(payment.RelatedDocuments) || !payment.RelatedDocuments.length
        ) throw new FiscalFailure('invalid_payment');
        for (const d of payment.RelatedDocuments) {
            if (
                !/^[0-9a-f-]{36}$/i.test(d.Uuid) || seen.has(d.Uuid.toLowerCase()) || d.Currency !== 'MXN' ||
                d.TaxObject !== '02' || !Number.isSafeInteger(d.PartialityNumber) || d.PartialityNumber < 1
            ) throw new FiscalFailure('invalid_application');
            seen.add(d.Uuid.toLowerCase());
            const paid = cents(d.AmountPaid), before = cents(d.PreviousBalanceAmount);
            if (paid <= 0n || paid > before || before - paid !== cents(d.ImpSaldoInsoluto)) {
                throw new FiscalFailure('invalid_balance');
            }
            const tax = d.Taxes?.[0], base = (paid * 100n + 58n) / 116n;
            if (
                d.Taxes?.length !== 1 || !tax || tax.Name !== 'IVA' || tax.Rate !== 0.16 ||
                tax.IsRetention !== false || cents(tax.Base) !== base || cents(tax.Total) !== paid - base
            ) throw new FiscalFailure('invalid_payment_tax');
            sum += paid;
        }
        if (sum !== cents(payment.Amount)) throw new FiscalFailure('unallocated_payment');
    } else throw new FiscalFailure('unsupported_cfdi');
}

function one(node: Json, local: string, uri: string, namespaces: Json): Json {
    const keys = Object.keys(node).filter((k) => !k.startsWith('@_') && k.split(':').pop() === local);
    if (
        keys.length !== 1 || !node[keys[0]] || Array.isArray(node[keys[0]]) ||
        typeof node[keys[0]] !== 'object'
    ) throw new FiscalFailure('invalid_xml_structure');
    const key = keys[0], prefix = key.includes(':') ? key.split(':')[0] : '';
    const child = node[key],
        ns = child['@_xmlns' + (prefix ? ':' + prefix : '')] ??
            namespaces['@_xmlns' + (prefix ? ':' + prefix : '')];
    if (ns !== uri) throw new FiscalFailure('invalid_xml_namespace');
    return child;
}
const CFDI = 'http://www.sat.gob.mx/cfd/4',
    TFD = 'http://www.sat.gob.mx/TimbreFiscalDigital',
    PAGOS = 'http://www.sat.gob.mx/Pagos20';
export function verifyXml(
    bytes: Uint8Array,
    payload: Json,
    expectedUuid?: string,
): { uuid: string; stampedAt: string; total: number; shaInput: Uint8Array } {
    const xml = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    if (bytes.length > 2_000_000 || /<!DOCTYPE|<!ENTITY/i.test(xml) || XMLValidator.validate(xml) !== true) {
        throw new FiscalFailure('invalid_xml');
    }
    const parsed = new XMLParser({
        ignoreAttributes: false,
        parseAttributeValue: false,
        parseTagValue: false,
        processEntities: false,
    }).parse(xml);
    const root = one(parsed, 'Comprobante', CFDI, {});
    const issuer = one(root, 'Emisor', CFDI, root), receiver = one(root, 'Receptor', CFDI, root);
    const complement = one(root, 'Complemento', CFDI, root),
        stamp = one(complement, 'TimbreFiscalDigital', TFD, { ...root, ...complement });
    const uuid = stamp['@_UUID'];
    if (
        root['@_Version'] !== '4.0' || stamp['@_Version'] !== '1.1' ||
        !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(uuid ?? '') ||
        (expectedUuid && uuid.toLowerCase() !== expectedUuid.toLowerCase()) || !stamp['@_SelloSAT'] ||
        !root['@_Sello'] || !root['@_Certificado'] || !stamp['@_FechaTimbrado']
    ) throw new FiscalFailure('unverified_stamp');
    if (
        issuer['@_Rfc'] !== payload.Issuer.Rfc || issuer['@_Nombre'] !== payload.Issuer.Name ||
        receiver['@_Rfc'] !== payload.Receiver.Rfc || receiver['@_Nombre'] !== payload.Receiver.Name ||
        root['@_Folio'] !== String(payload.Folio) || root['@_Serie'] !== payload.Serie ||
        root['@_Fecha'] !== payload.Date || root['@_TipoDeComprobante'] !== payload.CfdiType
    ) throw new FiscalFailure('xml_identity_mismatch');
    if (payload.CfdiType === 'I') {
        const subtotal = payload.Items.reduce((sum: bigint, i: Json) => sum + cents(i.Subtotal), 0n),
            total = payload.Items.reduce((sum: bigint, i: Json) => sum + cents(i.Total), 0n);
        if (
            root['@_Moneda'] !== 'MXN' || root['@_MetodoPago'] !== 'PPD' ||
            cents(root['@_SubTotal']) !== subtotal || cents(root['@_Total']) !== total
        ) throw new FiscalFailure('xml_amount_mismatch');
    } else {
        if (root['@_Moneda'] !== 'XXX' || cents(root['@_Total']) !== 0n || cents(root['@_SubTotal']) !== 0n) {
            throw new FiscalFailure('xml_amount_mismatch');
        }
        const pagos = one(complement, 'Pagos', PAGOS, { ...root, ...complement }),
            pago = one(pagos, 'Pago', PAGOS, { ...root, ...complement, ...pagos });
        if (
            pagos['@_Version'] !== '2.0' || pago['@_MonedaP'] !== 'MXN' ||
            cents(pago['@_Monto']) !== cents(payload.Complemento.Payments[0].Amount)
        ) throw new FiscalFailure('xml_payment_mismatch');
        const key = Object.keys(pago).find((k) => k.split(':').pop() === 'DoctoRelacionado');
        const raw = key ? pago[key] : [], docs = Array.isArray(raw) ? raw : [raw];
        if (docs.length !== payload.Complemento.Payments[0].RelatedDocuments.length) {
            throw new FiscalFailure('xml_application_mismatch');
        }
        const unique = new Set<string>();
        for (const d of docs) {
            const id = String(d['@_IdDocumento']).toLowerCase(),
                e = payload.Complemento.Payments[0].RelatedDocuments.find((x: Json) =>
                    x.Uuid.toLowerCase() === id
                );
            if (
                !e || unique.has(id) || d['@_NumParcialidad'] !== String(e.PartialityNumber) ||
                cents(d['@_ImpSaldoAnt']) !== cents(e.PreviousBalanceAmount) ||
                cents(d['@_ImpPagado']) !== cents(e.AmountPaid) ||
                cents(d['@_ImpSaldoInsoluto']) !== cents(e.ImpSaldoInsoluto)
            ) throw new FiscalFailure('xml_application_mismatch');
            unique.add(id);
        }
    }
    return {
        uuid,
        stampedAt: stamp['@_FechaTimbrado'],
        total: money(cents(root['@_Total'])),
        shaInput: bytes,
    };
}

export function verifyCancellationAck(bytes: Uint8Array, uuid: string): void {
    const xml = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    if (bytes.length > 2_000_000 || /<!DOCTYPE|<!ENTITY/i.test(xml) || XMLValidator.validate(xml) !== true) {
        throw new FiscalFailure('invalid_cancellation_ack');
    }
    const parsed = new XMLParser({
        ignoreAttributes: false,
        parseTagValue: false,
        parseAttributeValue: false,
        removeNSPrefix: true,
        processEntities: false,
    }).parse(xml);
    const root = parsed.Acuse;
    if (!root || Array.isArray(root) || root['@_RfcEmisor'] !== TEST_ISSUER.Rfc) {
        throw new FiscalFailure('invalid_cancellation_ack');
    }
    const folios = root.Folios, rows = Array.isArray(folios) ? folios : [folios];
    const text = (v: unknown): string => String(v && typeof v === 'object' ? (v as Json)['#text'] : v ?? '');
    const match = rows.filter((x: Json) =>
        text(x?.UUID ?? x?.['@_UUID']).toLowerCase() === uuid.toLowerCase()
    );
    if (
        match.length !== 1 ||
        !['201', '202'].includes(text(match[0].EstatusUUID ?? match[0]['@_EstatusUUID']))
    ) throw new FiscalFailure('unconfirmed_cancellation_ack');
}

export class FacturamaSandbox implements FiscalProviderAdapter {
    readonly providerCode = 'facturama';
    readonly baseUrl = SANDBOX;
    readonly #auth: string;
    constructor(
        config: {
            username: string;
            password: string;
            environment: string;
            baseUrl?: string;
            timeoutMs?: number;
        },
        private readonly transport: typeof fetch = fetch,
    ) {
        if (
            config.environment !== 'sandbox' || (config.baseUrl && config.baseUrl !== SANDBOX) ||
            !config.username || !config.password || config.username.includes(':')
        ) throw new FiscalFailure('sandbox_configuration_required');
        this.#auth = 'Basic ' +
            btoa(String.fromCharCode(...new TextEncoder().encode(config.username + ':' + config.password)));
        this.timeout = config.timeoutMs ?? 25_000;
    }
    private readonly timeout: number;
    async request(method: string, path: string, body?: Json): Promise<Json> {
        if (
            !/^(?:\/api-lite\/4\/cfdis|\/api-lite\/csds|\/api-lite\/cfdis\/[A-Za-z0-9_-]+(?:\?motive=0[1-4](?:&uuidReplacement=[0-9a-f-]{36})?)?|\/cfdi\?type=issuedLite&page=\d+&folio=[A-Z0-9-]+|\/api\/Cfdi\/xml\/issuedLite\/[A-Za-z0-9_-]+)$/
                .test(path) ||
            !['GET', 'POST', 'DELETE'].includes(method) ||
            (method === 'POST' && !['/api-lite/4/cfdis', '/api-lite/csds'].includes(path)) ||
            (method === 'DELETE' && !/^\/api-lite\/cfdis\/[A-Za-z0-9_-]+\?motive=/.test(path))
        ) throw new FiscalFailure('forbidden_endpoint');
        const controller = new AbortController(), timer = setTimeout(() => controller.abort(), this.timeout);
        const mutating = method !== 'GET';
        try {
            const res = await this.transport(SANDBOX + path, {
                method,
                redirect: 'manual',
                signal: controller.signal,
                headers: {
                    Authorization: this.#auth,
                    Accept: 'application/json',
                    ...(body ? { 'Content-Type': 'application/json' } : {}),
                },
                ...(body ? { body: JSON.stringify(body) } : {}),
            });
            if (!res.ok) {
                const fields: string[] = [];
                if (res.status === 400 && Number(res.headers.get('content-length') ?? 0) < 100000) {
                    try {
                        const data = await res.json();
                        for (const k of Object.keys(data.ModelState ?? {})) {
                            if (/^[A-Za-z0-9_.\[\]]{1,160}$/.test(k)) fields.push(k);
                        }
                        const codes = JSON.stringify(data).match(/\b(?:CFDI|CRP)\d{3,8}\b/g) ?? [];
                        fields.push(...new Set<string>(codes));
                    } catch { /* no raw body retained */ }
                } else await res.body?.cancel();
                throw new FiscalFailure(
                    res.status >= 300 && res.status < 400 ? 'redirect_blocked' : 'provider_rejected',
                    res.status,
                    mutating && (res.status >= 500 || res.status < 400),
                    fields,
                );
            }
            const reader = res.body?.getReader();
            if (!reader) throw new FiscalFailure('empty_response', res.status, mutating);
            let size = 0;
            const chunks: Uint8Array[] = [];
            while (true) {
                const r = await reader.read();
                if (r.done) break;
                size += r.value.length;
                if (size > 3_000_000) {
                    await reader.cancel();
                    throw new FiscalFailure('response_too_large', res.status, mutating);
                }
                chunks.push(r.value);
            }
            const bytes = new Uint8Array(size);
            let offset = 0;
            for (const c of chunks) {
                bytes.set(c, offset);
                offset += c.length;
            }
            try {
                return JSON.parse(new TextDecoder().decode(bytes));
            } catch {
                throw new FiscalFailure('invalid_response', res.status, mutating);
            }
        } catch (e) {
            if (e instanceof FiscalFailure) throw e;
            throw new FiscalFailure('provider_timeout_or_network', undefined, mutating);
        } finally {
            clearTimeout(timer);
        }
    }
    listCsds(): Promise<Json> {
        return this.request('GET', '/api-lite/csds');
    }
    async registerOfficialTestCsd(csd: Json): Promise<void> {
        if (csd.Rfc !== TEST_ISSUER.Rfc || !csd.Certificate || !csd.PrivateKey || !csd.PrivateKeyPassword) {
            throw new FiscalFailure('official_test_csd_required');
        }
        const existing = await this.listCsds();
        if (!Array.isArray(existing)) throw new FiscalFailure('invalid_csd_listing');
        if (existing.some((r) => r.Rfc === TEST_ISSUER.Rfc)) {
            throw new FiscalFailure('csd_already_exists_do_not_replace');
        }
        await this.request('POST', '/api-lite/csds', csd);
    }
    async create(payload: Json): Promise<{ id: string; uuid?: string }> {
        validatePayload(payload);
        const r = await this.request('POST', '/api-lite/4/cfdis', payload);
        if (!/^[A-Za-z0-9_-]{1,150}$/.test(r.Id ?? '')) {
            throw new FiscalFailure('invalid_provider_id', undefined, true);
        }
        return { id: r.Id, uuid: r.Complement?.TaxStamp?.Uuid };
    }
    async detail(id: string): Promise<Json> {
        return this.request('GET', '/api-lite/cfdis/' + id);
    }
    async xml(id: string): Promise<Uint8Array> {
        const r = await this.request('GET', '/api/Cfdi/xml/issuedLite/' + id);
        if (
            r.ContentEncoding !== 'base64' || typeof r.Content !== 'string' ||
            !/^[A-Za-z0-9+/=\r\n]+$/.test(r.Content)
        ) throw new FiscalFailure('invalid_artifact');
        try {
            return Uint8Array.from(atob(r.Content), (c) => c.charCodeAt(0));
        } catch {
            throw new FiscalFailure('invalid_artifact');
        }
    }
    async find(folio: string, date: string, issuer: string): Promise<string | null> {
        let found: string | null = null;
        for (let page = 0; page < 100; page++) {
            const rows = await this.request('GET', `/cfdi?type=issuedLite&page=${page}&folio=${folio}`);
            if (!Array.isArray(rows)) throw new FiscalFailure('reconciliation_incomplete');
            for (const row of rows) {
                const d = await this.detail(row.Id);
                if (String(d.Folio) === folio && d.Date === date && d.Issuer?.Rfc === issuer) {
                    if (found && found !== d.Id) throw new FiscalFailure('duplicate_provider_result');
                    found = d.Id;
                }
            }
            if (rows.length < 10) return found;
        }
        throw new FiscalFailure('reconciliation_incomplete');
    }
    cancelDocument(id: string, motive: string, replacement?: string): Promise<Json> {
        if (
            !['01', '02', '03', '04'].includes(motive) || (motive === '01') !== Boolean(replacement) ||
            (replacement && !/^[0-9a-f-]{36}$/i.test(replacement))
        ) throw new FiscalFailure('invalid_cancellation');
        return this.request(
            'DELETE',
            '/api-lite/cfdis/' + id + '?motive=' + motive +
                (replacement ? '&uuidReplacement=' + replacement : ''),
        );
    }
    private assertRequest(r: FiscalCanonicalRequest): void {
        if (r.environment !== 'sandbox') throw new FiscalFailure('production_disabled');
    }
    async submit(r: FiscalCanonicalRequest): Promise<FiscalNormalizedResult> {
        this.assertRequest(r);
        if (!r.providerPayloadSnapshot) throw new FiscalFailure('frozen_provider_snapshot_required');
        const created = await this.create(r.providerPayloadSnapshot as Json);
        return {
            // The orchestrator must persist the ID before attempting XML reads.
            // No transport response alone is normalized to a final fiscal state.
            outcome: 'processing',
            providerDocumentId: created.id,
        };
    }
    async getStatus(r: FiscalCanonicalRequest): Promise<FiscalNormalizedResult> {
        this.assertRequest(r);
        if (!r.providerDocumentId) return { outcome: 'not_found' };
        await this.detail(r.providerDocumentId);
        return {
            outcome: 'processing',
            providerDocumentId: r.providerDocumentId,
        };
    }
    async cancel(r: FiscalCanonicalRequest): Promise<FiscalNormalizedResult> {
        this.assertRequest(r);
        if (!r.providerDocumentId) throw new FiscalFailure('missing_provider_id');
        await this.cancelDocument(
            r.providerDocumentId,
            String(r.payloadSnapshot.motive),
            r.payloadSnapshot.replacement as string | undefined,
        );
        return {
            outcome: 'processing',
            providerDocumentId: r.providerDocumentId,
        };
    }
    async getXml(r: FiscalCanonicalRequest): Promise<FiscalArtifact> {
        this.assertRequest(r);
        if (!r.providerDocumentId) throw new FiscalFailure('missing_provider_id');
        return { kind: 'xml', bytes: await this.xml(r.providerDocumentId), mimeType: 'application/xml' };
    }
    async getPdf(_r: FiscalCanonicalRequest): Promise<FiscalArtifact> {
        throw new FiscalFailure('artifact_unavailable');
    }
}
