---
name: rotero-guardrails
description: Aplicar los guardrails generales de ROTERO ERP en tareas de código, documentación, QA o Git. Usar cuando una tarea necesite seleccionar el worktree seguro, hacer preflight, limitar el scope, proteger staging/producción, validar cambios o entregar un veredicto.
---

# ROTERO Guardrails

## Preparar

1. Confirmar el worktree autorizado por la tarea y no editar el snapshot protegido `DEV`.
2. Leer `AGENTS.md` y solo las referencias que indique `docs/agent/INDEX.md` para el scope actual.
3. Ejecutar `scripts/codex/git-preflight.ps1` o comprobar de forma equivalente:
   - rama esperada;
   - worktree limpio;
   - `HEAD` alineado con la rama remota;
   - SHA esperado, cuando la tarea lo proporcione.
4. Detenerse ante branch, SHA, worktree o target inesperados.

## Mantener límites

- Trabajar en staging por defecto; no tocar producción sin autorización explícita.
- No usar browser, Playwright, Chromium ni screenshots sin autorización explícita.
- No ampliar la tanda ni corregir defectos ajenos. Registrar evidencia y detener esa línea.
- No editar áreas protegidas sin autorización específica; consultar `docs/agent/PROTECTED_AREAS.md`.
- Reutilizar arquitectura existente antes de crear helpers, services, hooks o componentes.
- No agregar dependencias sin autorización y justificación; no modificar package files por conveniencia.
- No imprimir ni persistir secrets, credenciales, JWT, capability tokens o datos privados. Redactar valores sensibles incluso en errores.
- No crear commits, push, PR, merge o deploy si la tarea no los autoriza.

## Validar

1. Revisar `git status --short` y el diff completo.
2. Ejecutar `git diff --check`.
3. Ejecutar las validaciones pedidas y las de `AGENTS.md` proporcionales al cambio.
4. Confirmar que no cambiaron archivos fuera de scope, package files, Supabase o producto cuando debían permanecer intactos.
5. No corregir fallos preexistentes fuera de scope; conservar la evidencia.

## Entregar

Informar de forma breve:

- worktree, rama y SHA relevantes;
- archivos modificados;
- validaciones y resultado;
- acciones externas realmente realizadas;
- riesgos o bloqueos;
- siguiente paso no ejecutado.

Usar `LISTO`, `LISTO CON BLOQUEOS` o `NO LISTO` solo cuando corresponda. Referenciar el estado temporal desde `docs/codex/CURRENT_STATE.md`; no copiarlo a esta skill.
