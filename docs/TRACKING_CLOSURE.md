# Tracking M4 — cierre y evidencia

> Estado: `CLOSED / PASS` · Fecha: 2026-08-13 · Entorno validado: staging

Este documento concentra la evidencia mínima auditable de M4.1–M4.5. Las
definiciones SQL, Edge y frontend versionadas siguen siendo la fuente de verdad;
las especificaciones históricas conservan contexto, pero no sustituyen al código
ni a las pruebas vigentes.

## Alcance cerrado

| Fase | Resultado verificable |
| --- | --- |
| M4.1 — contratos | PR #10 reconciliada y mergeada (`a602c8f`): creación/rotación, listado sanitizado y revocación de tokens; scopes separados y ACL explícita. |
| M4.2 — UI real | PR #13 mergeada (`b678de1`): `/tracking` consume contratos reales, genera enlaces correctos y crea QR local sin persistir el literal. |
| M4.3 — QA integral | PASS funcional en staging para generación, lectura PUBLIC/DRIVER, rotación y revocación. |
| M4.4 — Edge positivo | PASS para `track-public`, `driver-view`, aislamiento de scopes y una sola escritura segura de `track-driver`; cleanup y regresión post-revocación aprobados. |
| M4.5 — evidencia | Cierre consolidado en este documento; no ejecuta QA adicional ni modifica producto o infraestructura. |

El harness seguro usado en M4.4 quedó versionado mediante PR #15 (`d6f716b`):
una instancia, máximo un prompt por scope, resultado terminal sanitizado, sin
retry/relaunch y cleanup obligatorio después de parsear ambas capabilities.

## Contratos y permisos cerrados

- `public:read` habilita únicamente la vista pública mediante `track-public`.
- `driver:write` habilita `driver-view` y el envío controlado a `track-driver`.
- Usar un scope en la superficie del otro queda denegado.
- Crear, rotar y revocar requiere sesión `authenticated` con rol `admin` u
  `operator`; `viewer` conserva listado de metadatos, pero no administración.
- El listado no expone `token_hash`, prefijos ni literales.
- Los RPC administrativos no conceden ejecución a `PUBLIC`, `anon` ni
  `service_role`. Los RPC privados consumidos por Edge conservan únicamente la
  ejecución necesaria para `service_role` y validan la capability dentro del
  contrato versionado.
- La pertenencia al tenant, los scopes, TTL y aislamiento cross-tenant quedaron
  cubiertos por las suites contractuales y la QA integral.

## Evidencia final M4.4

Operación controlada: `BETA-STG-OPS-005`.

| Señal | PRE | POST | Resultado |
| --- | ---: | ---: | --- |
| Eventos de tracking | 4 | 5 | `+1`, exactamente la escritura positiva autorizada |
| Puntos de ruta | 2 | 2 | Sin cambio |
| Capability `public:read` activa | 0 | 0 | Residuo final cero |
| Capability `driver:write` activa | 0 | 0 | Residuo final cero |
| `tracking_access_log` | 0 | 0 | Sin fila persistida en esta ejecución |
| Runners vivos | 0 | 0 | Sin procesos pendientes |
| Artefactos de capability | 0 | 0 | Sin archivos o resultados con capabilities |

La matriz positiva terminó con `exit_code=0`, `write_count=1`, sin HTTP 500,
`SQLERRM`, fuga de scope ni DML de negocio inesperado. Después de la revocación
manual se verificó que las capabilities originales quedaron denegadas y que el
intento de escritura post-revocación produjo delta DML cero.

El evento adicional es residuo QA esperado y deliberado del único caso positivo
autorizado. No debe borrarse ni compensarse como parte de este cierre.

## Evidencia sensible

Los literales, URLs completas, UUID de tokens y hashes de capability nunca se
retuvieron como evidencia. No están en este documento, resultados terminales,
logs versionados ni artefactos temporales. La evidencia conserva únicamente
conteos, scopes, estados, códigos sanitizados y deltas.

## Pendientes fuera de M4

Estos asuntos son adyacentes a Tracking, pero no reabren ni bloquean M4:

- **SEC.4:** retirar `legacy_fallback` y la credencial legacy de `service_role`
  solo mediante una tanda de hardening separada, con evidencia de logs y plan de
  rollback. No se revoca ninguna key por este cierre.
- **Observabilidad posterior:** `tracking_access_log` permaneció en cero aunque
  `track-public` respondió correctamente; evaluar el logging best-effort en una
  tarea separada si se requiere evidencia operativa de accesos.
- **Hardening futuro:** la idempotencia general por `clientTimestamp` no forma
  parte del contrato cerrado y debe tratarse como backlog independiente.
- **GPS externo/Traccar:** sigue siendo una fase futura y no es requisito del
  flujo broker-first ni del cierre actual.

## Veredicto

`LISTO M4 TRACKING CLOSED / PASS`
