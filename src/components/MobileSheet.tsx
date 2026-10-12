import { X } from 'lucide-react';
import { useEffect, useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

interface MobileSheetProps {
    open: boolean;
    title: string;
    subtitle?: string;
    onClose: () => void;
    children: ReactNode;
    footer?: ReactNode;
}

export function MobileSheet({ open, title, subtitle, onClose, children, footer }: MobileSheetProps) {
    const titleId = useId();
    const closeRef = useRef<HTMLButtonElement>(null);
    const onCloseRef = useRef(onClose);
    onCloseRef.current = onClose;

    useEffect(() => {
        if (!open) return;
        const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
        const previousOverflow = document.body.style.overflow;
        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === 'Escape') onCloseRef.current();
        };
        document.body.style.overflow = 'hidden';
        document.addEventListener('keydown', handleKeyDown);
        closeRef.current?.focus();
        return () => {
            document.body.style.overflow = previousOverflow;
            document.removeEventListener('keydown', handleKeyDown);
            previousFocus?.focus();
        };
    }, [open]);

    if (!open || typeof document === 'undefined') return null;

    return createPortal(
        <div className="fixed inset-0 z-[90] flex items-end" data-mobile-sheet>
            <button type="button" aria-label={`Cerrar ${title}`} onClick={onClose} className="absolute inset-0 bg-slate-950/55 backdrop-blur-[2px]" />
            <section role="dialog" aria-modal="true" aria-labelledby={titleId} className="relative z-10 flex max-h-[calc(100dvh-0.5rem)] w-full min-w-0 flex-col overflow-hidden rounded-t-2xl border border-b-0 bg-surface-card shadow-2xl">
                <header className="flex shrink-0 items-start justify-between gap-3 border-b px-4 py-3">
                    <div className="min-w-0">
                        <h2 id={titleId} className="truncate text-base font-black text-slate-800">{title}</h2>
                        {subtitle && <p className="mt-0.5 text-xs text-slate-500">{subtitle}</p>}
                    </div>
                    <button ref={closeRef} type="button" onClick={onClose} aria-label={`Cerrar ${title}`} className="-mr-2 flex h-11 w-11 shrink-0 items-center justify-center rounded-xl text-slate-500 hover:bg-slate-100">
                        <X size={18} />
                    </button>
                </header>
                <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{children}</div>
                {footer && <footer className="shrink-0 border-t bg-surface-card px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3">{footer}</footer>}
            </section>
        </div>,
        document.body,
    );
}
