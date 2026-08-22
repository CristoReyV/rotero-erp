import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration=readFileSync('supabase/migrations/20260826000000_f6_data_operations.sql','utf8');
const service=readFileSync('src/services/dataOperations.service.ts','utf8');
const wizard=readFileSync('src/components/dataOperations/ImportWizard.tsx','utf8');
const page=readFileSync('src/pages/DataOperationsPage.tsx','utf8');
for(const rpc of ['rpc_validate_bulk_import','rpc_start_bulk_import','rpc_apply_bulk_import','rpc_export_data_page','rpc_list_import_batches','rpc_save_import_mapping','rpc_bulk_update_operations','rpc_record_data_action']) assert.ok(service.includes(rpc),`Missing frontend RPC ${rpc}`);
assert.ok(!service.includes(".from('customers')")&&!service.includes(".from('logistics_providers')")&&!service.includes(".from('operations')"),'F6 frontend must not write canonical tables directly');
assert.ok(service.includes('MAX_IMPORT_ROWS = 1000')&&service.includes('CHUNK_SIZE = 200')&&service.includes('MAX_SYNC_EXPORT_ROWS = 5000'),'F6 limits must be explicit');
assert.ok(wizard.includes('Confirmo que revisé')&&wizard.includes('checked={confirmed}')&&wizard.includes('disabled={!confirmed || busy}'),'Import requires explicit confirmation');
assert.ok(wizard.includes('La vista previa no escribe datos')&&wizard.includes('validationErrorsCsv')&&wizard.includes('Reintentar errores'),'Preview/error recovery contract missing');
assert.ok(page.includes("'import'")&&page.includes("'history'")&&page.includes("'export'"),'Data workspace views missing');
assert.ok(migration.includes("v_outcome-'normalized'")&&migration.includes('pg_advisory_xact_lock')&&migration.includes('data_import_chunks_batch_key_unique'),'Idempotency/privacy contract missing');
assert.ok(!migration.match(/SQLERRM/i),'F6 must not return raw SQLERRM');
for(const role of ['PUBLIC','anon','service_role']) assert.ok(migration.includes(`FROM PUBLIC,anon,service_role`)||role==='PUBLIC','F6 RPC ACL revocation missing');
assert.ok(migration.includes("'status','planned'")&&migration.includes("'execution_type','third_party'"),'Imported operations must remain broker-first planned');
