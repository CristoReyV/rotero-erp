# AGENTS.md — ROTERO ERP

## Entrada

- Leer primero `docs/agent/INDEX.md` y cargar solo lo necesario para la tarea.
- Leer `docs/codex/CURRENT_STATE.md` solo cuando importen la fase o los targets actuales.
- Verificar en código, pruebas y configuración cualquier hecho de implementación.
- Separar hechos verificados, decisiones aprobadas, pendientes, propuestas y contenido legacy.

## Scope

ROTERO es un ERP broker-first para intermediación logística. `third_party` es el camino principal; `own_fleet` es secundario/futuro. Usar lenguaje de proveedor y ejecución contratados, red operativa, operador o unidad del proveedor, datos por confirmar, utilidad y margen.

## Safety

- Usar staging por defecto. Nunca operar en producción sin autorización explícita en la tarea.
- Editar solo el worktree autorizado. No tocar el worktree snapshot protegido `DEV`.
- No usar browser, Playwright, Chromium ni screenshots salvo autorización explícita.
- No exponer secrets, credenciales, JWT, capability tokens ni datos privados en archivos o logs.
- No agregar dependencias sin autorización y justificación concreta.
- Reutilizar helpers, services, hooks, componentes, librerías y patrones existentes antes de crear otros.
- Respetar roles, permisos y visibilidad económica; no exigir datos de flota propia a `third_party` sin contrato real.
- Tratar backend, Supabase, Auth/RLS, tracking público, `.env*`, fixtures, entornos y contratos como áreas protegidas; ver `docs/agent/PROTECTED_AREAS.md`.

## Git

- Ejecutar preflight antes de editar: rama/commit esperados, worktree limpio y `HEAD` alineado con su rama remota.
- Revisar `git status`, el diff completo y `git diff --check` antes de entregar.
- No usar force, reescribir historia ni revertir cambios ajenos.
- No hacer commit, push, PR, merge o deploy salvo autorización explícita de la tarea.

## Disciplina de alcance

- No ampliar una tanda ni hacer arreglos oportunistas.
- Ante drift o un defecto fuera de scope, documentar evidencia y detener esa línea de trabajo.
- Preservar cambios ajenos y mantener documentación breve, portable y sin secretos.

## Skills

| Skill | Usar para |
| --- | --- |
| `rotero-guardrails` | Tareas generales ERP, preflight, límites y cierre. |
| `rotero-tracking-qa` | QA reusable de tokens, Edge y tracking. |
| `rotero-db-qa` | Migraciones, baseline, fingerprints y reconciliación DB. |
| `rotero-release-staging` | PR, merge autorizado y release solo a staging. |

Skills repo-locales: `.agents/skills/<skill>/SKILL.md`.

## Validación y entrega

- Para cambios autorizados ejecutar, salvo instrucción contraria: `npm run lint` y `npm run build -- --mode staging`.
- No corregir fallos ajenos fuera del scope; reportarlos.
- Informar cambios, validaciones, targets/SHA relevantes y bloqueos.
- Cuando corresponda usar solo: `LISTO`, `LISTO CON BLOQUEOS` o `NO LISTO`.
