# Implementación de Auth + RBAC en módulo de Tracking

## Migraciones Supabase ejecutadas
1. **`memberships_role_constraint`**: Agregado el `CHECK constraint` en la columna `role` (`admin`, `operator`, `viewer`), después de inicializar a los existentes con `operator`.
2. **`harden_tracking_admin_rpcs`**: Modificadas `rpc_create_tracking_token` y `rpc_revoke_tracking_token` con una guarda condicional `auth.uid() IS NOT NULL` verificando si el llamador (`admin` o `operator`) pertenece directamente al `tenant_id` objetivo del token. (Previene cross-tenant admin exploits).
3. **`rpc_get_my_context`**: Creada función RPC (`SECURITY DEFINER`) para obtener el listado activo de memberships para el usuario autenticado desde Postgres.
4. **`enable_auth_rls`**: Activado progresivamente Row Level Security para las tablas `memberships`, `tenants` y `operations` con sus políticas de selección filtradas por `auth.uid()`.

## Implementación en Frontend (Zustand + React Router)
1. **Estado manejado con Zustand (`authStore.ts`)**: Se guarda la `Session`, membresías del usuario (`context`) y el `activeTenant` en memoria cache local usando storage asíncrono configurado a `sessionStorage`.
2. **Setup de Supabase (`lib/supabase.ts`)**: Cliente simple usando environment variables locales.
3. **Auth y Session Persistence (`auth.service.ts`)**: Servicio para llamar a `rpc_get_my_context` cada vez que hay recarga o sign-in con Supabase Auth event listener.
4. **Protección de Rutas (`AuthGuard.tsx` + `RoleGuard.tsx`)**:
   - `AuthGuard`: Revisa la sesión base de Supabase y de manera bloqueante re-carga el contexto antes de abrir `AppLayout`. Redirecciona al usuario a `/login` si es fallido.
   - `RoleGuard`: Filtra hijos mediante validación del rol contra `getRole()` (en el Tracking page especificamos `['admin', 'operator', 'viewer']`).
5. **UI Restringida para 'viewers' (`TrackingPage.tsx`)**: Eliminadas renderizaciones de botones de "Revocar Enlace" y "Configuración" interactivas para solo-lectura sí el AuthStore verifica rol de viewer.

## Pruebas de Sistema superadas
- [x] TypeScript types checker completo y exitoso.
- [x] Reglas RBAC en Frontend y Backend aplicadas y sincrónicas.
- [x] Prevención de vulnerabilidades *Cross-Tenant* para las RPC Security Definer.
