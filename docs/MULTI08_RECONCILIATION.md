# MULTI-08 — Finance y proveedores fiscales

**Candidato local; no habilitable como aislamiento integral.** Sin aplicación,
configuración, personas, llamadas fiscales o publicación remotas.

## Procedencia y cambios

- Main: `0e9e2eb4dc4e66698e026507b260e8196a549584`, con PR #46.
- MULTI-04/05 ya incorporados: se conservan las variantes fiscales del trigger
  privado multi04_touch_updated_at y sus grants puntuales de DDL. No se duplican.
- MULTI-06 selectivo: commit `4a61ce2acbdd50d4fe6a481b62d0cdd38dbe5d95`;
  SQL original SHA-256 `930cceeafd48571a34dfb541d416499c8ec238733b6e66677169580bbca95d3a`.
- MULTI-07 selectivo: candidato original sin commit;
  SQL original SHA-256 `b58dcf0781d31729248acf7de7c13fc0206ef9f6929df44b9cad8fcacdfc3b49`.
  Rama, archivos y evidencia originales se preservan. Se usan versiones nuevas
  posteriores al delta fiscal; no se editan migraciones históricas.

| Migración | Cambio |
|---|---|
| 20261026222327_multi08_operations_prerequisite.sql | Propiedad/evidencia y tres RPC mínimas cerradas de MULTI-06 |
| 20261026222328_multi08_finance_fiscal_reconciliation.sql | Propiedad financiera, relaciones, owners limitados, cuatro RPC cerradas y diez cuerpos legacy filtrados |
| 20261026222330_multi08_finance_write_boundary.sql | Cinco respuestas/validaciones de escritura de Finance |
| 20261026222331_multi08_fiscal_provider_policy.sql | Selección empresarial, origen inmutable, namespace y lane local de envío |

Se conserva WLS como tenant: ROTERO / WORLD'S LOGISTIC SOLUTIONS ROTERO /
WLS110325JH8 y ROTERITO / WLS ROTERO / WRO2507109E0, con nombres comerciales
editables y posibilidad de agregar empresas. No se crean filas ni asignaciones.
Las tres personas financieras aprobadas siguen pendientes de verificar por UUID.
Nombres visibles, user_metadata, roles y cuentas técnicas/QA no conceden full.read.

## Reconciliación y límite de Finance

El guard conserva los hashes originales de los diez lectores MULTI-07. Un
normalizador temporal revierte **sólo** las sustituciones de fuentes fiscal02
revisadas; cualquier otro cambio de cuerpo, owner, SECURITY DEFINER o search_path
aborta. Las fuentes finales componen fiscal02 (sin laboratorio) con autorización
empresarial antes de proyección/agregado. Los helpers multi07_row_allowed y
multi07_legacy_visible excluyen laboratorio también en la transición desconocida.

FKs compuestas/evidencia/triggers verifican tenant/empresa y grafo de operación,
factura, pago, Billing, crédito y complemento. Las FKs históricas NOT VALID no
certifican registros remotos. No hay clasificación por nombre, creador o default.

Las cinco RPC rpc_create_finance_invoice, rpc_record_payment,
rpc_update_finance_invoice_status, rpc_void_finance_invoice y
rpc_create_payment_complement mantienen firma, ACL, owner y gate de rol original.
Toman el lock de clasificación y comprueban IDs **antes** de valores/saldos.
Grafo clasificado, incoherente, inaccesible o de laboratorio: sólo
company_finance_write_pending, sin balance/expected_amount/registered_amount ni
mutación. Se rechazan campos de autoclasificación en payload. Full.read y
companies.manage no sustituyen permisos laborales de escritura aún no aprobados.

Un grafo completamente desconocido conserva el contrato legacy y **no se declara
protegido**. Finance muestra transición de cobertura y errores explícitos; no se
bloquea globalmente el ERP. Los nuevos clientes/CSV no están conectados a UI y sus
RPC siguen sin EXECUTE API, mientras existan las alternativas siguientes.

## Matriz de vías financieras

