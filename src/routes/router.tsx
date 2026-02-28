import { createBrowserRouter, Navigate } from 'react-router-dom';
import { AppLayout } from '@/layout/AppLayout';
import { AuthGuard } from '@/components/AuthGuard';
import { RoleGuard } from '@/components/RoleGuard';
import DashboardPage from '@/pages/DashboardPage';
import OperationsPage from '@/pages/OperationsPage';
import InventoryPage from '@/pages/InventoryPage';
import CustomsPage from '@/pages/CustomsPage';
import BillingPage from '@/pages/BillingPage';
import FinancePage from '@/pages/FinancePage';
import CommercialPage from '@/pages/CommercialPage';
import TrackingPage from '@/pages/TrackingPage';
import TrackingPublicPage from '@/pages/TrackingPublicPage';
import DriverTrackingPage from '@/pages/DriverTrackingPage';
import ReportsPage from '@/pages/ReportsPage';
import SecurityPage from '@/pages/SecurityPage';
import SecurityUsersPage from '@/pages/SecurityUsersPage';
import SecurityAuditPage from '@/pages/SecurityAuditPage';
import SettingsPage from '@/pages/SettingsPage';
import LoginPage from '@/pages/LoginPage';
import InvitePage from '@/pages/InvitePage';

export const router = createBrowserRouter([
    {
        path: '/login',
        element: <LoginPage />
    },
    {
        path: '/',
        children: [
            {
                index: true,
                element: <LoginPage />
            },
            {
                element: <AuthGuard />,
                children: [
                    {
                        element: <AppLayout />,
                        children: [
                            { path: 'dashboard', element: <DashboardPage /> },
                            { path: 'operations', element: <OperationsPage /> },
                            { path: 'inventory', element: <InventoryPage /> },
                            { path: 'customs', element: <CustomsPage /> },
                            { path: 'billing', element: <BillingPage /> },
                            { path: 'finance', element: <FinancePage /> },
                            { path: 'commercial', element: <CommercialPage /> },
                            {
                                element: <RoleGuard allowedRoles={['admin', 'operator', 'viewer']} />,
                                children: [
                                    { path: 'tracking', element: <TrackingPage /> },
                                ]
                            },
                            { path: 'reports', element: <ReportsPage /> },
                            {
                                path: 'security',
                                element: <SecurityPage />,
                                children: [
                                    { index: true, element: <Navigate to="users" replace /> },
                                    { path: 'users', element: <SecurityUsersPage /> },
                                    { path: 'audit', element: <SecurityAuditPage /> },
                                    { path: 'settings', element: <SettingsPage /> },
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
        element: <TrackingPublicPage />
    },
    {
        path: '/driver/:token',
        element: <DriverTrackingPage />
    },
    {
        path: '/invite/:token',
        element: <InvitePage />
    },
    {
        path: '/demo/public/:token',
        element: <TrackingPublicPage />
    },
    {
        path: '/demo/driver/:token',
        element: <DriverTrackingPage />
    }
]);
