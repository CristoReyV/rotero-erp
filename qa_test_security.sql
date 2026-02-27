/* 
========================================================================
  QA DURO DE SEGURIDAD (RLS / RBAC / CROSS-TENANT)
========================================================================
Este script está diseñado para ejecutarse en el SQL Editor de Supabase.

INSTRUCCIONES:
1. Asegúrate de haber ejecutado las migraciones de seguridad primero 
   (o que el backend ya tenga los guards y RLS activos).
2. Busca el UUID de un usuario "Admin de Tenant A" y un "Viewer de Tenant A".
   Puedes encontrarlos en la tabla auth.users o memberships.
3. Reemplaza el parámetro '<USER_ID>' abajo con el UUID real.
4. Ejecuta los bloques (Testeando A, B, C...) uno por uno.
*/

-- 1. Helper para reiniciar tu sesión en el SQL Editor y volver a ser Admin global
-- (Ejecuta esto si terminaste de probar o te bloqueaste)
SELECT set_config('role', 'postgres', true);
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claim.sub', '', true);

-- ========================================================================
-- CASO 1: COMO USUARIO "ADMIN DEL TENANT A"
-- ========================================================================

-- A) Simular sesión:
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '<INGRESA_AQUI_UUID_ADMIN_TENANT_A>', true);

-- B) Prueba RLS de Membresías
-- Resultado Esperado: Debe retornar SOLO las filas de SU tenant. Jamás membresías de otros tenants.
SELECT * FROM memberships;

-- C) Prueba RLS de Operaciones
-- Resultado Esperado: Debe retornar SOLO operaciones de su Tenant. No cruzadas.
SELECT * FROM operations;

-- D) Prueba de Inyección de Tenant Ajeno en RPC (Crear Token)
-- Instrucción: Pon aquí un ID Válido de la tabla "tenants" y "operations", 
-- PERO que pertenezcan al Tenant B.
SELECT rpc_create_tracking_token(
    '<UUID_TENANT_B>', 
    '<UUID_OPERACION_TENANT_B>', 
    'driver:write'
);
-- Resultado Esperado: {"error": "unauthorized"}

-- E) Prueba de Revocación de Token Ajeno en RPC
-- Instrucción: Pon aquí un ID Válido de un "tracking_token" que sea del Tenant B.
SELECT rpc_revoke_tracking_token('<UUID_TOKEN_TENANT_B>');
-- Resultado Esperado: {"error": "unauthorized"}

-- F) Intentar Bypass Directo (Insert manual)
-- Resultado Esperado: "new row violates row-level security policy for table operations" o nada insertado.
INSERT INTO operations (tenant_id, internal_ref, status) 
VALUES ('<UUID_TENANT_B>', 'HACK', 'draft');


-- ========================================================================
-- CASO 2: COMO USUARIO "VIEWER DEL TENANT A"
-- ========================================================================

-- A) Simular sesión de VIEWER
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '<INGRESA_AQUI_UUID_VIEWER_TENANT_A>', true);

-- B) Prueba RLS: El viewer sí debe poder leer sus operaciones
-- Resultado Esperado: Filas del Tenant A se muestran normales.
SELECT * FROM operations;

-- C) Prueba RPC "Crear": El viewer de Tenant A intenta crear un link para Tenant A
SELECT rpc_create_tracking_token(
    '<UUID_TENANT_A>', 
    '<UUID_OPERACION_TENANT_A>', 
    'public:read'
);
-- Resultado Esperado: {"error": "unauthorized"} (porque rol != admin/operator)

-- D) Prueba RPC "Revocar": El viewer intenta revocar
SELECT rpc_revoke_tracking_token('<UUID_TOKEN_TENANT_A>');
-- Resultado Esperado: {"error": "unauthorized"}
