import React from 'react';
import { Navigate, Outlet } from 'react-router-dom';
import { useAuthStore } from '@/store/authStore';

interface RoleGuardProps {
    allowedRoles: ('admin' | 'operator' | 'viewer')[];
}

export const RoleGuard: React.FC<RoleGuardProps> = ({ allowedRoles }) => {
    const role = useAuthStore(state => state.getRole());

    if (!role) {
        return <Navigate to="/dashboard" replace />;
    }

    if (!allowedRoles.includes(role)) {
        return <Navigate to="/dashboard" replace />;
    }

    return <Outlet />;
};
