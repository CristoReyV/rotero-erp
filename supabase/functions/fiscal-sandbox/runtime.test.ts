import assert from 'node:assert/strict';

Deno.test('deployed wrapper returns 503 for non-sandbox configuration before creating clients', async () => {
    const names = ['FACTURAMA_SANDBOX_ENABLED', 'FACTURAMA_ENVIRONMENT', 'SUPABASE_URL'];
    const previous = names.map((name) => Deno.env.get(name));
    const serve = Deno.serve;
    let handler: ((request: Request) => Promise<Response>) | undefined;
    Deno.serve = ((callback: (request: Request) => Promise<Response>) => {
        handler = callback;
        return {};
    }) as typeof Deno.serve;
    try {
        await import('./index.ts');
        assert.ok(handler);
        for (
            const [enabled, environment, supabaseUrl] of [
                ['false', 'sandbox', 'https://mxpmgihuheagrcowwbia.supabase.co'],
                ['true', 'production', 'https://mxpmgihuheagrcowwbia.supabase.co'],
                ['true', 'sandbox', 'https://other.supabase.co'],
            ]
        ) {
            for (const [i, value] of [enabled, environment, supabaseUrl].entries()) {
                Deno.env.set(names[i], value);
            }
            const response = await handler(new Request('https://synthetic.invalid'));
            assert.equal(response.status, 503);
            assert.deepEqual(await response.json(), { error: 'sandbox_disabled' });
        }
    } finally {
        Deno.serve = serve;
        names.forEach((name, i) =>
            previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!)
        );
    }
});
