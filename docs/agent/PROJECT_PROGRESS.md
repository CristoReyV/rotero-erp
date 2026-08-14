# Progreso del proyecto

## Snapshot 2026-08-13 — Tracking M4

- M4.1–M4.5 están cerradas con estado `CLOSED / PASS`.
- Los contratos RPC, la UI real, la QA integral y la matriz Edge positiva están
  consolidados en `docs/TRACKING_CLOSURE.md`.
- La operación QA conserva exactamente un evento positivo esperado; el residuo
  final de capabilities es cero y no se retuvieron literales ni hashes.
- Los pendientes de SEC.4, observabilidad y GPS externo pertenecen a tandas
  separadas y no reabren Tracking M4.

## Snapshot 2026-07-14

### Verificado en código

- Operaciones separa centro de control, listas filtradas y detalle por ruta.
- Red Operativa dispone de vista proveedor-first y relaciones con recursos del proveedor.
- Comercial contiene cotizaciones, economía broker y continuidad hacia operaciones.
- El modelo incluye `third_party` y `own_fleet`, con señales broker-first en UI y tipos.

Estos puntos no equivalen a validación visual, runtime o productiva.

### Pendiente de reconciliación

- Billing y Finanzas están presentes y tienen implementación relevante.
- Notas históricas los describen en estados distintos; se necesita revisión documental/auditoría contra código y runtime antes de fijar un cierre.
- La auditoría integral del ERP se mantiene para el final, después de los bloques funcionales autorizados.

### Guardia del worktree

El worktree contiene numerosos cambios previos, incluidos cambios en áreas protegidas. Un agente debe preservarlos, comprobar el alcance con Git y no atribuirlos, revertirlos ni corregirlos sin autorización.
