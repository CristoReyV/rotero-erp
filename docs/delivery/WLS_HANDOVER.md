# Aceptación de ROTERO ERP para WLS

Estado del corte vigente: [PR 47 compatible con staging 61](WLS_PR47_STAGING61.md).

**Decisión actual: no habilitar WLS.** El PR #47 permanece en draft. La
aplicación revisada parte de `08c4fbd37da6377505eda7194edc19aae0981e8f`.
Este seguimiento cambia la prueba SQL y este documento. El SHA y Deploy
Preview vigentes se verifican juntos al entregar.

El conector de Supabase responde, pero el proyecto `mxpmgihuheagrcowwbia`
no aparece en su lista y deniega proyecto, historial y funciones. Las 60
migraciones son el último estado confirmado en CIERRE-03. La 61 pasó replay
local y sigue pendiente de ensayo sobre el respaldo vigente de staging.
Las versiones públicas de Edge tampoco se dan por verificadas en esta fase.
[Validación anterior](WORKFLOWS_VALIDATION.json)

## Matriz única de salida

“Día uno” identifica el alcance que se propone habilitar después de probarlo
en el preview con el backend autorizado. La evidencia local o histórica se
indica para que WLS pueda distinguirla de una aceptación real.

| Corte | Recorrido | Evidencia y estado | Responsable y próximo paso |
| --- | --- | --- | --- |
| Día uno | Acceso y contexto de empresa | El preview anterior mostró login y restringió Reportes sin sesión. Node cubrió recuperación y logout. Login real del operator y persistencia en este candidato siguen pendientes. | QA. Usar identidad sintética con membership operator, comprobar contexto, recarga, foco efectivo y cierre de la sesión propia. |
| Día uno | Alta, planeación, asignación y tránsito | SQL aprobado con operator, empresa explícita y proveedor sintético. Los enlaces vigentes son requisito de tránsito. La prueba real CIERRE-03 fue con admin de alcance parcial. | QA + Operaciones. Recorrer la ficha 360 con operator y comprobar persistencia de cada transición en A. |
| Día uno | Seguimiento público, chofer, entrega y POD privado | SQL aprobado para emisión, rotación concurrente, caducidad, revocación, separación de scopes y entrega. El reintento del chofer se probó con respuestas controladas en tres tamaños. Storage y POD tienen evidencia local y evidencia real previa de CIERRE-03. La reasignación y el recorrido de los tres endpoints en staging siguen pendientes de QA autenticada. | QA + administrador de staging. Tras la restauración y el delta, usar dos asignaciones sintéticas válidas y comprobar invalidación, entrega y acceso privado a los bytes del POD. |
| Día uno | Dashboard, búsqueda, notificaciones y jobs acotados | CIERRE-03 validó consultas por empresa y seis reglas manuales con destinatarios explícitos. Montar y navegar sólo consultan notificaciones. | QA. Confirmar aislamiento y lecturas en el preview si cambian las entradas. Ejecutar sólo una tarea dirigida al tenant sintético y comprobar dedup y retirada del scope. |
| Día uno | Operaciones y Finanzas con exportaciones | SQL y QA previa cubrieron 360/CSV operacional, AR parcial, acceso financiero completo y consolidación explícita. Objetos privados, alcance cruzado y revocación tienen cobertura anterior. | QA + Contabilidad. Con datos sintéticos poblados, reconciliar pantallas y exportaciones con el mismo filtro. Probar operator, finance parcial y una identidad con full explícito. |
| Día uno | Reportes por empresa | Las cuatro secciones y las siete claves de Tanda 1 tienen contrato probado. La validación remota previa usó respuesta vacía. Falta ejecutar el escenario poblado en el preview. | QA + Contabilidad. Verificar cifras sintéticas por empresa y periodo. Comparar CSV con pantalla y comprobar permisos revocados. |
| Día uno | Denegaciones legacy y controles de lectura | La prueba RBAC.3B original pasó con 45 migraciones y falló con 60 y 61 al buscar el guard en el wrapper de `rpc_list_deals`. La prueba revisada pasó 186 casos de lectura/denegación, además de las lecturas Finance aprobadas y las ACL de las 12 funciones. | Ingeniería. Conservar la prueba efectiva en el candidato. Repetir el gate sobre la restauración real si el catálogo difiere de la variante local. |
| Día uno | Catálogo, Edge y recuperación de staging | Bloqueado por acceso administrativo. El replay de los 61 blobs demuestra la variante local. Faltan respaldo vigente, restauración de bytes de Storage y verificación de la variante alojada. | Titular de Supabase. Restablecer una conexión autorizada al proyecto exacto. Ingeniería ejecuta el plan de recuperación antes de aplicar. |
| Aprobación WLS | Cierre normal y trazabilidad | El cierre sin `operation_billing.status=issued` se deniega correctamente. El alta legacy del documento sigue cerrada y aún falta un recorrido scoped de emisión válido para esta operación. | Contabilidad. Confirmar el productor autorizado y una operación apta. QA toma entrega/POD como hito independiente y después verifica cierre y trazabilidad cuando exista el requisito legítimo. |
| Aprobación WLS | Accesos definitivos y activación de empresas | Sin asignaciones reales. Lectura financiera completa, exportación y consolidación son concesiones separadas, además del acceso a empresa. | Titular de accesos + Contabilidad. Verificar titularidad de Luis Roberto Santamaria, Jhoselin Santamaria y Karina Pineda. Confirmar labor y alcance de cada operador antes de aprobar grants por UUID. |
| Aprobación WLS | Conciliación de históricos, UAT y decisión de salida | El concentrado conserva 2379 filas candidatas en HOLD. La salida técnica sigue pendiente de QA autenticada y del criterio contable de cierre. | WLS. Aprobar procedencia, agrupación y contrapartes por fila, criterios contables, roles y alcance de primer día. Aceptar el SHA y deploy exactos después del UAT. |
| Fuera del corte | Claims, Inventarios, Aduanas, Comercial, importación y plantillas compartidas | Sus flujos no adoptados permanecen cerrados y el frontend lo indica. El catálogo de reportes y búsquedas ya adoptados conserva su contrato. | Producto. Priorizar los módulos que WLS considere indispensables en un bloque aparte. Si alguno es requisito de salida, abrirlo como bloqueo funcional explícito. |
| Fuera del corte | Jobs programados de empresa, Excel en destino y fiscal real | Se mantienen seis reglas operativas manuales acotadas. Excel sigue en HOLD. Facturama conserva sandbox y Softmanagement permanece inactivo. | Producto + Contabilidad. Autorizar programación, lote contabilizado o alta fiscal en fases propias. |

