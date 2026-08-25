# F10 — Claims & Customer Service 360

## Alcance y gap map

F10 agrega control interno de reclamaciones de servicio para Admin. Antes de esta migración, F2 registraba incidentes operativos y evidencia, F3 administraba documentos privados, F5 componía Dashboard/Attention/Search/vistas, F7 materializaba automatizaciones y F9 administraba cumplimiento y contratos. No existía expediente de reclamación, SLA, timeline, acciones, contacto estructurado, exposición ni resolución.

F10 compone esos módulos sin duplicarlos:

- El incidente F2 sigue siendo un evento operativo. Una reclamación puede referenciarlo, pero no cambia su estado ni reemplaza su evidencia.
- La evidencia usa el bucket privado `tenant-documents`, SHA256, compensación de huérfanos y URL firmada de 300 segundos de F3.
- Dashboard, Attention, búsqueda global, paleta y vistas guardadas se extienden de forma aditiva.
- Las cuatro reglas F10 se materializan después de las evaluaciones F7 existentes; no se agrega cron, HTTP, Edge ni Vault.
- Customer360 y Provider360 muestran expedientes relacionados mediante un RPC aditivo Admin-only.
- Los vínculos a requisito o contrato F9 son contexto; no alteran elegibilidad ni contratos.

## Contrato funcional

El folio `CLM-AAAA-NNNNNN` usa una secuencia atómica por tenant y año comercial. El expediente exige al menos una operación, cliente o proveedor del mismo tenant. El lifecycle es explícito y resolución/cierre/cancelación requieren motivo. La reapertura conserva el resumen y las fechas anteriores en el timeline.

Los SLA sembrados son defaults internos configurables, no plazos legales ni promesas contractuales:

| Prioridad | Primera respuesta | Resolución |
| --- | ---: | ---: |
| Crítica | 2 h | 24 h |
| Alta | 4 h | 48 h |
| Media | 8 h | 96 h |
| Baja | 24 h | 168 h |

La responsabilidad y causa raíz son clasificaciones operativas internas; no determinan culpa o responsabilidad legal. La exposición se mantiene por moneda exacta (`MXN` o `USD`) y nunca se suma entre monedas ni se convierte con FX inventado. El acuerdo registrado tampoco crea asientos, AR/AP, pagos o notas en F4. El handoff abre Finance 360 para que un usuario autorizado cree el ajuste explícitamente.

No existe envío externo de correo, WhatsApp o SMS. Comunicación es una bitácora sobre contactos estructurados tenant-safe.

## Automatizaciones

Reglas Admin-only con fingerprint estable y resolución derivada:

- `claim_first_response_overdue`
- `claim_resolution_overdue`
- `claim_action_overdue`
- `critical_claim_open`

Se incluyen en notificaciones y digest F7. Repetir la evaluación no duplica filas; una condición que deja de ser verdadera resuelve la notificación y una recurrencia posterior reinicia su ciclo. Los dos cron F7 permanecen exactamente en `0 * * * *` y `15 12 * * *`.

## Seguridad y release

Las tablas tienen RLS Admin-only y no otorgan DML directo. Los RPC normales son `SECURITY DEFINER`, fijan `search_path`, validan tenant/rol internamente y sólo conceden `EXECUTE` a `authenticated`; `PUBLIC`, `anon` y `service_role` quedan revocados. Los helpers privados no son ejecutables por roles de API. Finance no recibe rutas, búsquedas, notificaciones, digest ni datos Claims. Tracking público/driver, Auth y Edge no cambian.

El preflight read-only contra staging del 24-ago-2026 encontró cero tablas o funciones remotas con nombre `claim`; por tanto, la colisión exacta previa de F10 es **0**. La migración usa `CREATE FUNCTION`, no reemplaza RPC remotos.

Migración local nueva: `20260830000000_f10_claims_customer_service.sql`. El preflight linked read-only del 24-ago-2026 confirmó como pendientes, exactamente y en este orden:

1. `20260828000000_f8_rates_partner_360.sql`
2. `20260829000000_f9_compliance_contracts.sql`
3. `20260830000000_f10_claims_customer_service.sql`

La release sigue pendiente: no ejecutar `db push`, repair, deploy ni escrituras de staging desde este PR. En release, revalidar el listado remoto y el dry-run antes de cualquier push autorizado; F10 depende de que F8 y F9 se apliquen primero.

## QA manual diferido y F11

Este slice prohíbe navegador/Playwright. Tras una release autorizada, el smoke manual pendiente es: crear desde operación/incidente, verificar filtros/deep links, subir/abrir/descargar evidencia privada, completar acción, resolver/reabrir, revisar Partner360, Dashboard, Attention, búsqueda, paleta, vistas, CSV y confirmar aislamiento con Finance.

Fuera de F10 y candidato a F11: mensajería externa real con consentimiento/plantillas, integraciones legales o aseguradoras, contabilización automática aprobada y analítica avanzada de calidad. Nada de ello se simula aquí.
