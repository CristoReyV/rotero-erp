import { createBrowserRouter, Navigate } from 'react-router-dom';
import { lazy, Suspense, type ReactNode } from 'react';
import { AppLayout } from '@/layout/AppLayout';
import { AuthGuard } from '@/components/AuthGuard';
import { RoleGuard } from '@/components/RoleGuard';
import { ROTERO_ENABLED_ROLES } from '@/constants/roles';

const DashboardPage=lazy(()=>import('@/pages/DashboardPage')); const OperationsPage=lazy(()=>import('@/pages/OperationsPage'));
const InventoryPage=lazy(()=>import('@/pages/InventoryPage')); const CustomsPage=lazy(()=>import('@/pages/CustomsPage'));
const BillingPage=lazy(()=>import('@/pages/BillingPage')); const FinancePage=lazy(()=>import('@/pages/FinancePage'));
const CommercialPage=lazy(()=>import('@/pages/CommercialPage')); const DocumentsPage=lazy(()=>import('@/pages/DocumentsPage'));
const DataOperationsPage=lazy(()=>import('@/pages/DataOperationsPage')); const TrackingPage=lazy(()=>import('@/pages/TrackingPage'));
const TrackingPublicPage=lazy(()=>import('@/pages/TrackingPublicPage')); const DriverTrackingPage=lazy(()=>import('@/pages/DriverTrackingPage'));
const ReportsPage=lazy(()=>import('@/pages/ReportsPage')); const SecurityPage=lazy(()=>import('@/pages/SecurityPage'));
const SecurityUsersPage=lazy(()=>import('@/pages/SecurityUsersPage')); const SecurityAuditPage=lazy(()=>import('@/pages/SecurityAuditPage'));
const SettingsPage=lazy(()=>import('@/pages/SettingsPage')); const AutomationsPage=lazy(()=>import('@/pages/AutomationsPage'));
const ClaimsPage=lazy(()=>import('@/pages/ClaimsPage')); const LoginPage=lazy(()=>import('@/pages/LoginPage'));

const page=(element:ReactNode)=><Suspense fallback={<div className="p-10 text-center text-sm text-slate-400">Cargando módulo…</div>}>{element}</Suspense>;

export const router = createBrowserRouter([
    {
        path: '/login',
        element: page(<LoginPage />)
    },
    {
        path: '/',
        children: [
            {
                index: true,
                element: page(<LoginPage />)
            },
            {
                element: <AuthGuard />,
                children: [
                    {
                        element: <AppLayout />,
                        children: [
                            {
                                element: <RoleGuard allowedRoles={ROTERO_ENABLED_ROLES} />,
                                children: [
                                    { path: 'dashboard', element: page(<DashboardPage />) },
                                    { path: 'operations', element: page(<OperationsPage />) },
                                    { path: 'billing', element: page(<BillingPage />) },
                                    { path: 'finance', element: page(<FinancePage />) },
                                    { path: 'reports', element: page(<ReportsPage />) },
                                    { path: 'documents', element: page(<DocumentsPage />) },
                                ]
                            },
                            {
                                element: <RoleGuard allowedRoles={['admin']} />,
                                children: [
                                    { path: 'inventory', element: page(<InventoryPage />) },
                                    { path: 'customs', element: page(<CustomsPage />) },
                                    { path: 'commercial', element: page(<CommercialPage />) },
                                    { path: 'claims', element: page(<ClaimsPage />) },
                                    { path: 'data', element: page(<DataOperationsPage />) },
                                    { path: 'tracking', element: page(<TrackingPage />) },
                                    {
                                        path: 'security',
                                        element: page(<SecurityPage />),
                                        children: [
                                            { index: true, element: <Navigate to="users" replace /> },
                                            { path: 'users', element: page(<SecurityUsersPage />) },
                                            { path: 'audit', element: page(<SecurityAuditPage />) },
                                            { path: 'settings', element: page(<SettingsPage />) },
                                            { path: 'automations', element: page(<AutomationsPage />) },
                                        ]
                                    },
                                ]
                            },
                            { path: '*', element: <Navigate to="/dashboard" replace /> },
                        ]
                    }
                ]
            }
        ],
    },
    {
        path: '/t/:token',
        element: page(<TrackingPublicPage />)
    },
    {
        path: '/driver/:token',
        element: page(<DriverTrackingPage />)
    },
    {
        path: '/invite/:token',
        element: <Navigate to="/login" replace />
    },
    {
        path: '/demo/public/:token',
        element: page(<TrackingPublicPage />)
    },
    {
        path: '/demo/driver/:token',
        element: page(<DriverTrackingPage />)
    }
]);
