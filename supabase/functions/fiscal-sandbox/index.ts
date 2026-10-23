import { createClient } from '@supabase/supabase-js';
import { FacturamaSandbox } from '../_shared/facturama.ts';
import { createFiscalHandler } from './handler.ts';
const staging = 'https://mxpmgihuheagrcowwbia.supabase.co';
// Immutable deployment boundary. The test harness injects local clients into
// handler.ts; deployment never accepts a caller-provided URL or environment.
Deno.serve(async (req: Request) => {
    if (
        Deno.env.get('FACTURAMA_SANDBOX_ENABLED') !== 'true' ||
        Deno.env.get('FACTURAMA_ENVIRONMENT') !== 'sandbox' || Deno.env.get('SUPABASE_URL') !== staging
    ) {
        return Response.json({ error: 'sandbox_disabled' }, {
            status: 503,
            headers: { 'Cache-Control': 'no-store' },
        });
    }
    const opts = { auth: { persistSession: false, autoRefreshToken: false } };
    const admin = createClient(staging, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, opts);
    const adapter = new FacturamaSandbox({
        username: Deno.env.get('FACTURAMA_SANDBOX_USER') ?? '',
        password: Deno.env.get('FACTURAMA_SANDBOX_PASSWORD') ?? '',
        environment: 'sandbox',
    });
    return createFiscalHandler({
        admin,
        adapter,
        userClient: (authorization) =>
            createClient(staging, Deno.env.get('SUPABASE_ANON_KEY')!, {
                ...opts,
                global: { headers: { Authorization: authorization } },
            }),
    })(req);
});
