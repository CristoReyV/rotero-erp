import React from 'react';
import type { BadgeVariant } from '@/types/common';

const BADGE_STYLES: Record<BadgeVariant, string> = {
    default: 'bg-slate-50 text-slate-500 ring-1 ring-slate-200',
    success: 'bg-emerald-50 text-emerald-700 ring-1 ring-emerald-200/60',
    warning: 'bg-amber-50 text-amber-700 ring-1 ring-amber-200/60',
    danger: 'bg-red-50 text-red-700 ring-1 ring-red-200/60',
    info: 'bg-blue-50 text-blue-700 ring-1 ring-blue-200/60',
};

export const Badge = ({ children, variant = 'default' }: { children: React.ReactNode; variant?: BadgeVariant }) => (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${BADGE_STYLES[variant]}`}>
        {children}
    </span>
);
