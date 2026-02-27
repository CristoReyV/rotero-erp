import { supabase } from '@/lib/supabase';
import type {
    Deal, DealFilters, DealCreatePayload, DealUpdatePatch,
    DealStage, PipelineColumn
} from '@/types/commercial';

const USE_MOCKS = import.meta.env.VITE_USE_MOCKS === 'true';

const formatValue = (val: number, cur: string) => {
    if (!val) return '0';
    if (val >= 1000000) return `$${(val / 1000000).toFixed(1)}M`;
    if (val >= 1000) return `$${(val / 1000).toFixed(0)}k`;
    return `$${val}`;
};

const getProbForStage = (stage: string): string => {
    switch (stage) {
        case 'lead': return '20%';
        case 'qualified': return '50%';
        case 'proposal': return '80%';
        case 'won': return 'Won';
        case 'lost': return 'Lost';
        default: return '0%';
    }
};

const STAGE_MAP: Record<DealStage, string> = {
    'lead': 'Prospecto',
    'qualified': 'Cotización',
    'proposal': 'Negociación',
    'won': 'Cierre',
    'lost': 'Perdido'
};

export async function listPipelineDeals(tenantId: string, filters: DealFilters = {}): Promise<PipelineColumn[]> {
    if (USE_MOCKS) {
        const { getMockPipeline } = await import('@/mocks/commercial.mock');
        return getMockPipeline();
    }

    const { data, error } = await supabase.rpc('rpc_list_deals', {
        p_tenant_id: tenantId,
        p_filters: filters
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    const deals: Deal[] = data || [];

    // Group by stage into the UI standard format (Lost is usually hidden or separate, but we ignore it here or could add a column)
    const pipeline: Record<string, PipelineColumn> = {
        'lead': { id: 'lead', title: 'Prospecto', count: 0, deals: [] },
        'qualified': { id: 'qualified', title: 'Cotización', count: 0, deals: [] },
        'proposal': { id: 'proposal', title: 'Negociación', count: 0, deals: [] },
        'won': { id: 'won', title: 'Cierre', count: 0, deals: [] },
    };

    deals.forEach(deal => {
        const stageId = deal.stage as keyof typeof pipeline;
        if (pipeline[stageId]) {
            pipeline[stageId].count++;
            pipeline[stageId].deals.push({
                db_id: deal.id,
                name: deal.title, // Title of the deal serves as name here
                value: formatValue(deal.value || 0, deal.currency),
                prob: getProbForStage(deal.stage)
            });
        }
    });

    return [pipeline['lead'], pipeline['qualified'], pipeline['proposal'], pipeline['won']];
}

export async function createDeal(tenantId: string, payload: DealCreatePayload): Promise<{ id: string }> {
    if (USE_MOCKS) return { id: 'mock-deal-uuid' };

    const { data, error } = await supabase.rpc('rpc_create_deal', {
        p_tenant_id: tenantId,
        p_payload: payload
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);

    return { id: data.id };
}

export async function updateDeal(dealId: string, patch: DealUpdatePatch): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_update_deal', {
        p_deal_id: dealId,
        p_patch: patch
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}

export async function moveDeal(dealId: string, newStage: DealStage): Promise<void> {
    if (USE_MOCKS) return;

    const { data, error } = await supabase.rpc('rpc_move_deal', {
        p_deal_id: dealId,
        p_new_stage: newStage
    });

    if (error) throw error;
    if (data?.error) throw new Error(data.error);
}
