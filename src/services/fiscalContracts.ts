import type { FiscalReadiness, FiscalSafeError, FiscalStatus } from '@/types/billing';

export const FISCAL_ERROR_MESSAGES: Record<FiscalSafeError, string> = {
    provider_not_configured: 'Proveedor fiscal no configurado',
    validation_failed: 'Faltan datos fiscales requeridos.',
    provider_unavailable: 'El proveedor fiscal no está disponible.',
    provider_timeout: 'El proveedor fiscal no respondió a tiempo.',
    provider_rejected: 'El proveedor rechazó la solicitud fiscal.',
    already_processing: 'Ya existe una solicitud fiscal en proceso.',
    already_stamped: 'El comprobante ya está timbrado.',
    invalid_transition: 'La acción no está permitida en el estado fiscal actual.',
    cancellation_failed: 'El proveedor no confirmó la cancelación.',
    artifact_unavailable: 'El artefacto fiscal todavía no está disponible.',
    status_conflict: 'El estado remoto requiere revisión manual.',
};

export interface FiscalActionAvailability {
    validate: boolean;
    submit: boolean;
    retry: boolean;
    refresh: boolean;
    cancel: boolean;
    downloadXml: boolean;
    downloadPdf: boolean;
    externalDisabledReason: string | null;
}

export function getFiscalActionAvailability(readiness: FiscalReadiness): FiscalActionAvailability {
    const status: FiscalStatus = readiness.fiscal_status;
    const configured = readiness.provider.configured;
    return {
        validate: status === 'draft',
        submit: configured && status === 'ready_for_api',
        retry: configured && status === 'api_error' && readiness.last_attempt?.status === 'technical_error',
        refresh: configured && ['processing', 'api_error', 'stamped', 'cancellation_requested', 'cancellation_rejected'].includes(status),
        cancel: configured && status === 'stamped',
        downloadXml: Boolean(readiness.xml_document_file_id),
        downloadPdf: Boolean(readiness.pdf_document_file_id),
        externalDisabledReason: configured ? null : FISCAL_ERROR_MESSAGES.provider_not_configured,
    };
}

export function normalizeFiscalError(code: unknown): string {
    const safeCode = typeof code === 'string' ? code as FiscalSafeError : 'provider_unavailable';
    return FISCAL_ERROR_MESSAGES[safeCode] ?? 'No fue posible completar la acción fiscal.';
}

const pendingMutations = new Set<string>();

export async function withFiscalMutationGuard<T>(identity: string, action: () => Promise<T>): Promise<T> {
    if (pendingMutations.has(identity)) throw new Error(FISCAL_ERROR_MESSAGES.already_processing);
    pendingMutations.add(identity);
    try { return await action(); } finally { pendingMutations.delete(identity); }
}
