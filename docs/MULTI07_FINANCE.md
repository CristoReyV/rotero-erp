# MULTI-07 — Propiedad y lectura financiera por empresa

Incorporación revisada en MULTI-08: ver [reconciliación y matriz vigente](MULTI08_RECONCILIATION.md).
La migración incorporada es 20261026222328, compuesta con fiscal02. La sección
histórica de escrituras pendientes queda acotada por el cierre MULTI-08 de cinco
RPC para registros clasificados; no se han aprobado permisos de trabajo ni
protección financiera integral. Las bases/resultados siguientes son históricos.

Base: MULTI-06 `4a61ce2acbdd50d4fe6a481b62d0cdd38dbe5d95`. Preparación local,
sin asignaciones reales, backfill, UI o aplicación remota. **No habilitable aún.**
Se protegen las lecturas financieras adaptadas de filas con empresa conocida;
el histórico no atribuible conserva su contrato legacy y no se declara protegido.

## Entidades y propiedad

| Entidad real | Relación / tratamiento |
|---|---|
| finance_invoices | AR/AP son direction=ar/ap de la misma tabla, no nuevos libros paralelos. Raíz con company_id, estado y evidencia de clasificación; operación/Billing deben ser coherentes |
| finance_payments | Cada pago tiene invoice_id único como aplicación a una cuenta. Hereda propiedad de la factura; no se inventa una tabla de aplicaciones múltiples ni otro company_id editable |
| billing_documents | Raíz documental financiera vinculada opcionalmente a operación. Empresa/evidencia propias coherentes con la operación; no se cambian estados fiscales, importes o snapshots |
| billing_credit_notes | Raíz con empresa/evidencia; referencias opcionales a operación, factura, documento origen y documento de crédito. Todas las empresas conocidas deben coincidir |
| billing_payment_complements | Hereda factura; payment_id debe pertenecer a esa misma factura y tenant. Ambos documentos vinculados deben ser coherentes. No se modifica preparación/emisión/cancelación fiscal |

No se encontró un modelo adicional de aplicaciones de pago en las migraciones
activas de este recorrido. Se conserva el cálculo F4: pago asociado a factura,
créditos applied y saldo GREATEST(amount-paid-credit,0). No cambia política FX,
moneda, liquidación, estatus contable o contabilización de pagos/créditos.

Tres raíces reciben company_id sin default de empresa, estado
pending_classification/conflict/resolved y referencia de evento. Tres registros
privados cerrados de evidencia tienen FKs compuestas al mismo tenant/objeto/
empresa/decisión. No se resuelve por nombre, creador, rol o tenant predeterminado.
La evidencia externa debe verificarse mediante un proceso administrativo futuro;
la estructura SQL no acredita un hecho externo por recibir texto.

FKs de parentesco tenant/empresa protegen nuevas referencias entre operación,
factura, Billing y notas. Pagos/complementos usan invoice_id como autoridad;
la FK de complemento a pago incluye tenant+invoice+payment, evitando aplicar un
pago de otra factura aunque ambas empresas coincidan. FKs añadidas a historia
son NOT VALID: no certifican filas remotas anteriores ni ejecutan reparaciones.

El comprobador de relaciones verifica el grafo afectado y sus descendientes,
incluidos cambios del padre. Rechaza tenants/empresas incompatibles, padres
faltantes y un hijo con empresa conocida que pretenda contribuir a una factura
sin atribución compatible. Una historia incongruente no debe filtrar dinero por
sumas de hijos. Tampoco bloquea una operación ajena al grafo. La serialización
de cambios de propiedad usa un advisory lock de transacción por tenant; no
modifica cantidades, estados o reglas de negocio. Rendimiento/concurrencia con
volumen real siguen pendientes antes de staging.

## Historia y transición explícitas

- **Raíz resolved:** exige evento determinista y empresa del tenant; no puede
  tomar evidencia de otra raíz ni cambiar empresa conservando el evento.
- **Raíz pending/conflict:** no recibe empresa. Si tiene un padre de empresa
  conocida, esa relación limita la autorización sin convertirla en backfill.
  No puede usarse NULL para eludir el permiso del padre.
