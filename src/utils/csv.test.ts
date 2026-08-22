import assert from 'node:assert/strict';
import { mapCsvRows, normalizeHeader, parseCsv, serializeCsv, suggestMapping, templateCsv, validationErrorsCsv } from './csv';
import { IMPORT_FIELDS } from '@/types/dataOperations';

const parsed=parseCsv('\uFEFFexternal_key;nombre;notas\r\nCLI-1;"Logística Ñ";"Texto; con separador"\r\nCLI-2;"Comillas ""dobles""";normal\r\n\r\n');
assert.equal(parsed.delimiter,';'); assert.deepEqual(parsed.headers,['external_key','nombre','notas']); assert.equal(parsed.rows.length,2); assert.equal(parsed.rows[0][2],'Texto; con separador'); assert.equal(parsed.rows[1][1],'Comillas "dobles"');
assert.equal(normalizeHeader('Razón social'),'razon_social');
const mapping=suggestMapping(parsed.headers,IMPORT_FIELDS.customers); assert.equal(mapping.external_key,'external_key'); assert.equal(mapping.display_name,'nombre');
assert.deepEqual(mapCsvRows(parsed,mapping)[0],{row_number:2,external_key:'CLI-1',display_name:'Logística Ñ',notes:'Texto; con separador'});
const exported=serializeCsv([{name:'Cliente, S.A.',formula:'=HYPERLINK("bad")',plus:'+1',at:'@cmd',safe:'áéíóú'}]);
assert.ok(exported.startsWith('\uFEFF')); assert.ok(exported.includes('"\'=HYPERLINK(""bad"")"')); assert.ok(exported.includes('"\'+1"')); assert.ok(exported.includes('"\'@cmd"')); assert.ok(exported.includes('\r\n'));
assert.ok(templateCsv('operations').includes('"origin_municipality"')); assert.ok(templateCsv('operations').includes('"cargo_description"'));
assert.ok(validationErrorsCsv([{row_number:7,external_key:'OP-7',action:'error',errors:[{code:'invalid','message':'Inválido, revisar'}],warnings:[]}]).includes('Inválido, revisar'));
assert.throws(()=>parseCsv('a,b\n"sin cierre,b'),/csv_unclosed_quote/); assert.throws(()=>parseCsv('a,a\n1,2'),/csv_invalid_headers/);
