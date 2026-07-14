# Contexto del proyecto

## Modelo operativo aprobado

ROTERO es un ERP para una operación principalmente broker/intermediaria logística. El flujo principal contrata capacidad a una red operativa; no parte de asumir flota propia.

- `third_party`: camino principal.
- `own_fleet`: camino secundario/futuro.
- Lenguaje: proveedor contratado, ejecución contratada, red operativa, operador/chofer del proveedor, unidad del proveedor y datos por confirmar.
- Economía broker: costo del proveedor, precio al cliente, utilidad y margen.
- Chofer, unidad, placas y GPS no se vuelven obligatorios para `third_party` salvo exigencia real del contrato/backend.

## Stack verificado

- Frontend: React, TypeScript y Vite.
- UI: Tailwind CSS y componentes internos.
- Navegación: React Router.
- Estado cliente: Zustand.
- Backend/datos: Supabase, área protegida.
- Acceso: rutas y acciones condicionadas por roles existentes.

No se afirma aquí el estado de producción, staging, runtime, RLS ni datos vivos.

## Módulos y rutas verificadas en código

- `/operations`: centro de control diario.
- `/operations/list`: listas y vistas filtradas.
- `/operations/:operationId`: detalle separado de una operación.
- `/operations/resources`: Red Operativa.
- Comercial: cotizaciones, proveedor considerado/contratado, economía broker y conversión hacia operación.
- Billing y Finanzas: módulos presentes con flujos y datos propios; su estado dentro del rediseño requiere reconciliación documental y auditoría antes de declararlo cerrado.

El flujo conceptual es: cliente → cotización → proveedor contratado → ejecución contratada → tracking/documentos → entrega → billing/finanzas. Billing emitido, CFDI, cobro y cierre financiero son capas distintas y no deben inferirse entre sí.

## Límites de certeza

La presencia de código no demuestra validación visual, runtime, datos, permisos efectivos ni despliegue. Antes de cambiar producto se deben revisar contratos reales, helpers y servicios existentes, y obtener aprobación para cualquier área protegida.
