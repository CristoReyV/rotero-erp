---
name: rotero-db-qa
description: Ejecutar el workflow reusable de base de datos de ROTERO para migrations, canonical baseline, reset local, fingerprints, reconciliación staging, dry-run, rollback y verificación de RLS/grants/functions. Usar ante cambios o QA de schema y detenerse ante drift o DML inesperado.
---

# ROTERO Database QA

## Preparar evidencia

1. Confirmar scope, entorno autorizado y commit esperado. Staging es el máximo por defecto; nunca usar producción sin autorización explícita.
2. Leer `docs/codex/CURRENT_STATE.md` solo si importan los targets actuales.
3. Tratar `supabase/migrations/`, configuración, pruebas y schema observado como evidencia primaria. Consultar `docs/DB_BASELINE.md` y `docs/DB0D_ROLLOUT.md` para el modelo canónico y rollout.
4. Tomar backup verificable antes de cualquier reconciliación autorizada.
5. Generar fingerprint sanitizado con `scripts/db-schema-fingerprint.ps1` cuando aplique; no capturar datos ni secretos.

## Proteger historia

`supabase/migrations_legacy/` es histórico protegido. Nunca editar, renombrar, borrar ni reordenar esos archivos salvo autorización explícita. Conservar la representación legacy al construir o reconciliar el baseline canónico.

## Validar localmente

1. Verificar orden, idempotencia esperada y dependencias de migrations.
2. Ejecutar reset local limpio cuando el scope lo pida y el entorno esté disponible.
3. Comparar fingerprints antes/después contra el baseline esperado.
4. Probar functions, signatures, RLS, grants, ownership y contratos consumidos.
5. Confirmar zero unexpected DML; una prueba de schema no debe alterar datos de negocio inesperadamente.

## Reconciliar staging

1. Capturar fingerprint y estado de migrations PRE.
2. Comparar baseline canónico, historia remota y schema real.
3. Detenerse ante schema drift no explicado, target mismatch o historia divergente.
4. Ejecutar dry-run antes de apply cuando la herramienta lo permita.
5. Aplicar solo migrations autorizadas; no desplegar Edge Functions ni otros servicios por asociación.
6. Ejecutar pruebas contractuales y fingerprint POST; reconciliar el delta exacto.

## Rollback y cierre

- Definir y revisar el límite de rollback antes del apply; no prometer reversibilidad destructiva.
- Usar el backup y el procedimiento aprobado si falla una condición de aceptación.
- Detenerse ante DML inesperado, pérdida de grants/RLS, cambio de signatures o drift residual.
- Reportar baseline, fingerprints PRE/POST, migrations, pruebas, DML observado, rollback disponible y residuos.
- No incluir secretos, DSN, tokens, datos privados ni mensajes internos sin sanitizar.
