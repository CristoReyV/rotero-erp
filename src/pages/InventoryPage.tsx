import React, { useState, useEffect } from 'react';
import { Plus, TrendingUp, AlertTriangle, Search, Package, Loader2, ArrowRight, Download } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { listInventoryLots, getStockAlerts, createInventoryLot, updateInventoryLot } from '@/services/inventory.service';
import type { InventoryLot, StockAlert } from '@/types/inventory';
import { AnimatePresence, motion } from 'motion/react';
import { downloadCSV } from '@/utils/export';

const InventoryPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [lots, setLots] = useState<InventoryLot[]>([]);
    const [alerts, setAlerts] = useState<StockAlert[]>([]);
    const [loading, setLoading] = useState(true);

    const [searchTerm, setSearchTerm] = useState('');

    // Modals state
    const [showNewModal, setShowNewModal] = useState(false);
    const [showReserveModal, setShowReserveModal] = useState<string | null>(null);

    // Form states
    const [newSku, setNewSku] = useState('');
    const [newLotCode, setNewLotCode] = useState('');
    const [newDesc, setNewDesc] = useState('');
    const [newQty, setNewQty] = useState('');
    const [newCost, setNewCost] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Reserve state
    const [reserveQty, setReserveQty] = useState('');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const data = await listInventoryLots(activeTenant);
            const alertsData = await getStockAlerts(activeTenant);
            setLots(data);
            setAlerts(alertsData);
        } catch (err) {
            console.error('Failed to load inventory data:', err);
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
        if (!activeTenant || !newSku || !newQty) return;
        setIsSubmitting(true);
        try {
            await createInventoryLot(activeTenant, {
                sku: newSku,
                lot_code: newLotCode,
                description: newDesc,
                qty_on_hand: Number(newQty),
                unit_cost: newCost ? Number(newCost) : undefined
            });
            setShowNewModal(false);
            setNewSku('');
            setNewLotCode('');
            setNewDesc('');
            setNewQty('');
            setNewCost('');
            await fetchData();
        } catch (err) {
            console.error('Failed to create lot:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleReserve = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!showReserveModal || !reserveQty) return;
        setIsSubmitting(true);
        try {
            const lot = lots.find(l => l.id === showReserveModal);
            if (lot) {
                const newReserved = (lot.qty_reserved || 0) + Number(reserveQty);
                await updateInventoryLot(showReserveModal, {
                    qty_reserved: newReserved
                });
            }
            setShowReserveModal(null);
            setReserveQty('');
            await fetchData();
        } catch (err) {
            console.error('Failed to reserve stock:', err);
        } finally {
            setIsSubmitting(false);
        }
    };

    const displayLots = lots.filter(lot =>
        (lot.sku || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
        (lot.description || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
        (lot.lot || '').toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="space-y-6 relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Inventarios y Almacén</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Control PEPS con valorización en tiempo real</p>
                </div>
                <div className="flex items-center gap-2">
                    <button onClick={() => downloadCSV(lots, 'inventario_export')} className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Download size={14} /> Exportar
                    </button>
                    {!isViewer && (
                        <button
                            onClick={() => setShowNewModal(true)}
                            className="flex items-center gap-2 px-4 py-2 gradient-accent text-white rounded-xl text-xs font-semibold shadow-md shadow-accent-red/20 hover:shadow-lg hover:shadow-accent-red/30 transition-all"
                        >
                            <Plus size={14} /> Nuevo Lote
                        </button>
                    )}
                </div>
            </div>

            {/* Quick Stats */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-primary-50 rounded-xl">
                        <Package size={22} className="text-primary" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Lotes Activos</p>
                        <p className="text-xl font-bold text-slate-800">{lots.length}</p>
                    </div>
                </div>

                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-emerald-50 rounded-xl">
                        <TrendingUp size={22} className="text-emerald-600" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Rotación PEPS</p>
                        <p className="text-xl font-bold text-slate-800">4.2x</p>
                    </div>
                </div>

                <div className="bg-surface-card p-5 rounded-2xl border border-tech-border/60 flex items-center gap-4 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-3 bg-amber-50 rounded-xl">
                        <AlertTriangle size={22} className="text-amber-600" strokeWidth={1.8} />
                    </div>
                    <div>
                        <p className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">Alertas Stock</p>
                        <p className="text-xl font-bold text-amber-600">{alerts.length}</p>
                    </div>
                </div>
            </div>

            {/* Search */}
            <div className="relative max-w-md">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-300" size={15} />
                <input
                    type="text"
                    placeholder="Buscar por SKU, lote o descripción..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="w-full pl-9 pr-4 py-2.5 bg-surface-card border border-tech-border/60 rounded-xl text-sm placeholder:text-slate-300 focus:ring-2 focus:ring-primary/15 focus:border-primary/30 focus:outline-none transition-all"
                />
            </div>

            {/* Inventory Table */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="overflow-x-auto min-h-[300px]">
                    {loading ? (
                        <div className="flex items-center justify-center p-10"><Loader2 className="animate-spin text-slate-400" /></div>
                    ) : (
                        <table className="w-full text-left text-sm">
                            <thead>
                                <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60 bg-surface/50">
                                    <th className="px-5 py-3">PEPS / SKU</th>
                                    <th className="px-5 py-3">Descripción / Lote</th>
                                    <th className="px-5 py-3">Almacén</th>
                                    <th className="px-5 py-3 text-right">Estatus</th>
                                    <th className="px-5 py-3 text-right">Disponible</th>
                                    <th className="px-5 py-3 text-right">Reservado</th>
                                    <th className="px-5 py-3 text-right">Valorización</th>
                                    <th className="px-5 py-3">Ingreso</th>
                                    {!isViewer && <th className="px-5 py-3 text-right">Acción</th>}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border/40">
                                {displayLots.map((lot, i) => (
                                    <tr key={i} className="hover:bg-primary-50/30 transition-colors group">
                                        <td className="px-5 py-3.5">
                                            <div className="flex items-center gap-2">
                                                <div className="w-5 h-5 rounded-md bg-emerald-50 text-emerald-700 flex items-center justify-center text-[10px] font-bold border border-emerald-100">
                                                    {lot.pepsPosition}
                                                </div>
                                                <p className="font-semibold text-primary text-[13px]">{lot.sku}</p>
                                            </div>
                                        </td>
                                        <td className="px-5 py-3.5">
                                            <p className="text-slate-600 text-[13px] font-medium">{lot.description}</p>
                                            <p className="text-[10px] text-slate-400">Lote: {lot.lot}</p>
                                        </td>
                                        <td className="px-5 py-3.5">
                                            <span className="text-xs text-slate-400 font-mono bg-surface px-2 py-0.5 rounded-md">{lot.warehouse}</span>
                                        </td>
                                        <td className="px-5 py-3.5 text-right">
                                            <span className="text-xs text-slate-500 font-medium uppercase tracking-wider">{lot.status}</span>
                                        </td>
                                        <td className="px-5 py-3.5 text-right">
                                            <span className={`font-bold text-[13px] ${(lot.stock - (lot.qty_reserved || 0)) <= 10 ? 'text-amber-600' : 'text-slate-700'}`}>
                                                {(lot.stock - (lot.qty_reserved || 0)).toLocaleString()}
                                            </span>
                                            <span className="text-[10px] text-slate-400 ml-1">{lot.unit}</span>
                                        </td>
                                        <td className="px-5 py-3.5 text-right">
                                            <span className="font-bold text-[13px] text-slate-600">{(lot.qty_reserved || 0).toLocaleString()}</span>
                                        </td>
                                        <td className="px-5 py-3.5 text-right font-semibold text-slate-700 text-[13px]">${lot.value.toLocaleString()}</td>
                                        <td className="px-5 py-3.5 text-slate-400 text-xs">{lot.date}</td>
                                        {!isViewer && (
                                            <td className="px-5 py-3.5 text-right">
                                                <button
                                                    onClick={() => setShowReserveModal(lot.db_id || lot.id || null)}
                                                    className="w-full sm:w-auto px-3 py-1.5 bg-blue-50 hover:bg-blue-100 text-blue-700 rounded-lg text-xs font-semibold transition-colors flex items-center justify-center gap-1.5 opacity-0 group-hover:opacity-100 disabled:opacity-30 disabled:cursor-not-allowed"
                                                    disabled={lot.stock - (lot.qty_reserved || 0) <= 0 || lot.status === 'blocked'}
                                                >
                                                    Reservar <ArrowRight size={12} />
                                                </button>
                                            </td>
                                        )}
                                    </tr>
                                ))}
                                {displayLots.length === 0 && (
                                    <tr>
                                        <td colSpan={isViewer ? 8 : 9} className="px-5 py-8 text-center text-slate-400">
                                            No hay lotes de inventario encontrados.
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    )}
                </div>
            </div>

            {/* Stock Alerts */}
            {alerts.length > 0 && (
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 p-5">
                    <h3 className="font-bold text-slate-800 mb-4">⚠️ Alertas de Reabasto</h3>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                        {alerts.map((alert, i) => (
                            <div key={i} className={`flex items-center gap-3 p-3.5 rounded-xl border hover:scale-[1.01] transition-transform cursor-pointer ${alert.severity === 'danger' ? 'bg-red-50/60 border-red-200/40' : 'bg-amber-50/60 border-amber-200/40'}`}>
                                <div className={`w-2 h-2 rounded-full shrink-0 animate-pulse-dot ${alert.severity === 'danger' ? 'bg-red-500' : 'bg-amber-500'}`} />
                                <div className="min-w-0">
                                    <p className={`text-xs font-bold ${alert.severity === 'danger' ? 'text-red-800' : 'text-amber-800'}`}>{alert.sku} — {alert.description}</p>
                                    <p className={`text-[10px] mt-0.5 ${alert.severity === 'danger' ? 'text-red-600/80' : 'text-amber-600/80'}`}>
                                        Disp: {alert.currentStock} {alert.unit} (mínimo local: {alert.minStock})
                                    </p>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            )}

            {/* Add Modal */}
            {showNewModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-md shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Registrar Lote</h2>
                            <button onClick={() => setShowNewModal(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreate} className="p-6 space-y-4">
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">SKU *</label>
                                    <input
                                        required autoFocus
                                        type="text" value={newSku} onChange={(e) => setNewSku(e.target.value)}
                                        className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                        placeholder="Ej. MAT-101"
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Lote *</label>
                                    <input
                                        required
                                        type="text" value={newLotCode} onChange={(e) => setNewLotCode(e.target.value)}
                                        className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                        placeholder="#445"
                                    />
                                </div>
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Descripción</label>
                                <input
                                    type="text" value={newDesc} onChange={(e) => setNewDesc(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="Nombre del producto"
                                />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Qty Inicial *</label>
                                    <input
                                        required type="number" min="1" step="any"
                                        value={newQty} onChange={(e) => setNewQty(e.target.value)}
                                        className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Costo Unitario</label>
                                    <input
                                        type="number" min="0" step="any"
                                        value={newCost} onChange={(e) => setNewCost(e.target.value)}
                                        className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    />
                                </div>
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

            {/* Reserve Modal */}
            {showReserveModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div
                        initial={{ opacity: 0, scale: 0.95 }}
                        animate={{ opacity: 1, scale: 1 }}
                        className="bg-white rounded-2xl w-full max-w-sm shadow-xl overflow-hidden"
                    >
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Reservar Stock</h2>
                            <button onClick={() => setShowReserveModal(null)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleReserve} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Cantidad a reservar</label>
                                <input
                                    required autoFocus
                                    type="number" min="1" step="any"
                                    value={reserveQty} onChange={(e) => setReserveQty(e.target.value)}
                                    className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20"
                                    placeholder="0"
                                />
                            </div>
                            <div className="pt-4 flex items-center justify-end gap-3">
                                <button type="button" onClick={() => setShowReserveModal(null)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-blue-600 text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting && <Loader2 size={14} className="animate-spin" />} Confirmar
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}
        </div>
    );
};

export default InventoryPage;
