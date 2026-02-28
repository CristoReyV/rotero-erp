# Operations Workflow V2 — QA DB-first

Este documento detalla los resultados de las pruebas de integridad y seguridad realizadas sobre el flujo de operaciones implementado en el Paso 15.

## Resumen de Validaciones de Integridad

| Prueba | Descripción | Resultado |
| :--- | :--- | :--- |
| **Transición Inválida** | Intentar pasar de `draft` a `assigned` directamente. | **PASS** (Retorna `invalid_transition`) |
| **Requeridos Planned** | Intentar pasar a `planned` sin `origin_place` o `destination_place`. | **PASS** (Retorna `missing_places`) |
| **Requeridos Assigned** | Intentar pasar a `assigned` sin chofer ni unidad configurada en campos legibles. | **PASS** (Retorna `missing_driver`) |
| **Requeridos In Transit** | Intentar iniciar ruta sin un token de tracking activo (scope `driver:write`). | **PASS** (Retorna `missing_driver_token`) |
| **Requeridos Delivered** | Intentar marcar como entregado sin evento `delivered` en `tracking_events`. | **PASS** (Retorna `missing_delivered_event`) |
| **Cierre Estricto** | Intentar cerrar una operación que no esté en estado `delivered`. | **PASS** (Retorna `invalid_transition`) |
| **Seguridad de Rol** | Usuario con rol `viewer` intentando ejecutar `rpc_transition_operation_status`. | **PASS** (Retorna `unauthorized`) |

## Auditoría (Audit Log)

Se confirmó que cada cambio de estado exitoso genera una entrada en `audit_log` con:
- `action`: `operation_status_changed`
- `details`: JSON con `from_status` y `to_status`.

Los overrides generan:
- `action`: `operation_override_used`
- `details`: incluye `reason` legal (>10 chars) y estados involucrados.

## Hardening PostgREST

Se verificó que el acceso vía PostgREST (API REST directa de Supabase) para escrituras en la tabla `operations` está bloqueado por defecto para todos los usuarios autenticados, ya que solo existen políticas de `SELECT`. Las mutaciones están encapsuladas exclusivamente en RPCs con lógica de negocio y guardas de rol.

---
**QA Status: VERIFIED**
Finalizado el 2026-02-27.
