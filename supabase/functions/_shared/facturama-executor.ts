import {
    cents,
    FacturamaSandbox,
    FiscalFailure,
    type Json,
    money,
    sha256,
    TEST_ISSUER,
    validatePayload,
    verifyCancellationAck,
    verifyXml,
} from './facturama.ts';

export interface FiscalStore {
    worker(id: string, actor: string, action: string, data?: Json): Promise<Json>;
    upload(path: string, bytes: Uint8Array): Promise<void>;
    download(path: string): Promise<Uint8Array>;
}
export function invoiceFromSource(s: Json, date: string): Json {
    const lines = s.fiscal_input?.concepts;
    if (!Array.isArray(lines) || !lines.length || s.currency !== 'MXN') {
        throw new FiscalFailure('incomplete_draft');
    }
    const p: Json = {
        NameId: '1',
        CfdiType: 'I',
        Currency: 'MXN',
        PaymentForm: '99',
        PaymentMethod: 'PPD',
        ExpeditionPlace: '42501',
        Exportation: '01',
        Serie: s.serie,
        Folio: s.folio,
        Date: date,
        Issuer: { ...TEST_ISSUER },
        Receiver: {
            Rfc: 'URE180429TM6',
            Name: 'UNIVERSIDAD ROBOTICA ESPAÑOLA',
            FiscalRegime: '601',
            TaxZipCode: '86991',
            CfdiUse: 'G03',
        },
        Items: lines.map((l: Json) => {
            const base = cents(l.amount), vat = (base * 16n + 50n) / 100n;
            return {
                ProductCode: '78101800',
                UnitCode: 'E48',
                Description: String(l.description).slice(0, 200),
                UnitPrice: money(base),
                Quantity: 1,
                Subtotal: money(base),
                TaxObject: '02',
                Taxes: [{
                    Name: 'IVA',
                    Base: money(base),
                    Rate: 0.16,
                    Total: money(vat),
                    IsRetention: false,
                }],
                Total: money(base + vat),
            };
        }),
    };
    validatePayload(p);
    if (
        cents(s.total) !== p.Items.reduce((n: bigint, l: Json) => n + cents(l.Total), 0n) ||
        cents(s.subtotal) !== p.Items.reduce((n: bigint, l: Json) => n + cents(l.Subtotal), 0n)
    ) throw new FiscalFailure('draft_amount_mismatch');
    return p;
}
export function fiscalDate(now = new Date()): string {
    return new Intl.DateTimeFormat('sv-SE', {
        timeZone: 'America/Mexico_City',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hourCycle: 'h23',
    }).format(now).replace(' ', 'T');
}
export async function executeFiscal(
    store: FiscalStore,
    adapter: FacturamaSandbox,
    actor: string,
    id: string,
    action: string,
    options: Json = {},
): Promise<Json | Uint8Array> {
    if (action === 'prepare') {
        const source = await store.worker(id, actor, 'source');
        const payload = source.fiscal_input?.payment_payload ?? invoiceFromSource(source, fiscalDate());
        validatePayload(payload);
        return store.worker(id, actor, 'prepare', { company_id: source.company_id, payload });
    }
    if (action === 'xml' || action === 'ack') {
        const r = await store.worker(id, actor, action);
        if (!r.path) throw new FiscalFailure('artifact_unavailable');
        return store.download(r.path);
    }
    if (!['issue', 'status', 'cancel'].includes(action)) throw new FiscalFailure('unsupported_action');
    if (action === 'cancel' && options.recoverAck !== undefined && typeof options.recoverAck !== 'boolean') {
        throw new FiscalFailure('invalid_cancellation');
    }
    if (action === 'cancel' && options.recoverAck === true) {
        // Authorize a read without claiming a cancellation lease or changing its
        // original parameters. No documented read API provides this CFDI XML ack.
        const state = await store.worker(id, actor, 'load');
        throw new FiscalFailure(
            state.remote_cancel_status === 'canceled'
                ? 'ack_recovery_unavailable'
                : 'cancellation_not_confirmed',
        );
    }
    if (
        action === 'cancel' &&
        (!['01', '02', '03', '04'].includes(options.motive) ||
            (options.motive === '01') !== Boolean(options.replacement))
    ) throw new FiscalFailure('invalid_cancellation');
    const lease = await store.worker(
        id,
        actor,
        action === 'issue' ? 'claim' : action,
        action === 'cancel'
            ? {
                motive: options.motive,
                ...(options.replacement ? { replacement: options.replacement } : {}),
            }
            : {},
    );
    if (lease.busy || lease.reconcile_required || lease.cancellation_pending) {
        return { ...lease, message: 'Consulte el estado; no se reenviará automáticamente.' };
    }
    const token = lease.busy_token, payload = lease.provider_payload;
    if (!token || !payload) throw new FiscalFailure('invalid_worker_lease');
    const save = (kind: string, data: Json = {}) =>
        store.worker(id, actor, kind, { ...data, busy_token: token });
    let providerId = lease.provider_document_id;
    try {
        validatePayload(payload);
        if (action === 'cancel') {
            const correlated = (remote: Json) =>
                remote.Id === providerId &&
                remote.Complement?.TaxStamp?.Uuid?.toLowerCase() === lease.fiscal_uuid?.toLowerCase() &&
                remote.Issuer?.Rfc === TEST_ISSUER.Rfc;
            const cancellation = lease.cancellation_options ?? options;
            const result = await adapter.cancelDocument(
                providerId,
                cancellation.motive,
                cancellation.replacement,
            );
            const status = await adapter.detail(providerId);
            if (!correlated(status)) throw new FiscalFailure('uncorrelated_cancellation_status');
            if (
                result.Status !== 'canceled' || !['cancel', 'canceled'].includes(status.Status) ||
                result.Uuid?.toLowerCase() !== lease.fiscal_uuid?.toLowerCase()
            ) {
                await save('release');
                return {
                    status: 'cancellation_requested',
                    message: 'Cancelación pendiente de confirmación y acuse.',
                };
            }
            await save('cancel_confirmed', { uuid: lease.fiscal_uuid, provider_document_id: providerId });
            if (!result.AcuseXmlBase64) {
                await save('release');
                return {
                    status: 'cancellation_requested',
                    remoteCancellation: 'confirmed',
                    acknowledgement: 'unavailable',
                };
            }
            const ack = Uint8Array.from(atob(result.AcuseXmlBase64), (c) => c.charCodeAt(0));
            // Preserve an uncorrelated provider receipt in quarantine. It is not
            // linked or downloadable by application users until UUID validation.
            await store.upload(
                `${lease.tenant_id}/${lease.company_id}/${id}/unverified-cancellation-${await sha256(
                    ack,
                )}.xml`,
                ack,
            );
            try {
                verifyCancellationAck(ack, lease.fiscal_uuid);
            } catch {
                await save('cancel_ack_invalid', { ack_sha256: await sha256(ack) });
                await save('release');
                return {
                    status: 'cancellation_requested',
                    remoteCancellation: 'confirmed',
                    acknowledgement: 'mismatch',
                };
            }
            const path = `${lease.tenant_id}/${lease.company_id}/${id}/cancellation.xml`;
            await store.upload(path, ack);
            await save('cancelled', {
                uuid: lease.fiscal_uuid,
                ack_path: path,
                ack_sha256: await sha256(ack),
            });
            return { status: 'cancelled', uuid: lease.fiscal_uuid, acuseAvailable: true };
        }
        if (action === 'issue') {
            const created = await adapter.submit({
                requestId: lease.active_request_id ?? id,
                tenantId: lease.tenant_id,
                billingCfdiId: id,
                requestType: 'stamp',
                idempotencyKey: lease.payload_sha256,
                environment: 'sandbox',
                payloadSnapshot: {
                    schema: 'rotero.fiscal-input',
                    billing_cfdi_id: id,
                    company_id: lease.company_id,
                },
                providerPayloadSnapshot: payload,
            });
            providerId = created.providerDocumentId;
            if (!providerId) throw new FiscalFailure('missing_provider_id', undefined, true);
            await save('identified', { provider_document_id: providerId });
        } else if (!providerId) {
            providerId = await adapter.find(payload.Folio, payload.Date, payload.Issuer.Rfc);
            if (!providerId) {
                await save('release');
                return {
                    status: 'uncertain',
                    message: 'Sin coincidencia concluyente; no se autoriza reenvío automático.',
                };
            }
            await save('identified', { provider_document_id: providerId });
        }
        if (action === 'status') {
            const remote = await adapter.detail(providerId);
            if (['cancel', 'canceled'].includes(remote.Status)) {
                if (
                    remote.Id !== providerId ||
                    remote.Complement?.TaxStamp?.Uuid?.toLowerCase() !== lease.fiscal_uuid?.toLowerCase() ||
                    remote.Issuer?.Rfc !== TEST_ISSUER.Rfc
                ) {
                    throw new FiscalFailure('uncorrelated_cancellation_status');
                }
                await save('cancel_observed');
                return {
                    status: 'cancellation_requested',
                    message: 'El proveedor informa cancelación; falta un acuse correlacionado.',
                };
            }
        }
        const bytes = await adapter.xml(providerId),
            verified = verifyXml(bytes, payload, lease.fiscal_uuid ?? undefined);
        const path = `${lease.tenant_id}/${lease.company_id}/${id}/invoice.xml`;
        await store.upload(path, bytes);
        await save('verified', {
            provider_document_id: providerId,
            uuid: verified.uuid,
            stamped_at: verified.stampedAt,
            xml_path: path,
            xml_sha256: await sha256(bytes),
        });
        return { status: 'stamped', uuid: verified.uuid, providerDocumentId: providerId, xmlAvailable: true };
    } catch (e) {
        if (
            action === 'issue' && !providerId && e instanceof FiscalFailure && e.httpStatus === 400 &&
            !e.uncertain
        ) {
            await save('rejected');
            throw new FiscalFailure('provider_rejected', 400, false, e.validationFields);
        }
        // Mark uncertainty after any attempted mutation, malformed result or lost
        // persistence. Never return raw bodies/headers or queue blind retries.
        const uncertaintySaved = await save('uncertain', {
            http_status: e instanceof FiscalFailure ? e.httpStatus ?? null : null,
        }).then(() => true, () => false);
        if (
            uncertaintySaved && action === 'issue' && providerId && e instanceof FiscalFailure &&
            e.httpStatus === 404
        ) {
            // The provider ID is already durable. A temporarily unavailable XML
            // is pending verification, not permission to send another invoice.
            return {
                status: 'processing',
                uncertain: true,
                xmlAvailable: false,
                providerDocumentId: providerId,
                message:
                    'Identificador recibido; falta verificar el XML. Consulta el estado sin emitir de nuevo.',
            };
        }
        throw new FiscalFailure(
            e instanceof FiscalFailure ? e.code : 'fiscal_operation_uncertain',
            e instanceof FiscalFailure ? e.httpStatus : undefined,
            true,
        );
    }
}
