import { createClient } from '@supabase/supabase-js';
import { companyHeaders, scopedResponse } from '@/store/companyStore';

const configuredSupabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim();
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();

if (!configuredSupabaseUrl || !supabaseAnonKey) {
    throw new Error(
        'Configuración de Supabase incompleta: define VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY.',
    );
}

export const supabaseUrl = configuredSupabaseUrl.replace(/\/+$/, '');

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
        fetch: async (url, options) => {
            const target = new URL(typeof url === 'string' ? url : url instanceof URL ? url.href : url.url);
            const scoped = target.origin === new URL(supabaseUrl).origin &&
                (target.pathname.startsWith('/rest/v1/') || target.pathname.startsWith('/storage/v1/') ||
                    target.pathname === '/functions/v1/fiscal-sandbox');
            const headers = new Headers(
                options?.headers ?? (url instanceof Request ? url.headers : undefined),
            );
            if (scoped) Object.entries(companyHeaders()).forEach(([key, value]) => headers.set(key, value));
            const response = scoped
                ? await scopedResponse(async () => {
                    const incoming = await fetch(url, { ...options, headers });
                    const bytes = await incoming.arrayBuffer();
                    const responseHeaders = new Headers(incoming.headers);
                    responseHeaders.delete('content-encoding');
                    responseHeaders.delete('content-length');
                    return new Response([204, 205, 304].includes(incoming.status) ? null : bytes, {
                        status: incoming.status,
                        statusText: incoming.statusText,
                        headers: responseHeaders,
                    });
                })
                : await fetch(url, options);
            if (response.status === 401 || response.status === 403) {
                const path = window.location.pathname;
                if (!path.includes('/login') && !path.includes('/invite')) {
                    window.dispatchEvent(new CustomEvent('app:unauthorized'));
                }
            }
            return response;
        },
    },
});
