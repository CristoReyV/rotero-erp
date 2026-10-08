import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
    X, Building2, User, Phone, Mail, FileText, Send,
    Calendar, Tag, Clock, Loader2, AlertCircle
} from 'lucide-react';
import {
    getDealDetail, getDealActivities, addDealActivity, moveDeal,
    addDealNote, listDealNotes, listDealChecklist, toggleChecklistItem
} from '@/services/commercial.service';
import type { DealDetail, DealActivity, DealStage, DealNote, DealChecklistItem } from '@/types/commercial';
import { useAuthStore } from '@/store/authStore';
import {
    CheckSquare, MessageSquare, ClipboardList, CheckCircle
} from 'lucide-react';


interface DealDetailDrawerProps {
    dealId: string | null;
    isOpen: boolean;
    onClose: () => void;
    onChanged: () => Promise<void> | void;
}

const STAGES: Record<DealStage, string> = {
    'lead': 'Prospecto',
    'qualified': 'Cotización',
    'proposal': 'Negociación',
    'won': 'Cierre',
    'lost': 'Perdido',
};

const STAGE_COLORS: Record<string, string> = {
    'lead': 'bg-blue-50 text-blue-700 border-blue-200',
    'qualified': 'bg-amber-50 text-amber-700 border-amber-200',
    'proposal': 'bg-purple-50 text-purple-700 border-purple-200',
    'won': 'bg-emerald-50 text-emerald-700 border-emerald-200',
    'lost': 'bg-rose-50 text-rose-700 border-rose-200',
};

