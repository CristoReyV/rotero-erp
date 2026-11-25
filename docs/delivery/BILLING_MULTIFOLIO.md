# Una factura de ingreso para varios folios internos

El vínculo registra que un mismo CFDI de ingreso cubre varias operaciones entregadas. Se ejecuta con una sola empresa activa seleccionada, un rol `finance` o `admin` y las capacidades vigentes `financial.full.read` y `finance.write`. El rol por sí solo no permite esta acción.

## Contrato local

- `rpc_delivery_link_issued_income(p_tenant_id, p_cfdi_id, p_operation_ids, p_xml_base64)` recibe de 1 a 100 IDs de operaciones y los bytes originales del XML en base64 sin saltos de línea. El XML debe pesar como máximo 2 MB. La acción compara el tamaño y SHA-256 con el artefacto fiscal privado ya vinculado al CFDI. Comprueba el tipo ingreso, el UUID fiscal, los RFC, la moneda, el total y la coincidencia exacta de cada folio interno con un `NoIdentificacion` de los conceptos. La integridad del archivo depende del registro fiscal autorizado del artefacto.
- El CFDI debe tener estado fiscal confirmado como timbrado y estar respaldado por un documento de ingreso y una única cuenta por cobrar vigente, en la misma empresa y por el total y la moneda de la factura. Los documentos del laboratorio fiscal quedan excluidos.
- Se registra un `operation_billing` por operación mediante su `linked_cfdi_id` existente, con una entrada de auditoría por vínculo nuevo. El documento, el importe por cobrar y los pagos se conservan. Un reintento de los mismos vínculos devuelve `linked_count: 0`, incluso después del cierre. Si el lote enviado contiene un folio inválido o incompatible, el servidor rechaza el lote completo.
- El operador cierra cada operación mediante la transición habitual y sus validaciones vigentes. La factura de proveedor puede conciliarse por operación cuando llegue. Su ausencia no condiciona el vínculo ni el cierre.

## Facturación

1. Selecciona una sola empresa y abre el detalle de una factura emitida en **Facturación**. La sección **Vincular factura a folios internos** consulta la elegibilidad y muestra los vínculos guardados.
2. Ingresa un folio exacto por línea. La revisión usa el XML registrado si la sesión autoriza su descarga privada. También se puede seleccionar una copia original. Cualquier archivo se comprueba contra el SHA-256 del artefacto fiscal; seleccionar un archivo no lo guarda en Storage.
3. Revisa el resultado por folio. **Vincular** confirma únicamente los marcados **Se vinculará**. Los ya vinculados y los rechazados conservan su estado. El servidor vuelve a aplicar sus validaciones al confirmar y guarda el lote en una transacción.
4. Recarga el detalle y verifica **Folios vinculados**. Revisa los mismos folios para confirmar que figuran como **Ya vinculado a esta factura**.

`rpc_delivery_review_issued_income` consulta los vínculos y, con folios y XML, devuelve el resultado por folio con la misma autorización del vínculo. Un folio de otra empresa se presenta como no disponible; la respuesta no confirma que exista fuera de la selección.

## Prueba y puesta en uso

La prueba `supabase/tests/billing_link_issued_income.sql` se ejecuta con `psql -X -v ON_ERROR_STOP=1 -f` sobre la base local desechable, después del replay y de la migración del vínculo. Usa un CFDI y una cuenta por cobrar sintéticos, dos operaciones entregadas y una factura cancelada de control. Revierte los datos, identidades y concesiones.

### QA visual local del 25 de noviembre de 2026

Se usó Chromium con ventana, la aplicación compilada, Auth local y una base aislada. Ambos folios sintéticos estaban entregados y pertenecían a la misma empresa. El XML original contenía `NoIdentificacion="A1"`. El folio `A10` no aparecía en el XML.

| Comprobación | Observación en pantalla |
| --- | --- |
| Revisión inicial | `A1` apareció como «Se vinculará». `A10` apareció como «Rechazado» con el motivo de coincidencia exacta. El botón indicó «Vincular 1 folio». |
| Confirmación y recarga de la página | La pantalla informó «Folios vinculados: 1». Tras recargar, la lista de vínculos mostró únicamente `A1`. |
| Segunda revisión | `A1` apareció como «Ya vinculado a esta factura». `A10` volvió a mostrar el motivo del rechazo. La revisión terminó sin una segunda solicitud de vínculo. |

La consulta directa en la base local confirmó un CFDI y una cuenta por cobrar antes y después, con el mismo saldo sintético de 116.00 MXN. Quedaron un vínculo para `A1` y un evento de auditoría. Las capturas corresponden al panel de vínculo y contienen sólo datos sintéticos.

Antes de liberar este cambio para WLS, Contabilidad debe confirmar dónde registra el productor autorizado los folios en el XML. El contrato probado localmente usa coincidencias exactas en `NoIdentificacion`. Si WLS confirma otro campo, su lectura requiere una prueba con el mismo formato y casos que descarten coincidencias parciales. Para la aceptación operativa sigue vigente el preview del PR #47.
