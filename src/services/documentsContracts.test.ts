import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { registerWithCompensation, validateDocumentFile } from './documentsContracts';
import type { DocumentUploadContract } from '@/types/documents';

const contract: DocumentUploadContract = {
    bucket: 'tenant-documents', private: true, max_file_size: 100,
    allowed_mime_types: ['application/pdf', 'image/jpeg'], signed_url_ttl_seconds: 300,
};
assert.equal(validateDocumentFile({ name: 'pod.pdf', type: 'application/pdf', size: 50 }, contract), null);
assert.match(validateDocumentFile({ name: 'pod.exe', type: 'application/pdf', size: 50 }, contract) ?? '', /tipo|extensión/i);
assert.match(validateDocumentFile({ name: 'pod.pdf', type: 'application/pdf', size: 101 }, contract) ?? '', /límite/i);
assert.match(validateDocumentFile({ name: 'pod.jpg', type: 'application/octet-stream', size: 20 }, contract) ?? '', /tipo/i);

let compensated = false;
await assert.rejects(() => registerWithCompensation(
    async () => { throw new Error('raw storage detail'); },
    async () => { compensated = true; },
), /intentó revertir/i);
assert.equal(compensated, true);

const source = readFileSync('src/services/documents.service.ts', 'utf8');
assert.match(source, /createSignedUrl\(file\.storage_path, 300/);
assert.match(source, /upsert: false/);
assert.match(source, /rpc_register_document_file/);
assert.doesNotMatch(source, /service_role|base64/i);
