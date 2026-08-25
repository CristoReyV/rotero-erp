import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const read = (path: string) => readFileSync(join(root, path), 'utf8');
const files = (directory: string): string[] => readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? files(path) : [path];
});

const router = read('src/routes/router.tsx');
assert.match(
    router,
    /path:\s*['"]\/invite\/:token['"][\s\S]{0,100}element:\s*<Navigate\s+to=['"]\/login['"]\s+replace\s*\/>/,
    'The invitation route must remain fail-closed at /login',
);
assert.doesNotMatch(router, /InvitePage/, 'The disabled InvitePage must not be routed');

const activeSources = files(join(root, 'src'))
    .filter((path) => /\.(ts|tsx)$/.test(path))
    .filter((path) => !path.endsWith('invitation.service.ts'))
    .filter((path) => !path.endsWith('admin.service.ts'))
    .filter((path) => !path.endsWith('InvitePage.tsx'))
    .filter((path) => !path.endsWith('r41InvitationDisabledContract.test.ts'))
    .map((path) => readFileSync(path, 'utf8'))
    .join('\n');

assert.doesNotMatch(activeSources, /acceptInvitation\s*\(/, 'No active consumer may call legacy invitation acceptance');
assert.doesNotMatch(activeSources, /inviteMember\s*\(/, 'No active UI may expose invitation provisioning');

console.log('R4.1 disabled invitation deployment contract passed');
