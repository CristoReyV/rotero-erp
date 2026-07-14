# AGENTS.md — ROTERO ERP

## Entrada canónica

Leer primero `docs/agent/INDEX.md` y cargar solo los documentos necesarios para la tarea.

## Contexto

ROTERO es un ERP para un broker/intermediario logístico. `third_party` es el camino principal y `own_fleet` queda como opción secundaria/futura.

Usar lenguaje broker-first: proveedor contratado, ejecución contratada, red operativa, operador/chofer del proveedor, unidad del proveedor, datos por confirmar, utilidad y margen.

## Reglas de trabajo

- Verificar código, pruebas y configuración antes de documentar algo como hecho.
- Separar hechos verificados, decisiones aprobadas, pendientes, propuestas y contenido legacy.
- Antes de crear lógica, evaluar helpers, componentes, hooks, servicios, librerías y patrones existentes; reutilizar cuando sea seguro.
- No hacer obligatorios chofer, unidad, placas o GPS para `third_party` si el contrato real/backend no lo exige.
- Respetar roles, permisos y visibilidad de información económica.
- Preservar cambios ajenos y mantener documentación breve, portable y sin secretos.
- No agregar dependencias, subagentes, commits, push o deploy sin autorización explícita.

## Áreas protegidas

No tocar sin aprobación explícita: backend, `supabase/`, migraciones, RPCs, Edge Functions, Auth/RLS, tracking público, `/t/:token`, `/driver/:token`, Traccar/GPS, `.env*`, fixtures, producción, staging, deploy y contratos de datos. Ver `docs/agent/PROTECTED_AREAS.md`.

## Validación

Para cambios autorizados ejecutar, salvo indicación contraria:

- `npm run lint`
- `npm run build -- --mode staging`

No corregir fallos ajenos fuera del alcance aprobado; reportarlos.
