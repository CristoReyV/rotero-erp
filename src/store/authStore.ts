import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

export interface Membership {
    tenant_id: string;
    tenant_name: string;
    role: 'admin' | 'operator' | 'viewer';
}

export interface AuthContext {
    user_id: string;
    email: string;
    memberships: Membership[];
}

interface AuthState {
    context: AuthContext | null;
    activeTenant: string | null;
    setContext: (context: AuthContext | null) => void;
    setActiveTenant: (tenantId: string | null) => void;
    logout: () => void;
    getRole: () => 'admin' | 'operator' | 'viewer' | null;
}

export const useAuthStore = create<AuthState>()(
    persist(
        (set, get) => ({
            context: null,
            activeTenant: null,
            setContext: (context) => {
                set({ context });
                if (context && context.memberships.length > 0) {
                    const currentTenant = get().activeTenant;
                    const isValidTenant = context.memberships.find(m => m.tenant_id === currentTenant);
                    if (!isValidTenant) {
                        set({ activeTenant: context.memberships[0].tenant_id });
                    }
                } else {
                    set({ activeTenant: null });
                }
            },
            setActiveTenant: (tenantId) => set({ activeTenant: tenantId }),
            logout: () => set({ context: null, activeTenant: null }),
            getRole: () => {
                const { context, activeTenant } = get();
                if (!context || !activeTenant) return null;
                const membership = context.memberships.find(m => m.tenant_id === activeTenant);
                return membership ? membership.role : null;
            }
        }),
        {
            name: 'rotero-auth-store',
            storage: createJSONStorage(() => sessionStorage),
        }
    )
);
