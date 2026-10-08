import { Search, SlidersHorizontal, X } from 'lucide-react';
import { useState } from 'react';
import type { OperationsView } from './operationsControl';
import { OPERATIONS_VIEWS, OPERATION_STATUS_META } from './operationsControl';

interface OperationsFiltersProps {
    view: OperationsView;
    status: string;
    query: string;
    resultCount: number;
    onViewChange: (view: OperationsView) => void;
    onStatusChange: (status: string) => void;
    onQueryChange: (query: string) => void;
    onClear: () => void;
}

export function OperationsFilters({
    view,
    status,
    query,
    resultCount,
    onViewChange,
    onStatusChange,
    onQueryChange,
    onClear,
}: OperationsFiltersProps) {
    const hasFilters = view !== 'active' || Boolean(status) || Boolean(query);
    const [mobileFiltersOpen, setMobileFiltersOpen] = useState(false);

    return (
        <section className="min-w-0 rounded-2xl border border-tech-border/60 bg-surface-card p-3 sm:p-4">
            <div className="flex min-w-0 flex-col gap-3 sm:gap-4">
                <div className="flex max-w-full gap-1.5 overflow-x-auto overscroll-x-contain pb-1" aria-label="Vistas de operaciones">
                    {OPERATIONS_VIEWS.map((item) => (
                        <button
                            key={item.value}
                            type="button"
                            onClick={() => onViewChange(item.value)}
                            aria-pressed={view === item.value}
                            className={`min-h-11 shrink-0 rounded-xl px-3 text-xs font-semibold transition-colors sm:px-3.5 ${
                                view === item.value
                                    ? 'bg-primary text-white shadow-sm shadow-primary/20'
                                    : 'bg-slate-50 text-slate-500 hover:bg-primary-50 hover:text-primary'
                            }`}
                        >
                            {item.label}
                        </button>
                    ))}
                </div>

                <div className="grid min-w-0 gap-2 md:grid-cols-[minmax(0,1fr)_220px_auto] md:items-center md:gap-3">
                    <div className="flex min-w-0 gap-2">
                    <label className="relative block min-w-0 flex-1">
                        <span className="sr-only">Buscar operaciones</span>
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                        <input
                            type="search"
                            value={query}
                            onChange={(event) => onQueryChange(event.target.value)}
                            placeholder="Buscar referencia, cliente, ruta o asignación"
                            className="min-h-11 w-full rounded-xl border bg-surface py-2.5 pl-10 pr-4 text-sm text-slate-700 outline-none transition focus:border-primary/40 focus:ring-2 focus:ring-primary/10"
                        />
                    </label>
                    <button type="button" aria-expanded={mobileFiltersOpen} onClick={() => setMobileFiltersOpen((value) => !value)} className="inline-flex min-h-11 shrink-0 items-center gap-2 rounded-xl border px-3 text-xs font-bold text-slate-600 md:hidden"><SlidersHorizontal size={15} />Filtros{status && <span className="h-2 w-2 rounded-full bg-primary" />}</button>
                    </div>

                    <label className={`relative ${mobileFiltersOpen ? 'block' : 'hidden'} md:block`}>
                        <span className="sr-only">Filtrar por estado</span>
                        <SlidersHorizontal className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={15} />
                        <select
                            value={status}
                            onChange={(event) => onStatusChange(event.target.value)}
                            className="min-h-11 w-full appearance-none rounded-xl border bg-surface-card py-2.5 pl-9 pr-8 text-sm font-medium text-slate-600 outline-none transition focus:border-primary/40 focus:ring-2 focus:ring-primary/10"
                        >
                            <option value="">Todos los estados</option>
                            {Object.entries(OPERATION_STATUS_META).map(([value, meta]) => (
                                <option key={value} value={value}>{meta.label}</option>
                            ))}
                        </select>
                    </label>

                    <div className={`${mobileFiltersOpen || hasFilters ? 'flex' : 'hidden'} items-center justify-between gap-3 md:flex md:justify-end`}>
                        <span className="whitespace-nowrap text-xs font-semibold text-slate-400">
                            {resultCount} {resultCount === 1 ? 'resultado' : 'resultados'}
                        </span>
                        {hasFilters && (
                            <button
                                type="button"
                                onClick={onClear}
                                className="inline-flex min-h-11 items-center gap-1.5 rounded-lg px-2.5 text-xs font-semibold text-slate-500 hover:bg-slate-100 hover:text-slate-700"
                            >
                                <X size={14} /> Limpiar
                            </button>
                        )}
                    </div>
                </div>
            </div>
        </section>
    );
}
