import type { HTMLAttributes } from 'react';

export type SemanticTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';

export const SEMANTIC_TONE_STYLES: Record<SemanticTone, {
    panel: string;
    accent: string;
    soft: string;
    border: string;
}> = {
    neutral: {
        panel: 'border-semantic-neutral-border bg-surface-card text-slate-800',
        accent: 'text-semantic-neutral',
        soft: 'bg-semantic-neutral-soft text-semantic-neutral',
        border: 'border-semantic-neutral-border',
    },
    info: {
        panel: 'border-semantic-info-border bg-surface-card text-slate-800',
        accent: 'text-semantic-info',
        soft: 'bg-semantic-info-soft text-semantic-info',
        border: 'border-semantic-info-border',
    },
    success: {
        panel: 'border-semantic-success-border bg-surface-card text-slate-800',
        accent: 'text-semantic-success',
        soft: 'bg-semantic-success-soft text-semantic-success',
        border: 'border-semantic-success-border',
    },
    warning: {
        panel: 'border-semantic-warning-border bg-surface-card text-slate-800',
        accent: 'text-semantic-warning',
        soft: 'bg-semantic-warning-soft text-semantic-warning',
        border: 'border-semantic-warning-border',
    },
    danger: {
        panel: 'border-semantic-danger-border bg-surface-card text-slate-800',
        accent: 'text-semantic-danger',
        soft: 'bg-semantic-danger-soft text-semantic-danger',
        border: 'border-semantic-danger-border',
    },
};

export function SemanticPanel({ tone = 'neutral', className = '', ...props }: HTMLAttributes<HTMLDivElement> & { tone?: SemanticTone }) {
    return <div {...props} className={`rounded-xl border ${SEMANTIC_TONE_STYLES[tone].panel} ${className}`} />;
}
