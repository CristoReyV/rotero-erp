import { ArrowUpRight, ArrowDownRight } from 'lucide-react';

interface KPICardProps {
    title: string;
    value: string;
    change?: string;
    icon: any;
    trend?: 'up' | 'down';
    className?: string;
}

export const KPICard = ({ title, value, change, icon: Icon, trend, className = '' }: KPICardProps) => (
    <div className={`bg-surface-card rounded-2xl border border-tech-border/60 p-5 hover:shadow-lg hover:shadow-primary/4 transition-all duration-300 group ${className}`}>
        <div className="flex justify-between items-start mb-4">
            <div className="p-2.5 bg-primary-50 rounded-xl text-primary group-hover:bg-primary group-hover:text-white transition-all duration-300">
                <Icon size={20} strokeWidth={1.8} />
            </div>
            {change && (
                <div className={`flex items-center gap-0.5 text-xs font-semibold px-2 py-0.5 rounded-full
          ${trend === 'up' ? 'text-emerald-700 bg-emerald-50' : 'text-red-600 bg-red-50'}`}>
                    {trend === 'up' ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
                    {change}
                </div>
            )}
        </div>
        <p className="text-[11px] text-slate-400 font-semibold uppercase tracking-widest mb-1">{title}</p>
        <h3 className="text-2xl font-bold text-slate-800">{value}</h3>
    </div>
);
