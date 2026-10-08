import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const router = readFileSync('src/routes/router.tsx', 'utf8');
const page = readFileSync('src/pages/OperationsPage.tsx', 'utf8');
const panel = readFileSync('src/components/operations/Operation360Panel.tsx', 'utf8');
const assignment = readFileSync('src/components/operations/AssignmentDrawer.tsx', 'utf8');
const nav = readFileSync('src/constants/nav.ts', 'utf8');

assert.match(router, /path: 'operations', element: page\(<OperationsPage/);
assert.match(page, /<OperationsTable/);
assert.match(page, /<Operation360Panel/);
assert.match(page, /canManage=\{canManageOperations\}/);
for (const tab of ['Resumen', 'Ejecución', 'Historial', 'Incidencias', 'Documentos', 'Evidencias', 'Economía']) {
    assert.match(panel, new RegExp(`label: '${tab}'`));
}
assert.match(panel, /operation\.operation_scope === 'international'/);
assert.match(assignment, /execution_type: 'third_party'/);
assert.match(assignment, /external_driver:/);
assert.match(assignment, /external_vehicle:/);
assert.doesNotMatch(assignment, /b1f50123|c2a60123|Seleccionar Conductor|Seleccionar Unidad/);
assert.equal((nav.match(/operations/g) ?? []).length >= 1, true);
assert.doesNotMatch(nav, /operation-incidents|operation-documents|operation-evidence|operation-crossings/);
