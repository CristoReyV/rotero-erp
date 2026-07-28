import { createClient } from '@supabase/supabase-js';

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
            const response = await fetch(url, options);
            if (response.status === 401 || response.status === 403) {
                const path = window.location.pathname;
                if (!path.includes('/login') && !path.includes('/invite')) {
                    window.dispatchEvent(new CustomEvent('app:unauthorized'));
                }
            }
            return response;
        }
    }
});
