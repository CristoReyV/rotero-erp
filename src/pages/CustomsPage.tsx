import React, { useState, useEffect } from 'react';
import { Plus, Download, Search, Gavel, ShieldCheck, FileText, Loader2, Info } from 'lucide-react';
import { Badge } from '@/components/Badge';
import { useAuthStore } from '@/store/authStore';
import { listPedimentos, createPedimento, listDescargoLines, addDescargoLine } from '@/services/customs.service';
import type { Pedimento, DescargoLine } from '@/types/customs';
import type { BadgeVariant } from '@/types/common';
import { AnimatePresence, motion } from 'motion/react';
import { downloadCSV } from '@/utils/export';

const getStatusVariant = (status: string): BadgeVariant => {
    if (status === 'Activo') return 'success';
    if (status === 'Auditado') return 'info';
    if (status === 'Cerrado') return 'default';
    return 'warning';
};

const CustomsPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [pedimentos, setPedimentos] = useState<Pedimento[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');

    const [showNewModal, setShowNewModal] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [newNumber, setNewNumber] = useState('');
    const [newRegimen, setNewRegimen] = useState('');
    const [newValue, setNewValue] = useState('');

    // Details/Descargos Drawer
    const [selectedPedimento, setSelectedPedimento] = useState<Pedimento | null>(null);
    const [descargoLines, setDescargoLines] = useState<DescargoLine[]>([]);
    const [loadingLines, setLoadingLines] = useState(false);

    // Add Descargo Line
    const [addLineSku, setAddLineSku] = useState('');
    const [addLineQty, setAddLineQty] = useState('');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await listPedimentos(activeTenant);
            setPedimentos(data);
        } catch (err) {
            console.error('Failed to load pedimentos:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !newNumber) return;
        setIsSubmitting(true);
        try {
            await createPedimento(activeTenant, {
                pedimento_number: newNumber,
                regimen: newRegimen || undefined,
                total_value: newValue ? Number(newValue) : undefined,
                status: 'draft'
            });
            setShowNewModal(false);
            setNewNumber('');
            setNewRegimen('');
            setNewValue('');
            await fetchData();
        } catch (err) {
            console.error('Failed to create pedimento:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleRowClick = async (pedimento: Pedimento) => {
        setSelectedPedimento(pedimento);
        if (!pedimento.db_id) return;

        setLoadingLines(true);
        try {
            const lines = await listDescargoLines(pedimento.db_id);
            setDescargoLines(lines);
        } catch (err) {
            console.error('Failed to load lines:', err);
        } finally {
            setLoadingLines(false);
        }
    };

    const handleAddLine = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!selectedPedimento?.db_id || !addLineSku || !addLineQty) return;
        setIsSubmitting(true);
        try {
            await addDescargoLine(selectedPedimento.db_id, {
                sku: addLineSku,
                qty: Number(addLineQty)
            });
            setAddLineSku('');
            setAddLineQty('');

            // Refetch lines
            const lines = await listDescargoLines(selectedPedimento.db_id);
            setDescargoLines(lines);
        } catch (err) {
            console.error('Failed to add descargo line', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const displayPedimentos = pedimentos.filter(p =>
        (p.id || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
        (p.material || '').toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="space-y-6 relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Aduanas & Anexo 24</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Control de pedimentos y descargas de materiales</p>
                </div>
                <div className="flex items-center gap-2">
                    <button onClick={() => downloadCSV(pedimentos, 'pedimentos_export')} className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Download size={14} /> Exportar
                    </button>
                    {!isViewer && (
                        <button
                            onClick={() => setShowNewModal(true)}
                            className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all"
                        >
                            <Plus size={14} /> Nuevo Pedimento
                        </button>
                    )}
                </div>
            </div>

            {/* Quick KPIs */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-primary-50 rounded-xl">
                        <Gavel size={22} className="text-primary" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Pedimentos</p>
                        <p className="text-xl font-bold text-slate-800">{pedimentos.length}</p>
                    </div>
                </div>
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-emerald-50 rounded-xl">
                        <ShieldCheck size={22} className="text-emerald-600" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Auditados</p>
                        <p className="text-xl font-bold text-emerald-600">{pedimentos.filter(p => p.status === 'Auditado').length}</p>
                    </div>
                </div>
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-blue-50 rounded-xl">
                        <FileText size={22} className="text-blue-600" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Balance Total</p>
                        <p className="text-xl font-bold text-slate-800">{pedimentos.reduce((s, p) => s + p.balance, 0).toLocaleString()}</p>
                    </div>
                </div>
            </div>

            {/* Search */}
            <div className="relative max-w-md">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                <input
                    type="text"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    placeholder="Buscar pedimento o material..."
                    className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                />
            </div>

            {/* Table */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="overflow-x-auto min-h-[300px]">
                    {loading ? (
                        <div className="flex items-center justify-center p-10"><Loader2 className="animate-spin text-slate-400" /></div>
                    ) : (
                        <table className="w-full text-left text-sm">
                            <thead>
                                <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60 bg-surface/50">
                                    <th className="px-5 py-3">No. Pedimento</th>
                                    <th className="px-5 py-3">Fecha</th>
                                    <th className="px-5 py-3">Material</th>
                                    <th className="px-5 py-3 text-right">Balance</th>
                                    <th className="px-5 py-3">Estado</th>
                                    <th className="px-5 py-3">Descarga</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border/40">
                                {displayPedimentos.map((ped, i) => (
                                    <tr
                                        key={i}
                                        onClick={() => handleRowClick(ped)}
                                        className="hover:bg-primary-50/30 transition-colors cursor-pointer group"
                                    >
                                        <td className="px-5 py-3.5 font-semibold text-primary text-[13px] font-mono">{ped.id}</td>
                                        <td className="px-5 py-3.5 text-slate-400 text-xs">{ped.date}</td>
                                        <td className="px-5 py-3.5 text-slate-600 text-[13px]">{ped.material}</td>
                                        <td className="px-5 py-3.5 text-right font-bold text-slate-700 text-[13px]">{ped.balance.toLocaleString()}</td>
                                        <td className="px-5 py-3.5"><Badge variant={getStatusVariant(ped.status)}>{ped.status}</Badge></td>
                                        <td className="px-5 py-3.5">
                                            <span className={`text-xs font-mono px-2 py-0.5 rounded-md ${ped.discharge === 'Auto' ? 'bg-emerald-50 text-emerald-700' : ped.discharge === 'Manual' ? 'bg-amber-50 text-amber-700' : 'bg-slate-50 text-slate-500'}`}>
                                                {ped.discharge}
                                            </span>
                                        </td>
                                    </tr>
                                ))}
                                {displayPedimentos.length === 0 && (
                                    <tr>
                                        <td colSpan={6} className="px-5 py-8 text-center text-slate-400">
                                            No hay pedimentos encontrados.
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>

            {/* Modal: New Pedimento */}
            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-sm shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Registrar Pedimento</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Nº de pedimento *</label>
                                <input
                                    required autoFocus
                                    type="text" value={newNumber} onChange={(e) => setNewNumber(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 font-mono"
                                    placeholder="23-50-3921000"
                                />
                                <p className="text-[10px] text-slate-400 mt-1">Debe incluir aduana inicial y año u omitir en test, min 10 chars.</p>
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Régimen</label>
                                <input
                                    type="text" value={newRegimen} onChange={(e) => setNewRegimen(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="Ej. IMMEX"
                                />
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Valor Agregado/Total</label>
                                <input
                                    type="number" min="0" step="any"
                                    value={newValue} onChange={(e) => setNewValue(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="0.00"
                                />
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button type="button" onClick={() => setShowNewModal(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} Crear
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Modal: Descargo Details */}
            {selectedPedimento && (
                <div className="fixed inset-y-0 right-0 z-50 flex items-center justify-center bg-slate-900/20 backdrop-blur-sm p-4 w-full">
                    <div className="flex-1 h-full w-full" onClick={() => setSelectedPedimento(null)}></div>
                    <motion.div
                        initial={{ opacity: 0, x: 100 }}
                        animate={{ opacity: 1, x: 0 }}
                        className="bg-white h-full shadow-2xl overflow-y-auto w-full max-w-md absolute right-0"
                    >
                        <div className="sticky top-0 bg-white/90 backdrop-blur-md px-6 py-4 border-b border-slate-100 flex items-center justify-between z-10">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800 font-mono">{selectedPedimento.id}</h2>
                                <p className="text-xs text-slate-500">Detalle de Descargas</p>
                            </div>
                            <button onClick={() => setSelectedPedimento(null)} className="text-slate-400 hover:text-slate-600 bg-slate-50 p-2 rounded-lg">✕</button>
                        </div>
                        <div className="p-6">
                            <div className="mb-6 bg-slate-50 p-4 rounded-xl border border-slate-100 flex flex-col gap-2">
                                <div className="flex justify-between items-center text-sm">
                                    <span className="text-slate-500">Estado</span>
                                    <Badge variant={getStatusVariant(selectedPedimento.status)}>{selectedPedimento.status}</Badge>
                                </div>
                                <div className="flex justify-between items-center text-sm">
                                    <span className="text-slate-500">Material</span>
                                    <span className="font-semibold text-slate-700">{selectedPedimento.material}</span>
                                </div>
                                <div className="flex justify-between items-center text-sm">
                                    <span className="text-slate-500">Valor Balance</span>
                                    <span className="font-bold text-slate-800">${selectedPedimento.balance.toLocaleString()}</span>
                                </div>
                            </div>

                            <h3 className="font-bold text-slate-800 flex items-center gap-2 mb-4">
                                <Info size={16} className="text-primary" /> Partidas de Descargo (Anexo 24)
                            </h3>

                            {loadingLines ? (
                                <div className="flex justify-center p-6"><Loader2 className="animate-spin text-slate-400" /></div>
                            ) : (
                                <div className="space-y-3 mb-6">
                                    {descargoLines.length === 0 ? (
                                        <p className="text-sm text-slate-500 italic bg-white border border-dashed border-slate-200 p-4 rounded-xl text-center">
                                            Ningún descargo registrado
                                        </p>
                                    ) : (
                                        descargoLines.map(line => (
                                            <div key={line.id} className="p-3 border border-slate-100 rounded-xl bg-slate-50/50 flex flex-col gap-1">
                                                <div className="flex justify-between font-semibold text-sm">
                                                    <span className="text-primary">{line.sku}</span>
                                                    <span>{line.qty} {line.unit}</span>
                                                </div>
                                                <div className="text-xs text-slate-400 flex justify-between">
                                                    <span>{new Date(line.created_at).toLocaleDateString()}</span>
                                                </div>
                                            </div>
                                        ))
                                    )}
                                </div>
                            )}

                            {!isViewer && (
                                <form onSubmit={handleAddLine} className="border-t border-slate-100 pt-6 space-y-4">
                                    <h4 className="text-xs font-bold text-slate-500 uppercase tracking-wider">Añadir Nueva Línea</h4>
                                    <div className="grid grid-cols-3 gap-2">
                                        <input
                                            required
                                            type="text" value={addLineSku} onChange={(e) => setAddLineSku(e.target.value)}
                                            placeholder="SKU"
                                            className="col-span-2 px-3 py-2 border border-slate-200 rounded-lg text-sm w-full focus:outline-none focus:ring-2 focus:ring-primary/20"
                                        />
                                        <input
                                            required min="1" step="any"
                                            type="number" value={addLineQty} onChange={(e) => setAddLineQty(e.target.value)}
                                            placeholder="Qty"
                                            className="px-3 py-2 border border-slate-200 rounded-lg text-sm w-full focus:outline-none focus:ring-2 focus:ring-primary/20"
                                        />
                                    </div>
                                    <button disabled={isSubmitting} type="submit" className="w-full py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold rounded-lg text-sm transition-colors flex items-center justify-center gap-2">
                                        {isSubmitting && <Loader2 size={14} className="animate-spin" />} Añadir a Descarga PEPS
                                    </button>
                                </form>
                            )}
                        </div>
                    </motion.div>
                </div>
            )}
        </div>
    );
};

export default CustomsPage;
