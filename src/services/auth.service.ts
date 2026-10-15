import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { createAuthAccess, type SignInInput } from './authAccess';

const access = createAuthAccess({
    getSession: async () => {
        const { data, error } = await supabase.auth.getSession();
        if (error) throw new Error('session_lookup_failed');
        return data.session ? { userId: data.session.user.id } : null;
    },
    getContext: async signal => {
        const { data, error } = await supabase.rpc('rpc_get_my_context').abortSignal(signal);
        if (error || (data && typeof data === 'object' && 'error' in data)) throw new Error('context_lookup_failed');
        return data;
    },
    signIn: async input => {
        const { data, error } = await supabase.auth.signInWithPassword(input);
        if (error) throw new Error('sign_in_failed');
        return data.session ? { userId: data.session.user.id } : null;
    },
    signOut: async () => {
        const { error } = await supabase.auth.signOut();
        if (error) throw new Error('sign_out_failed');
    },
    onAuthChange: callback => {
        const { data } = supabase.auth.onAuthStateChange((event, session) => {
            callback(event, session ? { userId: session.user.id } : null);
        });
        return () => data.subscription.unsubscribe();
    },
    store: {
        getContext: () => useAuthStore.getState().context,
        getTenant: () => useAuthStore.getState().activeTenant,
        clear: () => useAuthStore.getState().logout(),
        commit: (context, tenant) => {
            useAuthStore.getState().setContext(context);
            useAuthStore.getState().setActiveTenant(tenant);
        },
        subscribe: callback => useAuthStore.subscribe(callback),
    },
});

export const authService = {
    access,
    loadContext: () => access.retry(),
    signIn: (input: SignInInput) => access.signIn(input),
    signOut: () => access.signOut(),
};
