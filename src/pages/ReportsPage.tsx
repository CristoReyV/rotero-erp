import React, { useState, useEffect } from 'react';
import { BarChart3, Download, FileText, PieChart, TrendingUp, Calendar, ChevronDown, Package, Code } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import {
    getReportModules,
    getFinancialSummary,
    getPipelineSummary,
    getInventorySummary,
    getOperationsSummary
} from '@/services/reports.service';

import type {
    ReportModuleDef,
    ReportsFinancialSummary,
    ReportsPipelineSummary,
    ReportsInventorySummary,
    ReportsOperationsSummary
} from '@/types/reports';

const iconMap = {
    TrendingUp,
    BarChart3,
    FileText,
    PieChart,
} as const;

const formatCurrency = (val: number, cur: string = 'MXN') => {
    return new Intl.NumberFormat('es-MX', { style: 'currency', currency: cur, maximumFractionDigits: 0 }).format(val);
};

const ReportsPage = () => {
    const activeTenant = useAuthStore((s) => s.activeTenant);
    const [loading, setLoading] = useState(true);

    const [modules, setModules] = useState<ReportModuleDef[]>([]);
    const [finances, setFinances] = useState<ReportsFinancialSummary | null>(null);
    const [pipeline, setPipeline] = useState<ReportsPipelineSummary | null>(null);
    const [inventory, setInventory] = useState<ReportsInventorySummary | null>(null);
    const [operations, setOperations] = useState<ReportsOperationsSummary | null>(null);

    const fetchData = async () => {
        if (!activeTenant) return;
        setLoading(true);
        try {
            const [mods, fin, pip, inv, ops] = await Promise.all([
                getReportModules(),
                getFinancialSummary(activeTenant),
                getPipelineSummary(activeTenant),
                getInventorySummary(activeTenant),
                getOperationsSummary(activeTenant)
            ]);
            setModules(mods);
            setFinances(fin);
            setPipeline(pip);
            setInventory(inv);
            setOperations(ops);
        } catch (error) {
            console.error('Failed to load BI reports', error);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [activeTenant]);

    if (loading && !finances) {
        return (
            <div className="flex flex-col items-center justify-center p-20 min-h-[50vh] text-slate-400 gap-4">
                <BarChart3 className="animate-pulse" size={32} />
                <p className="text-sm">Generando cubo de datos OLAP...</p>
            </div>
        );
    }

    // Safeblocks
    const fin = finances!;
    const pip = pipeline!;
    const inv = inventory!;
    const ops = operations!;

    const maxChartValue = fin.revenue_by_month.length > 0 ? Math.max(...fin.revenue_by_month) : 100;

    return (
        <div className="space-y-6 relative">
            {loading && finances && (
                <div className="absolute inset-0 bg-white/50 backdrop-blur-[1px] z-10 flex items-start justify-center pt-20 rounded-xl">
                    <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
                </div>
            )}

            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                    <h1 className="text-2xl font-bold text-slate-800">Reportes & BI</h1>
                    <p className="text-sm text-slate-400 mt-0.5">Centro de inteligencia de negocio y reporteo</p>
                </div>
                <div className="flex items-center gap-2">
                    <button className="flex items-center gap-2 px-3.5 py-2 bg-surface border border-tech-border/60 rounded-xl text-xs font-semibold text-slate-500 hover:text-primary hover:border-primary/30 transition-all">
                        <Calendar size={14} /> This Month <ChevronDown size={14} />
                    </button>
                    <button className="flex items-center gap-2 px-4 py-2 gradient-primary text-white rounded-xl text-xs font-semibold shadow-md shadow-primary/15 hover:shadow-lg hover:shadow-primary/25 transition-all">
                        <Download size={14} /> Exportar Suite
                    </button>
                </div>
            </div>

            {/* Module cards (Top row UI retained from mock) */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                {modules.map((mod) => {
                    const Icon = iconMap[mod.iconName];
                    return (
                        <div key={mod.name} className="bg-surface-card rounded-2xl border border-tech-border/60 p-5 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300 cursor-pointer group">
                            <div className={`p-2.5 rounded-xl w-fit ${mod.color} group-hover:scale-110 transition-transform`}>
                                <Icon size={20} strokeWidth={1.8} />
                            </div>
                            <p className="text-[13px] font-bold text-slate-700 mt-3">{mod.name}</p>
                            <p className="text-[10px] text-slate-400 mt-0.5">{mod.count} reportes disponibles</p>
                        </div>
                    );
                })}
            </div>

            {/* Main chart placeholder modified dynamically with Supabase Arrays */}
            <div className="bg-surface-card rounded-2xl border border-tech-border/60 p-6 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                <div className="flex justify-between items-center mb-5">
                    <div>
                        <h3 className="font-bold text-slate-800">Tendencia Operativa / Revenue</h3>
                        <p className="text-xs text-slate-400 mt-0.5">Comparativa semestral (Ingreso Timbrado)</p>
                    </div>
                    <div className="flex bg-surface rounded-lg p-0.5 border border-tech-border/60">
                        <button className="text-[11px] font-semibold text-primary bg-primary-50 px-3 py-1 rounded-md">Revenue</button>
                        <button className="text-[11px] font-medium text-slate-400 px-3 py-1 rounded-md">Volume</button>
                        <button className="text-[11px] font-medium text-slate-400 px-3 py-1 rounded-md">Margin</button>
                    </div>
                </div>

                <div className="h-48 flex items-end justify-between gap-4 px-2">
                    {fin.revenue_by_month.map((h, i) => (
                        <div key={i} className="flex-1 flex items-end justify-center gap-1.5 group">
                            <span className="text-[10px] font-semibold text-slate-400 opacity-0 group-hover:opacity-100 transition-opacity absolute -mt-6">
                                {formatCurrency(h)}
                            </span>
                            <div className="w-full max-w-10 rounded-lg transition-all duration-500 gradient-primary" style={{ height: `${Math.max(5, (h / maxChartValue) * 100)}%` }} />
                        </div>
                    ))}
                </div>
                <div className="flex justify-between mt-3 text-[10px] text-slate-400 font-semibold uppercase tracking-wider px-4">
                    <span>M-5</span><span>M-4</span><span>M-3</span><span>M-2</span><span>M-1</span><span>Mes Actual</span>
                </div>
            </div>

            {/* Split row: Pipeline and Top SKUs to replace the static table */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
                {/* Pipeline & KPIs */}
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 p-6 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <h3 className="font-bold text-slate-800 mb-4">Métricas Consolidadas (YTD)</h3>
                    <div className="grid grid-cols-2 gap-4">
                        <div className="p-4 bg-slate-50/50 rounded-xl border border-slate-100 text-center">
                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Pipeline Activo</p>
                            <p className="text-lg font-bold text-slate-800 mt-1">{formatCurrency(pip.total_pipeline_value)}</p>
                            <p className="text-[10px] text-emerald-600 font-semibold mt-1">WIN {pip.conversion_rate.toFixed(1)}%</p>
                        </div>
                        <div className="p-4 bg-slate-50/50 rounded-xl border border-slate-100 text-center">
                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Rutas Activas</p>
                            <p className="text-lg font-bold text-slate-800 mt-1">{ops.active_routes_count}</p>
                            <p className="text-[10px] text-blue-600 font-semibold mt-1">Avg {ops.avg_delivery_time} hrs</p>
                        </div>
                        <div className="p-4 bg-slate-50/50 rounded-xl border border-slate-100 text-center">
                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Inv. Valorizado</p>
                            <p className="text-lg font-bold text-slate-800 mt-1">{formatCurrency(inv.inventory_total_value)}</p>
                            <p className="text-[10px] text-amber-600 font-semibold mt-1">{inv.blocked_count} Lotes Detenidos</p>
                        </div>
                        <div className="p-4 bg-slate-50/50 rounded-xl border border-slate-100 text-center">
                            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">Net Position</p>
                            <p className="text-lg font-bold text-slate-800 mt-1">{formatCurrency(fin.net_position)}</p>
                            <p className="text-[10px] text-slate-500 font-semibold mt-1">EBITDA Mapped</p>
                        </div>
                    </div>
                </div>

                {/* Top SKUs */}
                <div className="bg-surface-card rounded-2xl border border-tech-border/60 overflow-hidden hover:shadow-lg hover:shadow-primary/4 transition-all duration-300">
                    <div className="p-5 border-b border-tech-border/40">
                        <h3 className="font-bold text-slate-800">Top SKUs Valorizados (Pareto ABC)</h3>
                    </div>
                    {inv.top_skus_by_value.length === 0 ? (
                        <div className="p-8 text-center bg-surface/50">
                            <Package size={24} className="mx-auto text-slate-300 mb-2" />
                            <p className="text-sm text-slate-400">Sin movimientos de inventario en almacén</p>
                        </div>
                    ) : (
                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="text-[10px] font-semibold text-slate-400 uppercase tracking-widest border-b border-tech-border/60 bg-surface/50">
                                        <th className="px-5 py-3">Código SKU</th>
                                        <th className="px-5 py-3 text-right">Valor Retenido Estimado</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-tech-border/40">
                                    {inv.top_skus_by_value.map((skItem, i) => (
                                        <tr key={i} className="hover:bg-primary-50/30 transition-colors group">
                                            <td className="px-5 py-3.5 flex items-center gap-2">
                                                <div className="w-6 h-6 rounded bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0">
                                                    <Code size={12} strokeWidth={2.5} />
                                                </div>
                                                <p className="text-[13px] font-semibold text-slate-700 font-mono">{skItem.sku}</p>
                                            </td>
                                            <td className="px-5 py-3.5 text-right font-bold text-slate-800">
                                                {formatCurrency(skItem.value)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
};

export default ReportsPage;
