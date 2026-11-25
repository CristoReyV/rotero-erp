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
    company_provider_configuration_required: 'La configuración fiscal requiere una empresa autorizada.',
    company_fiscal_transport_disabled: 'La ejecución fiscal general está deshabilitada; configurar un proveedor no la habilita.',
    fiscal_reconciliation_required: 'Existe un envío fiscal previo. Concilia su resultado antes de continuar.',
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
    const enabled = configured && readiness.provider.enabled === true
        && readiness.provider.code === 'facturama' && readiness.provider.environment === 'sandbox'
        && readiness.provider.validation === 'sandbox_only';
    const canStamp = enabled && readiness.provider.capabilities?.stamp === true;
    const canStatus = enabled && readiness.provider.capabilities?.status === true;
    const canCancel = enabled && readiness.provider.capabilities?.cancel === true;
    return {
        validate: status === 'draft',
        submit: canStamp && status === 'ready_for_api',
        retry: canStamp && status === 'api_error' && readiness.last_attempt?.status === 'technical_error',
        refresh: canStatus && ['processing', 'api_error', 'stamped', 'cancellation_requested', 'cancellation_rejected'].includes(status),
        cancel: canCancel && status === 'stamped',
        downloadXml: Boolean(readiness.xml_document_file_id),
        downloadPdf: Boolean(readiness.pdf_document_file_id),
        externalDisabledReason: !configured ? FISCAL_ERROR_MESSAGES.provider_not_configured
            : readiness.provider.validation === 'pending_validation' ? 'Proveedor pendiente de validación; ejecución deshabilitada'
                : !enabled || !(canStamp || canStatus || canCancel) ? 'Proveedor configurado; ejecución deshabilitada' : null,
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
