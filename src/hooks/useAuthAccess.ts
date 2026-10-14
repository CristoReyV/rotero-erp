import { useEffect, useSyncExternalStore } from 'react';
import { authService } from '@/services/auth.service';

export function useAuthAccess() {
    const state = useSyncExternalStore(authService.access.subscribe, authService.access.getSnapshot);
    useEffect(() => {
        const stop = authService.access.start();
        const unauthorized = () => { void authService.signOut(); };
        window.addEventListener('app:unauthorized', unauthorized);
        return () => {
            window.removeEventListener('app:unauthorized', unauthorized);
            stop();
        };
    }, []);
    return state;
}
