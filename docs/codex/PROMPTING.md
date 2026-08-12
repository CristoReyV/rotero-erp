# Prompts cortos para ROTERO

El harness distribuye contexto por responsabilidad:

- `AGENTS.md`: reglas universales, siempre visibles.
- `.agents/skills/<skill>/SKILL.md`: workflow reusable, cargar por nombre.
- `docs/codex/CURRENT_STATE.md`: fase y targets dinámicos, solo cuando importan.
- `scripts/codex/`: comprobaciones deterministas.

Un prompt normal debe indicar skill, objetivo, entorno, límites de escritura y condición de parada. Tres a diez líneas suelen bastar.

## Tracking

```text
Use rotero-tracking-qa. Continue M4.4 from CURRENT_STATE.md.
Run the approved positive Edge matrix on BETA-STG-OPS-005.
Exactly one safe track-driver positive write. Stop on unexpected DML.
Do not start M4.5.
```

## Database

```text
Use rotero-db-qa. Reconcile the specified staging contract.
No production. Stop on schema drift.
```

## Release

```text
Use rotero-release-staging. Merge the approved PR and deploy only to staging.
Stop before manual visual QA.
```

## General ERP

```text
Use rotero-guardrails. Implement only the approved UI scope in the authorized worktree.
No backend, Supabase, new dependencies, browser, merge or deploy.
Run the repository validations and report out-of-scope defects without fixing them.
```

No copiar a los prompts secretos, capability tokens, rutas absolutas personales ni historia completa de fases. Actualizar `CURRENT_STATE.md` en lugar de engordar las skills.
