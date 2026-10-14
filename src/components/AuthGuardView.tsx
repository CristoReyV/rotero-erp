import { Navigate, Outlet } from 'react-router-dom';
import { Loader2, LogOut } from 'lucide-react';
import type { AuthAccessState } from '@/services/authAccess';

export function AuthGuardView({ state, onRetry, onSignOut }: {
    state: AuthAccessState;
    onRetry: () => void;
    onSignOut: () => void;
}) {
    if (state.status === 'loading') {
        return <div className="min-h-screen flex items-center justify-center bg-gray-50" role="status" aria-label="Verificando acceso">
            <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
        </div>;
    }
    if (state.status === 'unauthenticated') return <Navigate to="/login" replace />;
    if (state.status === 'authorized') return <Outlet />;
    return <div className="min-h-screen flex items-center justify-center bg-gray-50 p-6">
        <div className="w-full max-w-md rounded-2xl border border-gray-200 bg-white p-8 text-center shadow-sm" role="alert">
            <h1 className="text-xl font-bold text-gray-900">
                {state.status === 'disabled' ? 'Acceso ERP no habilitado' : 'No fue posible verificar el acceso'}
            </h1>
            <p className="mt-3 text-sm leading-6 text-gray-600">{state.message}</p>
            <button type="button" onClick={onRetry} className="mt-6 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-white">Reintentar</button>
            {state.status === 'error' && <button type="button" onClick={() => window.location.reload()} className="mt-3 ml-3 rounded-lg border px-4 py-2 text-sm font-semibold text-gray-700">Recargar página</button>}
            <button type="button" onClick={onSignOut} className="mt-3 inline-flex items-center gap-2 rounded-lg bg-gray-900 px-4 py-2 text-sm font-semibold text-white">
                <LogOut size={16} />Cerrar sesión
            </button>
        </div>
    </div>;
}
