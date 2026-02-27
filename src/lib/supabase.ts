import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://hoxmscslxmbdfyyfkhrt.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'dummy_key';

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
