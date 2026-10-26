# FACTURAMA-04 — recuperación de acuse y origen staging

## Lectura de evidencia, sin nueva cancelación

[GET de acuse CFDI](https://facturama.mx/docs/api-reference/endpoint/factura-cfdi/obtiene-el-acuse-de-un-cfdi)
documenta formatos PDF/HTML. La mención de XML en el DTO genérico de archivos no
documenta ese formato para la ruta. El endpoint XML de retenciones usa otro tipo
de documento e identificador. No hay una recuperación XML CFDI de lectura
documentada y comprobada en esta integración; no se prueban rutas inventadas.

El botón de recuperación queda deshabilitado. Una petición directa
`action=cancel,recoverAck=true` autoriza `load` como lectura y responde 409
`ack_recovery_unavailable`, sin adquirir lease, crear solicitud, modificar motivo
ni llamar al proveedor. Un flag no booleano se rechaza con 400. El mensaje es:
«Cancelación confirmada; acuse XML pendiente del proveedor».
Si aún no hay confirmación remota, responde `cancellation_not_confirmed` sin
afirmar que esté cancelado, igualmente sin reenviar ni contactar al proveedor.

La cancelación inicial mantiene los parámetros autorizados devueltos por el
worker y valida ID/UUID/issuer y acuse por separado. Un XML ajeno sigue rechazado.
Descargar un acuse previamente validado desde Storage es otra acción de lectura;
no inicia una cancelación. Los registros anteriores y su motivo no se reescriben.
No se modifica SQL aplicado: el worker administrativo permanece sin EXECUTE para
usuarios ordinarios, y la API autenticada no expone su flag legacy de recuperación.

## Origen y autorización

Se añade exclusivamente `https://rotero-erp-staging.netlify.app` a los previews
del mismo sitio y loopback existentes. HTTP del sitio, dominios parecidos,
branch deploys y otros sitios Netlify siguen rechazados. CORS no concede acceso:
se conservan getUser, empresa/capacidad vigente, allowlist de laboratorio,
binding sandbox, proyecto exacto y host inmutable del proveedor.

El wrapper devuelve 503 antes de crear clientes si enabled/environment/proyecto
no corresponden al staging sandbox autorizado. Las pruebas locales del wrapper
no tienen permiso de red. Habilitar el origen backend no despliega el frontend
principal: su recorrido nuevo requiere merge y validación posterior separados.

## Dependencias y adopción pendiente

El PR incorpora empresas y acceso explícito MULTI-04 (`companies`,
`membership_company_access`, `multi04_has_company_access`) y capacidades MULTI-05
(`membership_company_capabilities`, bindings humanos verificados y grants/scope
de consolidación; helpers `multi05_has_company_capability`/`multi05_can_consolidate`).
No hay concesión financiera automática por admin/finance. Fiscal añade capacidades
de tarea y un laboratorio separado; no asigna personas ni autoriza QA a full read.
Las variantes de dependencia y sus versiones se explican en FACTURAMA02_STAGING;
compartir versión con la rama MULTI no implica compartir bytes.

MULTI-07 no se porta aquí. Antes de aplicarlo después del delta fiscal hay que:

1. Reconciliar su bloque `legacy_source_guard`: espera cuerpos previos a los
   FROM/JOIN filtrados por `fiscal02_*`. Afecta los cores `rpc_finance_overview`,
   `rpc_list_finance_invoices`, `rpc_get_finance_invoice_detail`,
   `rpc_list_finance_payments`, `rpc_list_finance_due_alerts`,
   `rpc_get_operation_finance_summary`, `rpc_finance_profitability`,
   `rpc_export_finance_ledger`, `rpc_list_payment_complements` y
   `rpc_export_data_page`, junto a sus overloads. No basta cambiar hashes para
   saltarse el guard: hay que componer filtros empresariales y exclusión de lab.
2. Conservar en `multi07_row_allowed` y `multi07_legacy_visible` la exclusión
   fiscal de laboratorio que el bridge sólo añade cuando esos helpers ya existen.
   Revalidar ACL/RLS, relaciones, el lock compartido 7007, agregados y exportación
   sobre esquema canónico y restaurado; sin inferir empresas para historia ambigua.

Siguen pendientes de adopción empresarial: `rpc_list_operations`/
`rpc_get_operation` y sus DTO/360; archivos F3 (`rpc_list_document_files`,
`rpc_list_generated_documents`, snapshots y `createDocumentSignedUrl`/Storage);
respuestas de escritura legacy de Finance/Billing; exportación genérica fuera
del cierre financiero; dashboard/búsqueda/notificaciones, jobs y las cuatro RPC
legacy de Reportes más su resumen operativo. Este PR sólo cierra el laboratorio,
no todas esas vías ni el aislamiento financiero integral del ERP.

Para merge: revisar el candidato y checks exactos. Para UAT: validar el frontend
principal cuando se despliegue, con cuenta dedicada y alcance explícito. Para
producción: identidad/empresa y permisos reales verificados, adopción de vías
pendientes, recuperación, credenciales/CSD reales mediante fase autorizada y
acuse correlacionado. Ninguna de esas activaciones se concede por este cambio.
