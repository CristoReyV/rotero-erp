# CIERRE-03: workflows empresariales

El corte empresarial sigue siendo explícito. Esta adopción no clasifica históricos,
no habilita WLS, no asigna personas reales y no reabre contratos legacy. Las
migraciones anteriores permanecen intactas. El PR continúa draft hasta cerrar
los pendientes funcionales y UAT.

## Contratos y autorización

Las cinco migraciones `20261030*_cierre03_*` parten del catálogo reconciliado de
53 migraciones. Verifican los cuerpos consumidos antes de componer núcleos
privados y conservan estados, cumplimiento de proveedores y reglas de negocio.
Los manifiestos de `supabase/contracts/cierre03/` fijan esos orígenes.

Cada lectura y escritura vuelve a comprobar identidad, membership, tenant,
empresa activa, acceso y capacidades. Las escrituras requieren una sola empresa;
la consolidación no es un contexto de escritura. Admin/finance no implican full.
Ninguna migración contiene asignaciones ni activa empresas, tenants o jobs.

| Acción | Capacidad explícita adicional a acceso empresarial | Condición conservada |
| --- | --- | --- |
| Listado, ficha, historial operativo, dashboard | `operations.read` | DTO operacional mínimo; sin notas/snapshots financieros históricos |
| Crear | `operations.capture` | Rol laboral admitido por el contrato anterior; recibo idempotente |
| Editar / planificar / asignar / transición | `operations.edit` / `operations.plan` / `operations.assign` / `operations.transition` | Rol operativo anterior; revisión esperada y reglas de estado vigentes |
| Cambiar importes durante planificación | `financial.full.read` + `finance.write` | Sin ambos, se rechazan claves financieras y se conservan los valores previos |
| Incidencias, cruces y requisitos | Capacidad de la acción operativa correspondiente | IDs hijos comprobados contra la operación autorizada |
| Evidencia operacional | `operations.evidence.write` | Archivo administrado del mismo padre; sin referencias externas arbitrarias |
| Leer documentos | `billing.document.read` y permiso del padre | Clase financiera exige full; se conservan exclusiones de nómina/laboratorio |
| Cargar / sustituir / cancelar | `documents.upload` / además `documents.manage` | Evidencia operativa o full + `finance.write`, según clase y rol anterior |
| CSV | `export.operational` o `export.financial` | Mismo conjunto autorizado que pantalla; full no sustituye permiso de exportar |
| Dashboard financiero | `financial.full.read` | Rol admin/finance anterior y vinculación verificada vigente |
| Consolidado | Grant de consolidación + permisos requeridos en todas las empresas | Conjunto exacto; no se reduce silenciosamente tras revocación |
| Preparar/configurar/ejecutar automatización | `automations.manage` + `operations.read` | Admin; scope explícito, destinatarios autorizados y vigencia limitada |

Los códigos laborales nuevos no se conceden por defecto. Los roles de deployment
operator/viewer siguen cerrados. El perfil QA llamado operativo utiliza admin
con concesiones operativas parciales; no representa una nueva aprobación de roles.

## Operaciones y concurrencia

`rpc_delivery_create_operation_once`, `rpc_delivery_operation_action` y
`rpc_delivery_operation_child_action` conservan recibos mínimos, actor, hash de
solicitud y revisión. Reutilizar una solicitud con otro cuerpo se rechaza; un
retry exitoso se reautoriza antes de devolver el recibo. Un escritor obsoleto
recibe `stale_operation`. Locks compartidos de chofer/unidad mantienen la regla
de recurso ocupado incluso entre empresas del mismo tenant.

La planificación parcial conserva importes, moneda, catálogo y notas restringidas.
La revisión técnica no altera `updated_at` cuando es el único cambio: las métricas
de duración y reglas de antigüedad conservan su reloj de negocio. Los cambios
reales siguen ejecutando las reglas temporales anteriores.

Transitar no elude Tracking, POD, cumplimiento ni Billing emitido. El ensayo SQL
positivo completo utiliza prerrequisitos sintéticos locales. No se fabrican estados
fiscales o entregas remotas para conseguir una transición. La gestión de tokens
públicos de Tracking continúa cerrada en la experiencia empresarial; requiere
adopción específica antes de un recorrido real nuevo de punta a punta.

