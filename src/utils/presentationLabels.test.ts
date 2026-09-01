import assert from 'node:assert/strict';
import {
    CLAIM_EVENT_LABELS,
    CLAIM_TYPE_LABELS,
    DOCUMENT_KIND_LABELS,
    DOCUMENT_STATUS_LABELS,
    formatFiscalMissingFields,
    getClaimEventLabel,
    getReadinessReasonLabel,
} from './presentationLabels';

assert.equal(getReadinessReasonLabel('missing_planning_data'), 'Planeación incompleta');
assert.equal(getReadinessReasonLabel('missing_assignment'), 'Proveedor sin asignar');
assert.equal(getReadinessReasonLabel('unknown_internal_reason'), 'Requisito operativo pendiente');

assert.equal(CLAIM_TYPE_LABELS.delay, 'Retraso');
assert.equal(CLAIM_TYPE_LABELS.damage, 'Daño');
assert.equal(CLAIM_TYPE_LABELS.loss, 'Pérdida');
assert.equal(CLAIM_TYPE_LABELS.documentation, 'Documentación');
assert.equal(CLAIM_TYPE_LABELS.billing, 'Facturación');
assert.equal(CLAIM_EVENT_LABELS.created, 'Creado');
assert.equal(getClaimEventLabel('unknown_event_name'), 'Evento registrado');

assert.equal(DOCUMENT_KIND_LABELS.generated_pdf, 'PDF generado');
assert.equal(DOCUMENT_STATUS_LABELS.active, 'Activo');
assert.equal(formatFiscalMissingFields(['concepts', 'payment.method']), 'Faltan: Conceptos y método de pago');
assert.equal(formatFiscalMissingFields(['unknown.path']), 'Faltan: otro dato fiscal requerido');

console.log('MOBILE.1A presentation label contracts passed');
