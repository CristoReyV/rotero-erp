import { useState, useEffect, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuthStore } from '@/store/authStore';

export function useModuleGate(moduleName: string) {
    const activeTenant = useAuthStore(s => s.activeTenant);
    const [isConfigured, setIsConfigured] = useState<boolean>(true); // default true to avoid flicker blocking? Or false. Let's start false/true depending on loading.
    const [configData, setConfigData] = useState<any>(null);
    const [loading, setLoading] = useState<boolean>(true);
    const [error, setError] = useState<string | null>(null);

    const checkAccess = useCallback(async () => {
        if (!activeTenant) return;
        setLoading(true);
        setError(null);
        try {
            if (import.meta.env.VITE_USE_MOCKS === 'true') {
                setIsConfigured(true);
                if (moduleName === 'inventory') {
                    setConfigData({ units: ['Piezas (Mock)', 'Kilos', 'Litros'] });
                } else if (moduleName === 'billing') {
                    setConfigData({ rfc: 'MOCK010101000' });
                } else if (moduleName === 'customs') {
                    setConfigData({ patente: '9999' });
                } else {
                    setConfigData({});
                }
                setLoading(false);
                return;
            }

            const { data, error: rpcError } = await supabase.rpc('rpc_validate_module_access', {
                p_tenant_id: activeTenant,
                p_module_name: moduleName
            });

            if (rpcError) throw rpcError;
            if (data?.error) throw new Error(data.error);

            setIsConfigured(data?.is_configured === true);
            setConfigData(data?.config_data || {});
        } catch (err: any) {
            console.error(`Error checking module access [${moduleName}]:`, err);
            setError(err.message);
            // Default to unconfigured on error for security
            setIsConfigured(false);
        } finally {
            setLoading(false);
        }
    }, [activeTenant, moduleName]);

    useEffect(() => {
        let isMounted = true;

        const init = async () => {
            if (isMounted) await checkAccess();
        };
        init();

        return () => { isMounted = false; };
    }, [checkAccess]);

    return {
        isConfigured,
        configData,
        loading,
        error,
        refresh: checkAccess
    };
}
