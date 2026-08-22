import assert from 'node:assert/strict';
import {
    PRODUCT_ROLES,
    ROTERO_ENABLED_ROLES,
    ROTERO_PROVISIONABLE_ROLES,
    canAccessRoteroModule,
    canManageRoteroModule,
    canProductRoleAccessModule,
    canProductRoleManageDocumentContext,
    canProductRoleManageModule,
    findRoteroEnabledTenantId,
    isProductRole,
    isRoteroEnabledRole,
    isRoteroProvisionableRole,
} from './roles';
import type { Module } from '@/types/modules';

const ALL_MODULES: Module[] = [
    'dashboard',
    'operations',
    'inventory',
    'customs',
    'billing',
    'finance',
    'commercial',
    'documents',
    'data',
    'tracking',
    'reports',
    'security',
];

assert.deepEqual(PRODUCT_ROLES, ['admin', 'operator', 'finance', 'viewer']);
assert.deepEqual(ROTERO_ENABLED_ROLES, ['admin', 'finance']);
assert.deepEqual(ROTERO_PROVISIONABLE_ROLES, ['admin', 'finance']);

for (const role of PRODUCT_ROLES) assert.equal(isProductRole(role), true);
assert.equal(isProductRole('customer'), false);

for (const module of ALL_MODULES) {
    assert.equal(canProductRoleAccessModule('admin', module), true);
    assert.equal(canProductRoleManageModule('admin', module), true);
    assert.equal(canAccessRoteroModule('admin', module), true);
    assert.equal(canManageRoteroModule('admin', module), true);
}

for (const module of ['dashboard', 'operations', 'billing', 'finance', 'documents', 'reports'] as Module[]) {
    assert.equal(canAccessRoteroModule('finance', module), true);
}
for (const module of ['billing', 'finance', 'documents'] as Module[]) {
    assert.equal(canManageRoteroModule('finance', module), true);
}
for (const module of ['operations', 'inventory', 'customs', 'commercial', 'data', 'tracking', 'security'] as Module[]) {
    assert.equal(canManageRoteroModule('finance', module), false);
}
for (const module of ['inventory', 'customs', 'commercial', 'data', 'tracking', 'security'] as Module[]) {
    assert.equal(canAccessRoteroModule('finance', module), false);
}

assert.equal(canProductRoleAccessModule('operator', 'operations'), true);
assert.equal(canProductRoleManageModule('operator', 'operations'), true);
assert.equal(canProductRoleAccessModule('viewer', 'operations'), true);
assert.equal(canProductRoleManageModule('viewer', 'operations'), false);
assert.equal(canProductRoleManageDocumentContext('finance', 'operations'), true);
assert.equal(canProductRoleManageDocumentContext('finance', 'commercial'), false);
assert.equal(canProductRoleManageDocumentContext('operator', 'commercial'), true);
assert.equal(canProductRoleManageDocumentContext('viewer', 'operations'), false);

for (const role of ['operator', 'viewer'] as const) {
    assert.equal(isRoteroEnabledRole(role), false);
    assert.equal(isRoteroProvisionableRole(role), false);
    for (const module of ALL_MODULES) {
        assert.equal(canAccessRoteroModule(role, module), false);
        assert.equal(canManageRoteroModule(role, module), false);
    }
}

assert.equal(isRoteroProvisionableRole('admin'), true);
assert.equal(isRoteroProvisionableRole('finance'), true);
assert.equal(canAccessRoteroModule(null, 'dashboard'), false);

const memberships = [
    { tenant_id: 'tenant-operator', role: 'operator' as const },
    { tenant_id: 'tenant-finance', role: 'finance' as const },
    { tenant_id: 'tenant-admin', role: 'admin' as const },
];
assert.equal(findRoteroEnabledTenantId(memberships, 'tenant-operator'), 'tenant-finance');
assert.equal(findRoteroEnabledTenantId(memberships, 'tenant-admin'), 'tenant-admin');
assert.equal(findRoteroEnabledTenantId(memberships.slice(0, 1), null), null);
