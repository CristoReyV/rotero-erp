import {
    LayoutDashboard,
    Truck,
    Package,
    Gavel,
    FileText,
    Wallet,
    Users,
    BarChart3,
    Settings,
    MapPin,
    Files,
    Database,
    MessageSquareWarning,
} from 'lucide-react';
import type { Module } from '@/types/modules';

export interface NavItem {
    path: string;
    icon: typeof LayoutDashboard;
    label: string;
    module: Module;
}

export const NAV_ITEMS: NavItem[] = [
    { path: '/dashboard', icon: LayoutDashboard, label: 'Dashboard', module: 'dashboard' },
    { path: '/operations', icon: Truck, label: 'Operaciones', module: 'operations' },
    { path: '/inventory', icon: Package, label: 'Inventarios', module: 'inventory' },
    { path: '/customs', icon: Gavel, label: 'Aduanas', module: 'customs' },
    { path: '/billing', icon: FileText, label: 'Facturación', module: 'billing' },
    { path: '/finance', icon: Wallet, label: 'Finanzas', module: 'finance' },
    { path: '/commercial', icon: Users, label: 'Comercial', module: 'commercial' },
    { path: '/claims', icon: MessageSquareWarning, label: 'Reclamaciones', module: 'claims' },
    { path: '/documents', icon: Files, label: 'Documentos', module: 'documents' },
    { path: '/data', icon: Database, label: 'Datos / Importación', module: 'data' },
    { path: '/tracking', icon: MapPin, label: 'Tracking & GPS', module: 'tracking' },
    { path: '/reports', icon: BarChart3, label: 'Reportes / BI', module: 'reports' },
    { path: '/security', icon: Settings, label: 'Seguridad', module: 'security' },
];

export const ROUTE_TITLES: Record<string, string> = {
    '/dashboard': 'Dashboard Operativo',
    '/operations': 'Operaciones y Logística',
    '/inventory': 'Inventarios y Almacén',
    '/customs': 'Aduanas y Anexo 24',
    '/billing': 'Facturación y CFDI 4.0',
    '/finance': 'Finanzas operativas',
    '/commercial': 'Comercial y CRM',
    '/claims': 'Claims & Customer Service 360',
    '/documents': 'Documents 360',
    '/data': 'Data Operations 360',
    '/tracking': 'Tracking y GPS',
    '/reports': 'Reportes y BI',
    '/security': 'Seguridad y Configuración',
};