- **Sin atribución conocida en todo el grafo:** mantiene lecturas legacy de
  su rol actual. No es información aprobada por MULTI-05 ni un consolidado seguro.
- **Grafo incoherente:** se deniega la lectura/total de la factura afectada;
  no se recorta un hijo para inventar otro saldo. Requiere clasificación/conciliación.

Los contratos nuevos excluyen raíces no resueltas y siempre devuelven un aviso
resolved_only. La UI existente no se conecta a ellos. Antes de cualquier cutover
real se necesita manifiesto por ID, fuentes verificadas, responsables de resolución,
reconciliación de conteos/importes, aviso de cobertura en consumidores y autorización
de backfill. No asignar una empresa para evitar pendientes ni presentar una suma
legacy parcial como el total empresarial aprobado.

## Autorización y contratos nuevos, cerrados

Se reutilizan financial.full.read, export.financial y el grant de consolidación
MULTI-05. Acceso empresarial vigente, binding humano verificado, issuer y vigencia
son obligatorios. Admin/finance no conceden lectura completa de empresa conocida.
No hay asignaciones a QA/técnicos/personas reales ni mínimos laborales nuevos.

| RPC preparada | Requisitos / proyección |
|---|---|
| rpc_multi07_list_invoices | Tenant y company_ids explícitos. Una empresa en modo individual; varias sólo con modo consolidado y grant suficiente para todo el conjunto. Búsqueda literal, dirección, moneda, cursor UUID y límite 1–100; total scoped |
| rpc_multi07_get_invoice | Tenant+empresa+invoice_id; full.read individual. Factura mínima y pagos/créditos/complementos del mismo padre; sin notas privadas, banco, snapshots o archivos |
| rpc_multi07_finance_summary | Mismo scope. Grupos por moneda/dirección, y empresa en modo individual; sin sumar monedas o ampliar el conjunto |
| rpc_multi07_export_invoices_page | Mismas filas/columnas/filtros que listado, más export.financial en cada empresa. Revocación o empresa insuficiente deniega todo el pedido |

Scope nulo/vacío/duplicado/multidimensional, empresa/tenant ajenos o consolidación
implícita se deniegan. Full.read de A y B no concede consolidación. El grant
consolidado no sustituye full.read ni incluye empresas nuevas automáticamente.

Proyección de factura: id, company_id, operation_id, direction, reference,
counterparty_name, currency, status, due_date, amount, paid_amount, credit_amount,
balance_amount y created_at. Los importes sólo se producen después del gate full.read.
Denegación devuelve únicamente error, sin payload, filas, conteos o sumas.
Las facturas con payroll_period_id se excluyen del contrato nuevo incluso para
full.read, conforme a MULTI-03: nómina individual requiere una decisión separada.
El aviso de cobertura menciona esa exclusión; no se añade un permiso de nómina.

Dos propietarios NOLOGIN/NOINHERIT limitados: scope_owner sólo puede leer
identificadores/propiedad y el registro cerrado de evidencia; no tiene SELECT de
importes. read_owner sólo dispone de columnas del DTO y RLS, sin notas/banco o
documentos. Ningún rol API puede asumirlos. Helpers en private, search_path vacío,
referencias calificadas; sin administración pública o metadatos editables como permiso.

Las cuatro RPC nuevas y helpers están sin EXECUTE para PUBLIC/anon/authenticated/
service_role. Pruebas positivas sólo con grants transaccionales locales. Las tablas
financieras conservan ACL cerradas y añaden RLS restrictiva contra aperturas directas
accidentales; las funciones de escritura existentes siguen con su contrato definer.

Cliente preparado: companyFinance.service.ts, sin imports desde rutas/componentes.
No inicializa sesión ni cae a RPC legacy. Valida scope, claves/tipos y pertenencia
de cada fila/hijo. CSV usa serializeCsv existente, misma proyección, máximo 5000
filas y descarga sólo después de todas las páginas; falla completa por revocación,
error, cursor repetido o dispose del contexto. La integración al ciclo real de UI
y permisos permanece pendiente.

## Lecturas legacy adaptadas y límites de la protección

