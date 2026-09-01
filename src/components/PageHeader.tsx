import type { ReactNode } from 'react';
import type { LucideIcon } from 'lucide-react';

interface PageHeaderProps {
    title: string;
    subtitle?: string;
    actions?: ReactNode;
}

export const PageHeader = ({ title, subtitle, actions }: PageHeaderProps) => (
    <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="min-w-0">
            <h1 className="break-words text-xl font-bold text-slate-800 sm:text-2xl">{title}</h1>
            {subtitle && <p className="mt-0.5 text-xs leading-relaxed text-slate-500 sm:text-sm">{subtitle}</p>}
        </div>
        {actions && <div className="flex min-w-0 w-full flex-wrap items-center gap-2 sm:w-auto sm:shrink-0 sm:justify-end">{actions}</div>}
    </div>
);
