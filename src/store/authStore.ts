import { create } from 'zustand';
import { createJSONStorage, persist } from 'zustand/middleware';
import { useCompanyStore } from './companyStore';
import { findRoteroEnabledTenantId, isRoteroEnabledRole, type ProductRole } from '@/constants/roles';

export interface Membership {
    tenant_id: string;
    tenant_name: string;
    role: ProductRole;
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
    getRole: () => ProductRole | null;
}

export const useAuthStore = create<AuthState>()(
    persist(
        (set, get) => ({
            context: null,
            activeTenant: null,
            setContext: (context) => {
                const activeTenant = context
                    ? findRoteroEnabledTenantId(context.memberships, get().activeTenant)
                    : null;
                if (
                    context?.user_id !== get().context?.user_id || activeTenant !== get().activeTenant ||
                    JSON.stringify(context?.memberships) !== JSON.stringify(get().context?.memberships)
                ) {
                    useCompanyStore.getState().reset(activeTenant);
                }
                set({ context, activeTenant });
            },
            setActiveTenant: (tenantId) => {
                if (tenantId !== get().activeTenant) useCompanyStore.getState().reset(tenantId);
                const context = get().context;
                const membership = context?.memberships.find((item) => item.tenant_id === tenantId);
                set({ activeTenant: membership && isRoteroEnabledRole(membership.role) ? tenantId : null });
            },
            logout: () => {
                useCompanyStore.getState().reset();
                set({ context: null, activeTenant: null });
            },
            getRole: () => {
                const { context, activeTenant } = get();
                if (!context || !activeTenant) return null;
                const membership = context.memberships.find((m) => m.tenant_id === activeTenant);
                return membership ? membership.role : null;
            },
        }),
        {
            name: 'rotero-auth-store',
            storage: createJSONStorage(() => sessionStorage),
        },
    ),
);
