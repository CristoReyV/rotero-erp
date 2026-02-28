import React, { useEffect, useState } from 'react';
import { Navigate, Outlet } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';
import { authService } from '@/services/auth.service';
import { Loader2 } from 'lucide-react';

export const AuthGuard: React.FC = () => {
    const { context } = useAuthStore();
    const [isLoading, setIsLoading] = useState(true);
    const [isAuthenticated, setIsAuthenticated] = useState(false);

    useEffect(() => {
        let mounted = true;

        const checkAuth = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session) {
                if (mounted) {
                    setIsAuthenticated(false);
                    setIsLoading(false);
                }
                return;
            }

            if (!context) {
                // Have session but no context in Zustand layer, fetch it now
                const success = await authService.loadContext();
                if (mounted) {
                    setIsAuthenticated(success);
                    setIsLoading(false);
                }
            } else {
                // Have session and context
                if (mounted) {
                    setIsAuthenticated(true);
                    setIsLoading(false);
                }
            }
        };

        checkAuth();

        const { data: authListener } = supabase.auth.onAuthStateChange(async (event, session) => {
            if (event === 'SIGNED_OUT') {
                useAuthStore.getState().logout();
                if (mounted) setIsAuthenticated(false);
            } else if (event === 'SIGNED_IN' && !useAuthStore.getState().context) {
                await authService.loadContext();
                if (mounted) setIsAuthenticated(true);
            }
        });

        const handleUnauthorized = () => {
            useAuthStore.getState().logout();
            supabase.auth.signOut().then(() => {
                if (mounted) setIsAuthenticated(false);
            });
        };
        window.addEventListener('app:unauthorized', handleUnauthorized);

        return () => {
            mounted = false;
            authListener.subscription.unsubscribe();
            window.removeEventListener('app:unauthorized', handleUnauthorized);
        };
    }, [context]);

    if (isLoading) {
        return (
            <div className="min-h-screen flex items-center justify-center bg-gray-50">
                <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
            </div>
        );
    }

    if (!isAuthenticated) {
        return <Navigate to="/login" replace />;
    }

    return <Outlet />;
};
