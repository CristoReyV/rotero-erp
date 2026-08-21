# F4 — ROTERO Finance 360

## Alcance

Finance 360 implementa el control operativo `Operación → AR/AP → vencimiento → pago → saldo → complemento preparado → documentos → rentabilidad`. No incorpora contabilidad general, pólizas, conciliación bancaria, feeds bancarios, timbrado SAT ni tipos de cambio en vivo.

La cuenta financiera es explícita: cerrar o entregar una operación no crea AR/AP automáticamente. Una operación puede tener varias cuentas. El backend compara lo registrado contra venta/costo esperado y exige motivo auditado para cualquier excedente.

## Contratos de integridad

- MXN usa tipo de cambio `1`; USD abierta exige tipo de cambio y fecha capturados manualmente.
- Importe, moneda y tipo de cambio son inmutables después de abrir la cuenta.
- `paid` se deriva de pagos y notas de crédito aplicadas; `overdue` se deriva de saldo abierto + fecha.
- Registrar un pago bloquea la fila de la cuenta con `FOR UPDATE`, recalcula el saldo dentro de la transacción y rechaza `payment_exceeds_balance`.
- La anulación requiere motivo y no se permite después de pagos o créditos.
- Los complementos quedan en estado preparado (`ready`). La ejecución fiscal pertenece exclusivamente a Billing.
- Los archivos usan el bucket privado y URLs firmadas de Documents 360 bajo el contexto `finance/finance_invoice`.
- Los agregados de rentabilidad separan MXN y USD; no existe conversión implícita ni reescritura histórica.

## Seguridad

Los RPC Finance son `SECURITY DEFINER` con `search_path = pg_catalog, public`, validación de `auth.uid()` y rol `admin|finance`. `PUBLIC`, `anon` y `service_role` no tienen ejecución; las tablas no otorgan acceso directo. Comercial, Tracking y Seguridad no reciben acceso económico.

## Compatibilidad y rollout pendiente

Staging se consultó sólo en modo lectura. Conserva contratos históricos enriquecidos de Billing/Finance y tiene F2 como última vertical aplicada; F3 aún está pendiente. F4 es aditiva: reconstruye el subconjunto Finance/Billing ausente en el reset canónico y endurece las mismas tablas/RPC cuando ya existen.

No desplegar F4 antes de liberar F3. En la ventana aprobada, volver a ejecutar preflight de migraciones y aplicar la secuencia pendiente completa conforme a la nota F3; F4 debe quedar después de `20260823000000_f3_documents_360` como `20260824000000_f4_finance_360.sql`. Esta rama no ejecuta `db push`, `migration repair`, deploy de Netlify ni escrituras en staging.

## QA local

El reset esperado es baseline → F1 → compat → F2 → F3 → F4. La suite `supabase/tests/f4_finance_360.sql` cubre ACL, tenant, FX, creación desde operación, excedente controlado, estados, documentos, complementos, pagos exactos/parciales, centavo excedente y cuenta liquidada. La validación final también ejecuta F1–F3, contratos consumidos, RBAC.3A/B/C, Tracking, frontend, lint y build staging.
