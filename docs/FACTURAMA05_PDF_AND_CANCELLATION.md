# FACTURAMA-05 — evidencia de cancelación sandbox

## Contrato del proveedor y límites

Soporte aclaró que el UUID mostrado en el acuse sandbox corresponde a la solicitud
de cancelación y que no ofrece consulta XML del acuse de una factura. No se
extrapola esa semántica a producción ni se modifica la verificación del XML de
facturas/REP. Los archivos y diagnósticos anteriores se conservan.

El [artículo oficial](https://facturama.elevio.help/es/articles/110-descarga-del-archivo-html-o-pdf-del-acuse-de-cancelacion-de-una-factura-en-api-multiemisor)
y el [GET de acuse](https://facturama.mx/docs/api-reference/endpoint/factura-cfdi/obtiene-el-acuse-de-un-cfdi)
documentan PDF/HTML, tipo issuedLite. Antes de implementar el decodificador se
comprobó GET /acuse/pdf/issuedLite/{Id} sobre un documento persistido y cancelado:
HTTP 200, ContentType=pdf, ContentEncoding=base64, ContentLength numérico y Content
base64. El ejemplo documental usa Data/UTF-8; se admite ese envoltorio sólo si
contiene base64 y bytes PDF válidos. Envoltorios contradictorios se rechazan.

La validación comprueba límites, cabecera/cierre PDF, longitud y SHA-256. Sólo
acredita formato e ID persistido utilizado para recuperarlo, no la firma ni la
correlación interna del PDF. No se renderiza HTML del proveedor.

## Estados y recorrido

Se mantienen separados UUID fiscal, ID del proveedor, identificador de solicitud
sandbox cuando está disponible, confirmación remota y disponibilidad PDF.

- `recover_pdf`: identidad validada por getUser → load con fiscal.read vigente →
  GET de detalle correlacionado por ID/UUID/emisor → conciliación → lease PDF →
  GET de PDF → archivo privado inmutable por hash → metadatos/procedencia.
- `ack_pdf`: vuelve a comprobar identidad/tenant/empresa/capacidad/laboratorio,
  usa sólo la ruta privada persistida y verifica hash antes de la descarga.
- El cliente sólo elige el UUID local del documento; no controla URL, ID del
  proveedor, ruta Storage, resultado remoto o metadatos de evidencia.
- `cancel + recoverAck=true` sigue bloqueado; no ejecuta DELETE. La cancelación
  inicial conserva motivo autoritativo y sólo puede hacer su mutación inicial.
- Una descarga PDF fallida libera su lease y mantiene la cancelación confirmada.
  Puede intentarse otra lectura explícita, nunca otra cancelación automática.

El lease PDF independiente evita duplicados concurrentes y vence a los dos
minutos. No crea fiscal_requests ni fiscal_provider_attempts. La descarga ya
guardada no vuelve a contactar al proveedor. Host sandbox inmutable, sin seguir
redirects; respuestas 3 MB como máximo, PDF 2 MB como máximo y timeout acotado.

## Persistencia y conciliación

La migración aditiva amplía la tabla privada ya cerrada, preserva RLS/ACL y añade
un RPC service-role-only con search_path vacío y referencias calificadas.
Reutiliza la autorización MULTI-04/05 y la allowlist/binding de laboratorio.
No hay vía pública para administrar permisos ni autorizarse por rol/nombre.
El bucket existente permanece privado; sólo añade application/pdf a XML y
conserva su límite de 2 MB.

La observación remota se guarda con host/ruta GET, ID, UUID fiscal, estado,
HTTP y fecha de servidor. Una operación activa real conserva su intento real;
cerrar el registro histórico añade auditoría, no inventa otro intento HTTP.
El motivo, payload, attempt_count e intentos históricos no se reescriben.

Aplicar la migración no concilia datos. La recuperación explícita del documento
revalida la evidencia antes de finalizarlo. El rollout se limita a los casos
sandbox identificados; no existe un barrido ni backfill general. La interpretación
del identificador histórico requiere hash igual al archivo preservado; el campo
diagnóstico mismatch y el archivo siguen intactos, sin aprobación fiscal XML.

Antes de cualquier modificación persistente: backup cifrado DPAPI, restauración
local y comparación de sus bloques, fingerprint PRE, revisión del único delta,
dry-run y pruebas del candidato canónico/restaurado. El backup lógico incluye
Auth y metadatos Storage; no bytes Storage, secretos de plataforma ni PITR.
El delta no elimina ni reemplaza archivos existentes. No se ofrece rollback
automático destructivo: conservar la evidencia y revisar cualquier fallo.

## Validación y límites de activación

La regresión cubre cero DELETE durante recuperación, ID persistido, PDF inválido,
timeout/error/redirect, cache/hash, cancelación sin XML, estados separados, UUID
ajeno, ACL efectivas, acceso cruzado y revocación. El replay canónico y las suites
previas se conservan; las suites que exigen raíces vacías no se aplican a un clon
restaurado con historia. Esa diferencia no se oculta ni se arregla borrando datos.

QA de preview y UAT principal usan cuenta dedicada, contexto aislado y permisos
temporales de lectura, retirados al terminar. Se reutilizan documentos cancelados
y XML existentes, sin emitir/cancelar ni registrar CSD adicionales. El resultado
real, SHA, merge/deploy si procede y limitaciones se registran en el informe de
ejecución; ready de Netlify por sí solo no aprueba el frontend.

## Siguiente bloque MULTI-07

No integrar toda la rama MULTI. Preparar un delta revisable posterior al fiscal:

1. Componer guards y cuerpos de los diez cores Finance/exportación enumerados en
   FACTURAMA04_RECOVERY_AND_STAGING con sus FROM/JOIN fiscal02_*; mantener tanto
   autorización empresarial como exclusión de laboratorio. No cambiar hashes
   para saltar el guard sin revisar la composición y sus overloads.
2. Incorporar explícitamente la exclusión de laboratorio en multi07_row_allowed
   y multi07_legacy_visible cuando M07 se aplique después de fiscal02. Conservar
   el lock 7007 y las relaciones tenant/empresa sin clasificar historia ambigua.
3. Probar el delta sobre canónico y copia restaurada: ID directo, RLS/ACL, lectura,
   agregados, CSV/exportación y negación de laboratorio por todas las rutas legacy.

Permanecen pendientes Operaciones/DTO360, documentos/Storage, proyecciones legacy
Finance/Billing, exportación genérica, dashboards, notificaciones, jobs y Reportes.
Esta fase no aprueba aislamiento integral, otras cuentas/roles, datos poblados ni
producción. Credenciales/CSD reales y permisos personales requieren otra fase.
