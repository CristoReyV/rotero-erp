import { create } from 'zustand';

export interface AuthorizedCompany {
    id: string;
    display_name: string;
    legal_name: string;
    rfc: string;
    capabilities: string[];
}

type Phase = 'loading' | 'ready' | 'error' | 'inactive';
interface CompanyState {
    epoch: number;
    tenantId: string | null;
    companies: AuthorizedCompany[];
    consolidations: string[][];
    selectedIds: string[];
    mode: 'company' | 'consolidated';
    phase: Phase;
    reset: (tenantId?: string | null) => void;
    accept: (tenantId: string, companies: AuthorizedCompany[], consolidations?: string[][]) => void;
    select: (companyId: string) => void;
    selectConsolidation: (ids: string[]) => void;
    fail: () => void;
    deactivate: () => void;
}

// Deliberately not persisted: permissions must be read again for each identity.
export const useCompanyStore = create<CompanyState>((set, get) => ({
    epoch: 0,
    tenantId: null,
    companies: [],
    consolidations: [],
    selectedIds: [],
    mode: 'company',
    phase: 'loading',
    reset: (tenantId = null) =>
        set((state) => ({
            epoch: state.epoch + 1,
            tenantId,
            companies: [],
            consolidations: [],
            selectedIds: [],
            mode: 'company',
            phase: 'loading',
        })),
    accept: (tenantId, companies, consolidations = []) => {
        const previous = get();
        if (previous.tenantId !== tenantId) return;
        const sets = consolidations.filter((ids) =>
            ids.length > 1 && new Set(ids).size === ids.length &&
            ids.every((id) => companies.some((company) => company.id === id))
        ).map((ids) => [...ids].sort());
        if (previous.mode === 'consolidated') {
            const valid = sets.some((ids) =>
                JSON.stringify(ids) === JSON.stringify([...previous.selectedIds].sort())
            );
            const changed = !valid || JSON.stringify(previous.companies) !== JSON.stringify(companies) ||
                JSON.stringify(previous.consolidations) !== JSON.stringify(sets);
            set({
                companies,
                consolidations: sets,
                selectedIds: valid ? previous.selectedIds : [],
                phase: 'ready',
                epoch: previous.epoch + (changed ? 1 : 0),
            });
            return;
        }
        const selected = previous.selectedIds.length === 1
            ? companies.find((company) => company.id === previous.selectedIds[0])
            : null;
        // ROTERO is a preference only among companies the server authorized.
        const preferred = previous.selectedIds.length > 0
            ? selected
            : companies.find((company) => company.rfc === 'WLS110325JH8') ??
                (companies.length === 1 ? companies[0] : null);
        const changed = JSON.stringify(previous.companies) !== JSON.stringify(companies) ||
            previous.selectedIds[0] !== preferred?.id;
        set({
            companies,
            consolidations: sets,
            selectedIds: preferred ? [preferred.id] : [],
            phase: 'ready',
            epoch: previous.epoch + (changed ? 1 : 0),
        });
    },
    select: (companyId) => {
        if (!get().companies.some((company) => company.id === companyId)) return;
        if (get().selectedIds[0] === companyId) return;
        set((state) => ({ selectedIds: [companyId], mode: 'company', epoch: state.epoch + 1 }));
    },
    selectConsolidation: (ids) => {
        const selected = [...ids].sort();
        if (!get().consolidations.some((set) => JSON.stringify(set) === JSON.stringify(selected))) return;
        set((state) => ({ selectedIds: selected, mode: 'consolidated', epoch: state.epoch + 1 }));
    },
    fail: () =>
        set((state) => ({
            phase: 'error',
            companies: [],
            consolidations: [],
            selectedIds: [],
            epoch: state.epoch + 1,
        })),
    deactivate: () =>
        set((state) => ({
            phase: 'inactive',
            companies: [],
            consolidations: [],
            selectedIds: [],
            epoch: state.epoch + 1,
        })),
}));

export function hasCompanyCapability(capability: string): boolean {
    const state = useCompanyStore.getState();
    return state.phase === 'ready' && state.selectedIds.length > 0 &&
        state.selectedIds.every((id) =>
            state.companies.find((company) => company.id === id)?.capabilities.includes(capability)
        );
}

export function companyHeaders(): Record<string, string> {
    const state = useCompanyStore.getState();
    if (state.phase !== 'ready' || !state.selectedIds.length) return { 'x-rotero-scope': 'required' };
    if (state.mode === 'consolidated') {
        return {
            'x-rotero-scope': 'consolidated',
            'x-rotero-company-ids': JSON.stringify(state.selectedIds),
        };
    }
    return { 'x-rotero-scope': 'company', 'x-rotero-company-id': state.selectedIds[0] };
}

export async function scopedResponse<T>(request: () => Promise<T>): Promise<T> {
    const epoch = useCompanyStore.getState().epoch;
    const result = await request();
    if (epoch !== useCompanyStore.getState().epoch) throw new Error('company_context_changed');
    return result;
}
