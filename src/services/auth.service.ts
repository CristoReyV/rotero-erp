import { supabase } from '@/lib/supabase';
import { useAuthStore, AuthContext } from '@/store/authStore';

export const authService = {
    /**
     * Rehydrates the auth context from the database if a session exists.
     * Should be called on app mount and after login.
     */
    async loadContext(): Promise<boolean> {
        try {
            const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
            if (sessionError || !sessionData.session) {
                return false;
            }

            const { data, error } = await supabase.rpc('rpc_get_my_context');
            if (error) {
                console.error('Failed to load auth context:', error);
                return false;
            }

            // data could theoretically be an error object if the RPc returned jsonb_build_object('error', '...')
            if (data && typeof data === 'object' && 'error' in data) {
                console.error('Auth context error:', data.error);
                return false;
            }

            const ctx = data as AuthContext;
            useAuthStore.getState().setContext(ctx);
            return true;

        } catch (e) {
            console.error('Unexpected error loading context', e);
            return false;
        }
    },

    /**
     * Signs out the user and clears local state.
     */
    async signOut() {
        await supabase.auth.signOut();
        useAuthStore.getState().logout();
    }
};
