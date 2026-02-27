import type { PipelineColumn } from '@/types/commercial';

// TODO: Replace with commercial.service.ts → rpc_get_pipeline
export const MOCK_PIPELINE: PipelineColumn[] = [
    { title: 'Prospecto', count: 3, deals: [{ name: 'Logística Monterrey', value: '$150k', prob: '60%' }, { name: 'Grupo Transportes', value: '$300k', prob: '45%' }] },
    { title: 'Cotización', count: 1, deals: [{ name: 'Transportes del Norte', value: '$850k', prob: '80%' }] },
    { title: 'Negociación', count: 2, deals: [{ name: 'AutoParts Global', value: '$1.2M', prob: '90%' }] },
    { title: 'Cierre', count: 5, deals: [{ name: 'Comercializadora Bajio', value: '$420k', prob: 'Won' }] },
];

// Async wrapper for future service swap (SF-02)
export async function getMockPipeline() { return MOCK_PIPELINE; }
