import { useState, useEffect } from 'react';
import { Search, Users, Monitor, MoreHorizontal, Loader2, ShieldAlert } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getMembers, changeMemberRole } from '@/services/admin.service';
import type { Member } from '@/types/settings';
import {
    isRoteroEnabledRole,
    isRoteroProvisionableRole,
    PRODUCT_ROLE_LABELS,
    ROTERO_PROVISIONABLE_ROLES,
} from '@/constants/roles';

const roleColors: Record<string, string> = {
    'viewer': 'bg-slate-50 text-slate-600 ring-1 ring-slate-200',
    'operator': 'bg-blue-50 text-blue-700 ring-1 ring-blue-200/60',
    'finance': 'bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200/60',
    'admin': 'bg-red-50 text-red-700 ring-1 ring-red-200/60',
};

const SecurityUsersPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const userRole = useAuthStore((s) => s.getRole());
    const isAdmin = userRole === 'admin';

    const [loading, setLoading] = useState(true);
    const [members, setMembers] = useState<Member[]>([]);

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const mm = await getMembers(activeTenant);
            setMembers(mm);
        } catch (error) {
            console.error('Failed to load members', error);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    const handleChangeRole = async (userId: string) => {
        if (!activeTenant || !isAdmin) return;
        const currentM = members.find(m => m.user_id === userId);
        if (!currentM) return;

        const roleStr = prompt(
            `Nuevo rol activo para ${currentM.name || currentM.email} (${ROTERO_PROVISIONABLE_ROLES.join(', ')}):`,
            isRoteroProvisionableRole(currentM.role) ? currentM.role : 'finance',
        );
        if (!isRoteroProvisionableRole(roleStr) || roleStr === currentM.role) {
            return;
        }

        try {
            await changeMemberRole(activeTenant, userId, roleStr);
            fetchData();
        } catch (error: any) {
            alert('Error al cambiar rol: ' + error.message);
        }
    };

    if (loading && members.length === 0) {
        return (
            <div className="flex flex-col items-center justify-center p-20 min-h-[50vh] text-slate-400 gap-4">
                <Loader2 className="animate-spin" size={32} />
                <p className="text-sm">Cargando Usuarios...</p>
            </div>
        );
    }

    return (
        <div className="space-y-6 animate-in fade-in duration-500">
            {/* Stats */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-primary-50 rounded-xl">
                        <Users size={22} className="text-primary" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Total Usuarios</p>
                        <p className="text-xl font-bold text-slate-800">{members.length}</p>
                    </div>
                </div>
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-emerald-50 rounded-xl">
                        <Monitor size={22} className="text-emerald-600" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Activos</p>
                        <p className="text-xl font-bold text-emerald-600">{members.filter((member) => isRoteroEnabledRole(member.role)).length}</p>
                    </div>
                </div>
            </div>

            <div className="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-amber-900">
                <ShieldAlert size={20} className="mt-0.5 shrink-0" />
                <div>
                    <p className="text-sm font-bold">Alta de usuarios gestionada manualmente durante beta</p>
                    <p className="mt-1 text-xs leading-5 text-amber-800">
                        Este despliegue habilita únicamente Administrador y Finanzas. Las invitaciones automáticas permanecen ocultas.
                    </p>
                </div>
            </div>

            {/* Actions Bar */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div className="relative max-w-md w-full">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                    <input
                        type="text"
                        placeholder="Buscar usuarios..."
                        className="w-full pl-9 pr-4 py-2 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                    />
                </div>
            </div>

            {/* Users List */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden shadow-sm">
                <div className="px-5 py-4 border-b border-tech-border/40 bg-surface/50">
                    <h3 className="text-xs font-bold text-slate-400 uppercase tracking-widest">Personal Autorizado</h3>
                </div>
                <div className="divide-y divide-tech-border/40">
                    {members.length === 0 && (
                        <p className="p-10 text-sm text-center text-slate-400">Sin miembros registrados</p>
                    )}
                    {members.map((user, i) => (
                        <div key={user.user_id || i} className="flex items-center gap-4 px-5 py-4 hover:bg-primary-50/20 transition-colors cursor-pointer group">
                            <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-xs font-bold text-white shrink-0
                ${i % 4 === 0 ? 'bg-indigo-500' : i % 4 === 1 ? 'bg-amber-500' : i % 4 === 2 ? 'bg-slate-400' : 'gradient-accent'}`}>
                                {(user.name || user.email).slice(0, 2).toUpperCase()}
                            </div>
                            <div className="flex-1 min-w-0">
                                <p className="text-[13px] font-semibold text-slate-700">{user.name || 'Usuario'}</p>
                                <p className="text-[10px] text-slate-400 mt-0.5">{user.email}</p>
                            </div>
                            <div className="hidden sm:block text-right px-4">
                                <p className="text-[10px] text-slate-400">Miembro desde</p>
                                <p className="text-[11px] font-medium text-slate-600">{new Date(user.created_at).toLocaleDateString()}</p>
                            </div>
                            <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-semibold ${roleColors[user.role] || roleColors['viewer']} uppercase`}>
                                {PRODUCT_ROLE_LABELS[user.role]}
                                {!isRoteroEnabledRole(user.role) && ' · no habilitado'}
                            </span>
                            {isAdmin && (
                                <button
                                    onClick={() => handleChangeRole(user.user_id)}
                                    className="text-slate-300 p-2 hover:bg-slate-100 rounded-lg hover:text-primary opacity-0 group-hover:opacity-100 transition-all">
                                    <MoreHorizontal size={16} />
                                </button>
                            )}
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
};

export default SecurityUsersPage;
