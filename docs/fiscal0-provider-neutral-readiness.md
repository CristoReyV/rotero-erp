# FISCAL.0 — Provider-neutral fiscal readiness

## Alcance y estado

FISCAL.0 prepara ROTERO para integrar un proveedor fiscal mexicano sin implementar ni llamar a un PAC. No contiene endpoints, transporte, autenticación, payloads, códigos de error, webhooks ni serialización de Soft Management. La integración real queda cerrada (`provider_not_configured`) hasta FISCAL.1.

## Inventario y gap map

`billing_cfdis` ya era el agregado fiscal canónico: tenant, operación, UUID, serie/folio, RFC emisor/receptor, importes MXN/USD, tipo de cambio, Carta Porte, estado interno y proveedor PAC nominal. `billing_carta_porte` conserva el contexto logístico; `billing_documents` y F4 conservan los documentos/efectos contables; F3 aporta Storage privado, SHA256, relaciones y URL firmada de 300 segundos. Billing ya estaba restringido a Admin/Finance y mostraba los datos como registros internos.

`20260515120000_billing_api_ready_fiscal_backend.sql` es un marcador histórico sin efectos recuperables. No existían snapshot fiscal inmutable, ciclo fiscal separado, configuración no secreta, outbox, intentos, idempotencia, preflight, límite de adaptador, reconciliación o acciones reales de UI. No se modificó ninguna migración histórica.

Contratos reutilizados:

- `billing_cfdis` y `billing_carta_porte`, sin una factura paralela.
- F4 como única verdad de AR/AP, pagos, saldos y liquidación.
- F3 `tenant-documents`, artefactos privados, checksum, relaciones y descarga firmada.
- `audit_log` mediante `rpc_write_audit`.
- RBAC actual: Admin y Finance operan Billing; otros roles, público y Driver no reciben datos fiscales internos.

## Agregado y ciclo fiscal

El estado legado `billing_cfdis.status` no se reutiliza como verdad externa. `fiscal_status` modela exclusivamente la vida fiscal:

```text
draft → ready_for_api → queued → submitting → processing
                                      ├─→ stamped → cancellation_requested → cancelled
                                      │                         └─→ cancellation_rejected
                                      ├─→ rejected → draft (corrección explícita)
                                      └─→ api_error → queued (reintento técnico) | draft
```

No se permiten saltos arbitrarios. `stamped` significa aceptación/timbrado fiscal; no significa pagado. Cancelar fiscalmente no borra facturas, pagos, saldos, complementos ni historial de Finance. Una reconciliación tardía `stamped` preserva una cancelación pendiente o ya confirmada. `not_found` nunca destruye verdad local timbrada: registra `status_conflict` para revisión.

El agregado añade proveedor/documento externo, versión CFDI, timestamps, error seguro, fingerprint y enlaces XML/PDF. `fiscal_input` solo puede cambiar en `draft`. Al validar se crea `fiscal_snapshot`; después es inmutable salvo regreso explícito desde rechazo/error a borrador. El snapshot es un DTO ROTERO, no un payload de proveedor, e incluye emisor, receptor, conceptos, impuestos, pago, relacionados, moneda/importes y referencia provider-neutral a Carta Porte.

## Preflight, identidad y concurrencia

El preflight verifica datos que ROTERO conoce: RFC de emisor/receptor, moneda admitida, importes positivos/coherentes, conceptos con descripción/importe, método de pago y relación con operación o documento de Billing. No pretende validar todo el Anexo 20 ni reglas SAT que requieren catálogos/contrato aún no incorporados.

El fingerprint SHA256 se calcula sobre la representación JSONB estable del snapshot. Una solicitud `stamp` usa `SHA256(stamp + cfdi + fingerprint)`. El lock transaccional por CFDI y dos índices únicos garantizan una sola identidad y una sola solicitud activa por tipo, incluso ante doble clic o carreras. Cancelación también usa razón + identidad documental y solo admite una solicitud activa.

## Outbox, intentos y retry

`fiscal_requests` es una outbox enfocada, no un framework genérico ni una cola F7. Soporta `stamp`, `status`, `cancel`, `fetch_xml` y `fetch_pdf`; conserva snapshot, idempotency key, bloqueo, intentos y programación acotada. `private.fiscal0_claim_requests` usa `FOR UPDATE SKIP LOCKED` y solo queda disponible al owner/server boundary.

`fiscal_provider_attempts` es append-only. Guarda tiempos, status HTTP opcional, código de proveedor opcional, resultado normalizado y error seguro; un trigger impide UPDATE/DELETE. No guarda headers, credenciales, certificados, XML/PDF en base64 ni cuerpo bruto. Los errores técnicos se reintentan hasta tres veces con backoff acotado. Rechazos de negocio, payload inválido, ya timbrado y cancelación rechazada no se reintentan automáticamente.

## Adaptador y límite server-side

`supabase/functions/_shared/fiscal-provider.ts` define `FiscalProviderAdapter` con DTOs ROTERO y operaciones `submit`, `getStatus`, `cancel`, `getXml` y `getPdf`. El registro reconoce `soft_management` únicamente como identificador candidato y responde `provider_not_configured`; no existe cliente Soft Management. El mock vecino exige runtime literal `test` y cubre resultados deterministas; no puede seleccionarse desde configuración de tenant (`mock` está prohibido).

El flujo futuro es:

