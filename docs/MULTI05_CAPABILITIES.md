# MULTI-05: capacidades y autorización financiera explícitas

Base: `b694b7c1d50df12ab2da40cba48d8151909905b8`. Extensión aditiva de MULTI-04,
sin modificar sus tablas/helpers, usuarios reales, permisos actuales o contratos
de módulos. **Este modelo todavía no protege los datos financieros del ERP.**
RPC, consultas, exportaciones, Storage y jobs deben adoptarlo antes del cutover.

## Modelo cerrado

| Objeto | Propósito e integridad |
|---|---|
| `membership_company_access` (existente) | Prerrequisito vigente por tenant/usuario/empresa; se reutiliza, no se duplica |
| `membership_company_capabilities` | Una fila por acceso+capacidad; FK compuesta al acceso existente. Estado, vigencia, otorgante y referencia de aprobación. Sin JSON arbitrario ni grants por rol |
| `private.financial_principal_bindings` | Vinculación de una persona aprobada a UUID Auth e issuer verificados; FK a membership. Tipo verified_human, evidencia, verificador, fechas y revocación. Sin API administrativa ordinaria |
| `membership_consolidation_grants` | Concesión distinta, una por usuario/tenant, vinculada a la misma identidad verificada. Estado, vigencia, otorgante y aprobación |
| `consolidation_grant_companies` | Conjunto explícito por grant. FK al grant del mismo tenant/usuario y a financial.full.read de cada empresa. Sin comodín o ampliación automática |

PK/UNIQUE/FK y CHECK impiden identidades cruzadas, duplicados activos de persona
o cuenta, códigos desconocidos, revocaciones incompletas y vigencias inválidas.
Una capacidad financiera exige binding del mismo tenant/usuario; una laboral
no admite binding como atajo. Una scope row exige que exista financial.full.read;
el helper comprueba además que esté vigente y use el binding del grant.

Las FKs usan DELETE RESTRICT, como MULTI-04. No cambian ni añaden claves a
memberships o company access. El borrado de membership referenciada se rechaza;
no puede dejar concesiones huérfanas. La revocación lógica de acceso/binding/
capacidad/grant corta las comprobaciones siguientes sin borrar su historia.
La suite también retira dependencias sintéticas y elimina una membership para
comprobar la pérdida efectiva. Eso no implementa un procedimiento real de baja
ni autoriza borrar auditoría o concesiones históricas de personas.

## Principales aprobados, todavía sin cuentas

| Código estable de aprobación | Persona autorizada por producto | Estado |
|---|---|---|
| approved_financial_01 | Luis Roberto Santamaria | UUID/issuer/cuenta/membership por verificar |
| approved_financial_02 | Jhoselin Santamaria | UUID/issuer/cuenta/membership por verificar |
| approved_financial_03 | Karina Pineda, contabilidad | UUID/issuer/cuenta/membership por verificar |

Los códigos son slots internos cerrados de aprobación, **no comparaciones de
nombres visibles, correos, roles o metadata**. No identifican por sí mismos una
cuenta. Sólo un procedimiento servidor autorizado fuera de la administración
ordinaria podrá verificar titularidad humana y registrar UUID, issuer, prueba y
aprobador. No se insertan bindings o asignaciones en la migración, ni se asignan
permisos a QA/cuentas técnicas. Las positivas de la suite representan personas
sintéticas en tenants locales sintéticos, sin relación con WLS o cuentas reales.
Los índices impiden dos bindings con estado active para la misma persona o
cuenta, incluso si uno caducó; su sustitución exige revocarlo explícitamente.

Como toda autorización por registros servidor, la veracidad de esa verificación
pertenece a la frontera de confianza administrativa; el esquema no acredita una
persona física por recibir una cadena de texto. Owners/superusuarios de DB no
están contenidos por una promesa de RLS. Usuarios ordinarios no pueden escribir
los registros ni asumir su propietario. Una cuenta recreada/reverificada usa
nuevo binding: los grants antiguos no reviven automáticamente.

## Matriz de capacidades

Todas requieren identidad y acceso empresarial activos/vigentes. Ninguna se
asigna por ser admin/finance, crear empresa, estar en contabilidad o tener acceso
a dos empresas. Las referencias de aprobación son opacas, sin secretos/PII.

