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
- SEC.4B: CLOSED / STAGING PASS. `driver-view` v5, `track-public` v5 y
  `track-driver` v7 ejecutan el merge `b64c202` con `verify_jwt=false`.
- El resolver Tracking acepta únicamente la secret moderna nombrada
  `trackingedge`; la ausencia o forma inválida falla con
  `503 tracking_service_unavailable` y no usa `service_role`.
- Canary staging: customer/driver positivos, scope/invalid/revoked denegados,
  eventos `5 → 5`, route points `2 → 2`, residue activo `0/0` y artefactos de
  capability `0`.

## Acceso y seguridad

- Runtime Admin: PASS.
- RBAC.3A, RBAC.3B y RBAC.3C: merged/deployed.
- Runtime Finance: pendiente de una credencial legítima; no usar credenciales sustitutas.
- SEC.4: carril de remediación de credenciales activo.
- SEC.4B retiró del runtime Tracking los fallbacks singular y `service_role`.
  Las llaves legacy del proyecto NO fueron deshabilitadas: Netlify/frontend aún
  declaran consumidores anon legacy y los consumidores externos siguen sin un
  inventario autoritativo completo.

## Producto

- F1–F10, BH1, R4.1 y BH2: merged en `main`, con migraciones aplicadas y verificadas en Supabase staging.
- R5 desplegó BH2 en staging con DB lint remoto en 0 errores, historiales Partner360 paginados, precedencia `business_contacts` → `contact_*` → fallback legacy y fechas de negocio tenant-aware activas.
- F3–F10 y los hardenings BH1/R4.1/BH2: activos en Netlify staging con lazy routing saludable; bundle inicial BH2 `361.56 kB / 114.86 kB gzip`.
- F8 Rates/Partner360, F9 Compliance/Contracts y F10 Claims/Customer Service: staging PASS mediante el release acumulado R3.
- F7: `pg_cron` instalado y saludable; conserva exactamente los jobs hourly y daily digest con sus schedules canónicos.
- El onboarding por invitación permanece deshabilitado: `/invite/:token` redirige a login, los overloads legacy están fail-closed y el aprovisionamiento beta sigue siendo manual.
- R2.2: completado con backup lógico POST_F4_PRE_F5 restaurable y verificado.
- R3: completado con backup lógico PRE_F8_F10 restaurable y verificado; rollout DB, deploy staging y smoke HTTP aprobados.
- R4.1: completado con backup lógico POST_BH1_PRE_INVITE_FIX restaurable y verificado; rollout DB, lint remoto, seguridad, deploy staging y smoke HTTP aprobados.
- R5: completado con backup lógico PRE_BH2 restaurable y verificado; rollout BH2, seguridad, integridad, deploy staging y smoke HTTP aprobados.
- R6.2: FISCAL.0 provider-neutral activo en Supabase staging con 38 migraciones y `20260903000000_fiscal0_provider_neutral_readiness` como última versión. La migración aún no aplicada se reconcilió con la forma Billing real: el contexto operativo se deriva por `billing_documents.linked_cfdi_id` + `billing_documents.operation_id`, sin duplicar `operation_id` en `billing_cfdis`.
- FISCAL.0 permanece fail-closed: adaptador Soft Management `NOT_CONFIGURED`, configuraciones/solicitudes/intentos persistentes en cero, llamadas al proveedor `0` y ningún secreto fiscal agregado. DB lint remoto: 0 errores.
- R6.2 desplegó el merge verificado a Netlify staging; smoke HTTP aprobado en rutas ERP, públicas y de operador. Bundle inicial `361.71 kB / 114.96 kB gzip`.
- QA visual/manual de F1–F10/BH1/BH2: pendiente; el smoke HTTP de staging está aprobado.
- Integración real con proveedor Fiscal API y documentación oficial de Soft Management: pendientes.

## Límites vigentes

- Producción: sin cambios durante R5.
- Auth, Edge Functions y llaves: sin cambios durante R5.
- Runtime Finance: sigue pendiente de una credencial legítima.
- Tracking M4: permanece CLOSED / PASS, sin cambios de capacidades durante R4.1.
- SEC.4: no fue modificado por R5; conserva su carril activo.
- R6.2 no modificó producción, Auth, Edge Functions, Tracking ni SEC.4.
- SEC.4B modificó y desplegó únicamente las tres Edge Functions de capability
  Tracking en staging. Producción, Auth users, Finance y Fiscal permanecieron
  sin cambios; ninguna llave legacy fue deshabilitada.

Actualizar este archivo solo con estado verificado y aprobado. El código, los contratos y el target observado prevalecen si existe drift.
