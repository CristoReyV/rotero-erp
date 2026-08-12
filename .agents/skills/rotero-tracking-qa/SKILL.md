---
name: rotero-tracking-qa
description: Ejecutar QA reusable del tracking de ROTERO, incluidos contratos RPC, capability tokens, QR local, Edge Functions y aislamiento de scopes. Usar para matrices positivas/negativas de `track-public`, `driver-view` o `track-driver`, con snapshots, escrituras seguras y limpieza final.
---

# ROTERO Tracking QA

## Establecer contrato

1. Leer `docs/codex/CURRENT_STATE.md` solo si importan fase, operación o targets actuales.
2. Tratar las definiciones RPC, pruebas contractuales, configuración y código vigentes como source of truth. Usar `docs/TRACKING_EDGE_FUNCTIONS.md` y `docs/DB_BASELINE.md` como contexto, no como sustituto del código.
3. Confirmar los scopes independientes:
   - `public:read`: lectura pública;
   - `driver:write`: vista y escritura del operador.
4. Confirmar antes de probar qué create, rotate y revoke están autorizados.

## Proteger capabilities

- Tratar cada capability token como secreto one-time.
- No persistir, copiar a documentación, registrar en logs ni devolver el token en evidencia.
- Construir el enlace y QR localmente solo durante la acción autorizada; no subir el QR ni su payload.
- Rotar o revocar mediante los contratos vigentes; no manipular hashes o filas directamente.
- Mantener aislados `public:read` y `driver:write`; un scope nunca debe adquirir capacidades del otro.

## Ejecutar la matriz

1. Tomar snapshot PRE de eventos, route points, tokens activos y cualquier tabla afectable de la operación QA.
2. Probar casos positivos y negativos aprobados para:
   - `track-public` con `public:read`;
   - `driver-view` con `driver:write`;
   - `track-driver` con `driver:write`.
3. Incluir token ausente, inválido, revocado/expirado y scope incorrecto cuando estén en la matriz.
4. Verificar status y shape sanitizado; ninguna respuesta o evidencia pública debe exponer `SQLERRM`, hashes, tokens o secretos.
5. No usar browser, Playwright, Chromium ni screenshots. Usar requests directos autorizados y redactar capabilities.

## Controlar escrituras

- Usar únicamente la operación QA indicada; no improvisar fixtures u operaciones.
- Ejecutar exactly one safe `track-driver` positive write solo cuando la tanda lo indique expresamente.
- Tomar snapshot POST y reconciliar deltas por tabla con el efecto esperado.
- Detenerse de inmediato ante DML inesperado, scope leakage, delta distinto o respuesta no sanitizada.
- No repetir una escritura positiva para “confirmar” si rompería exactly-one-write.

## Cerrar

1. Revocar todas las capabilities creadas o rotadas durante QA.
2. Confirmar active capability residue = 0.
3. Confirmar capability artifacts = 0 en archivos, logs y evidencia.
4. Reportar matriz, PRE/POST, delta exacto, revocación y bloqueos sin incluir capabilities.
5. No iniciar la siguiente fase sin autorización.
