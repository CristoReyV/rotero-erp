# FACTURAMA-01 — integración sandbox de FISCAL.0

Fecha: 2026-10-23. Estado: **recorrido local con servicio sandbox real; exposición
general y producción cerradas**. El acuse de cancelación no se considera aprobado
cuando su UUID no corresponde al comprobante. No es una habilitación productiva.

## Base y dependencias

- `main` verificado inicialmente en `55cffc06fe3cc5e44c093c55c9dd6cad187567e7`.
- Base deliberada `32b2c7ef3cfbadecc1458cb083dd50f74449ec98`: incorpora sólo los
  commits revisados MULTI-04 (`b694b7c…`) y MULTI-05 (`32b2c7e…`). Se necesitan
  `companies`, acceso empresarial y `multi05_has_company_capability`.
- No se porta MULTI-06 ni el trabajo sin commit de MULTI-07. Sus contratos de
  Operaciones/Finance y los worktrees existentes se preservan.
- No se sustituye FISCAL.0: se reutilizan `billing_cfdis`, `fiscal_requests`,
  `fiscal_provider_attempts`, sus transiciones, auditoría y la pantalla Billing.
  Softmanagement y sus evidencias permanecen intactos, sin invocación o fallback.

## Contratos oficiales consultados

- [Basic Auth](https://facturama.mx/docs/es/guias/autenticacion).
- [Multiemisor](https://facturama.mx/docs/es/api-lite/pasos-api-multiemisor),
  [creación v4](https://facturama.mx/docs/es/api-lite/crear-cfdi),
  [consulta](https://facturama.mx/docs/es/api-lite/consultar-cfdi).
- [CSD](https://facturama.mx/docs/es/api-lite/cargar-csds) y
  [certificados oficiales de prueba](https://facturama.mx/docs/es/catalogos/csds-pruebas).
- [Pagos 2.0](https://facturama.mx/docs/es/complementos/complemento-pago),
  [cancelación](https://facturama.mx/docs/es/api-lite/cancelar-cfdi) e
  [idempotencia](https://facturama.mx/docs/es/cfdi40/idempotencia).
- [Colección oficial](https://github.com/Facturama/facturama-api-collections):
  `bruno/API-Lite/Cfdis/Descargar Cfdi.yml` y
  [referencia de descarga](https://api.facturama.mx/Docs/Api/GET-api-Cfdi-format-type-id).
  El sandbox real usa `GET /api/Cfdi/xml/issuedLite/{id}`. La ruta `/cfdi/xml/...`
  devolvió 404; se corrigió la lectura, sin volver a emitir.

El proveedor documenta folio/fecha fijos y consulta antes del reenvío. No se
supone un header idempotente universal. La prueba deliberada de un segundo POST
idéntico devolvió el mismo ID; esto no certifica todos los casos concurrentes del
proveedor. El ERP evita el segundo POST mediante su propia lease persistente.

## Implementación y estados

`facturama.ts` implementa la frontera `FiscalProviderAdapter`. Sólo admite
`https://apisandbox.facturama.mx`, rutas/métodos enumerados y redirecciones
deshabilitadas. Basic Auth existe únicamente en memoria servidor. Las respuestas
tienen plazo y límite de tamaño; los errores no contienen cuerpos o headers.

La función `fiscal-sandbox` valida el JWT con `getUser`, deriva el actor verificado
y usa RPC servidor. El wrapper desplegable exige proyecto staging exacto,
`FACTURAMA_SANDBOX_ENABLED=true` y `FACTURAMA_ENVIRONMENT=sandbox`; el valor por
defecto es cerrado. La inyección de clientes locales en `handler.ts` sirve a las
pruebas, y no es una opción de URL/entorno enviada por el navegador.

La migración `20261023180009_facturama01_sandbox_execution.sql` añade:

| Objeto privado | Propósito |
|---|---|
| `fiscal01_company_bindings` | Empresa/tenant → emisor de prueba, sandbox y habilitación explícita |
| `fiscal01_lab_actors` | Allowlist temporal y aprobada, sin asignaciones iniciales |
| `fiscal01_draft_scope` | Clasificación explícita del CFDI de prueba; sin deducciones por nombre/creador/default |
| `fiscal01_documents` | Extensión del agregado existente: payload proveedor congelado, SHA-256, lease, ID proveedor y evidencia privada |
| `fiscal01_invoice_links` | Vínculo explícito a la factura financiera existente |
| `fiscal01_receipts` | Cabecera del cobro, con referencia administrativa distinta del folio fiscal |
| `fiscal01_applications` | Aplicaciones a `finance_payments`, saldos y parcialidad congelados |

Todas tienen RLS y ACL cerradas, sin administración pública. Las FKs vinculan
tenant/empresa/CFDI/factura/pago; se impiden cambios de parent e identidades
congeladas. Unicidad del identificador proveedor y de emisor/serie/folio/fecha
evita reutilizar una identidad fiscal entre empresas del sandbox compartido.
No hay seeds ni backfill en la migración.

El hash persistido de emisión es SHA-256 de UTF-8 del `jsonb::text` de PostgreSQL.
El payload es inmutable antes del primer POST. No se compara ese hash con otra
serialización JSON. También se conserva SHA-256 del XML validado.

- `draft → ready_for_api → queued → submitting`: validación, congelación y claim
  exclusiva, con fila de `fiscal_requests` e identificador local.
- Sólo XML correlacionado permite `stamped`. Se comprueban namespaces, versión,
  UUID, emisor/receptor, serie/folio/fecha e importes; para REP, las aplicaciones.
  Se registra la fecha del timbre XML. HTTP 200 por sí solo no acredita emisión.
- Resultado perdido, 5xx, descarga aún no disponible o persistencia interrumpida:
  `processing` + `uncertain`. Se guarda el ID tan pronto existe. Consultar puede
  reconciliar por folio/fecha/emisor; **no hay reenvío automático**.
- Un 400 definitivo de creación, sin ID proveedor, queda `rejected`. No revive
  la cola ni permite editar el payload enviado. La corrección necesita un nuevo
  borrador explícito; no se implementa un editor general de revisiones fiscales.
- Lease abandonada: sólo una consulta de estado puede recuperarla después de
  dos minutos. No se concede permiso de volver a emitir por vencer el plazo.
- Cancelación: petición explícita confirmada y motivo SAT; `01` exige sustituto,
  los demás no lo envían. Estado remoto y acuse se verifican por separado. Un
  acuse no correlacionado va a cuarentena privada y conserva estado pendiente.

XML/acuse se almacenan en bucket privado `fiscal-sandbox`, separado de las
políticas legacy de documentos. No hay lectura Storage directa para usuarios;
el servidor vuelve a autorizar y entrega el archivo, sin URL firmada persistente.
Se verifica correspondencia fiscal, **no una validación criptográfica SAT/XSD
independiente** de todas las firmas, catálogos y reglas.

## Capacidades y exposición

| Acción | Requisito adicional al acceso empresarial vigente |
|---|---|
| Preparar | `fiscal.prepare` |
| Emitir | `fiscal.issue` |
| Consultar / XML | `fiscal.read` |
| Cancelar | `fiscal.cancel` |
| Aplicar cobro / REP | `fiscal.payment` |

Se reutiliza el mismo registro y helper MULTI-05, ampliando sólo su vocabulario.
Además se exigen binding sandbox habilitado y actor en allowlist vigente. No
hay grants automáticos por admin/finance ni APIs de autoasignación. Los RPC de
worker/aplicación sólo son ejecutables por servidor; el contexto mínimo para UI
devuelve `available=false` ante denegación, sin provocar el logout global del
cliente por un 403 de una opción experimental.

No se concede `financial.full.read`, exportación financiera ni consolidación a
QA. Las vinculaciones personales aprobadas de MULTI-05 siguen pendientes de
verificación y no cambian. Leer el propio documento fiscal para una tarea no
autoriza consultar costos, utilidad, márgenes o todas las finanzas.

**No se declara aislamiento integral:** lecturas/escrituras legacy, documentos,
Storage anterior, jobs y Reportes siguen dependiendo de la adopción MULTI. Por
ello la integración se limita a fixtures sin operación, RFC oficiales de prueba
y un tenant local exclusivo. No se habilita selector empresarial ni consolidado.

## Pagos y límites contables

Se usa `finance_invoices` / `finance_payments` / `billing_payment_complements`;
la cabecera nueva agrupa varias aplicaciones existentes, sin duplicar un libro
financiero. Se conserva la regla F4: saldo agotado → factura pagada. Hay exclusión
por empresa, snapshots de saldo anterior/pagado/insoluto y parcialidad, referencia
administrativa independiente y protección contra duplicar una cabecera.

Este bloque admite exclusivamente AR, MXN, PPD, transferencia y conceptos de una
unidad con IVA 16%. Rechaza históricos sin vínculo inequívoco, pagos previos no
correlacionados, notas de crédito, nómina, otras monedas y empresas incompatibles.
No inventa saldos ni el siguiente folio PMT real: usa series `QA…` exclusivamente
de prueba. No anula un pago económico al cancelar su REP. Reemisión/reversión,
equivalencias de moneda, retenciones y la política productiva de PMT requieren
decisiones y contratos adicionales antes de habilitar esos casos.

## Configuración y reproducción segura

Servidor: `FACTURAMA_SANDBOX_USER`, `FACTURAMA_SANDBOX_PASSWORD`,
`FACTURAMA_ENVIRONMENT=sandbox`, `FACTURAMA_SANDBOX_ENABLED=true`, y credenciales
Supabase del runtime. Nunca `VITE_*`, argumentos con secretos ni archivos
versionados. La custodia de la prueba usa DPAPI para el usuario Windows ejecutor;
el informe local identifica el almacén, sin credenciales. Para staging se necesita
un gestor de secretos autorizado y una recuperación comprobada antes del DDL.

Pruebas locales:

```sh
npm ci
npm run lint
node --import tsx --test supabase/functions/_shared/facturama.test.ts \
  supabase/functions/_shared/fiscal-provider.mock.test.ts src/services/fiscalContracts.test.ts
deno check --config supabase/functions/fiscal-sandbox/deno.json supabase/functions/fiscal-sandbox/index.ts
```

Ejecutar SQL sólo en el runtime desechable con publicaciones loopback validado:
replay completo y `facturama01_sandbox.sql`, MULTI-04/05, baseline, contratos
consumidos y ambas regresiones FISCAL.0. La CLI se ejecuta desde carpeta temporal.
El build de comprobación usa un `envDir` temporal vacío y datos públicos
sintéticos; la compilación no requiere ni debe recibir credenciales Facturama.

## Resultados y límites comprobados

- Replay definitivo de 42 migraciones: las 41 de la base coinciden con sus blobs
  Git, sin cambios históricos. Pasaron las siete suites SQL anteriores, con
  ACL/RLS efectivas, revocación, relaciones y payloads congelados. Dos clientes
  PostgreSQL concurrentes obtuvieron una lease y un rechazo `busy`, sin POST.
- Pasaron 17 resultados de pruebas Node, lint/typecheck, comprobación Deno 2.9.6
  con lock congelado, formato, build staging local y `git diff --check`.
  `fast-xml-parser` 5.11.2 es la única dependencia directa nueva, sólo servidor.
- Se verificaron XML de ocho CFDI reales de prueba: cinco ingresos y tres REP.
  Incluyen pago parcial y un cobro aplicado a dos facturas. La repetición
  controlada del primer ingreso devolvió su mismo ID proveedor.
- Los ocho IDs conocidos terminaron con estado remoto `canceled`, confirmado
  mediante GET. El XML de acuse sandbox devolvió un UUID ajeno; se rechazó y
  quedó en cuarentena. No se aprueba acuse correlacionado ni se fuerza `canceled`
  local. El CSD oficial añadido se retiró, verificando su huella y lista final
  vacía. El historial de comprobantes cancelados permanece en el proveedor.
- Un fixture cuyo envío quedó incierto no tuvo coincidencia exacta en la
  reconciliación; no se reenvió. No se promete ausencia absoluta de una respuesta
  diferida del proveedor. El informe local conserva sus identificadores.
- Playwright usó contexto nuevo, Auth y datos locales exclusivos, el handler
  servidor exportado y Facturama real: Billing, preparación, emisión, XML,
  consulta, cancelación y REP. Los guards finales se cubrieron por SQL/unit;
  no se afirma que todo el recorrido remoto se repitiera después de cada ajuste.
- El logout mostró login, pero no se observó su finalización HTTP y una recarga
  inmediata recuperó acceso local. La revocación y restricción posterior quedan
  sin aprobar; no se atribuye causa ni se modifica Auth. Las sesiones locales
  desechables se retiraron al destruir el runtime propio.
- No se registraron cuerpos Auth, tokens, headers sensibles, HAR o tracing.
  La revisión del código y build no encontró la contraseña ni Basic Auth.

## Estado remoto y próximos días

Staging se confirmó saludable mediante CLI. Conserva las 39 migraciones de
`main`; no tiene MULTI-04/05, bindings ni bucket nuevos. El listado de recuperación
no aporta backups recuperables ni metadatos físicos utilizables; PITR está
desactivado. No se ha demostrado una recuperación disponible. **No se aplica DDL,
secretos o funciones a staging en esta ejecución.** No hay merge o producción.

1. Cerrar con Facturama la correspondencia del acuse sandbox, sin aceptar UUIDs
   ajenos ni cambiar estados manualmente. Revisar los fixtures y sus cancelaciones.
2. Comprobar recuperación de staging y revisar el delta exacto MULTI-04/05/fiscal.
   Preparar credenciales servidor y una identidad QA con alcance fiscal aprobado;
   no ampliar la cuenta QA habitual para hacer pasar pruebas.
3. Aplicar sólo el delta revisado si se cumplen esas condiciones. Ejecutar QA del
   preview aislado, con captura sanitizada y sin alterar el deploy principal.
4. Cerrar la matriz laboral, adopción empresarial y vías documentales/financieras
   pendientes. UAT de los casos fiscales adicionales que se decida entregar.
5. Para producción, por separado: cuentas verificadas, emisor real por empresa,
   CSD real bajo custodia autorizada, permisos fiscales aprobados, PMT/folios,
   recuperación, conciliación/reversión y observabilidad. El servidor actual
   continúa rechazando producción; nada de esa habilitación se ejecuta aquí.
