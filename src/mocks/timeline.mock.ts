import type { TimelineStep } from '@/types/operations';

export const MOCK_TIMELINE: TimelineStep[] = [
    { time: '10:00 AM', event: 'Salida de Almacén', desc: 'Laredo Distribution Center', done: true },
    { time: '12:30 PM', event: 'Cruce Fronterizo', desc: 'Puente Internacional III', done: true },
    { time: '02:45 PM', event: 'En Tránsito', desc: 'Carretera 85D - KM 120', current: true },
    { time: '06:00 PM', event: 'Arribo Estimado', desc: 'CEDIS Monterrey', future: true },
];