| Vía / datos | Consumidor y autorización efectiva | Estado / aceptación |
|---|---|---|
| Tablas finance_invoices/payments, billing_documents/credit_notes/payment_complements | RPC de Finance/Billing; ACL API y columnas cerrados, RLS restrictiva, owners metadata/DTO limitados | Adaptada. multi07...sql, bloques closed y raw_rls ejecutan permisos efectivos, no sólo presencia de policies |
| Vistas privadas fiscal02 y m07 | Definers F4; sin SELECT API, filtros antes de agregar | Adaptada; conservar cierre y exclusión lab |
| Listado/detalle/pagos/vencimientos/complementos y overloads F4 | finance.service, FinancePage/Drawer; tenant/rol y full.read verificado para empresa conocida | Adaptada. multi07...sql denials/positive; historia desconocida aún legacy |
| Overview/profitability/op_finance_summary | FinanceOverview, ProfitabilityWorkspace, Operation360; conjunto conocido completo y consolidación explícita | Adaptada en F4; otras lecturas de Operaciones siguen pendientes |
| rpc_export_finance_ledger, ambas firmas; export_data_page finance_ar/ap | finance.service, dataOperations.service/CSV; añade export.financial por empresa y consolidación | Adaptada antes de páginas/proyección. multi07...sql; las demás ramas no quedan protegidas |
| Cuatro rpc_multi07_* y DTO/CSV | companyFinance.service sin UI; full.read/export/consolidación separados, resolved_only | Preparada y cerrada. SQL y companyFinance.test.ts |
| Cinco escrituras F4, respuestas y errores económicos | InvoiceCreateModal, PaymentDrawer, complementos; gate legacy más denegación clasificada temprana | Cierre MULTI-08. multi08...sql writes/full_read_not_write; definir permisos de trabajo y altas completas después |
| rpc_list_operations / rpc_get_operation; export_data_page operations | operations.service, Operation360Panel y carga de operaciones en FinancePage; tenant/rol legacy | Pendiente: precio/costo de B aún reproducible en multi06...sql, bloque bypass. Adaptar DTO y todos los consumidores; repetir esa prueba exigiendo ausencia de datos restringidos |
| rpc_get_claim_finance_handoff, lecturas 360 de clientes/proveedores | Claims y partner360; no heredan automáticamente el guard F4 | Pendiente: probar cada ID/campo/agregado de B y otro tenant |
| Billing/CFDI/notas ordinarios, export documents/quotes | billing.service, documents.service, dataOperations.service; fiscal02 protege laboratorio, no propiedad general | Pendiente: raíz empresarial, detalle, generación, relaciones y export con mismo gate |
| F3 document_files/generated_documents, fuentes y snapshots | DocumentsPage/servicios F3; snapshots pueden contener economía, acceso tenant/rol | Pendiente: empresa y sensibilidad antes de devolver contenido, metadatos o errores |
| Storage tenant-documents, firma, descarga e impresión | documents.service/createSignedUrl; no adquiere empresa por el filtro F4 | Pendiente: list/get/sign/read de B, revocación, sensibilidad y vigencia de URLs ya emitidas |
| rpc_reports_financial_summary y otros reports; rpc_reports_tanda1 | reports.service/reportsTanda1.service; fuentes aún legacy | Pendiente: adoptar después de sus fuentes; no inventar consolidado parcial |
| rpc_dashboard_*, rpc_get_executive_dashboard | dashboard.service/executive.service; agregados y snapshots tenant/rol | Pendiente: autorización antes de sumar, denegación por B |
| rpc_global_search, rpc_list_attention_items | executive.service; etiquetas/importes/enlaces por distintas fuentes | Pendiente: gate en cada rama, conteos y payloads |
| Notificaciones/listado/refresh/marcas/descartes, digest, automatizaciones/jobs | notificationCenter, executive.service, automation.service; lectores y snapshots materializados | Pendiente: actor/empresa del job y consumo, revocación y snapshots existentes. Se conserva listado automático sin refresh de ACCESS; tráfico UI no certifica jobs ajenos |
| Facturama sandbox y Storage fiscal-sandbox | FiscalSandboxPanel/función fiscal-sandbox; allowlist, acceso y fiscal.task, sitio/proyecto sandbox | F01/F02/F05 compatibles. No implica lectura financiera completa, protección documental general ni producción |

Los bypasses operativos conservados son conducta legacy reproducida, no defectos
atribuidos sin evidencia a las RPC nuevas. No hay selector ni consolidado nuevo.

## Proveedores, origen y envío

rpc_configure_company_fiscal_provider exige acceso vigente y companies.manage
explícito, registra auditoría segura y siempre devuelve enabled=false. El getter
exige acceso empresarial. Tablas privadas cerradas; no acepta endpoint, secreto
ni enabled del navegador. El antiguo toggle por tenant devuelve error de
transición; cola/worker neutrales generales no tienen emisión activada.

| Proveedor | Disponibilidad y capacidades |
|---|---|
| Facturama | Sólo facturama_sandbox_lab_v1. Se conserva laboratorio explícito con binding/allowlist/fiscal.task: emisión, XML, status, cancelación y PDF de acuse según F05. Recuperación de XML de acuse no documentada/validada |
| Softmanagement | Disponible para configuración sandbox/production, pendiente de validación, ningún transporte habilitado. Conectividad/ByRef y código 18 son antecedentes; setFactura, ZIP/XML, cancelación, idempotencia y REP no están aprobados |

