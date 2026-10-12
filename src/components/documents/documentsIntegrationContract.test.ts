import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const quote = readFileSync('src/components/commercial/QuoteWorkspace.tsx', 'utf8');
const customer = readFileSync('src/components/commercial/CustomerDirectory.tsx', 'utf8');
const provider = readFileSync('src/components/commercial/ProviderDirectory.tsx', 'utf8');
const operationDocuments = readFileSync('src/components/operations/OperationDocuments.tsx', 'utf8');
const operationEvidence = readFileSync('src/components/operations/OperationEvidence.tsx', 'utf8');
const operationTypes = readFileSync('src/types/operations.ts', 'utf8');

assert.match(quote, /EntityDocumentsPanel[\s\S]*entityType="quote"/);
assert.match(quote, /relateQuoteDocumentsToOperation\(selected\.id, result\.operation_id\)/);
assert.match(customer, /entityType="customer"/);
assert.match(provider, /entityType="provider"[\s\S]*fileKind="provider_upload"/);
assert.match(operationDocuments, /attachOperationDocumentFile/);
assert.match(operationTypes, /proof_of_delivery/);
assert.doesNotMatch(operationDocuments, /proof_of_delivery/);
assert.match(operationDocuments, /prueba de entrega \(POD\)/i);
assert.match(operationDocuments, /createDocumentSignedUrl/);
assert.match(operationDocuments, /Relacionar un archivo ya registrado/);
assert.match(operationDocuments, /generateDocument\(tenantId, 'operation_document'/);
assert.match(operationEvidence, /fileKind="operation_evidence"/);
assert.match(operationEvidence, /addOperationFileEvidence/);
assert.doesNotMatch(operationDocuments, /Upload futuro|Archivo\/ref\. storage/);
