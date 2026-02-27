import type { DashboardOperation, FiscalAlert } from '@/types/dashboard';

// TODO: Replace with dashboard.service.ts → aggregated RPCs

export const MOCK_DASHBOARD_OPERATIONS: DashboardOperation[] = [
    { id: 'ROT-24-001', client: 'Logística Monterrey SA', status: 'En Tránsito', route: 'Laredo → CDMX', eta: 'Hoy, 14:00', variant: 'info' },
    { id: 'ROT-24-002', client: 'AutoParts Global', status: 'Despacho Aduanal', route: 'Manzanillo → QRO', eta: 'Mañana', variant: 'warning' },
    { id: 'ROT-24-003', client: 'Fresco Foods', status: 'Entregado', route: 'Veracruz → PUE', eta: 'Finalizado', variant: 'success' },
    { id: 'ROT-24-004', client: 'TechDistrib S.A.', status: 'Carga Pendiente', route: 'Tijuana → LDO', eta: '22/Oct', variant: 'default' },
];

export const MOCK_FISCAL_ALERTS: FiscalAlert[] = [
    { type: 'danger', title: 'Pedimentos por vencer', description: '2 Pedimentos (A1-9302, G3-2001) requieren validación en 48h.' },
    { type: 'warning', title: 'CFDI Pendientes', description: '5 facturas de fletes sin timbrar complemento Carta Porte.' },
    { type: 'info', title: 'Validación SAT', description: 'Sincronización de Anexo 24 completada exitosamente.' },
];

export const mockChartData = [40, 65, 45, 90, 55, 75, 50, 80, 60, 95, 70, 85];
export const mockChartLabels = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

// Async wrappers for future service swap (SF-02)
export async function getMockDashboardOperations() { return MOCK_DASHBOARD_OPERATIONS; }
export async function getMockFiscalAlerts() { return MOCK_FISCAL_ALERTS; }
