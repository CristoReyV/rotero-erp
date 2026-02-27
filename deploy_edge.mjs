import { execSync } from 'child_process';
import fs from 'fs';

const envFile = fs.readFileSync('.env.production', 'utf8');
let token = '';

envFile.split('\n').forEach(line => {
    line = line.trim();
    if (line.startsWith('SUPABASE_ACCESS_TOKEN=')) {
        token = line.substring('SUPABASE_ACCESS_TOKEN='.length).replace(/^['"]|['"]$/g, '').trim();
    }
});

if (!token) {
    console.error('SUPABASE_ACCESS_TOKEN not found in .env.production');
    process.exit(1);
}

console.log('Token found, length:', token.length);

try {
    console.log('Deploying track-public...');
    execSync('npx supabase functions deploy track-public --project-ref hoxmscslxmbdfyyfkhrt', {
        env: { ...process.env, SUPABASE_ACCESS_TOKEN: token },
        stdio: 'inherit'
    });

    console.log('Deploying driver-view...');
    execSync('npx supabase functions deploy driver-view --project-ref hoxmscslxmbdfyyfkhrt', {
        env: { ...process.env, SUPABASE_ACCESS_TOKEN: token },
        stdio: 'inherit'
    });

    console.log('Deployment complete.');
} catch (e) {
    console.error('Deployment failed.');
    process.exit(1);
}
