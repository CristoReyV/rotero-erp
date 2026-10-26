# FACTURAMA-02 — integración limitada a staging y sandbox

## Base y compatibilidad

Parte de `05eb83b` y conserva `def7528`, MULTI-04/05 y el historial original.
La rama de integración corrige únicamente dependencias necesarias; no incorpora
MULTI-06 ni el candidato sin commit MULTI-07 a la entrega. Ambos se superponen
temporalmente para comprobar compatibilidad, sin editar su worktree.

El replay canónico y el esquema real de staging son formas distintas. La copia
restaurada demostró tres diferencias relevantes:

- Falta `public.touch_updated_at()`: MULTI-04 añade su trigger privado, INVOKER,
  con search_path vacío y propietario limitado. MULTI-05 lo reutiliza mediante
  un grant temporal de DDL, revocado conservando privilegios anteriores.
- CFDI no tiene `operation_id`: se respeta la relación canónica por
  `billing_documents.linked_cfdi_id` / `operation_id`. Si la columna existe en
  el replay canónico, también se comprueba; no se duplica en staging.
- UUID tenía NOT NULL: se permite NULL para un borrador sin emisión. No se
  inventan UUID ni se modifica una fila existente. Consumidores fiscales ya
  admiten ausencia de UUID; sólo XML correlacionado establece el timbrado.

Se conservan las versiones originales de MULTI-04/05 y FACTURAMA-01, **no aplicadas
previamente al staging inspeccionado**. Sus bytes se corrigen en esta rama;
no se reescribe historia Git, renumera o repara una migración remota. Las 39
migraciones de main no cambian. Al integrar con MULTI se deberán usar estas
correcciones de dependencias y comparar hashes, no aplicar otra variante de la
misma versión. No se afirma compatibilidad por compartir sólo un número.

## Propiedad y exposición

El candidato combinado reprodujo una factura clasificada por MULTI-07 en B
mientras el vínculo fiscal de laboratorio conservaba A. La migración
`20261023202527_facturama02_cancellation_and_scope.sql` impide esa discrepancia
en ambas direcciones y comprueba los padres Billing relacionados. Utiliza el
mismo lock de relaciones de MULTI-07; las tablas y helpers siguen cerrados.

Una raíz histórica sin empresa no se clasifica automáticamente ni se presenta
como protegida por MULTI. El binding privado sólo autoriza documentos sandbox
explícitos de laboratorio. No es un modelo empresarial alternativo ni un grant
para ver todas las finanzas. Las rutas generales, selector y consolidación siguen
sin habilitarse por esta integración.

### Vías legacy del laboratorio

Una prueba sintética reprodujo lectura del CFDI B desde `rpc_get_cfdi_detail`
con acceso sólo a A. Se cierran las vías del laboratorio, conservando el contrato
de las filas que no son sandbox:

| Vía | Control y cobertura |
| --- | --- |
| CFDI, listado, ficha y preparación legacy | Vista privada con `fiscal.read` vigente; pruebas positivas A y denegación B por ID |
| Finance, detalle, agregados y exportación F6 | Vistas privadas excluyen las filas de laboratorio, incluso para admin; no se mezclan saldos sandbox con contabilidad legacy |
| Escrituras legacy de CFDI y relaciones | Triggers verifican OLD/NEW, empresa conocida y worker autorizado; prueba de edición directa denegada e inmutabilidad fiscal conservada |
| Tablas y vistas directas | ACL efectivas sin SELECT/INSERT ordinario; vistas privadas sin grants API |
| Worker fiscal y aplicación de pagos | Actor verificado, capacidad específica, allowlist y marca transaccional privada; una capacidad de emisión no concede lectura general |

La migración redirige las lecturas FROM/JOIN de las seis tablas implicadas en
funciones existentes propiedad del administrador hacia vistas privadas; conserva
firmas, propietarios, ACL y destinos INSERT/UPDATE. Incluye Billing, Finance,
exportación, buscador, dashboards, referencias documentales, notificaciones y
helpers FISCAL.0. El inventario exacto de funciones queda en la evidencia local.
No se otorga acceso directo a las vistas ni un setter público de la marca.

El replay combinado instala primero el candidato MULTI-07 inspeccionado y después
esta migración. Se comprueban sus dos helpers por hash, propietario y SECURITY
DEFINER antes de excluir documentos sandbox de esos lectores. **No** se acredita
que se pueda aplicar sin cambios el antiguo MULTI-07 después de FACTURAMA-02:
sus verificaciones de definiciones legacy rechazarían este delta. Su futura
publicación exige una integración revisada y nuevas migraciones, sin reparar
historial ni volver a aplicar otra variante de una versión existente.

## Cancelación y recuperación

Se distinguen solicitud, confirmación por consulta y acuse validado:

- `remote_cancel_status=pending`: solicitud enviada, confirmación pendiente.
- `remote_cancel_status=canceled`: GET correlacionado por ID proveedor, UUID e
  issuer confirma cancelación. No demuestra por sí solo un acuse SAT válido.
- `cancellation_ack_state`: unavailable, unverified, mismatch o validated.
  Un XML ajeno no se enlaza ni permite finalizar cancelación local.

El sandbox devolvió el mismo XML con UUID ajeno para dos comprobantes distintos;
detalle y HTML corresponden a sus respectivos IDs. El HTML se usó como diagnóstico,
no como sustituto del XML. Se conserva evidencia del incidente comunicado a soporte.

