import React, { useEffect, useState } from 'react';
import { Navigate, Outlet } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { authService } from '@/services/auth.service';
import { isRoteroEnabledRole } from '@/constants/roles';
import { Loader2, LogOut } from 'lucide-react';

type AccessState = 'loading' | 'unauthenticated' | 'authorized' | 'disabled';

export const AuthGuard: React.FC = () => {
    const { context } = useAuthStore();
    const [accessState, setAccessState] = useState<AccessState>('loading');

    useEffect(() => {
        let mounted = true;

        const checkAuth = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                if (mounted) setAccessState('unauthenticated');
                return;
            }

            if (!context) {
                const success = await authService.loadContext();
                if (mounted) {
                    const role = useAuthStore.getState().getRole();
                    setAccessState(success && isRoteroEnabledRole(role) ? 'authorized' : 'disabled');
                }
            } else {
                if (mounted) setAccessState(isRoteroEnabledRole(useAuthStore.getState().getRole()) ? 'authorized' : 'disabled');
            }
        };

        checkAuth();

        const { data: authListener } = supabase.auth.onAuthStateChange(async (event, session) => {
            if (event === 'SIGNED_OUT') {
                useAuthStore.getState().logout();
                if (mounted) setAccessState('unauthenticated');
            } else if (event === 'SIGNED_IN') {
                if (!useAuthStore.getState().context) await authService.loadContext();
                if (mounted) {
                    setAccessState(isRoteroEnabledRole(useAuthStore.getState().getRole()) ? 'authorized' : 'disabled');
                }
            }
        });

        const handleUnauthorized = () => {
            useAuthStore.getState().logout();
            supabase.auth.signOut().then(() => {
                if (mounted) setAccessState('unauthenticated');
            });
        };
        window.addEventListener('app:unauthorized', handleUnauthorized);

        return () => {
            mounted = false;
            authListener.subscription.unsubscribe();
            window.removeEventListener('app:unauthorized', handleUnauthorized);
        };
    }, [context]);

    if (accessState === 'loading') {
        return (
            <div className="min-h-screen flex items-center justify-center bg-gray-50">
                <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
            </div>
        );
    }

    if (accessState === 'unauthenticated') {
        return <Navigate to="/login" replace />;
    }

    if (accessState === 'disabled') {
        return (
            <div className="min-h-screen flex items-center justify-center bg-gray-50 p-6">
                <div className="w-full max-w-md rounded-2xl border border-gray-200 bg-white p-8 text-center shadow-sm">
                    <h1 className="text-xl font-bold text-gray-900">Acceso ERP no habilitado</h1>
                    <p className="mt-3 text-sm leading-6 text-gray-600">
                        Esta membresía conserva un rol de producto, pero no tiene acceso al despliegue actual de ROTERO.
                        Solicita al administrador una cuenta beta con rol Administrador o Finanzas.
                    </p>
                    <button
                        type="button"
                        onClick={() => supabase.auth.signOut()}
                        className="mt-6 inline-flex items-center gap-2 rounded-lg bg-gray-900 px-4 py-2 text-sm font-semibold text-white hover:bg-gray-800"
                    >
                        <LogOut size={16} />
                        Cerrar sesión
                    </button>
                </div>
            </div>
        );
    }

    return <Outlet />;
};
