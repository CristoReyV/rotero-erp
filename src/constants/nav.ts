import {
    LayoutDashboard,
    Truck,
    FileText,
    Wallet,
    BarChart3,
    Settings,
    Files,
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
    { path: '/billing', icon: FileText, label: 'Facturación', module: 'billing' },
    { path: '/finance', icon: Wallet, label: 'Finanzas', module: 'finance' },
    { path: '/documents', icon: Files, label: 'Documentos', module: 'documents' },
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
