import {
    cents,
    FacturamaSandbox,
    FiscalFailure,
    type Json,
    money,
    sandboxCancellationRequestId,
    sha256,
    TEST_ISSUER,
    validatePayload,
    verifyCancellationAck,
    verifyXml,
} from './facturama.ts';

export interface FiscalStore {
    worker(id: string, actor: string, action: string, data?: Json): Promise<Json>;
    upload(
        path: string,
        bytes: Uint8Array,
        contentType?: 'application/xml' | 'application/pdf',
    ): Promise<void>;
    download(path: string): Promise<Uint8Array>;
}

function cancellationEvidence(state: Json, remote: Json): Json {
    if (
        !state.provider_document_id || !state.fiscal_uuid || remote.Id !== state.provider_document_id ||
        remote.Complement?.TaxStamp?.Uuid?.toLowerCase() !== state.fiscal_uuid.toLowerCase() ||
        remote.Issuer?.Rfc !== TEST_ISSUER.Rfc || !['cancel', 'canceled'].includes(remote.Status)
    ) {
        throw new FiscalFailure('uncorrelated_cancellation_status');
    }
    return {
        provider_document_id: state.provider_document_id,
        uuid: state.fiscal_uuid,
        remote_status: remote.Status,
        http_status: 200,
        ...(state.busy_token ? { busy_token: state.busy_token } : {}),
    };
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
    if (action === 'ack_pdf') {
        const r = await store.worker(id, actor, 'pdf_load');
        if (!r.path || !r.sha256) throw new FiscalFailure('artifact_unavailable');
        const bytes = await store.download(r.path);
        if (await sha256(bytes) !== r.sha256) throw new FiscalFailure('artifact_integrity_failed');
        return bytes;
    }
    if (action === 'recover_pdf') {
        const state = await store.worker(id, actor, 'load');
        if (state.cancellation_pdf_path) return { pdfAvailable: true };
        if (
            !state.provider_document_id || !/^[A-Za-z0-9_-]+$/.test(state.provider_document_id) ||
            !state.fiscal_uuid
        ) {
            throw new FiscalFailure('cancellation_not_confirmed');
        }
        const proof = cancellationEvidence(state, await adapter.detail(state.provider_document_id));
        // Historical XML remains quarantined. Record only a supported sandbox
        // request identifier, never replace the invoice UUID or approve the XML.
        if (state.cancellation_ack_state === 'mismatch' && state.cancellation_ack_sha256) {
            const path =
                `${state.tenant_id}/${state.company_id}/${id}/unverified-cancellation-${state.cancellation_ack_sha256}.xml`;
            const bytes = await store.download(path);
            if (await sha256(bytes) !== state.cancellation_ack_sha256) {
                throw new FiscalFailure('artifact_integrity_failed');
            }
            const requestId = sandboxCancellationRequestId(bytes);
            if (requestId && requestId !== state.fiscal_uuid.toLowerCase()) {
                proof.request_identifier = requestId;
                proof.xml_source_sha256 = state.cancellation_ack_sha256;
            }
        }
        await store.worker(id, actor, 'observe_cancel', proof);
        const lease = await store.worker(id, actor, 'pdf_claim');
        if (lease.available || lease.busy) {
            return { pdfAvailable: Boolean(lease.available), busy: Boolean(lease.busy) };
        }
        if (!lease.busy_token || !lease.provider_document_id) throw new FiscalFailure('invalid_worker_lease');
        try {
            const bytes = await adapter.cancellationPdf(lease.provider_document_id),
                hash = await sha256(bytes);
            const path = `${lease.tenant_id}/${lease.company_id}/${id}/cancellation-${hash}.pdf`;
            await store.upload(path, bytes, 'application/pdf');
            await store.worker(id, actor, 'pdf_save', {
                busy_token: lease.busy_token,
                provider_document_id: lease.provider_document_id,
                path,
                sha256: hash,
                bytes: bytes.length,
            });
            return { status: 'cancelled', remoteCancellation: 'confirmed', pdfAvailable: true };
        } catch (e) {
            // Failure of a read/artifact never rewinds the confirmed cancellation
            // and never creates a fiscal HTTP attempt or resends DELETE.
            await store.worker(id, actor, 'pdf_release', { busy_token: lease.busy_token }).catch(() =>
                undefined
            );
            throw e;
        }
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
                result.Status !== 'canceled' || !['cancel', 'canceled'].includes(status.Status)
            ) {
                await save('release');
                return {
                    status: 'cancellation_requested',
                    message: 'Cancelación pendiente de confirmación remota.',
                };
            }
            await save('cancel_confirmed', { uuid: lease.fiscal_uuid, provider_document_id: providerId });
            const proof = cancellationEvidence(lease, status);
            if (!result.AcuseXmlBase64) {
                return store.worker(id, actor, 'observe_cancel', proof);
            }
            let ack: Uint8Array;
            try {
                ack = Uint8Array.from(atob(result.AcuseXmlBase64), (c) => c.charCodeAt(0));
            } catch {
                return store.worker(id, actor, 'observe_cancel', proof);
            }
            // Preserve an uncorrelated provider receipt in quarantine. It is not
            // linked or downloadable by application users until UUID validation.
            try {
                await store.upload(
                    `${lease.tenant_id}/${lease.company_id}/${id}/unverified-cancellation-${await sha256(
                        ack,
                    )}.xml`,
                    ack,
                );
            } catch {
                // Optional XML persistence cannot make a confirmed cancellation
                // non-terminal. Existing artifacts are never replaced.
                return store.worker(id, actor, 'observe_cancel', proof);
            }
            try {
                verifyCancellationAck(ack, lease.fiscal_uuid);
            } catch {
                const hash = await sha256(ack);
                await save('cancel_ack_invalid', { ack_sha256: hash });
                const requestId = (() => {
                    try {
                        return sandboxCancellationRequestId(ack);
                    } catch {
                        return undefined;
                    }
                })();
                if (requestId) {
                    proof.request_identifier = requestId;
                    proof.xml_source_sha256 = hash;
                }
                await store.worker(id, actor, 'observe_cancel', proof);
                return {
                    status: 'cancelled',
                    remoteCancellation: 'confirmed',
                    acknowledgement: 'historical_xml_unverified',
                    pdfAvailable: false,
                };
            }
            const path = `${lease.tenant_id}/${lease.company_id}/${id}/cancellation.xml`;
            try {
                await store.upload(path, ack);
            } catch {
                return store.worker(id, actor, 'observe_cancel', proof);
            }
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
                return store.worker(id, actor, 'observe_cancel', cancellationEvidence(lease, remote));
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
