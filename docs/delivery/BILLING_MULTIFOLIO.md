# Una factura de ingreso para varios folios internos

El vínculo registra que un mismo CFDI de ingreso cubre varias operaciones entregadas. Se ejecuta con una sola empresa activa seleccionada, un rol `finance` o `admin` y las capacidades vigentes `financial.full.read` y `finance.write`. El rol por sí solo no permite esta acción.

## Contrato local

- `rpc_delivery_link_issued_income(p_tenant_id, p_cfdi_id, p_operation_ids, p_xml_base64)` recibe de 1 a 100 IDs de operaciones y los bytes originales del XML en base64 sin saltos de línea. El XML debe pesar como máximo 2 MB. La acción compara el tamaño y SHA-256 con el artefacto fiscal privado ya vinculado al CFDI. Comprueba el tipo ingreso, el UUID fiscal, los RFC, la moneda, el total y la coincidencia exacta de cada folio interno con un `NoIdentificacion` de los conceptos. La integridad del archivo depende del registro fiscal autorizado del artefacto.
- El CFDI debe tener estado fiscal confirmado como timbrado y estar respaldado por un documento de ingreso y una única cuenta por cobrar vigente, en la misma empresa y por el total y la moneda de la factura. Los documentos del laboratorio fiscal quedan excluidos.
- Se registra un `operation_billing` por operación mediante su `linked_cfdi_id` existente, con una entrada de auditoría por vínculo nuevo. El documento, el importe por cobrar y los pagos se conservan. Un reintento de los mismos vínculos devuelve `linked_count: 0`, incluso después del cierre. Un folio inválido o un vínculo incompatible impide toda la selección.
- El operador cierra cada operación mediante la transición habitual y sus validaciones vigentes. La factura de proveedor puede conciliarse por operación cuando llegue. Su ausencia no condiciona el vínculo ni el cierre.

## Prueba y puesta en uso

La prueba `supabase/tests/billing_link_issued_income.sql` se ejecuta con `psql -X -v ON_ERROR_STOP=1 -f` sobre la base local desechable, después del replay y de la migración del vínculo. Usa un CFDI y una cuenta por cobrar sintéticos, dos operaciones entregadas y una factura cancelada de control. Revierte los datos, identidades y concesiones.

El bloque entrega la RPC para que una interfaz autorizada pueda invocarla. Antes de usarla con WLS, Contabilidad debe confirmar el productor autorizado de la factura y que los conceptos del XML lleven los folios internos en `NoIdentificacion`. Una factura cuyos folios sólo figuran en texto libre requiere resolver su evidencia con Contabilidad. Para la aceptación operativa sigue vigente el preview del PR #47.
