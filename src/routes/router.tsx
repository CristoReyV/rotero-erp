import { createBrowserRouter, Navigate } from 'react-router-dom';
import { lazy, type ReactNode, Suspense } from 'react';
import { AppLayout } from '@/layout/AppLayout';
import { AuthGuard } from '@/components/AuthGuard';
import { RoleGuard } from '@/components/RoleGuard';
import { ROTERO_ENABLED_ROLES } from '@/constants/roles';

const DashboardPage = lazy(() => import('@/pages/CompanyDashboardPage'));
const OperationsPage = lazy(() => import('@/pages/CompanyOperationsPage'));
const BillingPage = lazy(() => import('@/pages/CompanyBillingPage'));
const FinancePage = lazy(() => import('@/pages/CompanyFinancePage'));
const DocumentsPage = lazy(() => import('@/pages/CompanyDocumentsPage'));
const TrackingPublicPage = lazy(() => import('@/pages/TrackingPublicPage'));
const DriverTrackingPage = lazy(() => import('@/pages/DriverTrackingPage'));
const ReportsPage = lazy(() => import('@/pages/ReportsPage'));
const SecurityPage = lazy(() => import('@/pages/SecurityPage'));
const SecurityUsersPage = lazy(() => import('@/pages/SecurityUsersPage'));
const SecurityAuditPage = lazy(() => import('@/pages/SecurityAuditPage'));
const SettingsPage = lazy(() => import('@/pages/SettingsPage'));
const AutomationsPage = lazy(() => import('@/pages/AutomationsPage'));
const LoginPage = lazy(() => import('@/pages/LoginPage'));

const page = (element: ReactNode) => (
    <Suspense fallback={<div className='p-10 text-center text-sm text-slate-400'>Cargando módulo…</div>}>
        {element}
    </Suspense>
);

export const router = createBrowserRouter([
    {
        path: '/login',
        element: page(<LoginPage />),
    },
    {
        path: '/',
        children: [
            {
                index: true,
                element: page(<LoginPage />),
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
                                    { path: 'documents', element: page(<DocumentsPage />) },
                                ],
                            },
                            {
                                element: <RoleGuard allowedRoles={['admin', 'finance']} />,
                                children: [
                                    { path: 'billing', element: page(<BillingPage />) },
                                    { path: 'finance', element: page(<FinancePage />) },
                                    { path: 'reports', element: page(<ReportsPage />) },
                                ],
                            },
                            {
                                element: <RoleGuard allowedRoles={['admin']} />,
                                children: [
                                    { path: 'inventory', element: <p role="status">Inventarios está pendiente de autorización por empresa.</p> },
                                    { path: 'customs', element: <p role="status">Aduanas está pendiente de autorización por empresa.</p> },
                                    { path: 'commercial', element: <p role="status">Comercial está pendiente de autorización por empresa.</p> },
                                    { path: 'claims', element: <p role="status">Reclamaciones está pendiente de autorización por empresa.</p> },
                                    { path: 'data', element: <p role="status">La importación de datos está pendiente de conciliación y aprobación.</p> },
                                    { path: 'tracking', element: <Navigate to='/operations' replace /> },
                                    {
                                        path: 'security',
                                        element: page(<SecurityPage />),
                                        children: [
                                            { index: true, element: <Navigate to='users' replace /> },
                                            { path: 'users', element: page(<SecurityUsersPage />) },
                                            { path: 'audit', element: page(<SecurityAuditPage />) },
                                            { path: 'settings', element: page(<SettingsPage />) },
                                            { path: 'automations', element: page(<AutomationsPage />) },
                                        ],
                                    },
                                ],
                            },
                            { path: '*', element: <Navigate to='/dashboard' replace /> },
                        ],
                    },
                ],
            },
        ],
    },
    {
        path: '/t/:token',
        element: page(<TrackingPublicPage />),
    },
    {
        path: '/driver/:token',
        element: page(<DriverTrackingPage />),
    },
    {
        path: '/invite/:token',
        element: <Navigate to='/login' replace />,
    },
    {
        path: '/demo/public/:token',
        element: page(<TrackingPublicPage />),
    },
    {
        path: '/demo/driver/:token',
        element: page(<DriverTrackingPage />),
    },
]);