## Acceso administrativo y plan de recuperación

1. El titular abre
   [el proyecto de staging](https://supabase.com/dashboard/project/mxpmgihuheagrcowwbia)
   en un perfil nuevo. Confirma que la cuenta elegida tiene acceso al proyecto y
   vuelve a autorizar el conector con la organización correcta. Si la cuenta
   carece de acceso, el titular administra su rol desde el equipo de Supabase
   con alcance al proyecto cuando el plan lo permita. La sesión anterior
   pendiente de revocación se gestiona por separado.
2. Ingeniería verifica identidad del proyecto, historial exacto de las 60
   versiones previas, dueños y ACL, fingerprints, storage y cron. Registra
   versiones, hashes y configuración de `track-public`, `driver-view` y
   `track-driver`. Si la versión 61 ya aparece, compara hash y catálogo antes
   de decidir. Una divergencia material detiene la aplicación.
3. Generar un respaldo vigente cifrado en custodia de Windows. Capturar schema,
   datos, roles e historial con el inventario de Auth que admita recuperación
   aislada. Exportar por separado los bytes de Storage y su metadata bajo
   custodia restringida. Guardar conteos, hashes y un marcador de coherencia
   previo a la escritura. Un backup de DB sólo recupera metadata de Storage.
4. Restaurar en una pila desechable con publicación loopback y cron detenido.
   Comprobar roles, relaciones y contratos, y verificar descargas restauradas
   por la API local con SHA-256. Ensayar la 61 exacta y comparar los conjuntos
   de objetos, ACL, filas y jobs con el delta esperado. Registrar exclusiones
   de recuperación, como secretos de plataforma y restauración operativa de
   CSD. Si el ensayo o sus evidencias fallan, mantener el estado de staging.
5. Con todas las condiciones comprobadas, desplegar primero la versión
   compatible de `track-public`, conservar `verify_jwt` y origen aprobados, y
   verificar la respuesta antes del cambio de DB. Aplicar sólo
   `20261123160000_cierre04_company_tracking.sql` y comparar catálogo POST con
   el ensayo. Verificar los tres endpoints con claves de scope correcto,
   ausente, revocado o ajeno. Confirmar caché y aislamiento de la proyección.
6. Ante una anomalía, detener la emisión de enlaces y suspender QA. Inventariar
   y revocar por ID sólo recursos sintéticos creados en el intento. Conservar
   el corte empresarial, evidencia, versiones de POD y el historial. Corregir
   con un delta aditivo y una versión compatible. Una recuperación en destino
   requiere un ensayo verificable y decisión explícita, coordinando DB, bytes y
   versión de frontend. La primera restauración siempre es aislada.

Referencias de configuración bajo custodia. Netlify staging debe apuntar al
proyecto exacto con `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` pública y
`VITE_PUBLIC_APP_URL`; mocks deshabilitados. Confirmar bucket privado y
`trackingedge` sólo en servidor. Facturama usa perfil por empresa y referencias
`FACTURAMA_SANDBOX_USER`, `FACTURAMA_SANDBOX_PASSWORD`,
`FACTURAMA_ENVIRONMENT` y `FACTURAMA_SANDBOX_ENABLED`. Contratación, credenciales
productivas, CSD y emisores requieren aceptación separada.

[Autorización Supabase](https://supabase.com/docs/guides/ai-tools/mcp) ·
[Acceso al proyecto](https://supabase.com/docs/guides/platform/access-control) ·
[Respaldos y alcance de Storage](https://supabase.com/docs/guides/platform/backups)

## Guion UAT y operación breve

1. **Preparar QA.** Verificar exclusividad, identidad, permisos vigentes y
   custodia antes de navegar. Comprobar los UUID y usuarios existentes, pues
   la vigencia y disponibilidad remota de las cuentas CIERRE-03 siguen sin
   verificar. Usar sólo el tenant sintético exclusivo y un operator real,
   con acceso y capacidades mínimos. Usar A y B del mismo tenant, y registrar
   el tenant X únicamente para pruebas cruzadas. Registrar IDs y estado PRE.
2. **Operador.** Iniciar sesión con rol operator, seleccionar A, crear y
   planear la operación, asignar proveedor y confirmar la salida. Abrir 360
   y generar los dos enlaces. Tratar las direcciones como secretos y
   mantenerlas sólo en el contexto de prueba. Comprobar que B y X no aparecen
   al intentar consultar su operación ni al exportar CSV de A.
3. **Cliente y chofer.** Abrir cada enlace en un contexto separado. Comprobar
   que el público sólo muestra hitos autorizados. Iniciar y registrar eventos
   con el enlace de chofer. Rotar o revocar y comprobar denegación. Reasignar
   a un segundo proveedor de prueba y comprobar que el enlace anterior no
   permite registrar eventos. Reemitir el enlace para la nueva asignación.
4. **Entrega y POD.** Operador avanza a tránsito con requisitos válidos.
   Chofer registra salida, llegada y entrega. Ante pérdida de respuesta,
   mantener la pestaña abierta y reintentar desde la cola en memoria. Operador
   registra la transición a entrega y sube un POD sintético privado. Verificar
   ruta, propiedad, contenido, descarga legítima y denegación contra B/X.
   Probar cierre sin Billing. Registrar la denegación esperada, y ejecutar el
   cierre positivo sólo con un requisito emitido mediante el flujo aprobado.
5. **Reportes y exportaciones.** Con datos sintéticos conocidos, comprobar
   periodo, volumen y agrupaciones. Validar las cuatro secciones y que Tanda 1
   conserva las siete claves. Comparar CSV de cada rol contra el mismo alcance
   visible y comprobar la retirada de acceso. El perfil parcial no recibe
   costos, ganancias, pérdidas ni márgenes.
6. **Evidencia y salida.** Probar a 1280×720, 390×844 y 360×800. Observar foco
   real y registrar ruta sin parámetros, método, código HTTP, resultado y
   persistencia. Quitar tokens, cuerpos Auth y datos de negocio de la evidencia.
   Verificar logout por clic y que Reportes vuelve a exigir login. Diferenciar
   limpieza de UI, finalización de la petición y revocación comprobada. No
   registrar como aprobada la revocación inmediata de todos los access tokens.
7. **Retirada.** Inventariar POST y revocar enlaces de esta sesión por ID.
   Cerrar sólo las sesiones QA iniciadas para UAT. Retirar scopes, grants
   temporales y fixtures eliminables según dependencias. Conservar auditoría,
   versiones y UUID ya registrados. Mantener intacto el ROTERO QA compartido.
   La custodia y la retirada final de las identidades dedicadas corresponden
   al responsable de entrega.
