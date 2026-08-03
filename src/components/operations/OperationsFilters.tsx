import { Search, SlidersHorizontal, X } from 'lucide-react';
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

    return (
        <section className="rounded-2xl border border-tech-border/60 bg-surface-card p-4">
            <div className="flex flex-col gap-4">
                <div className="flex gap-2 overflow-x-auto pb-1" aria-label="Vistas de operaciones">
                    {OPERATIONS_VIEWS.map((item) => (
                        <button
                            key={item.value}
                            type="button"
                            onClick={() => onViewChange(item.value)}
                            className={`shrink-0 rounded-xl px-3.5 py-2 text-xs font-semibold transition-colors ${
                                view === item.value
                                    ? 'bg-primary text-white shadow-sm shadow-primary/20'
                                    : 'bg-slate-50 text-slate-500 hover:bg-primary-50 hover:text-primary'
                            }`}
                        >
                            {item.label}
                        </button>
                    ))}
                </div>

                <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_220px_auto] md:items-center">
                    <label className="relative block">
                        <span className="sr-only">Buscar operaciones</span>
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                        <input
                            type="search"
                            value={query}
                            onChange={(event) => onQueryChange(event.target.value)}
                            placeholder="Buscar referencia, cliente, ruta o asignación"
                            className="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-10 pr-4 text-sm text-slate-700 outline-none transition focus:border-primary/40 focus:ring-2 focus:ring-primary/10"
                        />
                    </label>

                    <label className="relative block">
                        <span className="sr-only">Filtrar por estado</span>
                        <SlidersHorizontal className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={15} />
                        <select
                            value={status}
                            onChange={(event) => onStatusChange(event.target.value)}
                            className="w-full appearance-none rounded-xl border border-slate-200 bg-white py-2.5 pl-9 pr-8 text-sm font-medium text-slate-600 outline-none transition focus:border-primary/40 focus:ring-2 focus:ring-primary/10"
                        >
                            <option value="">Todos los estados</option>
                            {Object.entries(OPERATION_STATUS_META).map(([value, meta]) => (
                                <option key={value} value={value}>{meta.label}</option>
                            ))}
                        </select>
                    </label>

                    <div className="flex items-center justify-between gap-3 md:justify-end">
                        <span className="whitespace-nowrap text-xs font-semibold text-slate-400">
                            {resultCount} {resultCount === 1 ? 'resultado' : 'resultados'}
                        </span>
                        {hasFilters && (
                            <button
                                type="button"
                                onClick={onClear}
                                className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-2 text-xs font-semibold text-slate-500 hover:bg-slate-100 hover:text-slate-700"
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
