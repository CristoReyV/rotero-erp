# MULTI-04: empresas y acceso explícito cerrado

Base de implementación: `55cffc06fe3cc5e44c093c55c9dd6cad187567e7`.
Primer bloque de MULTI-03; no habilita multiempresa en los módulos actuales.

## Contrato nuevo

- `companies`: UUID, tenant, nombre comercial editable, razón social, RFC
  normalizado, estado draft/active/inactive y timestamps. RFC único por tenant;
  su validación es estructural, no una autorización fiscal. Empieza en draft.
- `membership_company_access`: acceso explícito de un usuario del tenant a una
  empresa del mismo tenant; concesión, vigencia y revocación trazables.
- Se reutiliza la clave canónica `(user_id, tenant_id)` de `memberships`, en vez
  de añadir otra clave a esa tabla o duplicar `membership_id` y `user_id`.
  Esto resuelve la variación física de MULTI-03 sin alterar memberships.
- FKs compuestas impiden empresa ajena al tenant y usuario sin esa membership.
  `ON DELETE RESTRICT` conserva referencias. Una asignación revocada también
  conserva su vínculo: una futura baja de membership debe resolver esta
  dependencia explícitamente, sin borrar el historial por cascada.
- Nombres no son claves. No existe default de empresa, wildcard, consolidado,
  capacidades financieras, semillas de WLS ni asignaciones personales.

## Cierre y helper

Ambas tablas tienen RLS y carecen de grants para PUBLIC, anon, authenticated y
service_role. No hay policies de escritura, RPC públicos, selector o consumidores
UI. Incluso un actor con concesión explícita no obtiene SELECT directo.

`private.multi04_has_company_access(uuid,uuid)` sólo devuelve un booleano para
el sujeto autenticado: concesión activa y vigente en empresa activa. No recibe user_id,
no compara nombres/email/metadata, no consulta el rol de producto y no autoriza
finanzas ni módulos. Null, empresa ajena o concesión ausente no concede acceso.
Sólo authenticated puede ejecutarlo en el esquema privado ya existente; no se
añade ese esquema a la API.

El helper usa SECURITY DEFINER con search_path vacío y referencias cualificadas.
Su propietario NOLOGIN `rotero_company_access_owner` no tiene SUPERUSER,
BYPASSRLS, CREATEROLE, CREATEDB, REPLICATION o acceso a tablas de negocio
existentes. En este primer bloque posee las dos tablas nuevas; esa propiedad permite leerlas sin
recursión de RLS. Por ello no se usa FORCE RLS sobre estas raíces. No se concede
el rol propietario a las identidades API. La extensión local
[MULTI-05](MULTI05_CAPABILITIES.md) reutiliza ese propietario para sus tablas de
concesiones cerradas, sin añadirle acceso a tablas de negocio existentes.

El administrador que ejecuta la migración recibe SET, sin INHERIT, sobre ese
propietario para mantenimiento/transferencia en PostgreSQL 17. CREATE en public
y private sólo se concede durante la transacción para transferir propiedad y
se revoca antes del commit. No se cambian los grants de los módulos existentes.
Sólo se añade al rol nuevo USAGE de public/private. El administrador local no es
superusuario ni puede conceder USAGE de auth. El helper lee el sub del contexto
autenticado de la solicitud con la misma precedencia que auth.uid() instalado
(claim.sub y después claims.sub); no lee user_metadata ni recibe una identidad
del cliente como parámetro. La suite contrasta ambos formatos, precedencia y
ausencia de identidad con auth.uid(). No se modifican permisos de Auth.

Las policies SELECT son defensa adicional: una futura concesión SELECT revisada
seguiría limitada a empresas explícitas y filas propias activas. Este bloque no
incluye esa concesión. No se debe añadir como atajo para implementar el selector.

## Validación local

Migración: `supabase/migrations/20261019171829_multi04_companies_explicit_access.sql`.
Suite: `supabase/tests/multi04_companies_explicit_access.sql`.

La suite requiere una base Supabase **local, nueva, desechable y sin semillas**,
con la línea activa de migraciones reproducida. No ejecutar sobre remoto o una
base de trabajo con empresas existentes. Usa datos sintéticos, no crea usuarios
Auth y revierte todo con ROLLBACK. Después comprueba ausencia de residuos y de
grants temporales. Asume explícitamente el propietario sólo para conceder los
permisos temporales de fixtures al ejecutor y los permisos de prueba de RLS;
todo queda dentro de la transacción que se revierte, sin INHERIT permanente.

Cubre:

- PK/FK, duplicados, RFC inválido, empresa/tenant incompatibles, usuario sin
  membership y referencias inexistentes; renombrado sin cambiar UUID.
- Admin/finance sin asignación denegados, metadata sin efecto; concesiones
  explícitas positivas, empresa ajena/otro tenant/null/no asignado denegados.