```text
Billing autenticado → RPC tenant/role-safe → outbox
→ Edge worker autenticado/owner → adapter → PAC
→ resultado normalizado → DB → F3 Storage privado
```

FISCAL.0 no crea endpoint Edge, webhook ni despliegue. Las funciones privadas son el límite de persistencia para un worker futuro y no tienen EXECUTE para PUBLIC, anon, authenticated ni service_role.

## Secretos y ambientes

Ningún secreto se almacena en tablas o Vite. Los nombres conceptuales reservados son `FISCAL_PROVIDER`, `FISCAL_API_BASE_URL`, `FISCAL_API_USER`, `FISCAL_API_SECRET` y `FISCAL_WEBHOOK_SECRET`; deberán ajustarse cuando exista documentación oficial. Nunca se versionan valores, certificados o llaves.

`fiscal_provider_configs` solo persiste código, enabled, ambiente (`sandbox|production`) y capacidades no secretas. Rechaza nombres obvios de secreto. Falta de configuración falla cerrada. Un runtime que no declara explícitamente `production` no puede consumir configuración production; staging nunca cae a production y no hay fallback entre ambientes.

## Artefactos, callback y polling

XML/PDF se almacenarán como `document_files` privados F3 bajo `billing/billing_cfdi`, con SHA256 y relación explícita a operación, Finance y dossier de cliente cuando corresponda. XML es la evidencia fiscal autoritativa e inmutable; PDF es una representación secundaria. Nunca hay URL pública ni documento base64 persistente; la descarga exige acceso explícito y URL firmada por 300 segundos.

Si el proveedor ofrece webhook, FISCAL.1 deberá verificar firma, deduplicar evento, resolver tenant desde identidad confiable del proveedor, ignorar tenant suministrado por caller y aplicar el resultado idempotentemente. Si no ofrece webhook, se usará polling mediante el adaptador. FISCAL.0 no activa ninguno.

## Auditoría, observabilidad y UI

Se auditan cambios de entrada, ready, queue, intentos, retry, status/cancel request y artefactos, siempre con metadatos seguros. No se auditan secretos, headers, certificados, XML ni cuerpos brutos. Admin/Finance pueden consultar profundidad de cola, fallos técnicos y procesos de más de 30 minutos.

Billing muestra operación, cliente, importe/moneda, estado fiscal, UUID, proveedor/ambiente, último intento, error seguro y artefactos. Los botones Validar, Enviar, Reintentar, Consultar, Cancelar y Descargar derivan del ciclo. Sin proveedor se muestra `Proveedor fiscal no configurado` y se deshabilitan acciones externas; nunca se simula timbrado. El guard frontend evita doble submit, pero la garantía real está en la base.

F7 no es cola fiscal. No se añadió cron, regla ni notificación para evitar spam mientras el proveedor está inactivo. Una integración futura puede materializar atención por `fiscal_request_failed`, `fiscal_processing_stale` y `cancellation_failed` usando la arquitectura existente, sin ejecutar trabajo fiscal desde F7.

## Información exacta requerida de Soft Management

Antes de FISCAL.1 se requiere documentación oficial y versionada de:

1. Producto/PAC legal y ambientes sandbox/production, URLs oficiales y SLA.
2. Protocolo (REST/SOAP u otro), versión, WSDL/OpenAPI/esquemas y límites.
3. Autenticación, rotación, IP allowlist, custodia de CSD/certificados y expiración.
4. Contrato completo para CFDI 4.0: request, response, catálogos, namespaces y codificación.
5. Carta Porte aplicable: versión, campos obligatorios, validaciones y muestras oficiales.
6. Idempotencia del proveedor, consulta por identidad, recuperación tras timeout y duplicados.
7. Estados, transiciones, códigos de negocio/técnicos, retry-after y límites de tasa.
8. Cancelación SAT: motivos, sustitución, aceptación, plazos, acuses y consulta.
9. Obtención de XML/PDF, integridad, retención, regeneración y disponibilidad.
10. Webhooks si existen: eventos, firma, replay window, retries, orden, dedupe y source IPs.
11. Datos permitidos en logs, soporte, trazabilidad y política de privacidad/retención.
12. Proceso de certificación, pruebas oficiales y contacto técnico de escalación.

## Checklist FISCAL.1

- Aprobar contrato y mapping Soft Management contra DTOs canónicos, sin cambiar UI/Finance al proveedor.
- Implementar adapter server-side con cliente generado o validado desde documentación oficial.
- Definir secretos reales por ambiente fuera de Git y probar fail-closed/rotación.
- Crear worker Edge autenticado que reclame outbox; no exponer helpers privados al cliente.
- Mapear errores y retry según contrato real; mantener resultados y logs redactados.
- Implementar webhook verificado o polling, nunca ambos por suposición.
- Serializar CFDI/Carta Porte con fixtures oficiales y validación SAT acordada.
- Guardar XML/PDF vía F3, verificar SHA256 y relaciones tenant-safe.
- Ejecutar sandbox end-to-end, carreras, timeouts, recuperación, cancelación y reconciliación.
- Revisar seguridad, pg_proc, RLS/ACL, observabilidad, runbook y release separado antes de producción.

## Release

Migración única: `20260903000000_fiscal0_provider_neutral_readiness.sql`. Release actual: Draft PR solamente; sin push de DB, provider calls, Edge deploy, Netlify, secretos o producción.