| Código / grupo | Requisitos adicionales | Lo que no concede |
|---|---|---|
| operations.read / operations.capture | Concesión explícita de esa acción | Finanzas, consolidado o todas las acciones operativas |
| billing.draft / billing.document.read | Concesión explícita; proyección de tarea futura | Costos/AP, emisión/cancelación fiscal o lectura financiera completa |
| receivables.read | Concesión explícita; proyección AR futura | AP, rentabilidad, pagos o libro general |
| export.operational / export.receivables | Concesión explícita y proyección autorizada futura | Exportación de campos/filas financieros no consultables |
| companies.manage / memberships.manage / company_access.manage | Concesión explícita de administración futura | Vincular personas financieras, otorgar finanzas/consolidado o autoasignarse poderes |
| financial.full.read | Binding humano aprobado vigente, issuer exacto, concesión por empresa ligada a ese binding | Exportar, pagar, modificar, emitir, administrar o consolidar |
| export.financial | Binding vigente + concesión propia + financial.full.read vigente para la misma empresa/binding | Consolidación o más empresas |
| consolidated.read | Grant independiente + conjunto explícito + full.read y acceso vigentes en **cada** empresa solicitada, mismo binding | Empresas futuras/ajenas, permisos faltantes, escritura o exportación financiera implícita |

Los códigos laborales representan el vocabulario propuesto de MULTI-03; su
presencia en CHECK no ratifica asignaciones, campos, objetos o mínimos por
puesto. **No hay permisos laborales habilitados por defecto ni consumidores
nuevos.** La matriz de tarea/otorgantes y sus proyecciones siguen pendientes.
No se incluyen nómina individual, capacidades fiscales ni permisos genéricos
de administración de este registro de concesiones.

## Helpers y contrato de solicitud

- `private.multi05_request_actor()`: parser interno STABLE/SECURITY INVOKER,
  ejecutable sólo por el propietario limitado. Reutiliza el contrato de sujeto
  de MULTI-04/auth.uid(): claim.sub no vacío y luego claims.sub. Issuer proviene
  exclusivamente de las claims autenticadas del gateway; no de parámetros,
  headers o user_metadata. El SQL no verifica una firma JWT: usa el contexto ya
  autenticado, igual que auth.uid(). Un acceso SQL administrativo queda fuera
  de la frontera de usuarios API.
- `private.multi05_has_company_capability(tenant,company,code)`: booleano sobre
  el actor actual; exige acceso existente y grant vigente. Para full.read exige
  binding vigente y issuer exacto. Export financiero exige también full.read
  vigente del mismo binding. No recibe p_user_id y no tiene fallback de rol.
- `private.multi05_can_consolidate(tenant,company_ids)`: booleano sobre el actor
  actual; rechaza null, vacío, duplicados, elementos null, arrays multidimensionales
  o con base distinta de 1. Todas las empresas solicitadas deben estar en su
  grant y conservar full.read del mismo binding. Una empresa insuficiente
  deniega el conjunto completo; nunca lo recorta. Un conjunto de una empresa
  también exige el grant separado. Orden diferente no cambia la autorización.

Los dos booleanos sólo conceden EXECUTE a authenticated en private, esquema no
añadido a Data API. No hay RPC público de lectura/escritura ni selector/contexto
nuevo. El parser no es ejecutable por authenticated. PUBLIC/anon/service_role
no reciben EXECUTE o acceso a las tablas, incluso si service_role omite RLS.

Las cuatro tablas nuevas tienen RLS sin policies y ACL cerradas. La suite prueba
también RLS bajo grants temporales: incluso la identidad autorizada no puede
listar/editar sus bindings o concesiones. Los booleanos SECURITY DEFINER usan
search_path vacío y referencias calificadas, con el mismo NOLOGIN/NOINHERIT
limitado de MULTI-04, ahora propietario de estas cuatro tablas adicionales.
No se le concede lectura de memberships/finanzas ni CREATE permanente de schemas.

El administrador de migración no hereda ese propietario. El DDL obtiene sólo
los REFERENCES de columnas que le falten para crear la FK al acceso existente;
se retiran antes del COMMIT y se preservan los derechos preexistentes. CREATE de
public/private para transferir los objetos también es transitorio. No cambian
ACL efectivos de consumidores previos. Cualquier error revierte la migración.

## Revocación y límites

La siguiente comprobación consulta estado/vigencia actuales de acceso, empresa,
capacidad, binding y grant; claims viejas no contienen una autorización nueva.
Revocar finanzas no concede ni borra acciones laborales. Revocar consolidado no
elimina la lectura individual. Reemplazar un binding exige volver a aprobar por
separado lectura, exportación y consolidación. Quitar una empresa del conjunto
no agrega ninguna otra.