Se conservan firmas, ACL API y fórmulas. Nueve cuerpos de F4 cambian fuentes a
vistas privadas security_invoker/security_barrier que autorizan **antes** de JOIN,
SUM o proyección. Se conserva SQL explícito revisable en la migración; un guard de
hash/owner impide reemplazar silenciosamente una versión distinta del baseline.

| Vía | Tratamiento / prueba |
|---|---|
| rpc_get_finance_invoice_detail / rpc_get_operation_finance_summary | Gate individual para empresa conocida; sin full.read no devuelven datos. El segundo cierra el acceso financiero a Operaciones dentro de F4 |
| rpc_finance_overview / rpc_list_finance_invoices / rpc_list_finance_payments / rpc_list_finance_due_alerts / rpc_finance_profitability / rpc_list_payment_complements | Fuente filtrada. Tenant-wide exige autorización de todo el conjunto conocido y consolidación si hay varias empresas; no reúne permisos individuales implícitamente. Wrappers/overloads delegan al mismo core |
| rpc_export_finance_ledger, ambas firmas | Además export.financial para cada empresa conocida; sin bypass por overload |
| rpc_export_data_page finance_ar/finance_ap | Sólo se cambia la fuente financiera; paginación y auditoría existentes se conservan. Las otras ramas no adquieren protección por este cambio |
| Tablas/columnas/vistas financieras directas | ACL cerrado; RLS restrictiva ejecutada bajo grants temporales reales; ni un full reader puede autoasignar empresa por esas vías |
| RPC nuevas | Cerradas en backend; permisos internos probados con fixtures |

Los filtros de conjunto legacy son conservadores: si alguna empresa conocida no
está autorizada, no se incorpora ninguna fila de ese conjunto conocido al
agregado/export; no se fabrica una consolidación parcial. El detalle individual autorizado sigue
disponible. Las filas totalmente desconocidas siguen siendo legacy, con sus
limitaciones explícitas, no un total financiero completamente protegido.

Pendientes concretos que impiden activar el recorrido nuevo:

- rpc_list_operations/rpc_get_operation y ramas operations/quotes/documents del
  exportador genérico: DTO laboral y contratos de captura/360 aún sin adoptar;
  el bloque $bypass$ de MULTI-06 sigue reproduciendo la exposición previa.
- F3 documentos, generated snapshots, relaciones y Storage/URLs firmadas; Billing
  y referencias CFDI no constituyen propiedad empresarial aprobada por este bloque.
- Respuestas/validaciones de escritura legacy (create invoice, record payment,
  etc.) todavía necesitan proyección y permisos de tarea aprobados. No se cambian
  por full.read genérico ni se afirma que estén protegidas por los filtros de lectura.
- Búsqueda/dashboard/notificaciones, jobs y Reportes aún pueden consumir fuentes
  fuera del cierre financiero adaptado. No se modifica materialización ni fiscal.

## Validación y siguiente bloque

Suite multi07_finance_company_authorization.sql: dos empresas de un tenant y otro
tenant, sólo identidades sintéticas; positivo full.read, negaciones admin/finance,
revocación, empresa inactiva, relaciones cruzadas, historial, DTO, filtros/páginas/
sumas/export y todas las lecturas legacy F4/overloads. RLS se ejecuta con grants
temporales que aíslan las policies de los ACL. Prueba de deriva histórica incluye
un hijo financiero incongruente y una operación ajena que sigue funcionando.

El informe local registra replay, hashes, seis suites SQL, regresiones de cliente/
CSV y build, delta esperado de diez funciones públicas, limpieza y preservación.
No equivale a validación de usuarios/datos reales o aplicación en staging.

Siguiente bloque: cierre documental por empresa y sensibilidad (F3, metadatos,
snapshots, relaciones y Storage), acompañado del cierre de DTO/salidas de Operaciones
y respuestas de escritura según tareas aprobadas. Resolver clasificación y comunicar
la cobertura antes del cutover. Reportes viene después de cerrar sus fuentes, no
como sustituto de esa transición. No declarar aislamiento integral o protección
financiera completa mientras permanezcan estas vías.
