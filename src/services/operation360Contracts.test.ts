import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildOperationTimeline, calculateOperationMargin, validateOperationalChronology } from '@/components/operations/operation360';
import { mapDbOperationToUI, type DbOperation } from '@/services/operationsContracts';
import type { Operation360Data } from '@/types/operations';

const converted = mapDbOperationToUI({
    id: '10000000-0000-4000-8000-000000000001', tenant_id: '10000000-0000-4000-8000-000000000002',
    reference_code: 'OP-F1-001', route_summary: 'Monterrey → Laredo', client_display_name: 'Cliente F1',
    destination_city: 'Laredo', eta_display: '21 ago', status: 'planned', created_at: '2026-08-21T10:00:00Z', eta: '2026-08-22T18:00:00Z',
    origin_place: { municipality: 'Monterrey', state: 'Nuevo León', countryCode: 'MX' }, destination_place: { municipality: 'Laredo', state: 'Texas', countryCode: 'US' },
    customer_id: '10000000-0000-4000-8000-000000000003', provider_id: '10000000-0000-4000-8000-000000000004', provider_name: 'Transportes Norte',
    execution_type: 'third_party', operation_scope: 'international', cargo_summary: { description: '12 tarimas' },
    operational_window_start: '2026-08-21T12:00:00Z', operational_window_end: '2026-08-21T16:00:00Z',
    service_type: 'FTL', service_catalog_snapshot: { service_type: 'FTL', modality: 'dry' },
    provider_cost_amount: 8000, customer_price_amount: 10000, pricing_currency: 'MXN',
    source_deal_id: '10000000-0000-4000-8000-000000000005',
} as DbOperation);

assert.equal(converted.client, 'Cliente F1');
assert.equal(converted.provider_name, 'Transportes Norte');
assert.equal(converted.execution_type, 'third_party');
assert.equal(converted.route_summary, 'Monterrey → Laredo');
assert.deepEqual(converted.cargo_summary, { description: '12 tarimas' });
assert.equal(converted.operational_window_start, '2026-08-21T12:00:00Z');
assert.deepEqual(converted.service_catalog_snapshot, { service_type: 'FTL', modality: 'dry' });
assert.equal(converted.provider_cost_amount, 8000);
assert.equal(converted.customer_price_amount, 10000);
assert.equal(converted.pricing_currency, 'MXN');
assert.equal(converted.source_deal_id, '10000000-0000-4000-8000-000000000005');

assert.deepEqual(calculateOperationMargin(8000, 10000), { amount: 2000, percentage: 20 });
assert.deepEqual(calculateOperationMargin(null, 10000), { amount: null, percentage: null });
assert.equal(validateOperationalChronology('2026-08-21T10:00:00Z', '2026-08-21T09:00:00Z', null), 'La ventana operativa debe terminar después de su inicio.');
assert.equal(validateOperationalChronology('2026-08-21T10:00:00Z', '2026-08-21T12:00:00Z', '2026-08-21T09:00:00Z'), 'La ETA no puede ser anterior al inicio de la ventana.');
assert.equal(validateOperationalChronology('2026-08-21T10:00:00Z', '2026-08-21T12:00:00Z', '2026-08-21T11:00:00Z'), null);

const data = {
    operation: converted,
    assignmentHistory: [{ id: 'a1', change_type: 'initial_assignment', new_provider_name_snapshot: 'Transportes Norte', changed_by: 'u1', changed_at: '2026-08-21T11:00:00Z' }],
    trackingEvents: [{ id: 't1', event_type: 'departure', server_timestamp: '2026-08-21T12:00:00Z' }],
    incidents: [{ id: 'i1', operation_id: converted.db_id!, category: 'delay', title: 'Demora', status: 'open', is_blocking: true, reported_by: 'u1', reported_at: '2026-08-21T13:00:00Z', created_at: '2026-08-21T13:00:00Z', updated_at: '2026-08-21T13:00:00Z' }],
    evidence: [], documents: [], crossings: [],
    incidentSummary: { open_incident_count: 1, blocking_incident_count: 1, has_open_incidents: true, has_blocking_incidents: true, can_close_operation: false, evidence_count: 0 },
    documentSummary: { required_count: 0, present_required_count: 0, missing_required_count: 0, has_missing_required: false, is_documentation_complete: true, pod_present: false, pod_required: false },
    readiness: { is_minimum_planned_complete: true, is_assignment_complete: true, is_tracking_ready: false, can_transition_to_assigned: true, can_transition_to_in_transit: false, has_driver_token: false, has_public_token: false, blocking_reasons: ['missing_driver_capability'] },
    billing: { has_billing_record: false, is_billing_ready: false, billing_blockers: [], is_billed: false, can_admin_close: false, pod_present: false, documentation_complete: true },
} as Operation360Data;
const timeline = buildOperationTimeline(data);
assert.equal(timeline[0].type, 'incident');
assert.deepEqual(new Set(timeline.map((item) => item.id)).size, timeline.length);

const serviceSource = readFileSync('src/services/operations.service.ts', 'utf8');
for (const rpc of ['rpc_complete_operation_planning_v2', 'rpc_assign_operation_v3', 'rpc_list_operation_incidents', 'rpc_add_operation_evidence', 'rpc_upsert_operation_document', 'rpc_list_operation_crossings', 'rpc_get_operation_billing_summary']) assert.match(serviceSource, new RegExp(rpc));
assert.doesNotMatch(serviceSource, /\.from\(['"]operation_(incidents|evidence|documents|crossings)/);

const executionSource = readFileSync('src/components/operations/OperationExecution.tsx', 'utf8');
assert.match(executionSource, /\.\.\.\(op\.cargo_summary \?\? \{\}\)/);
assert.match(executionSource, /mergePlace\(op\.origin_place/);
assert.match(executionSource, /documentation_received_at: form\.documentationReceived/);

const migration = readFileSync('supabase/migrations/20260822000000_f2_operation_360.sql', 'utf8');
assert.doesNotMatch(migration, /CREATE TABLE(?: IF NOT EXISTS)? public\.operation_timeline/i);
assert.match(migration, /SET search_path TO pg_catalog, public/g);
assert.match(migration, /REVOKE EXECUTE ON FUNCTION public\.rpc_assign_operation_v3[\s\S]*service_role/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.rpc_assign_operation_v3[\s\S]*TO authenticated/);
