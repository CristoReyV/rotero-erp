---
name: rotero-release-staging
description: Ejecutar releases autorizados de ROTERO mediante PR, validaciones, Ready, merge, main, build, Netlify staging, HTTP smoke y handoff visual manual. Usar para publicar cambios aprobados únicamente a staging y detenerse ante target mismatch.
---

# ROTERO Release Staging

## Resolver targets

1. Leer `docs/codex/CURRENT_STATE.md` para obtener main y targets actuales; no fijarlos de nuevo en esta skill.
2. Verificar repositorio, base branch, commit, sitio, site ID y URL antes de cualquier escritura externa.
3. Detenerse ante target mismatch, main inesperado, checks fallidos o worktree sucio.

## Publicar el cambio

Seguir solo hasta el punto autorizado:

1. Revisar scope y diff del PR.
2. Ejecutar validaciones requeridas.
3. Cambiar a Ready solo con autorización o criterio explícito cumplido.
4. Hacer merge solo si la tarea lo autoriza.
5. Actualizar `main` con fast-forward y registrar el merge SHA.
6. Ejecutar build de staging.
7. Desplegar únicamente al sitio Netlify staging verificado y registrar deploy ID.
8. Ejecutar HTTP smoke GET con `scripts/codex/http-smoke.ps1` o equivalente.
9. Entregar el target para QA visual manual; no simular aprobación visual.

## Límites

- Nunca desplegar a producción sin autorización explícita.
- No desplegar Supabase, migrations, Edge Functions o contratos DB salvo que sean scope explícito.
- No usar browser, Playwright, Chromium ni screenshots sin autorización explícita.
- No continuar después del punto pedido: Draft PR, Ready, merge y deploy son autorizaciones distintas.
- No instalar dependencias ni cambiar configuración para “hacer pasar” el release sin aprobación.

## Cerrar

Reportar PR, checks, merge SHA, build, sitio/URL staging, deploy ID, HTTP statuses y handoff manual. Indicar con claridad qué pasos no se ejecutaron y cualquier bloqueo.
