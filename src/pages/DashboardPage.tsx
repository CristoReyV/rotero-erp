import React, { useState, useEffect } from 'react';
import { CheckCircle2, Truck, Wallet, Package, AlertCircle, Clock, ShieldCheck, MoreHorizontal, ArrowRight, TrendingUp, Loader2 } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { getDashboardOverview, getDashboardRecentActivity, getDashboardAlerts } from '@/services/dashboard.service';
import { getDates } from '@/utils/date';
import { KPICard } from '@/components/KPICard';
import { Badge } from '@/components/Badge';
import type { DashboardOverview, DashboardOperation, FiscalAlert } from '@/types/dashboard';

const alertStyles = {
    danger: { bg: 'bg-red-50/80', border: 'border-red-200/50', icon: AlertCircle, iconColor: 'text-red-500', titleColor: 'text-red-700', descColor: 'text-red-600/80' },
    warning: { bg: 'bg-amber-50/80', border: 'border-amber-200/50', icon: Clock, iconColor: 'text-amber-500', titleColor: 'text-amber-700', descColor: 'text-amber-600/80' },
    info: { bg: 'bg-blue-50/80', border: 'border-blue-200/50', icon: ShieldCheck, iconColor: 'text-blue-500', titleColor: 'text-blue-700', descColor: 'text-blue-600/80' },
};

const formatCurrency = (val: number) => {
    if (val >= 1000000) return `$${(val / 1000000).toFixed(1)}M`;
    if (val >= 1000) return `$${(val / 1000).toFixed(0)}k`;
    return `$${val}`;
};

const DashboardPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const [loading, setLoading] = useState(true);
    const [overview, setOverview] = useState<DashboardOverview | null>(null);
    const [operations, setOperations] = useState<DashboardOperation[]>([]);
    const [alerts, setAlerts] = useState<FiscalAlert[]>([]);
    const [dateFilter, setDateFilter] = useState<'this_month' | 'last_7_days' | 'last_30_days' | 'this_year'>('this_month');

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const { start, end } = getDates(dateFilter);
            const [ov, ops, acts] = await Promise.all([
                getDashboardOverview(activeTenant, start, end),
                getDashboardRecentActivity(activeTenant, start, end),
                getDashboardAlerts(activeTenant, start, end)
            ]);
            setOverview(ov);
            setOperations(ops);
            setAlerts(acts);
        } catch (err) {
            console.error('Failed to fetch dashboard data', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant, dateFilter]);

    if (loading && !overview) {
        return (
            <div className="flex items-center justify-center p-20 min-h-[50vh]">
                <Loader2 className="animate-spin text-slate-400" size={30} />
            </div>
        );
    }

    const { kpis, chart } = overview || {
        kpis: { ops_total: 0, ops_in_transit: 0, billing_total: 0, inventory_value: 0 },
        chart: { data: [], labels: [] }
    };

    const maxChart = chart.data.length > 0 ? Math.max(...chart.data) : 100;

    return (
        <div className="space-y-6 relative">
            {/* Loading overlay for subsequent re-fetches */}
            {loading && overview && (
                <div className="absolute inset-0 bg-white/50 backdrop-blur-[1px] z-10 flex items-start justify-center pt-20 rounded-xl">
                    <Loader2 className="animate-spin text-primary" size={24} />
                </div>
            )}

            {/* Welcome header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Cargando Tablero Dashboard 👋</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Aquí está el resumen de la operativa para tu tenant</p>
                </div>
                <button className="hidden md:flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-xl text-sm font-semibold shadow-md shadow-primary/15 hover:shadow-lg hover:shadow-primary/25 transition-all">
                    <TrendingUp size={16} /> Ver reportes
                </button>
            </div>

            {/* KPI row */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <KPICard title="OTIF Score" value="98.5%" change="2.1%" trend="up" icon={CheckCircle2} className="animate-fade-in animate-fade-in-delay-1" />
                <KPICard title="En Tránsito" value={String(kpis.ops_in_transit)} change="Activas" trend="up" icon={Truck} className="animate-fade-in animate-fade-in-delay-2" />
                <KPICard title="Facturación Mes" value={formatCurrency(kpis.billing_total)} change="Total Timbrado" trend="up" icon={Wallet} className="animate-fade-in animate-fade-in-delay-3" />
                <KPICard title="Inv. Valorizado" value={formatCurrency(kpis.inventory_value)} change="Estimado Global" trend="down" icon={Package} className="animate-fade-in animate-fade-in-delay-4" />
            </div>

            {/* Chart + Alerts row */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
                {/* Chart */}
                <div className="lg:col-span-2 bg-surface-card rounded-2xl border border-tech-border/60 p-6 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="flex justify-between items-center mb-6">
                        <div>
                            <h3 className="font-bold text-slate-800">Flujo de Órdenes</h3>
                            <p className="text-xs text-slate-400 mt-0.5">Basado en el filtro actual</p>
                        </div>
                        <div className="flex bg-surface rounded-lg p-0.5 border border-tech-border/60">
                            <select
                                className="text-xs font-medium text-slate-600 bg-transparent border-none focus:ring-0 cursor-pointer px-2 py-1 outline-none"
                                value={dateFilter}
                                onChange={(e) => setDateFilter(e.target.value as any)}
                            >
                                <option value="last_7_days">Últimos 7 días</option>
                                <option value="last_30_days">Últimos 30 días</option>
                                <option value="this_month">Este Mes</option>
                                <option value="this_year">Este Año</option>
                            </select>
                        </div>
                    </div>
                    <div className="h-56 flex items-end justify-between gap-2 px-1">
                        {chart.data.map((h, i) => (
                            <div key={i} className="w-full flex flex-col items-center gap-2 group">
                                <span className="text-[10px] font-semibold text-slate-400 opacity-0 group-hover:opacity-100 transition-opacity">
                                    {h}%
                                </span>
                                <div className="w-full relative rounded-lg overflow-hidden bg-slate-100" style={{ height: '200px' }}>
                                    <div
                                        className="absolute bottom-0 w-full rounded-lg transition-all duration-500 group-hover:opacity-100"
                                        style={{
                                            height: `${(h / maxChart) * 100}%`,
                                            background: i === chart.data.length - 1 || i === chart.data.length - 2 ? 'linear-gradient(to top, #0F2B5B, #3b6cbf)' : 'linear-gradient(to top, #cbd5e1, #94a3b8)',
                                            opacity: i === chart.data.length - 1 || i === chart.data.length - 2 ? 1 : 0.5,
                                        }}
                                    />
                                </div>
                            </div>
                        ))}
                    </div>
                    <div className="flex justify-between mt-3 text-[10px] text-slate-400 font-semibold uppercase tracking-wider px-1">
                        {chart.labels.map((label, idx) => (
                            <span key={idx}>{label}</span>
                        ))}
                    </div>
                </div>

                {/* Fiscal Alerts */}
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 p-6">
                    <div className="flex justify-between items-center mb-5">
                        <h3 className="font-bold text-slate-800">Notificaciones</h3>
                        {alerts.length > 0 && (
                            <span className="flex items-center justify-center w-6 h-6 rounded-full bg-accent-red text-white text-[10px] font-bold">
                                {alerts.filter(a => a.type === 'danger' || a.type === 'warning').length || alerts.length}
                            </span>
                        )}
                    </div>
                    <div className="space-y-3">
                        {alerts.map((alert, i) => {
                            const style = alertStyles[alert.type];
                            const AlertIcon = style.icon;
                            return (
                                <div key={i} className={`flex gap-3 p-3.5 ${style.bg} rounded-xl border ${style.border} hover:scale-[1.01] transition-transform cursor-pointer`}>
                                    <div className="mt-0.5">
                                        <AlertIcon className={style.iconColor} size={16} strokeWidth={2} />
                                    </div>
                                    <div className="min-w-0">
                                        <p className={`text-xs font-bold ${style.titleColor}`}>{alert.title}</p>
                                        <p className={`text-[10px] ${style.descColor} mt-0.5 leading-relaxed`}>{alert.description}</p>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>
            </div>

            {/* Active Operations table */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="p-5 flex justify-between items-center">
                    <div>
                        <h3 className="font-bold text-slate-800">Operaciones Recientes</h3>
                        <p className="text-xs text-slate-400 mt-0.5">Mostrando últimás registradas.</p>
                    </div>
                    <button className="text-xs font-semibold text-primary hover:text-primary-light flex items-center gap-1 transition-colors">
                        Ver todas <ArrowRight size={14} />
                    </button>
                </div>
                <div className="overflow-x-auto">
                    <table className="w-full text-left text-sm">
                        <thead className="border-t border-tech-border/60">
                            <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest">
                                <th className="px-5 py-3">Referencia</th>
                                <th className="px-5 py-3">Cliente</th>
                                <th className="px-5 py-3">Estado</th>
                                <th className="px-5 py-3">Ruta</th>
                                <th className="px-5 py-3">ETA</th>
                                <th className="px-5 py-3 text-right">Acciones</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-tech-border/40">
                            {operations.length === 0 ? (
                                <tr>
                                    <td colSpan={6} className="px-5 py-8 text-center text-slate-400 text-sm">
                                        Sin operaciones recientes.
                                    </td>
                                </tr>
                            ) : operations.map((op, i) => (
                                <tr key={op.id || i} className="hover:bg-primary-50/30 transition-colors group cursor-pointer">
                                    <td className="px-5 py-3.5 font-semibold text-primary text-[13px]">{op.id}</td>
                                    <td className="px-5 py-3.5 text-slate-600 text-[13px]">{op.client}</td>
                                    <td className="px-5 py-3.5"><Badge variant={op.variant as any}>{op.status}</Badge></td>
                                    <td className="px-5 py-3.5 text-slate-400 text-xs font-mono">{op.route}</td>
                                    <td className="px-5 py-3.5 text-slate-500 text-xs">{op.eta}</td>
                                    <td className="px-5 py-3.5 text-right">
                                        <button className="text-slate-300 hover:text-primary transition-colors opacity-0 group-hover:opacity-100">
                                            <MoreHorizontal size={18} />
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
};

export default DashboardPage;
