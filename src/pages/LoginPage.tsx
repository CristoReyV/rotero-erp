import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { authService } from '@/services/auth.service';
import { useAuthAccess } from '@/hooks/useAuthAccess';
import { Mail, Lock, Loader2, AlertCircle } from 'lucide-react';

const checkRateLimit = (key: string) => {
    const MAX_ATTEMPTS = 5;
    const TIME_WINDOW = 5 * 60 * 1000;
    const data = JSON.parse(localStorage.getItem(key) || '{"attempts": 0, "firstAttempt": 0}');
    const now = Date.now();

    if (now - data.firstAttempt > TIME_WINDOW) {
        localStorage.setItem(key, JSON.stringify({ attempts: 1, firstAttempt: now }));
        return true;
    }

    if (data.attempts >= MAX_ATTEMPTS) {
        return false;
    }

    data.attempts += 1;
    localStorage.setItem(key, JSON.stringify(data));
    return true;
};

const LoginPage = () => {
    const navigate = useNavigate();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const access = useAuthAccess();
    const mounted = React.useRef(true);
    React.useEffect(() => {
        mounted.current = true;
        return () => { mounted.current = false; };
    }, []);
    React.useEffect(() => {
        if (access.status === 'authorized') navigate('/dashboard', { replace: true });
    }, [access.status, navigate]);

    const handleLogin = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(null);
        try {
            if (!checkRateLimit(`login_attempts_${email}`)) {
                setError('Demasiados intentos de inicio de sesión. Intenta nuevamente en 5 minutos.');
                return;
            }
        } catch {
            setError('No fue posible comprobar los intentos de acceso. Revisa el almacenamiento de esta pestaña y reintenta.');
            return;
        }
        setLoading(true);
        try {
            await authService.signIn({ email, password });
        } finally {
            if (mounted.current) setLoading(false);
        }
    };

    return (
        <div className="min-h-screen bg-gray-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8">
            <div className="sm:mx-auto sm:w-full sm:max-w-md">
                <div className="text-center">
                    <h2 className="text-3xl font-extrabold text-gray-900">
                        ROTERO <span className="text-blue-600">ERP</span>
                    </h2>
                    <p className="mt-2 text-sm text-gray-600">
                        Inicia sesión para continuar
                    </p>
                </div>
            </div>

            <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
                <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10 border border-gray-100">
                    {(error || access.message) && (
                        <div className="mb-4 rounded-md bg-red-50 p-4 border border-red-200">
                            <div className="flex items-center">
                                <AlertCircle className="h-5 w-5 text-red-500 mr-2" />
                                <h3 className="text-sm font-medium text-red-800">Error de inicio de sesión</h3>
                            </div>
                            <div className="mt-2 text-sm text-red-700">
                                <p>{error || access.message}</p>
                            </div>
                        </div>
                    )}

                    {['error', 'disabled'].includes(access.status) && (
                        <button type="button" onClick={() => { void authService.access.retry(); }} className="mb-4 text-sm font-semibold text-primary">Reintentar verificación</button>
                    )}
                    {access.status === 'error' && (
                        <button type="button" onClick={() => window.location.reload()} className="mb-4 ml-4 text-sm font-semibold text-gray-700">Recargar página</button>
                    )}
                    {access.message && (
                        <button type="button" onClick={() => { void authService.signOut(); }} className="mb-4 ml-4 text-sm font-semibold text-gray-700">Cerrar sesión</button>
                    )}
                    <form className="space-y-6" onSubmit={handleLogin}>
                        <div>
                            <label className="block text-sm font-medium text-gray-700" htmlFor="email">
                                Correo electrónico
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                                    <Mail className="h-5 w-5 text-gray-400" />
                                </div>
                                <input
                                    id="email"
                                    type="email"
                                    required
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="focus:ring-blue-500 focus:border-blue-500 block w-full pl-10 sm:text-sm border-gray-300 rounded-md py-2 px-3 border"
                                    placeholder="usuario@rotero.mx"
                                />
                            </div>
                        </div>

                        <div>
                            <label className="block text-sm font-medium text-gray-700" htmlFor="password">
                                Contraseña
                            </label>
                            <div className="mt-1 relative rounded-md shadow-sm">
                                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                                    <Lock className="h-5 w-5 text-gray-400" />
                                </div>
                                <input
                                    id="password"
                                    type="password"
                                    required
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="focus:ring-blue-500 focus:border-blue-500 block w-full pl-10 sm:text-sm border-gray-300 rounded-md py-2 px-3 border"
                                    placeholder="••••••••"
                                />
                            </div>
                        </div>

                        <div>
                            <button
                                type="submit"
                                disabled={loading}
                                className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {loading && <Loader2 className="w-5 h-5 mr-2 animate-spin" />}
                                Ingresar
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    );
};

export default LoginPage;
