# MULTI-06 — Propiedad de Operaciones y contrato operativo preparado

Incorporación selectiva en MULTI-08: ver [reconciliación](MULTI08_RECONCILIATION.md).
La base y los resultados históricos siguientes describen el bloque original;
la migración activa incorporada ahora es 20261026222327. Los bypasses y el cierre
de activación se conservan; este documento no acredita el ERP completo.

Base local: `32b2c7ef3cfbadecc1458cb083dd50f74449ec98`. Extiende MULTI-04/05
sin editarlos ni asignar empresas/cuentas reales. **Preparado, no habilitable.**
Las RPC nuevas no tienen EXECUTE para PUBLIC/anon/authenticated/service_role.
Ninguna ruta vigente importa el cliente nuevo. Este cierre es backend; no se
presenta un selector o aislamiento parcial ni se confía en ocultar pestañas.

## Propiedad, evidencia e integridad

Migración: `supabase/migrations/20261019215944_multi06_operations_company_scope.sql`.

- `operations.company_id`: nullable, sin empresa predeterminada; FK compuesta
  a companies del mismo tenant. Claves `(tenant_id,id)` y
  `(tenant_id,company_id,id)` conservan UUID y referencia/folio existentes.
- `company_classification_status`: pending_classification, conflict o resolved.
  Resolved exige empresa y evento de evidencia; los otros estados no admiten
  empresa. El default pending_classification preserva operaciones históricas y
  altas legacy durante la preparación; no es una excepción de captura habilitada.
- `company_classification_event_id`: FKs compuestas vinculan operación, tenant,
  decisión y empresa al evento correcto. Un evento de otra operación/empresa no
  permite resolver ni mover una operación.
- `private.operation_company_classification_events`: registro cerrado de
  decisiones, fuente, referencia opaca, registrador y fecha. Sin seeds, políticas
  de clientes o API administrativa. No copiar XML, contenido financiero, PII o
  secretos en referencias de evidencia.
- Nueve FKs nuevas `(tenant_id,operation_id)` para assignment_history, incidents,
  evidence, documents, crossings, operation_billing, tracking_tokens/events/
  route_points. La empresa se deriva del padre; no existe un company_id
  independiente en esos hijos. Se conservan sus contratos públicos y de tracking.

Las FKs nuevas de hijos son **NOT VALID**: exigen coherencia de escrituras nuevas,
sin afirmar que la historia no inspeccionada ya cumple. Su reconciliación y
validación en otro entorno es una fase posterior. No hay cambios de empresas,
pagos, documentos o movimientos existentes para hacerlas pasar. Las demás FKs
y CHECK del modelo nuevo se crean validadas en el replay local vacío.

### Clasificación histórica y transición

No hay algoritmo de inferencia ni backfill automático. Una resolución confiable
necesita un registro fuente inequívoco verificado, un padre ya verificado o una
resolución humana aprobada sustentada en evidencia. El emisor fiscal puede ser
fuente sólo si representa la entidad responsable y se ha comprobado esa relación;
el RFC receptor, el nombre parecido, el creador, el rol o la empresa predeterminada
no la demuestran. No se importó el Excel ni se consultó fiscal.

El registro admite verified_source_record, verified_parent y approved_resolution
para resolved; insufficient_evidence para pendientes y conflicting_evidence para
conflictos. La base comprueba estructura y correspondencia de IDs/decisión, no
certifica un hecho externo por recibir una cadena. Antes de poblar registros
reales, un procedimiento autorizado debe comprobar la fuente y conservar su
aprobación. Usuarios ordinarios no pueden declarar esa verificación.

Secuencia de una resolución autorizada futura: operación pendiente → evento
con evidencia verificada → actualización explícita de empresa/estado/evento en
la misma transacción. No existe RPC pública para hacerlo. Las FKs impiden
reutilizar evidencia de otra operación o cambiar empresa conservando el evento.
La retención de eventos impide borrar una operación referenciada sin un proceso
aprobado; no se implementa aquí una baja o transferencia empresarial.

Durante la preparación, la experiencia legacy mantiene sus filas, incluidas
pendientes/conflictos, con su autorización anterior. Los `to_jsonb` legacy reciben
las tres columnas aditivas; firmas, lógica y campos anteriores no se reescriben.
El contrato scoped devuelve sólo resolved y **siempre incluye un aviso explícito**
de exclusión. Sus totales son de la empresa y búsqueda solicitadas, nunca un total
tenant-wide de pendientes que revele actividad ajena. No se publica esa experiencia
ni se ocultan registros del recorrido actual. Antes del cutover deberá existir
una bandeja/proceso autorizado de clasificación, un manifiesto por ID con
resueltos + pendientes + conflictos = total inicial, y comunicación al operador.

