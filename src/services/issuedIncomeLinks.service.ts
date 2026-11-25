import { supabase } from '@/lib/supabase';
import { scopedResponse } from '@/store/companyStore';

export interface IssuedIncomeContext {
    xml_file_id: string;
    linked_folios: string[];
}

export type IncomeFolioReview =
    | { folio: string; operation_id: string; status: 'ready' | 'already_linked'; reason: null }
    | { folio: string; operation_id: null; status: 'rejected'; reason: string };

const messages: Record<string, string> = {
    unauthorized: 'No tienes autorización vigente para vincular en esta empresa.',
    invoice_not_issued: 'La factura seleccionada no está emitida y vigente.',
    verified_xml_required: 'La factura no tiene un XML fiscal verificable registrado.',
    xml_integrity_mismatch: 'El archivo no coincide con el XML registrado de esta factura.',
    invalid_xml: 'El archivo debe ser un XML fiscal válido.',
    income_xml_mismatch: 'El XML no corresponde al CFDI de ingreso seleccionado.',
    income_document_required: 'La factura no tiene un documento de ingreso vigente e inequívoco.',
    single_receivable_required: 'Se necesita una sola cuenta por cobrar vigente que coincida con la factura.',
    folio_not_available: 'El folio no está disponible en la empresa seleccionada.',
    folio_missing_from_invoice: 'El folio no coincide exactamente con un identificador de concepto en el XML.',
    operation_not_delivered: 'La operación todavía no está entregada.',
    billing_link_conflict: 'La operación tiene un registro de facturación incompatible con este vínculo.',
    invalid_payload: 'Verifica el XML y los folios indicados antes de continuar.',
};

export function incomeLinkMessage(code: string): string {
    return Object.hasOwn(messages, code) ? messages[code] : 'No fue posible verificar esta acción.';
}

export async function encodeIncomeXml(file: Blob): Promise<string> {
    if (file.size < 1 || file.size > 2_000_000) {
        throw new Error('Selecciona el XML original de la factura, de hasta 2 MB.');
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    const chunks = [];
    for (let offset = 0; offset < bytes.length; offset += 8192) {
        chunks.push(String.fromCharCode(...bytes.subarray(offset, offset + 8192)));
    }
    return btoa(chunks.join(''));
}

async function call<T>(rpc: string, args: Record<string, unknown>): Promise<T> {
    return scopedResponse(async () => {
        const { data, error } = await supabase.rpc(rpc, args);
        if (error || !data) {
            const message = error?.code === '40001'
                ? 'La facturación cambió mientras confirmabas. Vuelve a revisar los folios.'
                : 'No se pudo confirmar la respuesta. Vuelve a consultar la factura antes de reintentar.';
            throw new Error(message);
        }
        if (typeof data.error === 'string') throw new Error(incomeLinkMessage(data.error));
        return data as T;
    });
}

export function loadIssuedIncomeContext(tenantId: string, cfdiId: string): Promise<IssuedIncomeContext> {
    return call('rpc_delivery_review_issued_income', { p_tenant_id: tenantId, p_cfdi_id: cfdiId });
}

export async function reviewIssuedIncome(
    tenantId: string, cfdiId: string, folios: string[], xml: string,
): Promise<IncomeFolioReview[]> {
    const data = await call<{ results: IncomeFolioReview[] }>('rpc_delivery_review_issued_income', {
        p_tenant_id: tenantId, p_cfdi_id: cfdiId, p_folios: folios, p_xml_base64: xml,
    });
    return data.results;
}

export async function linkIssuedIncome(
    tenantId: string, cfdiId: string, operationIds: string[], xml: string,
): Promise<number> {
    const data = await call<{ success: boolean; linked_count: number }>('rpc_delivery_link_issued_income', {
        p_tenant_id: tenantId, p_cfdi_id: cfdiId, p_operation_ids: operationIds, p_xml_base64: xml,
    });
    return data.linked_count;
}