- SELECT, JSON, INSERT, UPDATE, DELETE, TRUNCATE y ALTER directos denegados;
  intentos de autoasignación o reasignar tenant; anon/service_role denegados.
- ACLs efectivos y propietario mínimo. En un tramo exclusivo del test se
  conceden permisos temporales de tablas para probar RLS real por separado:
  lectura propia positiva, lectura ajena vacía y ausencia de escritura.
- Empresa draft/inactiva, concesiones futuras/expiradas/revocadas denegadas,
  integridad de referencias y limpieza transaccional.

Las verificaciones estáticas, lint o build no sustituyen la ejecución de esta
suite SQL. El informe de ejecución debe indicar si pudo arrancar el runtime,
resultados/errores y comprobación de limpieza. No contar casos como aprobados
por revisar el texto de una policy.

Para arrancar una pila, reutilizar el ejecutable loopback aprobado previamente,
comprobando su SHA-256, con proyecto/red/carpeta/puertos nuevos. Verificar bindings
127.0.0.1 antes de SQL/API; no usar datos reales ni reparar Docker, actualizar
WSL o sustituir el CLI como efecto lateral. Ejecutar la suite mediante psql
dentro del contenedor nuevo, ON_ERROR_STOP activado. Si hay error, cerrar esa
conexión revierte su transacción; inspeccionar residuos sólo en esa base y
limpiar exclusivamente recursos creados para la prueba. No resetear otras pilas.

Validación efectiva del bloque (2026-10-19): replay limpio de las 39 migraciones
base más ésta en PostgreSQL 17.6, suite MULTI-04 y contratos consumidos aprobados.
ACLs de tabla/columna cerrados, positivos y denegaciones del helper, RLS bajo
grants temporales y rollback sin residuos comprobados por ejecución. No se
crearon usuarios Auth. Publicaciones sólo en 127.0.0.1 y pila propia retirada.
El baseline histórico rechazaba el search_path vacío de rpc_reports_tanda1, ya
presente antes del bloque y con referencias de aplicación calificadas por
esquema. MULTI-04R incorpora en `supabase/tests/db_baseline_contract.sql` el
ajuste probado primero en una copia temporal: aceptar también el valor vacío
exacto. Mantiene la comprobación para todas las funciones SECURITY DEFINER de
public; no acepta un search_path ausente ni una ruta sólo pública/controlable
por el llamador. No se alteraron migraciones históricas ni contratos consumidos.
Esto no aprueba el aislamiento de módulos actuales ni un despliegue remoto.

## Límites y siguiente bloque

No se aplica ninguna migración remota ni se cambian usuarios, asignaciones,
Reportes, fiscal, Storage, operaciones o permisos de los módulos actuales.
Los contratos tenant-only existentes **no adquieren aislamiento empresarial**
por añadir estas tablas. Tampoco se corrige aquí su autorización financiera.

Acceso empresarial, capacidades de trabajo, lectura financiera completa y
consolidación seguirán separados. Las únicas personas aprobadas para lectura
financiera completa WLS y consolidado son Luis Roberto Santamaria, Jhoselin
Santamaria y Karina Pineda. Sus bindings a cuentas verificadas siguen pendientes;
no se inventan correos/UUID ni se asigna acceso a QA/admin/finance por su rol.
Esto no restringe implícitamente otras funciones laborales actuales.

Se preservan las identidades aprobadas para una fase de inicialización posterior:
ROTERO / WORLD'S LOGISTIC SOLUTIONS ROTERO / WLS110325JH8 y ROTERITO / WLS ROTERO /
WRO2507109E0. No se insertan ahora. ROTERO sólo podrá ser default si está
autorizada. El concentrado Excel sigue como referencia, sin importación.

Siguiente bloque: capacidades por empresa, bindings financieros verificados y
grant separado de consolidación, todavía sin conectar módulos o asignar personas
sin verificación. Después adaptar contratos/proyecciones por empresa antes de
habilitar selector o acceso empresarial en el ERP.

Antes de aplicar esta migración en cualquier target: reconciliar schema-only y
privilegios de su administrador y revisar el delta. Un reset sólo de base puede
conservar roles: se reutiliza exclusivamente el propietario marcado por MULTI-04
si conserva todos los atributos mínimos y no tiene relaciones con roles API.
Un rol homónimo ajeno o alterado hace fallar la migración. Los objetos de tablas
existentes tampoco se adoptan. La migración es transaccional, sin replay manual
ciego. Si se revierte antes de activar, mantener raíces cerradas; no borrar documentos o
movimientos ni restaurar grants tenant-wide como supuesto rollback.

Referencias de seguridad consultadas: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[funciones](https://supabase.com/docs/guides/database/functions),
[GRANT PostgreSQL 17](https://www.postgresql.org/docs/17/sql-grant.html) y
[cambio de propietario](https://www.postgresql.org/docs/17/sql-altertable.html).
