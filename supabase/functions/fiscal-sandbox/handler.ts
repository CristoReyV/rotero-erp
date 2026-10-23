import type { SupabaseClient } from '@supabase/supabase-js';
import { FacturamaSandbox, FiscalFailure, type Json } from '../_shared/facturama.ts';
import { executeFiscal, type FiscalStore } from '../_shared/facturama-executor.ts';

const preview = /^https:\/\/deploy-preview-\d+--rotero-erp-staging\.netlify\.app$/;
const local = /^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/;
export interface FiscalHandlerDependencies {
    userClient: (authorization: string) => SupabaseClient;
    admin: SupabaseClient;
    adapter: FacturamaSandbox;
}
export function createFiscalHandler(deps: FiscalHandlerDependencies) {
    return async function handler(req: Request): Promise<Response> {
        const origin = req.headers.get('origin') ?? '';
        const headers = {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
            'Vary': 'Origin',
            ...(preview.test(origin) || local.test(origin) ? { 'Access-Control-Allow-Origin': origin } : {}),
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
        };
        const json = (body: Json, status = 200) => new Response(JSON.stringify(body), { status, headers });
        if (origin && !preview.test(origin) && !local.test(origin)) {
            return json({ error: 'origin_forbidden' }, 403);
        }
        if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
        if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
        try {
            if (Number(req.headers.get('content-length') ?? 0) > 16000) {
                return json({ error: 'request_too_large' }, 413);
            }
            const text = await req.text();
            if (text.length > 16000) return json({ error: 'request_too_large' }, 413);
            const input = JSON.parse(text);
            if (
                !/^[0-9a-f-]{36}$/i.test(input.cfdiId ?? '') ||
                !['prepare', 'issue', 'status', 'xml', 'ack', 'cancel', 'payment'].includes(input.action)
            ) return json({ error: 'invalid_action' }, 400);
            const authorization = req.headers.get('authorization') ?? '';
            if (!authorization.startsWith('Bearer ')) return json({ error: 'authentication_required' }, 401);
            const userClient = deps.userClient(authorization);
            const { data: { user }, error } = await userClient.auth.getUser();
            if (error || !user) return json({ error: 'authentication_required' }, 401);
            const admin = deps.admin;
            const store: FiscalStore = {
                async worker(id, actor, action, data = {}) {
                    const r = await admin.rpc('rpc_fiscal01_worker', {
                        p_cfdi_id: id,
                        p_actor: actor,
                        p_action: action,
                        p_data: data,
                    });
                    if (r.error || r.data?.error) {
                        throw new FiscalFailure(
                            r.error?.code === '42501' ? 'fiscal_forbidden' : 'fiscal_store_failed',
                        );
                    }
                    return r.data;
                },
                async upload(path, bytes) {
                    const r = await admin.storage.from('fiscal-sandbox').upload(path, bytes, {
                        contentType: 'application/xml',
                        upsert: false,
                    });
                    if (r.error) {
                        const old = await admin.storage.from('fiscal-sandbox').download(path);
                        if (
                            old.error || !old.data ||
                            !equal(bytes, new Uint8Array(await old.data.arrayBuffer()))
                        ) throw new FiscalFailure('artifact_store_failed');
                    }
                },
                async download(path) {
                    const r = await admin.storage.from('fiscal-sandbox').download(path);
                    if (r.error || !r.data) throw new FiscalFailure('artifact_unavailable');
                    return new Uint8Array(await r.data.arrayBuffer());
                },
            };
            if (input.action === 'payment') {
                const r = await admin.rpc('rpc_fiscal01_record_payment', {
                    p_cfdi_id: input.cfdiId,
                    p_actor: user.id,
                    p_paid_at: input.paidAt,
                    p_applications: input.applications,
                });
                if (r.error) {
                    throw new FiscalFailure(
                        r.error.code === '42501' ? 'fiscal_forbidden' : 'payment_validation_failed',
                    );
                }
                return json(r.data);
            }
            const adapter = deps.adapter;
            const result = await executeFiscal(store, adapter, user.id, input.cfdiId, input.action, {
                motive: input.motive,
                replacement: input.replacement,
                recoverAck: input.recoverAck === true,
            });
            if (result instanceof Uint8Array) {
                return new Response(new Uint8Array(result).buffer, {
                    headers: {
                        ...headers,
                        'Content-Type': 'application/xml',
                        'Content-Disposition': 'attachment; filename="sandbox.xml"',
                    },
                });
            }
            return json(result);
        } catch (e) {
            const code = e instanceof FiscalFailure ? e.code : 'fiscal_operation_failed';
            // No raw exception, provider body, URL, JWT or Authorization in logs/output.
            return json({
                error: code,
                uncertain: e instanceof FiscalFailure && e.uncertain,
                validationFields: e instanceof FiscalFailure ? e.validationFields : [],
            }, code === 'fiscal_forbidden' ? 403 : 422);
        }
    };
    function equal(a: Uint8Array, b: Uint8Array): boolean {
        return a.length === b.length && a.every((n, i) => n === b[i]);
    }
}