fiscal-routing.ts usa perfiles finitos de servidor y nombres de credenciales
separados por proveedor/ambiente. No se leen ni guardan valores. Facturama conserva
host sandbox fijo; Soft no tiene endpoint habilitado ni adaptador ficticio. La UI
fiscal existente distingue disponible/configurado/pendiente/deshabilitado;
configured o flags ausentes no habilitan envío. No se construye otra interfaz.

- fiscal_document_origins fija tenant/empresa/proveedor/ambiente/perfil por CFDI,
  validando tenant e identidad externa ya conocida. No se cambia ni borra. El ID
  externo se fija una vez, con namespace proveedor+ambiente+perfil.
- Sólo fiscal01 explícito recibe metadata histórica demostrable; otros orígenes
  permanecen desconocidos. No se reescriben documentos/XML/intentos históricos.
  Nuevos campos canónicos se completan en futuras escrituras verificadas.
- Las solicitudes guardan un binding inmutable al agregado/origen, con FK
  compuesta. Historia sólo se vincula con snapshot de empresa de laboratorio y
  sin intentos de otro proveedor. Los intentos conservan filas originales y no
  admiten otro proveedor/tenant. La evidencia del artefacto sigue el agregado y
  sus rutas/relaciones guardadas; no se migra ni regenera.
- Status/cancelación/descarga usan origen, nunca la selección futura. SQL/dobles
  prueban cambiar a Soft sin redirigir el documento Facturama. Configurar una
  selección nueva deshabilita futuros prepare/claim de laboratorio para esa
  compañía; lectura y evidencia existentes conservan su origen.
- fiscal_stamp_lanes permite una adquisición por CFDI canónico, con PK común y
  lock transaccional, antes de devolver el claim Facturama al transporte. Nace
  incierta; tiempo/error/cierre no la liberan. Identificación/XML añaden evidencia.
  No hay fallback, borrado o reinicio automático; conciliación administrativa
  futura aún no expuesta. Un rechazo tampoco habilita otro proveedor.
- El worker neutral permanece cerrado y rechaza dispatch. Su futura adopción exige
  origen, catálogo validado y el mismo lane antes de I/O. Se protege el **mismo
  agregado canónico**; no se certifican duplicados creados como CFDIs distintos
  para un mismo hecho de negocio. Resolver política/clave de alta antes de emitir
  multiempresa de forma general.

## Validación y siguiente bloque

Replay: 45 blobs Git originales más cuatro migraciones candidatas LF exactas.
Una copia Windows CRLF cambia prosrc y rompe el guard histórico de hash; el
arnés usa los blobs del commit, sin editar ni debilitar la migración. CLI desde
carpeta temporal, puertos únicamente 127.0.0.1.

Suites baseline, consumidos, MULTI-04/05/06/07/08, F2/F3/F4/F6 y fiscal0/Facturama: ACL/columnas/
owners, RLS efectiva, concesión/revocación/consolidación, A/B/otro tenant, IDs,
páginas/agregados/CSV, relaciones/historia, errores de escritura y laboratorio.
scripts/multi08-local-concurrency.py usa transacciones independientes: un claim
aceptado y otro denegado para mismo/distinto proveedor, incertidumbre y reintento
bloqueado. Sus filas sintéticas se retiran con el runtime propio. Node valida
clientes/CSV, routing y dobles sin transporte Soft; Deno comprueba wrapper sandbox.
Typecheck/lint, formato pertinente, build sintético y diff/secret review.

El test fiscal0 de readiness sustituye la expectativa obsoleta de habilitar Soft
por tenant por denegación explícita. Conserva validación, snapshot, resultados
normalizados, artefactos, cancelación, errores, retry y bitácora inmutable, con
fixtures de owner/offline `synthetic_test_only`; no simula que Soft esté validado.
Sólo las dos RPC cerradas modificadas admiten search_path vacío en su aserción;
las demás mantienen el contrato anterior. No se modifica SQL histórico.

**MULTI-09:** cerrar salidas económicas de Operaciones y recorrido 360/listado/CSV,
reutilizando clasificación/capacidades. Adaptar todos los consumidores, incluida
FinancePage; aceptar sólo si el bloque bypass ya no revela costos de B ni campos
restringidos por ID/overload/export. Dependencia documental concreta: raíz y
sensibilidad F3 de snapshots/metadatos/Storage; si no se cierra, los contratos
preparados siguen cerrados. Reportes viene después de esas fuentes.

Manifiesto/backfill autorizado, las tres cuentas humanas verificadas y permisos
laborales mínimos siguen pendientes. Para Soft: fijar contrato/endpoint servidor,
resolver setFactura=18, verificar XML/ZIP e identidad, status/idempotencia,
cancelación/acuse/REP separadamente, credenciales y claves de operación, lane y
conciliación incierta; habilitar sólo capacidades validadas. Configuración no
basta. Producción/CSD, permisos reales, aplicación y UAT quedan fuera del bloque.
