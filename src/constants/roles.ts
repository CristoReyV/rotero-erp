/**
 * Roles and permissions per Architecture §3.2
 * Enforcement is server-side (RLS + RPC). These constants are for reference
 * and future use in route guards and UI conditional rendering.
 */

export const ROLES = {
    super_admin: { label: 'Super Admin', modules: 'all' },
    director: { label: 'Director General', modules: 'all' },
    ops_director: { label: 'Director Operativo', modules: ['dashboard', 'operations', 'inventory', 'customs', 'reports'] },
    ops_coordinator: { label: 'Coordinador Logístico', modules: ['operations', 'inventory'] },
    customs_agent: { label: 'Agente Aduanal', modules: ['customs', 'inventory'] },
    billing_admin: { label: 'Administrador Fiscal', modules: ['billing', 'finance'] },
    sales_exec: { label: 'Ejecutivo Comercial', modules: ['commercial', 'dashboard'] },
    warehouse: { label: 'Almacenista', modules: ['inventory'] },
    auditor: { label: 'Auditor Externo', modules: ['security', 'reports', 'customs'] },
    accountant: { label: 'Contador', modules: ['billing', 'finance', 'reports'] },
} as const;

export type RoleCode = keyof typeof ROLES;
