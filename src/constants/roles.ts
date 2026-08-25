import type { Module } from '@/types/modules';

/** Canonical roles supported by the product and enforced by the backend. */
export const PRODUCT_ROLES = ['admin', 'operator', 'finance', 'viewer'] as const;
export type ProductRole = (typeof PRODUCT_ROLES)[number];

/** Roles enabled for authenticated ERP access in the current ROTERO deployment. */
export const ROTERO_ENABLED_ROLES = ['admin', 'finance'] as const;
export type RoteroEnabledRole = (typeof ROTERO_ENABLED_ROLES)[number];

/** Beta provisioning is manual and limited to the active deployment roles. */
export const ROTERO_PROVISIONABLE_ROLES = ROTERO_ENABLED_ROLES;

export const PRODUCT_ROLE_LABELS: Record<ProductRole, string> = {
    admin: 'Administrador',
    operator: 'Operador',
    finance: 'Finanzas',
    viewer: 'Consulta',
};

const ALL_MODULES: readonly Module[] = [
    'dashboard',
    'operations',
    'inventory',
    'customs',
    'billing',
    'finance',
    'commercial',
    'claims',
    'documents',
    'data',
    'tracking',
    'reports',
    'security',
];

/** Product-level capability contract. Disabled deployment roles remain represented here. */
export const PRODUCT_ROLE_MODULES: Record<ProductRole, readonly Module[]> = {
    admin: ALL_MODULES,
    operator: ['dashboard', 'operations', 'inventory', 'customs', 'commercial', 'documents', 'tracking', 'reports', 'security'],
    finance: ['dashboard', 'operations', 'billing', 'finance', 'documents', 'reports'],
    viewer: ['dashboard', 'operations', 'inventory', 'customs', 'commercial', 'documents', 'tracking', 'reports', 'security'],
};

export const PRODUCT_ROLE_MANAGED_MODULES: Record<ProductRole, readonly Module[]> = {
    admin: ALL_MODULES,
    operator: ['operations', 'inventory', 'customs', 'commercial', 'tracking'],
    finance: ['billing', 'finance', 'documents'],
    viewer: [],
};

export function isProductRole(role: unknown): role is ProductRole {
    return typeof role === 'string' && PRODUCT_ROLES.some((candidate) => candidate === role);
}

export function isRoteroEnabledRole(role: unknown): role is RoteroEnabledRole {
    return typeof role === 'string' && ROTERO_ENABLED_ROLES.some((candidate) => candidate === role);
}

export function isRoteroProvisionableRole(role: unknown): role is RoteroEnabledRole {
    return isRoteroEnabledRole(role);
}

export function canProductRoleAccessModule(role: ProductRole | null, module: Module): boolean {
    return role !== null && PRODUCT_ROLE_MODULES[role].includes(module);
}

export function canProductRoleManageModule(role: ProductRole | null, module: Module): boolean {
    return role !== null && PRODUCT_ROLE_MANAGED_MODULES[role].includes(module);
}

export function canProductRoleManageDocumentContext(role: ProductRole | null, sourceModule: 'operations' | 'commercial' | 'billing' | 'finance' | 'documents' | 'claims'): boolean {
    if (role === 'admin') return true;
    if (role === 'finance') return ['operations', 'billing', 'finance'].includes(sourceModule);
    if (role === 'operator') return ['operations', 'commercial', 'documents'].includes(sourceModule);
    return false;
}

export function canAccessRoteroModule(role: ProductRole | null, module: Module): boolean {
    return isRoteroEnabledRole(role) && canProductRoleAccessModule(role, module);
}

export function canManageRoteroModule(role: ProductRole | null, module: Module): boolean {
    return isRoteroEnabledRole(role) && canProductRoleManageModule(role, module);
}

export function findRoteroEnabledTenantId(
    memberships: ReadonlyArray<{ tenant_id: string; role: ProductRole }>,
    preferredTenantId: string | null,
): string | null {
    const preferred = memberships.find(
        (membership) => membership.tenant_id === preferredTenantId && isRoteroEnabledRole(membership.role),
    );

    return preferred?.tenant_id
        ?? memberships.find((membership) => isRoteroEnabledRole(membership.role))?.tenant_id
        ?? null;
}
