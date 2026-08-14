import React from 'react';
import { Navigate, Outlet } from 'react-router-dom';
import { useAuthStore } from '@/store/authStore';
import { isRoteroEnabledRole, type ProductRole } from '@/constants/roles';

interface RoleGuardProps {
    allowedRoles: readonly ProductRole[];
}

export const RoleGuard: React.FC<RoleGuardProps> = ({ allowedRoles }) => {
    const role = useAuthStore(state => state.getRole());

    if (!role || !isRoteroEnabledRole(role)) {
        return <Navigate to="/dashboard" replace />;
    }

    if (!allowedRoles.includes(role)) {
        return <Navigate to="/dashboard" replace />;
    }

    return <Outlet />;
};
