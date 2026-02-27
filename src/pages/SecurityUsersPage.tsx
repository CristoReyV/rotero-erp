import React, { useState, useEffect } from 'react';
import { Plus, Search, Users, Monitor, MoreHorizontal, Loader2, X } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getMembers, changeMemberRole, inviteMember } from '@/services/admin.service';
import type { Member } from '@/types/settings';

const roleColors: Record<string, string> = {
    'viewer': 'bg-slate-50 text-slate-600 ring-1 ring-slate-200',
    'operator': 'bg-blue-50 text-blue-700 ring-1 ring-blue-200/60',
    'admin': 'bg-red-50 text-red-700 ring-1 ring-red-200/60',
};

const SecurityUsersPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const userRole = useAuthStore((s) => s.getRole());
    const isAdmin = userRole === 'admin';
    const canInvite = userRole === 'admin' || userRole === 'operator';

    const [loading, setLoading] = useState(true);
    const [members, setMembers] = useState<Member[]>([]);

    // Modal states
    const [isInviteOpen, setIsInviteOpen] = useState(false);
    const [isInviting, setIsInviting] = useState(false);
    const [inviteEmail, setInviteEmail] = useState('');
    const [inviteRole, setInviteRole] = useState<'viewer' | 'operator' | 'admin'>('viewer');

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

    const handleOpenModal = () => {
        console.debug("Nuevo Usuario click", { role: userRole, openBefore: isInviteOpen, openAfter: true });
        setIsInviteOpen(true);
    };

    const handleCloseModal = () => {
        setIsInviteOpen(false);
        setInviteEmail('');
        setInviteRole('viewer');
    };

    const handleInviteSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !canInvite) return;
        if (!inviteEmail) return;

        setIsInviting(true);
        try {
            const res = await inviteMember(activeTenant, inviteEmail, inviteRole);
            alert(`Invitación creada. Token: ${res.token}`);
            handleCloseModal();
            fetchData();
        } catch (error: any) {
            alert('Error al invitar: ' + error.message);
        } finally {
            setIsInviting(false);
        }
    };

    const handleChangeRole = async (userId: string) => {
        if (!activeTenant || !isAdmin) return;
        const currentM = members.find(m => m.user_id === userId);
        if (!currentM) return;

        const roleStr = prompt(`Nuevo rol para ${currentM.name || currentM.email} (admin, operator, viewer):`, currentM.role);
        if (!roleStr || !['admin', 'operator', 'viewer'].includes(roleStr) || roleStr === currentM.role) {
            return;
        }

        try {
            await changeMemberRole(activeTenant, userId, roleStr as any);
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
                        <p className="text-xl font-bold text-emerald-600">{members.length}</p>
                    </div>
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
                <button
                    type="button"
                    onClick={handleOpenModal}
                    disabled={!canInvite || isInviting}
                    className={`flex items-center justify-center min-w-[140px] gap-2 px-4 py-2 rounded-xl text-xs font-semibold shadow-md transition-all ${!canInvite
                            ? 'bg-slate-100 text-slate-400 cursor-not-allowed opacity-50'
                            : 'gradient-accent text-white shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30'
                        }`}
                >
                    {isInviting ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />}
                    Nuevo Usuario
                </button>
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
                                {user.role}
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

            {/* Invite Modal */}
            {isInviteOpen && (
                <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm transition-all text-left">
                    <div className="bg-white rounded-2xl shadow-xl w-full max-w-md overflow-hidden animate-in zoom-in-95 duration-200">
                        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
                            <h3 className="font-bold text-slate-800">Citar Nuevo Usuario</h3>
                            <button
                                type="button"
                                onClick={handleCloseModal}
                                className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-50 transition-colors"
                            >
                                <X size={18} />
                            </button>
                        </div>
                        <form onSubmit={handleInviteSubmit} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-semibold text-slate-600 mb-1.5">
                                    Correo Electrónico
                                </label>
                                <input
                                    type="email"
                                    required
                                    value={inviteEmail}
                                    onChange={(e) => setInviteEmail(e.target.value)}
                                    placeholder="ejemplo@empresa.com"
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary/40 transition-all"
                                />
                            </div>
                            <div>
                                <label className="block text-xs font-semibold text-slate-600 mb-1.5">
                                    Rol en la Plataforma
                                </label>
                                <select
                                    value={inviteRole}
                                    onChange={(e) => setInviteRole(e.target.value as any)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary/40 transition-all text-slate-700"
                                >
                                    <option value="viewer">Viewer (Solo lectura)</option>
                                    <option value="operator">Operator (Operaciones)</option>
                                    {isAdmin && <option value="admin">Admin (Acceso total)</option>}
                                </select>
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button
                                    type="button"
                                    onClick={handleCloseModal}
                                    className="px-4 py-2 text-sm font-semibold text-slate-600 hover:text-slate-800 hover:bg-slate-50 rounded-xl transition-colors"
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={isInviting || !inviteEmail}
                                    className="flex items-center gap-2 px-6 py-2 bg-primary text-white text-sm font-semibold rounded-xl hover:bg-primary-600 transition-all shadow-md shadow-primary/20 disabled:opacity-50"
                                >
                                    {isInviting ? <Loader2 size={16} className="animate-spin" /> : null}
                                    Enviar Invitación
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </div>
    );
};

export default SecurityUsersPage;
