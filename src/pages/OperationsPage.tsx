import React, { useState, useEffect } from 'react';
import { Filter, Plus, FileText, ShieldCheck, MapPin, Clock, Share2, Link as LinkIcon, Loader2, Copy, Check } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { Badge } from '@/components/Badge';
import { useAuthStore } from '@/store/authStore';
import { listOperations, createOperation } from '@/services/operations.service';
import type { Operation } from '@/types/operations';
import { MOCK_TIMELINE } from '@/mocks/timeline.mock';
import { supabase } from '@/lib/supabase';

const getTimelineDotStyle = (step: typeof MOCK_TIMELINE[0]) => {
    if (step.done) return 'bg-emerald-500 ring-4 ring-emerald-500/20';
    if (step.current) return 'bg-primary ring-4 ring-primary/20 animate-pulse-dot';
    return 'bg-slate-200 ring-4 ring-slate-100';
};

const OperationsPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [operations, setOperations] = useState<Operation[]>([]);
    const [loading, setLoading] = useState(true);
    const [selected, setSelected] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [showNewModal, setShowNewModal] = useState(false);

    // Tracking Link Generation State
    const [isGeneratingLink, setIsGeneratingLink] = useState(false);
    const [generatedLink, setGeneratedLink] = useState<string | null>(null);
    const [copiedLink, setCopiedLink] = useState(false);

    // Form state basic
    const [newOpRef, setNewOpRef] = useState('');
    const [newOpClient, setNewOpClient] = useState('');

    const activeOp = operations.find((o) => o.id === selected);

    const fetchOps = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await listOperations(activeTenant);
            setOperations(data);
            if (!selected && data.length > 0) {
                setSelected(data[0].id);
            }
        } catch (err) {
            console.error('Failed to load operations:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchOps();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !newOpRef) return;
        setIsCreating(true);
        try {
            await createOperation(activeTenant, {
                reference_code: newOpRef,
                client_display_name: newOpClient,
                status: 'planned'
            });
            setShowNewModal(false);
            setNewOpRef('');
            setNewOpClient('');
            await fetchOps();
        } catch (err) {
            console.error(err);
        } finally {
            setIsCreating(false);
        }
    };

    const handleGenerateLink = async () => {
        if (!activeTenant || !activeOp?.db_id) return;
        setIsGeneratingLink(true);
        try {
            // Generamos link público por defecto
            const { data, error } = await supabase.rpc('rpc_create_tracking_token', {
                p_tenant_id: activeTenant,
                p_operation_id: activeOp.db_id,
                p_scope: 'public:read'
            });

            if (error) throw error;
            if (data?.error) throw new Error(data.error);

            // Armar URL compatible con frontend local o remoto
            const origin = typeof window !== 'undefined' ? window.location.origin : '';
            setGeneratedLink(`${origin}/t/${data.token}`);
        } catch (err) {
            console.error('Error generating link:', err);
        } finally {
            setIsGeneratingLink(false);
        }
    };

    const handleCopy = () => {
        if (!generatedLink) return;
        navigator.clipboard.writeText(generatedLink);
        setCopiedLink(true);
        setTimeout(() => setCopiedLink(false), 2000);
    };

    return (
        <div className="space-y-5 relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Operaciones</h1>
                    <p className="text-sm text-slate-400 mt-0.5">{operations.length} operaciones activas</p>
                </div>
                <div className="flex items-center gap-2">
                    <button className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Filter size={14} /> Filtros
                    </button>
                    {!isViewer && (
                        <button
                            onClick={() => setShowNewModal(true)}
                            className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all"
                        >
                            <Plus size={14} /> Nueva P.O.
                        </button>
                    )}
                </div>
            </div>

            {/* Split view */}
            <div className="grid grid-cols-1 lg:grid-cols-5 gap-5">
                {/* Left – Operations list */}
                <div className="lg:col-span-3 bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden">
                    <div className="overflow-x-auto min-h-[300px]">
                        {loading ? (
                            <div className="flex items-center justify-center h-48">
                                <Loader2 className="animate-spin text-slate-400" size={24} />
                            </div>
                        ) : (
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60">
                                        <th className="px-5 py-3">Referencia</th>
                                        <th className="px-5 py-3">Cliente</th>
                                        <th className="px-5 py-3">Tipo</th>
                                        <th className="px-5 py-3">Estado</th>
                                        <th className="px-5 py-3">Ruta</th>
                                        <th className="px-5 py-3">Resp.</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-tech-border/40">
                                    {operations.map((op) => (
                                        <tr
                                            key={op.id}
                                            onClick={() => {
                                                setSelected(op.id);
                                                setGeneratedLink(null);
                                            }}
                                            className={`cursor-pointer transition-all duration-200 ${selected === op.id
                                                ? 'bg-primary-50/60 border-l-3 border-l-primary'
                                                : 'hover:bg-slate-50/80'
                                                }`}
                                        >
                                            <td className="px-5 py-3.5 font-semibold text-primary text-[13px]">{op.id}</td>
                                            <td className="px-5 py-3.5 text-slate-600 text-[13px]">{op.client}</td>
                                            <td className="px-5 py-3.5 text-slate-400 text-xs">{op.type}</td>
                                            <td className="px-5 py-3.5"><Badge variant={op.variant}>{op.status}</Badge></td>
                                            <td className="px-5 py-3.5 text-slate-400 text-xs font-mono">{op.route}</td>
                                            <td className="px-5 py-3.5 text-slate-500 text-xs">{op.owner}</td>
                                        </tr>
                                    ))}
                                    {operations.length === 0 && (
                                        <tr>
                                            <td colSpan={6} className="px-5 py-8 text-center text-slate-400">
                                                No hay operaciones registradas en este tenant.
                                            </td>
                                        </tr>
                                    )}
                                </tbody>
                            </table>
                        )}
                    </div>
                </div>

                {/* Right – Detail panel */}
                <div className="lg:col-span-2">
                    <AnimatePresence mode="wait">
                        {activeOp && (
                            <motion.div
                                key={activeOp.id}
                                initial={{ opacity: 0, x: 20 }}
                                animate={{ opacity: 1, x: 0 }}
                                exit={{ opacity: 0, x: -20 }}
                                transition={{ duration: 0.2 }}
                                className="bg-surface-card rounded-2xl border border-tech-border/60 p-6 space-y-6"
                            >
                                {/* Header */}
                                <div>
                                    <div className="flex items-center gap-3 mb-3">
                                        <h3 className="text-lg font-bold text-slate-800">{activeOp.id}</h3>
                                        <Badge variant={activeOp.variant}>{activeOp.status}</Badge>
                                    </div>
                                    <p className="text-sm text-slate-500">{activeOp.client}</p>
                                    <div className="flex items-center gap-2 mt-2">
                                        <MapPin size={13} className="text-slate-300" />
                                        <span className="text-xs text-slate-400 font-mono">{activeOp.route}</span>
                                    </div>
                                </div>

                                {/* Tracking Link Section */}
                                {!isViewer && (
                                    <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl">
                                        <div className="flex items-center justify-between mb-2">
                                            <h4 className="text-sm font-semibold text-slate-700 flex items-center gap-2">
                                                <Share2 size={16} className="text-slate-400" />
                                                Compartir Tracking Libre
                                            </h4>
                                        </div>
                                        {generatedLink ? (
                                            <div className="flex items-center gap-2 mt-3 p-2 bg-white rounded border border-slate-200">
                                                <div className="truncate flex-1 text-xs text-slate-600 font-mono pl-1">
                                                    {generatedLink}
                                                </div>
                                                <button
                                                    onClick={handleCopy}
                                                    className="p-1.5 shrink-0 bg-slate-100 hover:bg-slate-200 rounded text-slate-600 transition-colors"
                                                    title="Copiar al portapapeles"
                                                >
                                                    {copiedLink ? <Check size={14} className="text-emerald-600" /> : <Copy size={14} />}
                                                </button>
                                            </div>
                                        ) : (
                                            <button
                                                onClick={handleGenerateLink}
                                                disabled={isGeneratingLink}
                                                className="w-full mt-2 py-2 flex items-center justify-center gap-2 bg-white border border-slate-200 hover:border-blue-300 hover:text-blue-600 text-slate-600 text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
                                            >
                                                {isGeneratingLink ? <Loader2 size={16} className="animate-spin" /> : <LinkIcon size={16} />}
                                                Generar Link Público
                                            </button>
                                        )}
                                    </div>
                                )}

                                {/* Quick info */}
                                <div className="grid grid-cols-2 gap-3">
                                    <div className="p-3.5 bg-surface rounded-xl border border-tech-border/40">
                                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Tipo carga</p>
                                        <p className="text-sm font-bold text-slate-700 mt-1">{activeOp.type}</p>
                                    </div>
                                    <div className="p-3.5 bg-surface rounded-xl border border-tech-border/40">
                                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Responsable</p>
                                        <p className="text-sm font-bold text-slate-700 mt-1">{activeOp.owner}</p>
                                    </div>
                                </div>

                                {/* Timeline */}
                                <div>
                                    <h4 className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-4">Línea de tiempo</h4>
                                    <div className="space-y-0">
                                        {MOCK_TIMELINE.map((step, idx) => (
                                            <div key={idx} className="flex gap-3.5">
                                                {/* Vertical line + dot */}
                                                <div className="flex flex-col items-center">
                                                    <div className={`w-3 h-3 rounded-full shrink-0 ${getTimelineDotStyle(step)}`} />
                                                    {idx < MOCK_TIMELINE.length - 1 && (
                                                        <div className={`w-px flex-1 my-1 ${step.done ? 'bg-emerald-300' : 'bg-slate-200'}`} />
                                                    )}
                                                </div>
                                                {/* Content */}
                                                <div className="pb-5 min-w-0">
                                                    <div className="flex items-center gap-2">
                                                        <p className={`text-[13px] font-semibold ${step.current ? 'text-primary' : step.done ? 'text-slate-700' : 'text-slate-400'}`}>
                                                            {step.event}
                                                        </p>
                                                    </div>
                                                    <p className="text-[11px] text-slate-400 mt-0.5">{step.desc}</p>
                                                    <p className="text-[10px] text-slate-300 mt-1 flex items-center gap-1">
                                                        <Clock size={10} /> {step.time}
                                                    </p>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>

                                {/* Actions */}
                                <div className="flex gap-2">
                                    <button className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-primary text-white rounded-xl text-xs font-semibold hover:bg-primary-light transition-colors shadow-sm">
                                        <FileText size={14} /> Ver Docs
                                    </button>
                                    <button className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-emerald-50 text-emerald-700 rounded-xl text-xs font-semibold hover:bg-emerald-100 transition-colors">
                                        <ShieldCheck size={14} /> Validar SAT
                                    </button>
                                </div>
                            </motion.div>
                        )}
                    </AnimatePresence>
                </div>
            </div>

            {/* Simple Create Modal Overlay */}
            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-md shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Nueva Operación</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Referencia (Ej. OP-9001)</label>
                                <input
                                    required
                                    autoFocus
                                    type="text"
                                    value={newOpRef}
                                    onChange={(e) => setNewOpRef(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                    placeholder="Referencia única"
                                />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Cliente Principal</label>
                                <input
                                    type="text"
                                    value={newOpClient}
                                    onChange={(e) => setNewOpClient(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 focus:border-primary transition-all"
                                    placeholder="Nombre del cliente (opcional)"
                                />
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button
                                    type="button"
                                    onClick={() => setShowNewModal(false)}
                                    className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700"
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={isCreating}
                                    className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg shadow-sm shadow-primary/20 disabled:opacity-50 flex items-center gap-2"
                                >
                                    {isCreating && <Loader2 size={14} className="animate-spin" />}
                                    Crear Operación
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}
        </div>
    );
};

export default OperationsPage;