Las altas legacy todavía pueden quedar pendientes. Antes de activar, todas las
altas/importaciones/conversión de cotizaciones del conjunto adaptado deben exigir
empresa y evidencia según su contrato, sin permitir simular histórico con un flag
del cliente. No se implementan captura/importación ni decisiones laborales nuevas.

## Contratos preparados de sólo lectura

| RPC | Parámetros | Requisitos y resultado |
|---|---|---|
| rpc_multi06_list_operations | tenant_id, company_id obligatorios; search='', after_id=NULL, limit=50 | Acceso vigente + operations.read; items, total, next_cursor, scope y classification_notice |
| rpc_multi06_get_operation | tenant_id, company_id, operation_id | Mismo permiso; sólo item de esa empresa resolved; inexistente/otra empresa/pendiente responden not_found sin distinguir existencia |
| rpc_multi06_export_operations_page | Igual a list | Añade export.operational; reutiliza exactamente listado/proyección/paginación |

Limit de 1 a 100; búsqueda literal de hasta 160 caracteres sobre referencia,
ruta y etiquetas de cliente/proveedor. UUID ascendente con cursor; cursor ajeno o
inexistente se rechaza. Conteo y páginas usan el mismo conjunto filtrado antes de
agregar. Cada petición revalida acceso/capacidad/estado de empresa. La paginación
no promete un snapshot inmutable entre peticiones concurrentes.

Proyección exacta de quince campos: id, company_id, reference_code, status,
service_type, route_summary, client_display_name, provider_name, operation_scope,
execution_type, priority, planned_departure, operational_window_start,
operational_window_end, created_at. Es mínima para todos los actores, incluidos
los que eventualmente tengan full.read. Sin precios, costos, pérdidas, utilidad,
ganancias, márgenes, notas libres, snapshots, documentos o tokens. No incorpora
datos financieros para ocultarlos en el navegador.

Propietario `rotero_operations_read_owner`: NOLOGIN/NOINHERIT, sin SUPERUSER,
BYPASSRLS, creación de roles/bases o replicación. Sólo SELECT de las columnas
operativas necesarias, RLS de operations por empresa/capacidad y EXECUTE del
booleano MULTI-05; no lectura financiera o tablas de módulos. El helper de filas
es INVOKER; RPC DEFINER con search_path vacío y referencias calificadas. El owner
MULTI-04 no recibe lectura de operations. Los privilegios API anteriores no cambian.
REFERENCES temporal de companies para crear FKs se retira conservando ACL previos;
CREATE de esquemas para transferencia tampoco permanece concedido.

### Cliente y CSV sin activación

`src/services/companyOperations.service.ts` es una factoría con cliente RPC
inyectado y tenant/empresa inmutables. No inicializa Supabase/Auth, no usa mocks
en producción ni cae al servicio legacy. Valida scope, claves/tipos y company_id
de cada item; rechaza campos financieros o extras en vez de propagarlos.

CSV pagina por la RPC de export con los mismos campos/filtros y máximo 5000 filas.
Usa serializeCsv existente (comillas, saltos de línea y protección de fórmulas).
Sólo devuelve el archivo al terminar todas las páginas; error, revocación, cursor
repetido o datos incompatibles abortan la descarga entera. No hay entrega parcial
o cambio automático de empresa. `dispose()` descarta respuestas tardías e impide
peticiones posteriores; el futuro consumidor deberá llamarlo al cambiar identidad,
tenant, empresa o revisión de permisos. No existe cache de filas compartido.

## Vías alternativas y gate de activación

| Vía | Evidencia local / estado |
|---|---|
| Acceso directo a operations y columnas de clasificación | ACL efectivos denegados a anon/authenticated/service_role; rutas directas probadas |
| Lector privilegiado nuevo | Sólo columnas mínimas; SELECT de costos rechazado y RLS ejecutado con acceso exclusivo a A |
| Registro de evidencia | ACL cerrado; RLS bajo grants temporales también impide lectura/escritura/autodeclaración |
| RPC nuevas | EXECUTE cerrado, comprobado antes y después de los tests; positivos sólo con grants transaccionales de test |
| Vistas dependientes directamente de operations | Ninguna en el catálogo del replay; no certifica todos los consumidores que llamen funciones |
| rpc_list_operations / rpc_get_operation | **Pendiente**: prueba ejecutada demuestra acceso legacy a B sin permiso empresarial y costos en detalle; conserva pendientes en listado |
| rpc_export_data_page para operations | **Pendiente**: ejecución sintética confirma costos en export legacy; no se cambió ni se sanitizó sólo en UI |
| create/update/planning/assign y conversión/importación | Contratos actuales conservados. update_details usa campos explícitos y no asigna columnas nuevas; propiedad obligatoria de nuevas altas y respuesta/proyección necesitan adaptación antes del cutover |
| Operation360Panel/getOperation360Data y otros componentes | Loader legacy, Economía y sus ramas permanecen sin adaptar; cliente nuevo no se conecta a esas rutas |
| Finance/F4 y ledger, documentos/F3/Storage | Dependencias de otros módulos. Catálogo confirma EXECUTE vigente de sus RPC conocidas; sus límites siguen tenant/rol, no un cierre empresarial aprobado |
| Búsqueda/dashboard/notificaciones y las cinco RPC de Reportes | Pendientes de adopción y propiedad de sus fuentes. No se cambia materialización, Auth/logout, jobs o Reportes en este bloque |

