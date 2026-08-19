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

- F1 Commercial 360: Draft PR #21 corregido y validado localmente contra contratos staging-like; permanece sin merge ni deploy y no se declara validado en runtime staging.

Actualizar este archivo solo con estado verificado y aprobado. El código, los contratos y el target observado prevalecen si existe drift.
