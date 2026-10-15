import { useAuthAccess } from '@/hooks/useAuthAccess';
import { authService } from '@/services/auth.service';
import { useAuthStore } from '@/store/authStore';
import { isRoteroEnabledRole } from '@/constants/roles';
import { AuthGuardView } from './AuthGuardView';

export function AuthGuard() {
    const access = useAuthAccess();
    const { context, getRole } = useAuthStore();
    // A cleared/changed context must never reach RoleGuard's redirect fallback.
    const state = access.status === 'authorized'
        && (context?.user_id !== access.userId || !isRoteroEnabledRole(getRole()))
        ? { status: 'disabled' as const, userId: null, message: 'El contexto de acceso cambió. Reintenta la verificación.' }
        : access;
    return <AuthGuardView state={state}
        onRetry={() => { void authService.access.retry(); }}
        onSignOut={() => { void authService.signOut(); }} />;
}
