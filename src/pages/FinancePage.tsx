import React, { useState, useEffect, useRef } from 'react';
import { Wallet, TrendingUp, ArrowUpRight, ArrowDownRight, Truck, DollarSign, PieChart, ChevronDown, Plus, CreditCard, Loader2 } from 'lucide-react';
import { getDates, DateFilterRange } from '@/utils/date';
import { KPICard } from '@/components/KPICard';
import { Badge } from '@/components/Badge';
import { useAuthStore } from '@/store/authStore';
import {
    getFinanceOverview,
    listFinanceInvoices,
    createFinanceInvoice,
    recordPayment
} from '@/services/finance.service';
import type { FinanceInvoice, FinanceOverview } from '@/types/finance';
import { motion } from 'motion/react';
import type { BadgeVariant } from '@/types/common';

const formatCurrency = (val: number, cur: string = 'MXN') => {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: cur }).format(val);
};

const mapStatusToVariant = (status: string): BadgeVariant => {
    switch (status) {
        case 'paid': return 'success';
        case 'overdue': return 'danger';
        case 'open': return 'info';
        case 'draft': return 'default';
        case 'void': return 'default';
        default: return 'default';
    }
};

const FinancePage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const getRole = useAuthStore((s) => s.getRole);
    const isViewer = getRole() === 'viewer';

    const [loading, setLoading] = useState(true);
    const [overview, setOverview] = useState<FinanceOverview | null>(null);
    const [invoices, setInvoices] = useState<FinanceInvoice[]>([]);

    // UI State
    const [showNewInvoiceMode, setShowNewInvoiceMode] = useState(false);
    const [showPayModal, setShowPayModal] = useState<FinanceInvoice | null>(null);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [dateRange, setDateRange] = useState<'month' | 'quarter' | 'year' | 'all'>('month');
    const [showDateMenu, setShowDateMenu] = useState(false);
    const dateMenuRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (dateMenuRef.current && !dateMenuRef.current.contains(event.target as Node)) {
                setShowDateMenu(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

    // Form State
    const [formDir, setFormDir] = useState<'ar' | 'ap'>('ar');
    const [formName, setFormName] = useState('');
    const [formRef, setFormRef] = useState('');
    const [formAmount, setFormAmount] = useState('');
    const [formDate, setFormDate] = useState('');

    // Pay state
    const [payAmount, setPayAmount] = useState('');
    const [payMethod, setPayMethod] = useState<'transfer' | 'cash' | 'card' | 'other'>('transfer');
    const [payNote, setPayNote] = useState('');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        const { start, end } = getDates(dateRange as DateFilterRange);
        const sStr = start ? start.toISOString().split('T')[0] : undefined;
        const eStr = end ? end.toISOString().split('T')[0] : undefined;
        try {
            const [ov, invs] = await Promise.all([
                getFinanceOverview(activeTenant, sStr, eStr),
                listFinanceInvoices(activeTenant, 20, undefined, undefined, sStr, eStr)
            ]);
            setOverview(ov);
            setInvoices(invs);
        } catch (err) {
            console.error('Failed to fetch finance dat', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant, dateRange]);

    const handleCreateInvoice = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !formName || !formAmount) return;
        setIsSubmitting(true);
        try {
            await createFinanceInvoice(activeTenant, {
                direction: formDir,
                counterparty_name: formName,
                reference: formRef,
                amount: Number(formAmount),
                due_date: formDate || undefined
            });
            setShowNewInvoiceMode(false);
            setFormName(''); setFormRef(''); setFormAmount(''); setFormDate('');
            await fetchData();
        } catch (error) {
            console.error(error);
        } finally {
            setIsSubmitting(false);
        }
    };

    const handleRecordPayment = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!activeTenant || !showPayModal || !payAmount) return;
        setIsSubmitting(true);
        try {
            await recordPayment(activeTenant, {
                invoice_id: showPayModal.id,
                amount: Number(payAmount),
                method: payMethod,
                note: payNote
            });
            setShowPayModal(null);
            setPayAmount(''); setPayNote('');
            await fetchData();
        } catch (error) {
            console.error(error);
        } finally {
            setIsSubmitting(false);
        }
    };

    if (loading && !overview) {
        return (
            <div className="flex items-center justify-center p-20 min-h-[50vh]">
                <Loader2 className="animate-spin text-slate-400" size={30} />
            </div>
        );
    }

    const oData = overview || {
        total_ar_open: 0, total_ap_open: 0, total_overdue: 0, paid_this_month: 0, count_open_invoices: 0,
        chart: { labels: [], values: [] }
    };

    return (
        <div className="space-y-6 relative">
            {loading && overview && (
                <div className="absolute inset-0 bg-white/50 backdrop-blur-[1px] z-10 flex items-start justify-center pt-20 rounded-xl">
                    <Loader2 className="animate-spin text-primary" size={24} />
                </div>
            )}

            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Finanzas</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Control de cuentas por cobrar, pagar y flujos</p>
                </div>
                <div className="flex items-center gap-2">
                    <div className="relative" ref={dateMenuRef}>
                        <button onClick={() => setShowDateMenu(!showDateMenu)} className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                            {dateRange === 'month' ? 'Este Mes' : dateRange === 'quarter' ? 'Último Trimestre' : dateRange === 'year' ? 'Este Año' : 'Todo el Histórico'} <ChevronDown size={14} />
                        </button>
                        {showDateMenu && (
                            <div className="absolute right-0 top-full mt-2 w-40 bg-white rounded-xl shadow-lg border border-slate-100 py-2 z-20 animate-fade-in origin-top-right">
                                <button onClick={() => { setDateRange('month'); setShowDateMenu(false); }} className="w-full text-left px-4 py-2 text-sm hover:bg-slate-50 text-slate-600 transition-colors">Este Mes</button>
                                <button onClick={() => { setDateRange('quarter'); setShowDateMenu(false); }} className="w-full text-left px-4 py-2 text-sm hover:bg-slate-50 text-slate-600 transition-colors">Último Trimestre</button>
                                <button onClick={() => { setDateRange('year'); setShowDateMenu(false); }} className="w-full text-left px-4 py-2 text-sm hover:bg-slate-50 text-slate-600 transition-colors">Este Año</button>
                                <button onClick={() => { setDateRange('all'); setShowDateMenu(false); }} className="w-full text-left px-4 py-2 text-sm hover:bg-slate-50 text-slate-600 transition-colors">Todo el Histórico</button>
                            </div>
                        )}
                    </div>
                    {!isViewer && (
                        <button onClick={() => setShowNewInvoiceMode(true)} className="flex items-center gap-2 px-3.5 py-2 bg-primary text-white rounded-xl text-xs font-semibold shadow-sm hover:bg-primary-light transition-all">
                            <Plus size={14} /> Nueva Factura / Cuenta
                        </button>
                    )}
                </div>
            </div>

            {/* KPIs */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="gradient-primary rounded-2xl p-5 text-white shadow-lg shadow-primary/20 relative overflow-hidden animate-fade-in animate-fade-in-delay-1 lg:col-span-2 flex items-center gap-6 justify-between">
                    <div>
                        <div className="p-2.5 bg-white/10 rounded-xl w-fit mb-3">
                            <DollarSign size={20} strokeWidth={1.8} />
                        </div>
                        <p className="text-[10px] font-semibold uppercase tracking-widest text-white/60">Flujo Ingresado (Mes)</p>
                        <h3 className="text-2xl font-bold mt-1">{formatCurrency(oData.paid_this_month)} <span className="text-sm font-normal text-white/50">MXN</span></h3>
                    </div>
                    {oData.chart && oData.chart.values.length > 0 && (
                        <div className="flex items-end gap-1.5 h-16 opacity-80 shrink-0 pr-4">
                            {oData.chart.values.map((v, i) => (
                                <div key={i} className="w-3 bg-white/30 rounded-t-sm" style={{ height: `${Math.max(10, (v / Math.max(...oData.chart.values)) * 100)}%` }} />
                            ))}
                        </div>
                    )}
                </div>
                <KPICard title="Por Cobrar (Abierto)" value={formatCurrency(oData.total_ar_open)} change={`${oData.count_open_invoices} act`} trend="up" icon={ArrowUpRight} className="animate-fade-in animate-fade-in-delay-2" />
                <KPICard title="Vencido" value={formatCurrency(oData.total_overdue)} change="Prioridad" trend="down" icon={ArrowDownRight} className="animate-fade-in animate-fade-in-delay-3" />
            </div>

            {/* Invoices List */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="p-5 flex justify-between items-center border-b border-tech-border/40">
                    <h3 className="font-bold text-slate-800">Cuentas y Facturas Recientes</h3>
                    <div className="flex gap-2">
                        <span className="text-xs font-semibold text-slate-500 bg-slate-100 px-3 py-1 rounded-full">{invoices.length} Cuentas</span>
                    </div>
                </div>
                {invoices.length === 0 ? (
                    <div className="p-8 text-center bg-slate-50/50">
                        <p className="text-slate-400 text-sm">No hay cuentas por cobrar ni pagar registradas recientemente.</p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm">
                            <thead className="bg-slate-50/50 border-b border-tech-border/40">
                                <tr className="text-[10px] font-semibold text-slate-500 uppercase tracking-widest">
                                    <th className="px-5 py-3">Referencia / Cliente</th>
                                    <th className="px-5 py-3">Tipo</th>
                                    <th className="px-5 py-3">Vencimiento</th>
                                    <th className="px-5 py-3">Monto</th>
                                    <th className="px-5 py-3">Estado</th>
                                    <th className="px-5 py-3 text-right">Acciones</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border/40">
                                {invoices.map((inv) => (
                                    <tr key={inv.id} className="hover:bg-primary-50/30 transition-colors group">
                                        <td className="px-5 py-4">
                                            <p className="font-semibold text-slate-800 text-[13px]">{inv.reference || 'Sin Ref'}</p>
                                            <p className="text-[11px] text-slate-400 mt-0.5">{inv.counterparty_name}</p>
                                        </td>
                                        <td className="px-5 py-4">
                                            {inv.direction === 'ar'
                                                ? <span className="inline-flex items-center gap-1 text-[11px] font-bold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full"><ArrowUpRight size={12} /> Cobro (AR)</span>
                                                : <span className="inline-flex items-center gap-1 text-[11px] font-bold text-rose-600 bg-rose-50 px-2 py-0.5 rounded-full"><ArrowDownRight size={12} /> Pago (AP)</span>
                                            }
                                        </td>
                                        <td className="px-5 py-4 text-slate-500 text-xs">
                                            {inv.due_date || '-'}
                                        </td>
                                        <td className="px-5 py-4 font-bold text-slate-800 text-[13px]">
                                            {formatCurrency(inv.amount, inv.currency)}
                                        </td>
                                        <td className="px-5 py-4">
                                            <Badge variant={mapStatusToVariant(inv.status)}>{inv.status.toUpperCase()}</Badge>
                                        </td>
                                        <td className="px-5 py-4 text-right">
                                            {!isViewer && inv.status !== 'paid' && inv.status !== 'void' && (
                                                <button
                                                    onClick={() => setShowPayModal(inv)}
                                                    className="opacity-0 group-hover:opacity-100 transition-opacity text-xs font-semibold bg-white border border-slate-200 text-slate-600 hover:text-primary hover:border-primary/30 px-3 py-1.5 rounded-lg flex items-center gap-1 ml-auto shadow-sm"
                                                >
                                                    <CreditCard size={14} /> Pagar
                                                </button>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {/* Modal: Add Invoice/Account */}
            {showNewInvoiceMode && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="bg-white rounded-2xl w-full max-w-md shadow-xl overflow-hidden">
                        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
                            <h2 className="text-lg font-bold text-slate-800">Nueva Operación Financiera</h2>
                            <button onClick={() => setShowNewInvoiceMode(false)} className="text-slate-400 hover:text-slate-600">✕</button>
                        </div>
                        <form onSubmit={handleCreateInvoice} className="p-6 space-y-4">
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Tipo de Flujo</label>
                                    <div className="flex rounded-lg border border-slate-200 overflow-hidden bg-slate-50 p-1">
                                        <button type="button" onClick={() => setFormDir('ar')} className={`flex-1 py-1.5 text-xs font-semibold rounded-md transition-colors ${formDir === 'ar' ? 'bg-white shadow-sm text-primary' : 'text-slate-500'}`}>Por Cobrar (AR)</button>
                                        <button type="button" onClick={() => setFormDir('ap')} className={`flex-1 py-1.5 text-xs font-semibold rounded-md transition-colors ${formDir === 'ap' ? 'bg-white shadow-sm text-accent-red' : 'text-slate-500'}`}>Por Pagar (AP)</button>
                                    </div>
                                </div>
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Monto Total *</label>
                                    <input required type="number" step="any" min="0" value={formAmount} onChange={e => setFormAmount(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20" placeholder="0.00" />
                                </div>
                            </div>

                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Cliente / Proveedor *</label>
                                <input required type="text" value={formName} onChange={e => setFormName(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20" placeholder="Nombre completo o razón social" />
                            </div>

                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Referencia / Folio</label>
                                    <input type="text" value={formRef} onChange={e => setFormRef(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20" placeholder="F-2091" />
                                </div>
                                <div>
                                    <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Vencimiento</label>
                                    <input type="date" value={formDate} onChange={e => setFormDate(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 text-slate-600" />
                                </div>
                            </div>

                            <div className="pt-4 flex justify-end gap-3">
                                <button type="button" onClick={() => setShowNewInvoiceMode(false)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting ? <Loader2 size={14} className="animate-spin" /> : 'Crear Cuenta'}
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}

            {/* Modal: Record Payment */}
            {showPayModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-sm p-4">
                    <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="bg-white rounded-2xl w-full max-w-sm shadow-xl overflow-hidden">
                        <div className="px-6 py-4 border-b border-slate-100">
                            <h2 className="text-lg font-bold text-slate-800">Registrar Pago</h2>
                            <p className="text-xs text-slate-400 mt-0.5">Operación a la cuenta {showPayModal.reference || 'Sin Ref'} de {showPayModal.counterparty_name}</p>
                        </div>
                        <form onSubmit={handleRecordPayment} className="p-6 space-y-4">
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Monto Parcial o Total</label>
                                <input required type="number" step="any" min="0" value={payAmount} onChange={e => setPayAmount(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20" placeholder="0.00" />
                                <span className="text-[10px] text-slate-400 mt-1 block">Saldo actual: {formatCurrency(showPayModal.amount, showPayModal.currency)}</span>
                            </div>
                            <div>
                                <label className="block text-xs font-bold text-slate-500 uppercase tracking-wider mb-1.5">Método</label>
                                <select value={payMethod} onChange={(e: any) => setPayMethod(e.target.value)} className="w-full px-3 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 text-slate-700">
                                    <option value="transfer">Transferencia</option>
                                    <option value="cash">Efectivo</option>
                                    <option value="card">Tarjeta</option>
                                    <option value="other">Otro</option>
                                </select>
                            </div>
                            <div className="pt-4 flex justify-end gap-3">
                                <button type="button" onClick={() => setShowPayModal(null)} className="px-4 py-2 text-sm font-semibold text-slate-500 hover:text-slate-700">Cancelar</button>
                                <button type="submit" disabled={isSubmitting} className="px-4 py-2 bg-primary text-white text-sm font-semibold rounded-lg flex items-center gap-2">
                                    {isSubmitting ? <Loader2 size={14} className="animate-spin" /> : 'Confirmar'}
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}
        </div>
    );
};

export default FinancePage;
