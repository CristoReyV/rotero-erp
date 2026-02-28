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
    onChanged: () => void; // call when state changes or need to refresh parent
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
                if (isMounted) setError(err.message || 'Error loading deal');
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
            setError(err.message || 'Error adding note');
        } finally {
            setIsSubmittingNote(false);
        }
    };


    const handleStageChange = async (e: React.ChangeEvent<HTMLSelectElement>) => {
        const newStage = e.target.value as DealStage;
        if (!dealId || !activeTenant || !deal || deal.stage === newStage) return;

        try {
            await moveDeal(dealId, newStage);
            // optimistic 
            setDeal({ ...deal, stage: newStage });

            // refresh all
            const [aData, cData] = await Promise.all([
                getDealActivities(activeTenant, dealId),
                listDealChecklist(dealId)
            ]);
            setActivities(aData);
            setChecklist(cData);
            onChanged();
        } catch (err: any) {
            setError(err.message || 'Error changing stage');
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
            setError(err.message || 'Error updating checklist');
        }
    };


    const formatCurrency = (val: number, cur: string) => {
        return new Intl.NumberFormat('es-MX', { style: 'currency', currency: cur }).format(val);
    };

    return (
        <AnimatePresence>
            {isOpen && dealId && (
                <div className="fixed inset-y-0 right-0 z-50 flex items-center justify-center bg-slate-900/40 backdrop-blur-sm w-full font-sans">
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
                        className="bg-white h-full shadow-2xl overflow-hidden w-full max-w-lg absolute right-0 flex flex-col"
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
                                <div className="bg-white px-6 py-4 flex items-start justify-between z-10 border-b border-slate-100">
                                    <div className="flex-1 pr-4">
                                        <div className="flex items-center gap-2 mb-1.5">
                                            <span className={`text-[10px] font-bold px-2 py-0.5 rounded border uppercase tracking-wider ${STAGE_COLORS[deal.stage] || STAGE_COLORS['lead']}`}>
                                                {STAGES[deal.stage]}
                                            </span>
                                            {deal.priority === 'high' && <span className="text-[10px] font-bold px-2 py-0.5 rounded border uppercase tracking-wider bg-red-50 text-red-700 border-red-200">Alta Prioridad</span>}
                                        </div>
                                        <h2 className="text-xl font-bold text-slate-800 leading-tight">{deal.title}</h2>
                                        <p className="text-sm text-slate-500 mt-1 flex items-center gap-1.5">
                                            <Building2 size={13} className="text-slate-400" />
                                            {deal.company || 'Sin Empresa Definida'}
                                        </p>
                                    </div>
                                    <button onClick={onClose} className="p-2 -mr-2 text-slate-400 hover:text-slate-600 bg-slate-50 hover:bg-slate-100 rounded-lg transition-colors">
                                        <X size={18} />
                                    </button>
                                </div>

                                <div className="flex-1 overflow-y-auto bg-slate-50/50 flex flex-col">
                                    {/* Action Bar / Status Changer */}
                                    <div className="px-6 py-3 bg-white border-b border-slate-100 flex items-center justify-between shadow-sm shadow-slate-100/50">
                                        <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Mover Etapa</span>
                                        <select
                                            value={deal.stage}
                                            onChange={handleStageChange}
                                            className="text-sm font-bold bg-slate-50 border border-slate-200 text-slate-700 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-primary/20"
                                        >
                                            <option value="lead">Prospecto</option>
                                            <option value="qualified">Cotización</option>
                                            <option value="proposal">Negociación</option>
                                            <option value="won">Cierre</option>
                                            <option value="lost">Perdido</option>
                                        </select>
                                    </div>

                                    {/* Scrollable Content */}
                                    <div className="p-6 space-y-6">

                                        {/* Meta Section */}
                                        <div className="grid grid-cols-2 gap-4">
                                            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm">
                                                <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Valor Estimado</p>
                                                <p className="text-lg font-bold text-emerald-600">{formatCurrency(deal.value || 0, deal.currency)}</p>
                                            </div>
                                            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm flex flex-col justify-center">
                                                <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1">
                                                    <User size={12} /> Owner
                                                </p>
                                                <p className="text-sm font-bold text-slate-700">{deal.owner_name || 'Sin asignar'}</p>
                                            </div>
                                        </div>

                                        {/* Contact Section */}
                                        <div className="bg-white rounded-xl border border-slate-200 overflow-hidden shadow-sm">
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
                                                <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm text-sm text-slate-600 break-words">
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
                                                            <div key={stageKey} className={`rounded-xl border transition-all ${deal.stage === stageKey ? 'bg-white border-primary/20 shadow-md ring-1 ring-primary/5' : 'bg-slate-50 border-slate-200'}`}>
                                                                <div className="px-4 py-2 border-b border-inherit flex items-center justify-between">
                                                                    <span className={`text-[10px] font-bold uppercase tracking-wider ${deal.stage === stageKey ? 'text-primary' : 'text-slate-400'}`}>
                                                                        {STAGES[stageKey as DealStage]}
                                                                    </span>
                                                                    {deal.stage === stageKey && <span className="text-[10px] font-bold text-primary bg-primary/10 px-2 py-0.5 rounded-full">Etapa Actual</span>}
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
