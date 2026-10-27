# Candidato integrado de cierre

Estado: preparado y probado localmente, **NO LISTO para merge ni habilitación de WLS**. No se aplicó SQL, configuración, grants ni QA autenticada en staging. El preview por sí solo no valida la seguridad backend.

## Base y composición

Base remota verificada: `0e9e2eb4dc4e66698e026507b260e8196a549584` (PR fiscal #46 ya integrado). MULTI-04/05 no se duplican. Se incorporan selectivamente MULTI-08 `48dc7ad722268771d2c8c69c521a5b488f7066d0` y su cierre `eb33161c7dbb0cec309e9727a72d640613102d6a`, conservando trailers de origen. Sus prerrequisitos contienen la composición de MULTI-06/07 con Facturama. Las 45 migraciones aplicadas permanecen intactas. Las cuatro de MULTI-08 aún no aplicadas aceptan exclusivamente la representación uniforme LF/CRLF esperada, sin aceptar cambios arbitrarios de SQL. Se agregan cuatro migraciones de adopción empresarial (53 en total).

## Bloqueo P0 demostrado en staging

El historial remoto registra las mismas 45 migraciones de main; el catálogo real no corresponde completamente a sus definiciones canónicas. Hay 362 funciones públicas ejecutables por authenticated frente a 247 canónicas: 85 firmas RPC adicionales y 26 cuerpos RPC coincidentes en firma pero distintos. No son diferencias de finales de línea. Ejemplo: `rpc_get_operation` devuelve un JSON enriquecido en staging y otra definición en el replay.

El ensayo sobre una restauración aislada del staging real se detiene en `delivery_source_drift: rpc_get_operation`. No se elimina ese guard, no se repara el historial ni se sobrescriben contratos extra. Responsable: mantenimiento backend/DB. Acción: versionar y revisar el delta real, consumidores y ACL de las 85 firmas y 26 cuerpos; decidir qué conservar en el núcleo legacy y qué adoptar/denegar en contexto empresarial; ensayar nuevamente sobre la restauración antes de aplicar el delta completo. El manifiesto canónico no autoriza los contratos adicionales.

## Modelo y activación

Acceso, capacidades por acción, lectura financiera completa, exportación financiera y consolidación siguen separados. Admin/finance no son autorización financiera completa. La vinculación financiera verificada y el issuer siguen siendo obligatorios; metadatos editables y nombres no conceden acceso. Consolidación valida el conjunto exacto y todos los permisos empresariales.

El selector sólo arranca si el backend devuelve `cutover_required=true`. El registro privado de habilitación por tenant está cerrado, sin filas ni vía pública de administración. Sin habilitación, el frontend candidato informa que la transición está pendiente. La desactivación no se usa como rollback que reabra vías legacy. Antes de habilitar WLS deben resolverse todos los P0 de esta matriz, clasificación y UAT. No hay empresas, direcciones, grants ni backfills reales en estas migraciones.

Datos aprobados para una configuración posterior: ROTERO, WORLD'S LOGISTIC SOLUTIONS ROTERO, RFC WLS110325JH8; ROTERITO, WLS ROTERO, RFC WRO2507109E0. Nombres comerciales editables administrativamente. Domicilios/configuración fiscal permanecen pendientes de evidencia; no se inventan. Preferencia ROTERO sólo entre accesos concedidos. No se expone una interfaz de administración de estas concesiones.

## Vías y consumidores

| Vía | Implementación y prueba local | Pendiente para entrega/habilitación |
| --- | --- | --- |
| Operaciones listado/ID/360/CSV | Filtro backend por empresa antes de búsqueda, conteo y paginación; proyecciones explícitas; 360 sin costos/notas/snapshots financieros para acceso parcial; CSV mismo alcance | Clasificar históricos y conciliar contratos reales de staging |
| Captura operativa | Captura mínima planned, empresa explícita, capacidad capture y rol existente; respuesta id/company; evidencia atómica | Asignación, planificación, transiciones y gestión documental empresarial completas; sus rutas legacy quedan denegadas en cutover |
| Documentos/Storage | Metadatos clasificados, clase de acceso ligada a evidencia, padre coherente, archivo privado; descarga autenticada con RLS, sin emitir nuevas URLs firmadas | Carga, vínculo, generación y todos sus workflows administrativos siguen cerrados en cutover; URLs firmadas anteriores pueden durar hasta expirar |
| Finance/Billing | Lecturas completas/agregados/export requieren concesión full/export; núcleo scoped distinto del legacy; nuevas altas financieras clasificadas; escrituras financieras con permiso adicional explícito | Adoptar workflows no admitidos y clasificación de datos/CFDI/relaciones en staging; no se cambian reglas contables ni estados fiscales |
| Cobranza parcial | AR importe/pagos/créditos/saldo sin AP/costos/márgenes; lectura/export/registrar pago son capacidades distintas; pagos reutilizan math/lock F4 | Asignaciones laborales reales por aprobar; no se afirma idempotencia general exactamente-una-vez de pagos tras resultado incierto |
| Reportes | Cinco contratos conservados; Tanda 1 mantiene exactamente siete claves; métricas históricas y cálculo Prom. 71.4 h preservados; secciones sin permiso se indican como no autorizadas | QA integrada en staging, datos poblados conciliados y consolidación con identidades reales verificadas |
| Dashboard ejecutivo | Código/métricas legacy conservados; nueva vista informa sólo resumen operativo autorizado, sin renombrarlo como utilidad/pipeline/inventario | Adopción del dashboard ejecutivo/atención y sus dependencias. No se declara completada |
| Búsqueda/notificaciones | Búsqueda de operaciones por alcance; sólo notificaciones clasificadas y autorizadas, sin materialización al montar/navegar/foco | Búsqueda de otros dominios, notificaciones operativas por clase y acciones mark/dismiss empresarial; se mantienen cerradas en cutover |
| Jobs/automatizaciones/admin | Los materializadores revisados saltan tenants habilitados antes de materializar; resto de APIs no admitidas devuelve company_adoption_pending | Identidad de ejecución por empresa y adopción funcional de cada proceso. El corte seguro no equivale a automatizaciones completadas; puede mantenerse auditoría externa del job |
| Vías directas/legacy | 241 RPC antiguas pasan guard de contexto; 66 tablas tenant tienen policy restrictiva adicional; núcleos privados sin execute API; firma adicional aborta migración | Reconciliar catálogo real remoto. No se certifica aislamiento integral del ERP |
| Fiscal | Facturama sólo sandbox y laboratorio autorizado; política neutral por empresa, origen inmutable, exclusión fiscal02 y bloqueo concurrente se preservan; headers de empresa se transmiten por petición | Deploy/QA de Edge adoptada tras resolver DB; Softmanagement conservado e inactivo, emisión y recuperación no validadas |

`SCOPE_ADOPTION_MANIFEST.json` lista firmas, hashes exactos de origen y tablas. El generador exige un catálogo local canónico de las 49 migraciones y orden físico de columnas. Reproduce exactamente la migración revisada; no conecta a ninguna DB. Los wrappers públicos conservan configuración histórica segura, y los helpers nuevos usan referencias calificadas/search_path vacío. Los tests de introspección siguen el núcleo privado validando propietario y ACL; no se eliminan aserciones de locks, errores o comportamiento.

Cambiar empresa remonta el subárbol y limpia selección/estado. El cliente fija headers sólo para el backend del proyecto y descarta respuestas/descargas de un epoch anterior. Revocación no selecciona otra empresa ni reduce silenciosamente un consolidado. El contexto no se persiste: con varias empresas sin preferencia autorizada se pide selección tras recarga.

## Validación y evidencia nueva

- Replay limpio 53 migraciones, 25 suites SQL aprobadas: baseline/consumidos, MULTI-04 a 08, F1 a F10, BH1/BH2 y fiscal; nueva suite con 53 aserciones efectivas de permisos, DTO, IDs, exportación, archivo, revocación, empresa inactiva, membresía, helpers y vías directas. Datos sintéticos locales y rollback.
- 142 pruebas Node de 40 archivos (141 en corrida acumulada + archivo afectado corregido por formato); lint/typecheck, Deno check, prueba runtime sandbox, formato y build staging. Test real de menú: clic normal y Enter en 1280×720 y 1024×768.
- Navegador aislado contra Auth/PostgREST/Storage reales locales: login finance sintético, selector, Operaciones→360→archivo privado→CSV, cobranza/pago explícito, Tanda 1, recarga, cambio de empresa y logout. Captura sólo host/ruta/método/estado/finalización, nunca headers, cuerpos Auth, HAR o tokens. Foco sólo se aprueba con transición efectiva observada; ver informe de ejecución.
- No hay emisiones/cancelaciones nuevas, llamadas Softmanagement, SQL ni grants remotos. Evidencia histórica fiscal se conserva y no se presenta como prueba nueva. PDF de acuse acredita formato/hash/procedencia, no validación criptográfica ni correlación interna. Cierre local/HTTP de logout no demuestra revocación remota completa de todas las sesiones.

El arnés de navegador exige `LOCAL_QA_ALLOW_DISPOSABLE_FIXTURES=1`, CLI ya validada, proyecto local delivery propio, salidas temporales y API loopback. Crea exclusivamente identidades/datos sintéticos en esa pila desechable. No usa sesión del usuario ni persiste credenciales. No instalar dependencias para ejecutarlo.

## Recuperación y staging

Respaldo nuevo DB/roles/Auth (134 tablas COPY) cifrado DPAPI, restaurado aislado con hashes/conteos coincidentes. Storage privado: 15 objetos, 163317 bytes, bytes y metadatos cifrados; restauración por API local y comparación SHA-256 aprobadas. Custodia y manifiestos privados quedan fuera de Git. No incluye secretos de plataforma/Vault root/PITR/CSD de producción. Proyecto staging observado ACTIVE_HEALTHY; eso no resuelve su drift SQL.

No se aplica delta remoto mientras falle el guard. El único sitio conectado a la automatización del repositorio se verificó como rotero-erp-staging; su deploy principal se conserva. Preview automático no sustituye QA backend ni autoriza merge.

## Excel e identidades

Previsualización privada local, archivo fuente intacto. Mapping por hoja/columna, tipos/fórmulas/cache, huella de fila, candidatos de continuación/duplicados y totales AR/AP separados por moneda. Nada importado. Las filas no se convierten automáticamente en operaciones, pagos o asientos. Revisar el manifiesto exacto, agrupación y conciliación antes de aprobar un lote. El script portable de preview no conecta a servicios y no modifica el libro.

No se localizaron candidatos por los tres nombres exactos en la consulta acotada de metadatos editables de Auth. Eso no demuestra ausencia de sus cuentas. Los UUID y titularidad de Luis Roberto Santamaria, Jhoselin Santamaria y Karina Pineda requieren verificación administrativa independiente. Propuesta: acceso a ambas empresas y full/export/consolidación sólo después de verificar cada cuenta y aprobación; ninguna asignación ejecutada. QA/técnicas no reciben vinculación financiera completa real.

## Siguientes gates, UAT y producción (sin ejecutar)

1. Backend/DB: reconciliar 85 firmas extra y 26 cuerpos, recuperar/evaluar consumidores, ensayar delta en restore y revisar clasificación/relaciones incompatibles antes de aplicar staging.
2. Responsable funcional + backend: completar gestión operativa/documental, dashboard/automatizaciones pendientes, matriz de acciones y clasificación explícita. Revisar evidencia por entidad, sin empresa por defecto, creador ni nombre parecido.
3. Administración de identidades: verificar UUID/titularidad de las tres personas, aprobar accesos/capacidades sin ejecutarlos durante este encargo. Completar domicilios/RFC/config fiscal verificados.
4. QA staging aislada: operación→360→documento→CSV, AR/pago/AP, cinco Reportes y consolidado, IDs/Storage/bypass, revocación/cambio de empresa/respuesta tardía/logout y foco real. No reabrir legacy para hacer pasar UAT.
5. UAT Luis Roberto: ROTERO/ROTERITO por separado y consolidado exacto, utilidad/costos/márgenes y exportaciones conciliados; Jhoselin: cambio empresa, tardías y revocación; Karina: AR/AP/pagos/créditos, exclusión laboratorio y conciliación contable/Excel. Cada uno prueba sólo tras verificación/grant aprobado. Incluir contraparte parcial sin full y usuario sin empresa.
6. Producción: autorización aparte; inventario y delta del catálogo real, ensayo/backup DB+Storage restaurado, referencias de secretos sólo servidor, CSD reales bajo custodia y validación aparte, provider/profile/env explícitos, idempotencia/incertidumbre y monitoreo. Soft sigue deshabilitado hasta validar su emisión/recuperación. No fallback entre proveedores.
7. Recuperación: snapshot previo, manifiesto por objetos/lotes y evidencia; revisión de jobs y sesiones antes de restaurar. Nunca revertir sólo ACL/cutover para reabrir bypass ni restaurar Auth globalmente sobre sesiones ajenas. Mantener cierre seguro y corregir adelante; rollback de aplicación únicamente a un conjunto DB+frontend compatible y aprobado. Migraciones aditivas no se borran ni se repara su historial. No se ejecutó producción, rollback ni restore remoto.
