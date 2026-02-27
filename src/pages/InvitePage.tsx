import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useAuthStore } from '@/store/authStore';
import { acceptInvitation } from '@/services/invitation.service';
import { Lock, User, Loader2, CheckCircle2, AlertTriangle } from 'lucide-react';

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

const InvitePage = () => {
    const { token } = useParams<{ token: string }>();
    const navigate = useNavigate();
    const logout = useAuthStore((s) => s.logout);
    const context = useAuthStore((s) => s.context);

    const [form, setForm] = useState({ fullName: '', password: '', confirmPassword: '' });
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [success, setSuccess] = useState(false);

    // Force logout if someone is already authenticated
    useEffect(() => {
        if (context) {
            logout();
        }
    }, [context, logout]);

    const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        setForm({ ...form, [e.target.name]: e.target.value });
    };

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');

        if (!checkRateLimit(`invite_attempts_${token}`)) {
            setError('Demasiados intentos. Intenta nuevamente en 5 minutos.');
            return;
        }

        if (form.password.length < 8 || !/[A-Z]/.test(form.password) || !/[0-9]/.test(form.password)) {
            setError('La contraseña debe tener al menos 8 caracteres, 1 número y 1 mayúscula');
            return;
        }
        if (form.password !== form.confirmPassword) {
            setError('Las contraseñas no coinciden');
            return;
        }
        if (!form.fullName.trim()) {
            setError('El nombre completo es requerido');
            return;
        }
        if (!token) {
            setError('Token inválido');
            return;
        }

        setLoading(true);
        try {
            await acceptInvitation(token, form.password, form.fullName);
            setSuccess(true);
            setTimeout(() => {
                navigate('/login');
            }, 3000);
        } catch (err: any) {
            setError(
                err.message === 'invalid_or_expired'
                    ? 'El enlace de invitación es inválido o ha expirado.'
                    : 'Ocurrió un error al procesar la invitación. Contacta al administrador.'
            );
        } finally {
            setLoading(false);
        }
    };

    if (success) {
        return (
            <div className="min-h-screen bg-surface flex flex-col items-center justify-center p-4">
                <div className="w-full max-w-md bg-white p-8 rounded-3xl shadow-xl shadow-slate-200/50 border border-slate-100 flex flex-col items-center text-center animate-in zoom-in-95 duration-500">
                    <div className="w-16 h-16 bg-emerald-100 text-emerald-600 rounded-full flex items-center justify-center mb-6">
                        <CheckCircle2 size={32} />
                    </div>
                    <h2 className="text-2xl font-bold text-slate-800 mb-2">¡Bienvenido a WLS Rotero!</h2>
                    <p className="text-slate-500 text-sm">Tu cuenta ha sido activada exitosamente. Redirigiendo al login...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-surface flex flex-col items-center justify-center p-4">
            <div className="w-full max-w-md">

                <div className="mb-8 text-center animate-in slide-in-from-bottom-2 duration-500">
                    <div className="w-12 h-12 gradient-accent rounded-2xl flex items-center justify-center text-white font-black text-2xl mx-auto shadow-lg shadow-accent-red/25 mb-4 hover:scale-105 transition-transform cursor-default">
                        R
                    </div>
                    <h1 className="text-2xl font-extrabold text-slate-800 mb-1">Aceptar Invitación</h1>
                    <p className="text-slate-500 text-sm">Configura tu acceso al ERP</p>
                </div>

                <div className="bg-white p-6 sm:p-8 rounded-3xl shadow-xl shadow-slate-200/50 border border-slate-100 animate-in slide-in-from-bottom-4 duration-700">
                    {error && (
                        <div className="mb-6 bg-red-50 text-red-600 p-4 rounded-xl text-sm flex items-start gap-3 border border-red-100 animate-in slide-in-from-top-2">
                            <AlertTriangle size={18} className="shrink-0 mt-0.5" />
                            <p className="font-medium leading-relaxed">{error}</p>
                        </div>
                    )}

                    <form onSubmit={handleSubmit} className="space-y-5">
                        <div className="space-y-1.5 focus-within:text-primary transition-colors duration-300">
                            <label className="text-[11px] font-bold uppercase tracking-wider text-slate-500 transition-colors">Nombre Completo</label>
                            <div className="relative group">
                                <User className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary transition-colors" size={18} />
                                <input
                                    type="text"
                                    name="fullName"
                                    value={form.fullName}
                                    onChange={handleChange}
                                    placeholder="Ej. Juan Pérez"
                                    className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-sm focus:bg-white focus:ring-2 focus:ring-primary/20 focus:border-primary/50 outline-none transition-all placeholder:text-slate-400 font-medium text-slate-700"
                                    required
                                    disabled={loading}
                                    autoComplete="name"
                                />
                            </div>
                        </div>

                        <div className="space-y-1.5 focus-within:text-primary transition-colors duration-300">
                            <label className="text-[11px] font-bold uppercase tracking-wider text-slate-500 transition-colors">Crear Contraseña</label>
                            <div className="relative group">
                                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary transition-colors" size={18} />
                                <input
                                    type="password"
                                    name="password"
                                    value={form.password}
                                    onChange={handleChange}
                                    placeholder="Mínimo 8 caracteres"
                                    className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-sm focus:bg-white focus:ring-2 focus:ring-primary/20 focus:border-primary/50 outline-none transition-all placeholder:text-slate-400 font-medium text-slate-700"
                                    required
                                    disabled={loading}
                                    minLength={8}
                                    autoComplete="new-password"
                                />
                            </div>
                        </div>

                        <div className="space-y-1.5 focus-within:text-primary transition-colors duration-300">
                            <label className="text-[11px] font-bold uppercase tracking-wider text-slate-500 transition-colors">Confirmar Contraseña</label>
                            <div className="relative group">
                                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-primary transition-colors" size={18} />
                                <input
                                    type="password"
                                    name="confirmPassword"
                                    value={form.confirmPassword}
                                    onChange={handleChange}
                                    placeholder="Repítela para validar"
                                    className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-sm focus:bg-white focus:ring-2 focus:ring-primary/20 focus:border-primary/50 outline-none transition-all placeholder:text-slate-400 font-medium text-slate-700"
                                    required
                                    disabled={loading}
                                    minLength={8}
                                    autoComplete="new-password"
                                />
                            </div>
                        </div>

                        <button
                            type="submit"
                            disabled={loading || form.password.length < 8 || !/[A-Z]/.test(form.password) || !/[0-9]/.test(form.password) || form.password !== form.confirmPassword || !form.fullName.trim()}
                            className="w-full py-3.5 gradient-primary text-white rounded-xl text-sm font-bold shadow-lg shadow-primary/25 hover:shadow-xl hover:shadow-primary/30 active:scale-[0.98] disabled:opacity-50 disabled:hover:scale-100 disabled:active:scale-100 disabled:shadow-none flex items-center justify-center gap-2 mt-4 transition-all"
                        >
                            {loading && <Loader2 size={18} className="animate-spin" />}
                            {loading ? 'Activando...' : 'Comenzar ahora'}
                        </button>
                    </form>
                </div>

                <p className="text-center text-slate-400 text-xs mt-8">
                    Rotero ERP &copy; {new Date().getFullYear()}
                </p>
            </div>
        </div>
    );
};

export default InvitePage;
