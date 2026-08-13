# ROTERO Codex — estado actual

Leer este archivo solo cuando la tarea dependa de la fase o de targets actuales. Verificar cada target antes de una escritura externa. No guardar aquí secrets, hashes, JWT ni capability tokens.

## Targets

- Main vigente: resolver dinámicamente `origin/main` durante el preflight Git; no fijar un SHA como requisito reusable.
- Último main verificado antes del harness (trazabilidad): `b678de1aca07a31a4e0c3f65ce1db9930babeb84`
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

Actualizar este archivo solo con estado verificado y aprobado. El código, los contratos y el target observado prevalecen si existe drift.