## Documentos y Storage

Se admiten padres operación, cuenta financiera y documento Billing. La intención
de carga liga actor, empresa, padre, clase, ruta canónica, tamaño/MIME, checksum
declarado y TTL de 15 minutos. Storage INSERT exige esa intención vigente;
UPDATE/upsert/DELETE directos siguen cerrados. Finalizar comprueba objeto y
propietario y reautoriza. El checksum es una declaración del cliente, no un hash
del contenido verificado por SQL.

Sustituir conserva los bytes y evidencia anteriores, admite un único reemplazo
por versión y actualiza la referencia documental canónica. Cancelar conserva
auditoría/bytes y retira la referencia activa. Se serializa con acciones de la
operación. Historial sólo devuelve metadatos y eventos permitidos, sin motivos
históricos ni cuerpos arbitrarios que puedan contener información financiera.

Descargar usa una petición autenticada que revalida permiso; no crea URLs firmadas
nuevas. Una URL firmada emitida anteriormente conserva su límite de expiración;
revocar grants no invalida mágicamente un enlace ya entregado. Los intentos sin
finalizar quedan identificables para reconciliación dirigida, sin borrado automático.
Plantillas generadas y documentos compartidos de partners/cotizaciones no se
presentan como adoptados por este contrato de tres padres.

## Dashboard, búsqueda y jobs

Se filtra antes de joins, conteos y límites. Se conservan fórmulas ejecutivas,
operativas y financieras anteriores; una sección no autorizada se omite, no se
rellena con ceros. Reportes/Tanda 1 permanece sin cambios. El contexto y las
descargas descartan respuestas de un epoch anterior al cambiar empresa.

La paleta sólo ofrece módulos/acciones adoptados y no devuelve conteos o
sugerencias ajenos. Los enlaces de operación abren la ficha scoped correspondiente.

Los seis avisos operativos F7 se evalúan mediante un scope explícito con expiración
máxima de siete días, hasta 20 destinatarios verificados y hasta 500 operaciones.
Se conserva el catálogo de umbrales/roles y se permiten overrides por empresa sin
alterar defaults del tenant. Hay locks y deduplicación por empresa/regla/entidad/
destinatario. No se impersona un JWT ni se concede full a una identidad técnica.
No se añade un cron. El scheduler global anterior sigue saltando tenants en corte.
La UI muestra ejecución manual acotada; no promete programación empresarial.
Montar, navegar y recuperar foco sólo leen notificaciones. Marcar/descartar son
acciones explícitas separadas, con reautorización.

## Validación y límites

El replay limpio usa los 53 blobs aprobados y estas cinco migraciones exactas.
Las suites SQL sintéticas verifican denegaciones efectivas, relaciones, revisiones,
Storage, documentos financieros, revocación y jobs con reloj controlado. El arnés
de concurrencia usa dos conexiones reales. Los arneses versionados exigen proyecto
local desechable o el preview/proyecto de staging autorizados expresamente.

Playwright usa contexto independiente y clic normal, verifica persistencia y
observa sólo metadatos HTTP sanitizados. No conserva HAR, tracing, headers, cuerpos
Auth ni respuestas completas. Cerrar UI y recibir HTTP de logout son evidencias
separadas de revocación completa. Foco sólo se aprueba con cambio efectivo observado.

La evidencia local y la remota se registran separadas. Los respaldos, IDs privados
y credenciales QA permanecen fuera de Git. Las identidades dedicadas continúan
bajo DPAPI hasta la retirada final del usuario; cada recorrido cierra sus propios
contextos. No se habilita la empresa del tenant compartido ROTERO QA.

Pendientes de entrega: Tracking empresarial y prerrequisitos reales de cierre,
otros workflows no adoptados, clasificación histórica determinista, identidades
reales verificadas, UAT con datos conciliados y autorización de producción. Excel
sigue HOLD. Facturama continúa sólo sandbox; Softmanagement conservado e inactivo.
