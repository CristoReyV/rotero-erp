import type { UserRecord, AuditLog } from '@/types/security';

// TODO: Replace with security.service.ts → rpc_list_users
export const MOCK_USERS: UserRecord[] = [
    { name: 'Maria Gonzalez', role: 'Compliance Officer', status: 'Activo', last: 'Hace 5 min' },
    { name: 'Juan Perez', role: 'Warehouse Manager', status: 'Activo', last: 'Hoy, 10:42 AM' },
    { name: 'Sofia Ramirez', role: 'External Auditor', status: 'Inactivo', last: 'Ayer' },
    { name: 'Admin Rotero', role: 'Super Admin', status: 'Activo', last: 'Ahora' },
];

// TODO: Replace with security.service.ts → rpc_list_audit_logs
export const MOCK_AUDIT_LOGS: AuditLog[] = [
    { time: '10:42 AM', user: 'J. Perez', event: 'Login Exitoso', color: 'bg-emerald-500' },
    { time: '10:30 AM', user: 'M. Gonzalez', event: 'Generación CFDI #A-4022', color: 'bg-blue-500' },
    { time: '09:15 AM', user: 'Admin', event: 'Cambio de Permisos', color: 'bg-amber-500' },
    { time: 'Ayer, 11:59 PM', user: 'Unknown', event: 'Intento Fallido (x5)', color: 'bg-red-500' },
];

// Async wrappers for future service swap (SF-02)
export async function getMockUsers() { return MOCK_USERS; }
export async function getMockAuditLogs() { return MOCK_AUDIT_LOGS; }
