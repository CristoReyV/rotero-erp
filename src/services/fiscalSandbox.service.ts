import { supabase } from '@/lib/supabase';
export interface SandboxFiscalContext {
    cfdi_id: string;
    company_id: string;
    company_name: string;
    issuer_rfc: string;
    environment: 'sandbox';
    status: string;
    uuid?: string;
    provider_document_id?: string;
    cancellation_request_id?: string;
    cancellation_xml_interpretation?: 'sandbox_request_identifier';
    cancellation_pdf_available: boolean;
    cancellation_pdf_sha256?: string;
    cancellation_pdf_fetched_at?: string;
    cancellation_confirmed_at?: string;
    uncertain: boolean;
    document_type: 'invoice' | 'payment';
    payment_recorded: boolean;
    xml_available: boolean;
    cancellation_available: boolean;
    remote_cancel_status: 'pending' | 'canceled' | null;
    cancellation_ack_state: 'unavailable' | 'unverified' | 'mismatch' | 'validated';
    busy: boolean;
    future_provider?: {
        configured: boolean;
        enabled: false;
        code: 'facturama' | 'soft_management' | null;
        environment: 'sandbox' | 'production' | null;
        validation: 'sandbox_only' | 'pending_validation' | 'not_configured';
    };
    actions: Record<'prepare' | 'issue' | 'read' | 'cancel' | 'payment', boolean>;
    draft_summary: {
        receiver_rfc: string;
        subtotal: number;
        total: number;
        currency: string;
        serie: string;
        folio: string;
    };
}
export async function getSandboxFiscalContext(cfdiId: string): Promise<SandboxFiscalContext | null> {
    const r = await supabase.rpc('rpc_fiscal01_context', { p_cfdi_id: cfdiId });
    // Absent migration, ordinary document or denied task has no lab experience.
    if (r.error || !r.data?.cfdi_id) return null;
    return r.data as SandboxFiscalContext;
}
const pending = new Set<string>();
export async function sandboxFiscalAction(
    cfdiId: string,
    action: string,
    options: Record<string, unknown> = {},
): Promise<unknown> {
    if (pending.has(cfdiId)) throw new Error('Ya hay una solicitud en proceso.');
    pending.add(cfdiId);
    try {
        const { data, error } = await supabase.functions.invoke('fiscal-sandbox', {
            body: { ...options, cfdiId, action },
        });
        if (error || data?.error) {
            throw new Error(
                data?.uncertain
                    ? 'El resultado es incierto. Consulta el estado antes de continuar.'
                    : 'No se pudo completar la acción. Revisa los datos o consulta el estado.',
            );
        }
        return data;
    } finally {
        pending.delete(cfdiId);
    }
}
