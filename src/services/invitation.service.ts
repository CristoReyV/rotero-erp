import { supabase } from '@/lib/supabase';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

export async function acceptInvitation(token: string, password: string, fullName: string): Promise<{ success: boolean }> {
    if (USE_MOCKS) {
        return new Promise((resolve, reject) => {
            setTimeout(() => {
                if (token === 'mock-token-abc-123' || token.length > 8) {
                    resolve({ success: true });
                } else {
                    reject(new Error('invalid_or_expired'));
                }
            }, 800);
        });
    }

    const { data, error } = await supabase.rpc('rpc_accept_invitation', {
        p_token: token,
        p_password: password,
        p_full_name: fullName
    });

    if (error) {
        throw error;
    }

    if (data?.error) {
        throw new Error(data.error);
    }

    return data;
}
