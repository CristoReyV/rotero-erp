# Decisiones

## Aprobadas

- ROTERO se diseña y documenta broker-first, como intermediario logístico.
- `third_party` es el camino principal; `own_fleet` queda secundario/futuro.
- Se usa proveedor contratado, ejecución contratada, red operativa, operador/chofer del proveedor, unidad del proveedor y datos por confirmar.
- Chofer, unidad, placas y GPS no son obligatorios para `third_party` salvo que el contrato real/backend lo exija.
- La economía broker distingue costo proveedor, precio cliente, utilidad y margen.
- La auditoría integral se deja para el final.
- Backend, datos, contratos públicos, tracking, permisos, entornos y dependencias tienen puertas de aprobación explícita.
- Antes de crear lógica se evalúa y reutiliza la implementación interna existente.

## Antecedentes

Goals, planes, `.agents/*` y changelogs conservan contexto histórico, pero no sustituyen una decisión vigente ni prueban el estado actual.

## Propuestas

Ninguna propuesta queda aprobada por este documento. Deben registrarse como propuesta y someterse a decisión humana antes de ejecutarse.

## Dudas abiertas

El cierre exacto de Billing/Finanzas y la validación runtime/visual de los bloques existentes deben resolverse mediante reconciliación y auditoría autorizadas.
