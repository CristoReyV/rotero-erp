import React from 'react';
import type { BadgeVariant } from '@/types/common';

const BADGE_STYLES: Record<BadgeVariant, string> = {
    default: 'bg-semantic-neutral-soft text-semantic-neutral ring-1 ring-semantic-neutral-border',
    success: 'bg-semantic-success-soft text-semantic-success ring-1 ring-semantic-success-border',
    warning: 'bg-semantic-warning-soft text-semantic-warning ring-1 ring-semantic-warning-border',
    danger: 'bg-semantic-danger-soft text-semantic-danger ring-1 ring-semantic-danger-border',
    info: 'bg-semantic-info-soft text-semantic-info ring-1 ring-semantic-info-border',
};

export const Badge = ({ children, variant = 'default' }: { children: React.ReactNode; variant?: BadgeVariant }) => (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${BADGE_STYLES[variant]}`}>
        {children}
    </span>
);