La recuperación remota de acuse XML está deshabilitada. El endpoint documentado
de acuse CFDI sólo ofrece PDF/HTML; el de XML de retenciones es otro contrato.
Reenviar DELETE no es recuperar evidencia. UI deshabilita el control y backend
rechaza recoverAck=true con 409 y «Cancelación confirmada; acuse XML pendiente
del proveedor», después de autorizar sólo una lectura, sin lease ni escritura.
El motivo y la trazabilidad originales permanecen intactos. La descarga de un
acuse ya validado y almacenado sigue siendo de lectura.

Las consultas de estado reutilizan la solicitud canónica activa del mismo tipo.
Se conservan leases, intentos y auditoría, sin abrir reenvíos automáticos. Ver
[contrato y límites actuales](FACTURAMA04_RECOVERY_AND_STAGING.md).

## Recuperación de base de datos

El procedimiento usa la CLI autenticada, sin extraer tokens de otras sesiones.
Roles, schema y datos se cifran directamente con DPAPI fuera del repositorio y
de la evidencia textual, bajo ACL del ejecutor. No hay dump plano intermedio.
Se demostró restauración aislada de 121 bloques COPY, comparando filas y contenido.
El delta final se probó sobre otra copia restaurada con datos existentes; las 121 tablas conservaron sus filas, con una fila nueva esperada en el bucket privado. El informe identifica los hashes.

Es recuperación lógica de SQL, Auth y metadatos Storage. No copia binarios Storage,
secretos de plataforma, claves raíz Vault o PITR. El delta conserva archivos
existentes y añade un bucket separado; no se promete recuperación integral de
servicios externos. No se ejecutan jobs, Auth ni REST sobre la copia restaurada.
El informe local conserva ubicación, hashes, instante de la copia y límites.

## Validación y publicación

Antes de aplicar: verificar proyecto saludable, historial y schema coincidente
con el respaldo restaurado, hashes de las cuatro candidatas, replay y suites SQL,
lint/typecheck, adaptador, Deno, build, diff y secretos. CLI siempre desde carpeta
temporal. El paquete remoto excluye las migraciones temporales MULTI-06/07.

Sólo se permite el proyecto staging, host Facturama sandbox y previews del sitio
staging. El wrapper servidor rechaza producción. Basic permanece en servidor;
las variables VITE son exclusivamente públicas. Sin merge ni deploy principal.

QA de navegador requiere una identidad dedicada y contexto nuevo. El observador
retiene sólo metadatos HTTP. Antes de recargar tras logout hay que esperar la
finalización de la solicitud y limpieza de almacenamiento de esa sesión; mostrar
login por sí solo no acredita revocación. El comprobador de refresh token trabaja
en memoria, sin registrar tokens ni cuerpos Auth. No se confunde su revocación
con la vigencia restante del access token.

El informe de cierre registra qué se aplicó, PR/preview, casos ejecutados y
pendientes. No se convierten pruebas locales o simuladas en QA de staging.

El arnés crea borradores sintéticos con estado explícito y verifica UTF-8 del
receptor de prueba. La RPC legacy de staging convierte excepciones en JSON:
la regresión admite exclusivamente 42501 o el mensaje exacto del guard,
comprueba fila inalterada y prueba además la ruta SQL directa. No se debilita
la denegación por una diferencia de envoltura de errores.

La prueba local previa de logout recibió clic normal, mostró login, eliminó caché de sesión y
restringió Billing después de recargar. Un comprobador aislado recibió HTTP 400
para el refresh token de esa sesión. Se observaron encabezados 204 y después
ERR_ABORTED en Chromium; la finalización HTTP normal queda sin aprobar. Esto
no valida sesiones del preview ni demuestra revocación de access tokens vigentes.

El QA posterior del preview repitió ese recorrido con la cuenta dedicada y
obtuvo HTTP 400 al intentar renovar únicamente su refresh token cerrado. También
observó 204 seguido de ERR_ABORTED en logout. Se verificó la restricción tras
recarga; no se declara finalización HTTP normal ni invalidez inmediata del
access token. Los permisos fiscales temporales se revocaron al terminar.

## Conciliación de la solicitud original

El QA real verificó cuatro XML mediante consultas de estado posteriores a la
emisión. La solicitud `status` se completó, pero las solicitudes `stamp`
originales permanecieron en `processing`, sin retry programado. Se preparó una
migración nueva, sin editar versiones aplicadas: cierra sólo el registro `stamp`
cuando coinciden XML privado ya verificado, fingerprint congelado, UUID/ID del
proveedor y un resultado `status` terminado que confirme ese mismo comprobante.
El helper es privado INVOKER, sin EXECUTE de roles API. Conserva intentos y añade
la procedencia a auditoría; no invoca al proveedor ni aprueba un acuse pendiente.

La regresión sintética reproduce XML diferido, comprueba ambas solicitudes
terminales, ausencia de nuevos intentos, idempotencia, ACL y cancelación aún
pendiente con acuse ajeno. Se reprodujo el fallo en la base de 43 migraciones y
pasó con la corrección. Los replays de 44 migraciones (12 suites) y del overlay
MULTI-06/07 de 46 (14 suites) pasaron sin modificar esas ramas. La recuperación
actual se comprueba por separado antes de aplicar el delta remoto; el informe
local registra sus límites y el estado efectivo.

La misma observación mostró 404 al obtener el XML inmediatamente después de
recibir el ID del proveedor, seguido de recuperación válida por consulta. La
candidata devuelve `processing` (sin aprobación fiscal) únicamente si ese ID y
el marcador de incertidumbre ya se conservaron. Mantiene el bloqueo de reenvío,
la verificación estricta del XML y el error cuando falla la persistencia.
