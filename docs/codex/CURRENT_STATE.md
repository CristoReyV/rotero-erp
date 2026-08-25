# ROTERO Codex — estado actual

Leer este archivo solo cuando la tarea dependa de la fase o de targets actuales. Verificar cada target antes de una escritura externa. No guardar aquí secrets, hashes, JWT ni capability tokens.

## Targets

- Main vigente: resolver dinámicamente `origin/main` durante el preflight Git; no fijar un SHA como requisito reusable.
- Supabase staging project: `mxpmgihuheagrcowwbia`
- Netlify site: `rotero-erp-staging`
- Netlify site ID: `336756a2-c93f-40b5-829a-497e0ba30ac3`
- Staging URL: `https://rotero-erp-staging.netlify.app`
- QA operation: `BETA-STG-OPS-005`

## Tracking

- M4.1: CLOSED / PASS
- M4.2: CLOSED / PASS
- M4.3: CLOSED / PASS
- M4.4: CLOSED / PASS
- M4.5: CLOSED / PASS
- Tracking M4: CLOSED / PASS
- QA final: events `4 → 5`; route points `2 → 2`; active capabilities `0/0`.
- Evidencia canónica: `docs/TRACKING_CLOSURE.md`.
- Pendientes adyacentes de SEC.4 y fases posteriores no reabren M4.

## Acceso y seguridad

- Runtime Admin: PASS.
- RBAC.3A, RBAC.3B y RBAC.3C: merged/deployed.
- Runtime Finance: pendiente de una credencial legítima; no usar credenciales sustitutas.
- SEC.4: carril de remediación de credenciales activo.

## Producto

- F1–F10: merged en `main`; migraciones aplicadas y verificadas en Supabase staging.
- F3–F10: activos en Netlify staging sobre el mismo `main` verificado.
- F8 Rates/Partner360, F9 Compliance/Contracts y F10 Claims/Customer Service: staging PASS mediante el release acumulado R3.
- F7: `pg_cron` instalado y saludable; conserva exactamente los jobs hourly y daily digest con sus schedules canónicos.
- R2.2: completado con backup lógico POST_F4_PRE_F5 restaurable y verificado.
- R3: completado con backup lógico PRE_F8_F10 restaurable y verificado; rollout DB, deploy staging y smoke HTTP aprobados.
- QA visual/manual de F1–F10: pendiente; el smoke HTTP de staging está aprobado.

## Límites vigentes

- Producción: sin cambios durante R3.
- Auth, Edge Functions y llaves: sin cambios durante R3.
- Runtime Finance: sigue pendiente de una credencial legítima.
- Tracking M4: permanece CLOSED / PASS, sin cambios de capacidades durante R3.
- SEC.4: no fue modificado por R3; conserva su carril activo.

Actualizar este archivo solo con estado verificado y aprobado. El código, los contratos y el target observado prevalecen si existe drift.