**No habilitable** aunque los endpoints preparados pasen pruebas: las vías legacy
ejecutables por la misma identidad eluden el límite. No conceder EXECUTE a las
nuevas RPC hasta una migración posterior revisada que cierre los bypasses de las
superficies habilitadas. Tampoco bloquear globalmente el ERP o modificar roles
actuales para aparentar protección. Preparar contratos no aprueba aislamiento
integral ni protección financiera completa.

### Trazabilidad de los bypasses observados

Son contratos anteriores a MULTI-06, no defectos atribuibles a esta migración:
`rpc_list_operations(uuid)` y `rpc_get_operation(uuid)` están definidos en
`20260223000000_canonical_baseline.sql`; `rpc_export_data_page(uuid,text,jsonb,jsonb,integer)`
en `20260826000000_f6_data_operations.sql`. Sus definiciones ya estaban en la
base `32b2c7ef3cfbadecc1458cb083dd50f74449ec98` y MULTI-06 no las reemplaza.

Consumidores exactos: `operations.service.ts` listOperations/getOperation y
getOperation360Data, llamados desde OperationsPage/Operation360Panel; los importes
se usan en OperationEconomics. `dataOperations.service.ts` exportData llama a la
RPC genérica desde DataOperationsPage. El CSV de selección de OperationsPage
usa una proyección distinta del cache y no demuestra seguridad del export genérico.

Prueba ejecutada: `supabase/tests/multi06_operations_company_scope.sql`, bloque
`$bypass$`: rpc_get_operation devuelve B y provider_cost_amount sin acceso
empresarial a B; rpc_list_operations devuelve las seis filas del tenant, incluidas
pendiente/conflicto; rpc_export_data_page devuelve provider_cost_amount. Los
bloques `$closed$`/`$clean$` prueban EXECUTE cerrado antes/después de los grants
transaccionales de prueba. Esa evidencia demuestra autorización legacy tenant-only,
no una regresión introducida por las RPC nuevas.

## Validación y dependencias siguientes

Suite `supabase/tests/multi06_operations_company_scope.sql`: fixtures sintéticos
de dos empresas de un tenant y de otro tenant, sin usuarios Auth reales; rollback
de filas/grants. Comprueba integridad, clasificación, ACL/RLS efectivos, manipulación
de IDs/tenant/empresa, acceso directo, búsqueda/páginas/totales, proyección mínima,
export separado, revocación, empresa inactiva y bypasses legacy como bloqueo.

Ejecución local: replay limpio de 42 migraciones en PostgreSQL 17.6, cinco suites
SQL aprobadas (MULTI-04/05/06, baseline y consumidos). Las 41 anteriores se copian
de sus blobs Git; la nueva coincide por bytes. Contratos de funciones anteriores,
RLS/owners e indicadores ACL API sin drift inesperado; cambios propios de columnas,
constraints, policy y grant al lector nuevo quedan expresos arriba. Advisors locales
sin resultados, como complemento de pruebas. Typecheck/lint, build staging local
con envDir vacío/valores ficticios y 12 casos/regresiones de frontend aprobados.
Sin prueba de navegación autenticada o aplicación remota en esta fase.

Siguiente bloque concreto: preparar propiedad/classificación de Finance —facturas
AR/AP, pagos, notas/complementos y sus relaciones con operations/Billing— y gates
de lectura/export por empresa, conservando acciones laborales separadas. Después
cerrar documentos/Storage y las salidas habilitadas de operación/360/export/búsqueda;
Reportes sólo cuando sus fuentes estén correctamente clasificadas y protegidas.
No añadir todo ello implícitamente a MULTI-06.

Antes de staging: autorización específica, reconciliación de schema/ACL/roles,
backup/recuperación, fuentes y responsables de clasificación, manifiesto/dry-run,
backfill aprobado, validación de FKs históricas, adaptación coordinada de contratos
y pruebas de todas las vías habilitadas. Asignaciones personales, matriz laboral,
empresas WLS y Excel continúan pendientes; no son defaults de esta migración.

Referencias: [funciones Supabase](https://supabase.com/docs/guides/database/functions)
y [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