Esto no retira datos ya vistos ni URLs firmadas emitidas por contratos anteriores.
Tampoco certifica jobs o revocación de sesiones Auth. No se modifican esos
servicios ni el scope de logout.

## Consumidores pendientes antes de proteger datos actuales

| Superficie vigente | Adopción requerida en otro bloque |
|---|---|
| `operations.service.ts`, `commercial.service.ts`, OperationsTable/Operation360Panel/OperationEconomics | rpc_list_operations/get/create/update, cotizaciones y 360: empresa persistida y coherente; capacidad laboral explícita y DTO operativo sin costos. Economía completa requiere full.read |
| `finance.service.ts`; F4 `private.f4_user_can_manage_finance` | overview, invoices/detail, operación-finanzas, pagos, profitability y ambas firmas de ledger: separar capacidad de acción de full.read, filtrar antes de sumar y cerrar fallback admin/finance |
| `billing.service.ts` | list/get/create/update CFDI y preparación/cola fiscal: propiedad empresarial, proyecciones de tarea y capacidades separadas; este bloque no habilita fiscal |
| `reports.service.ts`, `reportsTanda1.service.ts` | Cinco RPC: financial_summary, pipeline_summary, inventory_summary, operations_summary y Tanda1. Scopes explícitos, full.read en financieros y can_consolidate en conjunto; preservar las siete claves de Tanda1 |
| `reportsLoader.ts`, ReportsPage, LegacyReportsSection | Llamadas según capacidades, tarjetas independientes, cache por identidad/empresa/modo y descarte de respuestas tardías; no invocar financiero sólo por rol |
| `documents.service.ts`, EntityDocumentsPanel y políticas Storage | Metadatos empresa/origen/clase, descargas autorizadas por petición y protección de paths antiguos; no confiar sólo en tenant/módulo del path |
| `dataOperations.service.ts`, `finance.service.ts` CSV, exportRates/compliance/claims y `utils/export.ts` | Capacidad de exportación adicional, mismas filas/columnas que lectura; full.read por empresa y consolidado separado si se solicita. Revalidar en cada página/entrega |
| `executive.service.ts`, `rates.service.ts`, `compliance.service.ts`, `claims.service.ts` | Búsqueda global, dashboard, rates/partners/360, expedientes y agregados: permisos antes de JOIN, filtros, conteos y proyección |
| `automation.service.ts`, F7, notificationCenter y executive | Revalidar actor/destinatario, empresa y sensibilidad al generar/entregar. No usar credenciales técnicas como permiso financiero humano. Automático de ACCESS conserva sólo lectura |
| `admin.service.ts` / rpc_deactivate_member | La baja legacy hace DELETE de memberships. Con dependencias RESTRICT requiere un procedimiento coordinado de revocación/retención antes de usar el nuevo modelo. No se modifica ni se crea API de concesiones aquí |
| Contexto/Auth/rutas/UI | Empresas/capacidades como contrato futuro, sin default que conceda, sin habilitar operator/viewer, selector o consolidado por esta migración |

Los nombres de archivos son relativos a src/services salvo componentes/utils
indicados. Las RPC y firmas actuales no se alteran. Hasta adaptar todas las
superficies habilitadas, los datos financieros legacy conservan su autorización
anterior; **no quedan protegidos por crear estas tablas**. El inventario de
MULTI-03 sigue siendo la referencia de familias/overloads, no una aprobación de
cutover. Tampoco se ejecutó backfill o importación Excel.

## Validación y ejecución

Migración: `supabase/migrations/20261019211546_multi05_company_capabilities_financial_access.sql`.
Suite: `supabase/tests/multi05_company_capabilities.sql`. Base local nueva,
desechable y sin seeds, CLI loopback validado desde carpeta temporal; verificar
bindings antes de SQL. Positivos, negativos, permisos efectivos y RLS se prueban
con psql/roles reales y datos sintéticos. Todo fixture/concesión de test revierte.
Conservar baseline, contratos consumidos y suite MULTI-04 como regresiones.

El informe de ejecución debe registrar replay, resultados, hashes, comparación
de contratos previos y limpieza de recursos propios; no basta inspeccionar
policies. Antes de aplicar en otro target se requiere autorización específica,
schema/ACL/roles reconciliados y plan de recuperación. Antes de activar módulos,
dejar este modelo cerrado es una recuperación segura; reabrir contratos tenant-wide
o borrar documentos/movimientos no lo es.