export const DealDetailDrawer: React.FC<DealDetailDrawerProps> = ({
    dealId, isOpen, onClose, onChanged
}) => {
    const activeTenant = useAuthStore(s => s.activeTenant);

    const [deal, setDeal] = useState<DealDetail | null>(null);
    const [activities, setActivities] = useState<DealActivity[]>([]);
    const [loading, setLoading] = useState(false);
    const [stageBusy, setStageBusy] = useState(false);
    const [error, setError] = useState('');

    // CRM Advancement State
    const [activeTab, setActiveTab] = useState<'notes' | 'checklist'>('notes');
    const [crmNotes, setCrmNotes] = useState<DealNote[]>([]);
    const [checklist, setChecklist] = useState<DealChecklistItem[]>([]);

    // Auth role check
    const userRole = useAuthStore(s => s.getRole());
    const isViewer = userRole === 'viewer';

    // Notes
    const [noteBody, setNoteBody] = useState('');
    const [isSubmittingNote, setIsSubmittingNote] = useState(false);

    // Initial fetch
    useEffect(() => {
        if (!isOpen || !dealId || !activeTenant) return;

        let isMounted = true;
        const load = async () => {
            setLoading(true);
            setError('');
            try {
                const [dData, aData, nData, cData] = await Promise.all([
                    getDealDetail(activeTenant, dealId),
                    getDealActivities(activeTenant, dealId),
                    listDealNotes(dealId),
                    listDealChecklist(dealId)
                ]);
                if (isMounted) {
                    setDeal(dData);
                    setActivities(aData);
                    setCrmNotes(nData);
                    setChecklist(cData);
                }
            } catch (err: any) {
                if (isMounted) setError(err.message || 'No fue posible cargar la oportunidad.');
            } finally {
                if (isMounted) setLoading(false);
            }
        };
        load();


        return () => { isMounted = false; };
    }, [dealId, isOpen, activeTenant]);

    const handleAddNote = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!noteBody.trim() || !dealId || !activeTenant) return;

        setIsSubmittingNote(true);
        try {
            await addDealNote(dealId, noteBody);
            setNoteBody('');
            // refresh
            const nData = await listDealNotes(dealId);
            setCrmNotes(nData);
            onChanged();
        } catch (err: any) {
            setError(err.message || 'No fue posible agregar la nota.');
        } finally {
            setIsSubmittingNote(false);
        }
    };


    const handleStageChange = async (e: React.ChangeEvent<HTMLSelectElement>) => {
        const newStage = e.target.value as DealStage;
        if (!dealId || !activeTenant || !deal || deal.stage === newStage) return;

        setStageBusy(true);
        setError('');
        try {
            await moveDeal(dealId, newStage);
        } catch (err: any) {
            setError(err.message || 'No fue posible cambiar la etapa.');
            setStageBusy(false);
            return;
        }

        setDeal((current) => current ? { ...current, stage: newStage } : current);
        try {
            const [dData, aData, cData] = await Promise.all([
                getDealDetail(activeTenant, dealId),
                getDealActivities(activeTenant, dealId),
                listDealChecklist(dealId)
            ]);
            setDeal(dData);
            setActivities(aData);
            setChecklist(cData);
            await onChanged();
        } catch (err: any) {
            setError(err.message || 'La etapa se guardó, pero no fue posible actualizar todos los datos relacionados.');
        } finally {
            setStageBusy(false);
        }
    };

    const handleToggleCheckItem = async (itemId: string, current: boolean) => {
        if (isViewer || !dealId) return;
        try {
            await toggleChecklistItem(itemId, !current);
            // optimistic refresh
            setChecklist(prev => prev.map(item => item.id === itemId ? { ...item, is_done: !current } : item));
            onChanged();
        } catch (err: any) {
            setError(err.message || 'No fue posible actualizar la lista de avance.');
        }
    };


    const formatCurrency = (val: number, cur: string) => {
        return new Intl.NumberFormat('es-MX', { style: 'currency', currency: cur }).format(val);
    };

    return (
        <AnimatePresence>
            {isOpen && dealId && (
                <div className="fixed inset-0 z-50 flex w-full items-center justify-center bg-slate-900/40 font-sans backdrop-blur-sm">
                    {/* Backdrop */}
                    <motion.div
                        initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                        className="fixed inset-0" onClick={onClose}
                    />

                    <motion.div
                        initial={{ opacity: 0, x: 100 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 100 }}
                        transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="deal-detail-title"
                        className="absolute right-0 flex h-dvh w-full min-w-0 max-w-lg flex-col overflow-hidden bg-surface-card shadow-2xl"
                    >
                        {loading && !deal ? (
                            <div className="flex-1 flex flex-col items-center justify-center text-slate-400">
                                <Loader2 className="animate-spin mb-4" size={32} />
                                <p className="text-sm font-semibold">Cargando detalles...</p>
                            </div>
                        ) : error && !deal ? (
                            <div className="flex-1 flex flex-col items-center justify-center text-red-400 p-6 text-center">
                                <AlertCircle className="mb-4" size={32} />
                                <p className="text-sm font-semibold">{error}</p>
                                <button onClick={onClose} className="mt-4 px-4 py-2 bg-slate-100 text-slate-600 rounded-lg text-xs font-bold hover:bg-slate-200">Cerrar</button>
                            </div>
                        ) : deal && (
                            <>
                                {/* Global Header */}
                                <div className="z-10 flex shrink-0 items-start justify-between gap-3 border-b bg-surface-card px-4 py-3 pt-[max(0.75rem,env(safe-area-inset-top))] sm:px-6 sm:py-4">
                                    <div className="min-w-0 flex-1 sm:pr-4">
                                        <div className="flex items-center gap-2 mb-1.5">
                                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded border uppercase tracking-wider ${STAGE_COLORS[deal.stage] || STAGE_COLORS['lead']}`}>
                                                {STAGES[deal.stage]}
                                            </span>
                                            {deal.priority === 'high' && <span className="text-[10px] font-bold px-2 py-0.5 rounded border uppercase tracking-wider bg-red-50 text-red-700 border-red-200">Alta Prioridad</span>}
                                        </div>
                                        <h2 id="deal-detail-title" className="break-words text-lg font-bold leading-tight text-slate-800 sm:text-xl">{deal.title}</h2>
                                        <p className="text-sm text-slate-500 mt-1 flex items-center gap-1.5">
                                            <Building2 size={13} className="text-slate-400" />
                                            {deal.company || 'Sin Empresa Definida'}
                                        </p>
                                    </div>
                                    <button onClick={onClose} aria-label="Cerrar detalle del deal" className="-mr-2 flex h-11 w-11 shrink-0 items-center justify-center rounded-lg bg-surface text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-600">
                                        <X size={18} />
                                    </button>
                                </div>

                                <div className="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain bg-surface">
                                    {/* Action Bar / Status Changer */}
                                    <div className="flex min-w-0 items-center justify-between gap-3 border-b bg-surface-card px-4 py-3 shadow-sm sm:px-6">
                                            <span className="text-xs font-bold uppercase tracking-wider text-slate-500">Cambiar etapa</span>
                                            <select
                                                value={deal.stage}
                                                onChange={handleStageChange}
                                                disabled={stageBusy}
                                                className="min-w-0 max-w-[60%] rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm font-bold text-slate-700 focus:outline-none focus:ring-2 focus:ring-primary/20 disabled:opacity-60"
                                        >
                                            <option value="lead">Prospecto</option>
                                            <option value="qualified">Cotización</option>
                                            <option value="proposal">Negociación</option>
                                            <option value="won">Cierre</option>
                                            <option value="lost">Perdido</option>
                                        </select>
                                    </div>

                                    {/* Scrollable Content */}
                                    <div className="space-y-4 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:space-y-6 sm:p-6">

                                        {/* Meta Section */}
                                        <div className="grid grid-cols-1 gap-3 min-[360px]:grid-cols-2 sm:gap-4">
                                            <div className="rounded-xl border border-slate-200 bg-surface-card p-4 shadow-sm">
                                                <p className="mb-2 text-[10px] font-bold uppercase tracking-wider text-slate-400">Valor estimado</p>
                                                <p className="text-lg font-bold text-emerald-600">{formatCurrency(deal.value || 0, deal.currency)}</p>
                                            </div>
                                            <div className="flex flex-col justify-center rounded-xl border border-slate-200 bg-surface-card p-4 shadow-sm">
                                                <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1">
                                                    <User size={12} /> Responsable
                                                </p>
                                                <p className="text-sm font-bold text-slate-700">{deal.owner_name || 'Sin asignar'}</p>
                                            </div>
                                        </div>

                                        {/* Contact Section */}
                                        <div className="overflow-hidden rounded-xl border border-slate-200 bg-surface-card shadow-sm">
                                            <div className="bg-slate-50 px-4 py-2.5 border-b border-slate-200">
                                                <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider">Contacto</h3>
                                            </div>
                                            <div className="p-4 space-y-3">
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                                                        <User size={14} />
                                                    </div>
                                                    <p className="text-sm font-semibold text-slate-700">{deal.contact_name || 'N/A'}</p>
                                                </div>
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-slate-50 text-slate-400 flex items-center justify-center shrink-0">
                                                        <Mail size={14} />
                                                    </div>
                                                    <p className="text-sm text-slate-600">{deal.contact_email || 'Sin correo'}</p>
                                                </div>
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-slate-50 text-slate-400 flex items-center justify-center shrink-0">
                                                        <Phone size={14} />
                                                    </div>
                                                    <p className="text-sm text-slate-600">{deal.contact_phone || 'Sin teléfono'}</p>
                                                </div>
                                            </div>
                                        </div>

                                        {/* Original Notes */}
                                        {deal.notes && (
                                            <div>
                                                <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Notas Originales</h3>
                                                <div className="break-words rounded-xl border border-slate-200 bg-surface-card p-4 text-sm text-slate-600 shadow-sm">
                                                    {deal.notes}
                                                </div>
                                            </div>
                                        )}

                                        <hr className="border-slate-200" />

                                        {/* Tabs Control */}
                                        <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-xl">
                                            <button
                                                onClick={() => setActiveTab('notes')}
                                                className={`flex-1 py-2 px-3 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-2 ${activeTab === 'notes' ? 'bg-white text-slate-800 shadow-sm' : 'text-slate-500 hover:text-slate-700'}`}
                                            >
                                                <MessageSquare size={14} />
                                                Notas
                                            </button>
                                            <button
                                                onClick={() => setActiveTab('checklist')}
                                                className={`flex-1 py-2 px-3 rounded-lg text-xs font-bold transition-all flex items-center justify-center gap-2 ${activeTab === 'checklist' ? 'bg-white text-slate-800 shadow-sm' : 'text-slate-500 hover:text-slate-700'}`}
                                            >
                                                <CheckSquare size={14} />
                                                Checklist
                                                {checklist.filter(i => i.is_done).length}/{checklist.length > 0 ? checklist.length : '0'}
                                            </button>
                                        </div>

                                        {activeTab === 'notes' ? (
                                            <div>
                                                <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-4 flex items-center gap-2">
                                                    <MessageSquare size={14} className="text-slate-400" /> Comentarios
                                                </h3>

                                                {/* Note Input */}
                                                {!isViewer && (
                                                    <form onSubmit={handleAddNote} className="mb-6 bg-white p-1 rounded-xl border border-slate-200 focus-within:border-primary/50 focus-within:ring-2 focus-within:ring-primary/10 transition-all shadow-sm">
                                                        <textarea
                                                            value={noteBody}
                                                            onChange={e => setNoteBody(e.target.value)}
                                                            placeholder="Agregar una nota sobre esta oportunidad..."
                                                            className="w-full text-sm p-3 bg-transparent resize-none focus:outline-none text-slate-700 min-h-[80px]"
                                                        />
                                                        <div className="flex justify-end p-2 border-t border-slate-100">
                                                            <button
                                                                type="submit"
                                                                disabled={isSubmittingNote || !noteBody.trim()}
                                                                className="px-4 py-1.5 bg-slate-800 hover:bg-slate-900 disabled:opacity-50 text-white rounded-lg text-xs font-bold flex items-center gap-2 transition-colors"
                                                            >
                                                                {isSubmittingNote ? <Loader2 size={12} className="animate-spin" /> : <Send size={12} />}
                                                                Postear
                                                            </button>
                                                        </div>
                                                    </form>
                                                )}

                                                {/* CRM Notes List */}
                                                <div className="space-y-4">
                                                    {crmNotes.length === 0 ? (
                                                        <div className="text-center py-8">
                                                            <div className="w-12 h-12 bg-slate-100 rounded-full flex items-center justify-center mx-auto mb-3 text-slate-400">
                                                                <MessageSquare size={20} />
                                                            </div>
                                                            <p className="text-sm text-slate-400 font-medium whitespace-pre-line">No hay notas registradas.{"\n"}Las notas ayudan al seguimiento comercial.</p>
                                                        </div>
                                                    ) : crmNotes.map(note => (
                                                        <div key={note.id} className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
                                                            <div className="flex items-center justify-between mb-2">
                                                                <span className="text-xs font-bold text-slate-700">{note.author_name}</span>
                                                                <span className="text-[10px] font-semibold text-slate-400 flex items-center gap-1">
                                                                    <Clock size={10} />
                                                                    {new Date(note.created_at).toLocaleDateString()} {new Date(note.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                                </span>
                                                            </div>
                                                            <p className="text-sm text-slate-600 break-words leading-relaxed">{note.note}</p>
                                                        </div>
                                                    ))}
                                                </div>
                                            </div>
                                        ) : (
                                            <div>
                                                <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-4 flex items-center gap-2">
                                                    <ClipboardList size={14} className="text-slate-400" /> Avance por Etapa
                                                </h3>

                                                <div className="space-y-6">
                                                    {/* We group checklist by stage or just show items for current stage? 
                                                        Request says "Items por etapa". Let's show current stage focused or all. 
                                                        Actually, showing all items ordered by stage is good.
                                                    */}
                                                    {['lead', 'qualified', 'proposal', 'won'].map(stageKey => {
                                                        const stageItems = checklist.filter(i => i.stage === stageKey);
                                                        if (stageItems.length === 0 && deal.stage !== stageKey) return null;

                                                        return (
                                                            <div key={stageKey} className={`rounded-xl border bg-surface-card transition-all ${deal.stage === stageKey ? 'border-primary/20 shadow-md ring-1 ring-primary/5' : 'border-slate-200'}`}>
                                                                <div className="px-4 py-2 border-b border-inherit flex items-center justify-between">
                                                                    <span className={`text-[10px] font-bold uppercase tracking-wider ${deal.stage === stageKey ? 'text-primary' : 'text-slate-400'}`}>
                                                                        {STAGES[stageKey as DealStage]}
                                                                    </span>
                                                                    {deal.stage === stageKey && <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-bold text-primary">Etapa actual</span>}
                                                                </div>
                                                                <div className="p-3 space-y-2.5">
                                                                    {stageItems.length === 0 ? (
                                                                        <p className="text-xs text-slate-400 italic px-1">Sin tareas definidas.</p>
                                                                    ) : stageItems.map(item => (
                                                                        <button
                                                                            key={item.id}
                                                                            type="button"
                                                                            disabled={isViewer || deal.stage !== stageKey}
                                                                            onClick={() => handleToggleCheckItem(item.id, item.is_done)}
                                                                            className={`w-full flex items-start gap-3 p-2 rounded-lg transition-all text-left ${item.is_done ? 'opacity-60 bg-slate-50' : 'hover:bg-slate-100'}`}
                                                                        >
                                                                            <div className={`mt-0.5 w-4 h-4 rounded border flex items-center justify-center shrink-0 transition-colors ${item.is_done ? 'bg-primary border-primary text-white' : 'bg-white border-slate-300'}`}>
                                                                                {item.is_done && <CheckCircle size={10} />}
                                                                            </div>
                                                                            <span className={`text-sm ${item.is_done ? 'line-through text-slate-400' : 'text-slate-700 font-medium'}`}>
                                                                                {item.label}
                                                                            </span>
                                                                        </button>
                                                                    ))}
                                                                </div>
                                                            </div>
                                                        );
                                                    })}
                                                </div>
                                            </div>
                                        )}

                                    </div>
                                </div>

                            </>
                        )}
                    </motion.div>
                </div>
            )}
        </AnimatePresence>
    );
};
