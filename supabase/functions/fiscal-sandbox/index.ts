import { createClient } from '@supabase/supabase-js';
import { FacturamaSandbox } from '../_shared/facturama.ts';
import {
    createFiscalHandler,
    fiscalCompanyHeaders,
    isFiscalSandboxRuntime,
    STAGING_SUPABASE_URL,
} from './handler.ts';
const staging = STAGING_SUPABASE_URL;
// Immutable deployment boundary. The test harness injects local clients into
// handler.ts; deployment never accepts a caller-provided URL or environment.
Deno.serve(async (req: Request) => {
    if (
        !isFiscalSandboxRuntime({
            enabled: Deno.env.get('FACTURAMA_SANDBOX_ENABLED'),
            environment: Deno.env.get('FACTURAMA_ENVIRONMENT'),
            supabaseUrl: Deno.env.get('SUPABASE_URL'),
        })
    ) {
        return Response.json({ error: 'sandbox_disabled' }, {
            status: 503,
            headers: { 'Cache-Control': 'no-store' },
        });
    }
    const opts = { auth: { persistSession: false, autoRefreshToken: false } };
    // Each request owns its clients; selectors never mutate a shared service client.
    const scope = fiscalCompanyHeaders(req.headers);
    const admin = createClient(staging, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
        ...opts,
        global: { headers: scope },
    });
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
                global: { headers: { ...scope, Authorization: authorization } },
            }),
    })(req);
});
