# Candidato integrado de cierre

Estado: **LISTO CON BLOQUEOS para revisión; NO LISTO para merge ni habilitación de WLS**. CIERRE-02 aplicó las ocho migraciones revisadas a staging, verificó el catálogo y ejecutó QA exclusiva sintética. El PR permanece draft y el deploy principal no cambió. Evidencia actual: [reconciliation/REMOTE_VALIDATION.json](reconciliation/REMOTE_VALIDATION.json).

CIERRE-03 adopta comandos operativos, documentos privados y versiones, dashboard,
búsqueda y ejecución manual acotada de seis automatizaciones. Sus contratos,
permisos y límites actuales están en [WORKFLOWS.md](WORKFLOWS.md). La evidencia
CIERRE-02 inferior es histórica; no acredita estas nuevas acciones.

## Base y composición

Base remota verificada: `0e9e2eb4dc4e66698e026507b260e8196a549584` (PR fiscal #46 ya integrado). MULTI-04/05 no se duplican. Se incorporan selectivamente MULTI-08 `48dc7ad722268771d2c8c69c521a5b488f7066d0` y su cierre `eb33161c7dbb0cec309e9727a72d640613102d6a`, conservando trailers de origen. Sus prerrequisitos contienen la composición de MULTI-06/07 con Facturama. Las 45 migraciones aplicadas permanecen intactas. Las cuatro de MULTI-08 aún no aplicadas aceptan exclusivamente la representación uniforme LF/CRLF esperada, sin aceptar cambios arbitrarios de SQL. Se agregan cuatro migraciones de adopción empresarial (53 en total).

## Reconciliación CIERRE-02

La comparación correcta A45/B45/C53 y las 177 decisiones están en [reconciliation/README.md](reconciliation/README.md). Hay 135 funciones adicionales (92 RPC), 34 distintas (29 RPC) y ocho ausentes (siete RPC). Las anteriores cifras 85/26 mezclaban parte del candidato con la referencia. No encontrar consumidor frontend no demuestra falta de uso.

El delta pasó replay limpio y ensayo completo sobre restauración real sin quitar `delivery_source_drift`. Conserva las variantes legacy revisadas y cierra las vías no adoptadas. Corrige la asignación de filas por nombre ante otro orden físico de columnas. El historial remoto pasó de 45 a 53 y los objetos posteriores coinciden con el ensayo. WLS sigue sin habilitarse y el PR permanece draft.

## Modelo y activación

Acceso, capacidades por acción, lectura financiera completa, exportación financiera y consolidación siguen separados. Admin/finance no son autorización financiera completa. La vinculación financiera verificada y el issuer siguen siendo obligatorios; metadatos editables y nombres no conceden acceso. Consolidación valida el conjunto exacto y todos los permisos empresariales.

El selector sólo arranca si el backend devuelve `cutover_required=true`. El registro privado está cerrado y sin vía pública de administración; las migraciones no insertan habilitaciones. Sólo se habilitaron dos tenants sintéticos exclusivos para QA. Tras retirar sus permisos, conservan el corte seguro y sus empresas están inactivas. Sin habilitación, el frontend candidato informa que la transición está pendiente. La desactivación no se usa como rollback que reabra vías legacy. Antes de habilitar WLS deben resolverse los P0 de esta matriz, clasificación y UAT. No hay empresas, direcciones, grants ni backfills reales en estas migraciones.

Datos aprobados para una configuración posterior: ROTERO, WORLD'S LOGISTIC SOLUTIONS ROTERO, RFC WLS110325JH8; ROTERITO, WLS ROTERO, RFC WRO2507109E0. Nombres comerciales editables administrativamente. Domicilios/configuración fiscal permanecen pendientes de evidencia; no se inventan. Preferencia ROTERO sólo entre accesos concedidos. No se expone una interfaz de administración de estas concesiones.

## Vías y consumidores

| Vía | Implementación y prueba local | Pendiente para entrega/habilitación |
| --- | --- | --- |
| Operaciones listado/ID/360/CSV | Filtro backend por empresa antes de búsqueda, conteo y paginación; proyecciones explícitas; 360 sin costos/notas/snapshots financieros para acceso parcial; CSV mismo alcance | Clasificar históricos reales; catálogo reconciliado y QA sintética ejecutada |
| Workflow operativo | Crear/editar/planificar/asignar/transitar mediante comandos scoped; revisión, recibos y locks; incidencias, evidencias, requisitos y cruces tipados; legacy cerrado | Gestión empresarial de tokens Tracking, prerrequisitos reales de entrega/cierre y clasificación histórica; no se simulan estados fiscales |
| Documentos/Storage | Carga privada por intención, tres padres autorizados, descarga, sustitución/cancelación, versiones y auditoría; vínculo canónico y Storage directo comprobados | Generación de plantillas y padres compartidos no adoptados; URLs firmadas anteriores pueden durar hasta expirar |
| Finance/Billing | Lecturas completas/agregados/export requieren concesión full/export; núcleo scoped distinto del legacy; nuevas altas financieras clasificadas; escrituras financieras con permiso adicional explícito | Adoptar workflows no admitidos y clasificación de datos/CFDI/relaciones en staging; no se cambian reglas contables ni estados fiscales |
| Cobranza parcial | AR importe/pagos/créditos/saldo sin AP/costos/márgenes; lectura/export/registrar pago son capacidades distintas; pagos reutilizan math/lock F4 | Asignaciones laborales reales por aprobar; no se afirma idempotencia general exactamente-una-vez de pagos tras resultado incierto |
| Reportes | Cinco contratos conservados; Tanda 1 mantiene exactamente siete claves; métricas históricas y cálculo Prom. 71.4 h preservados; secciones sin permiso se indican como no autorizadas | Datos reales conciliados y UAT con identidades verificadas; límites de foco/logout explícitos |
| Dashboard ejecutivo | Fórmulas anteriores sobre vistas scoped, atención y actividad autorizadas; métricas financieras sólo full y comercial según capacidad/rol anterior | UAT y datos reales clasificados; ausencia de permiso no se rellena con ceros |
| Búsqueda/notificaciones | Operaciones, documentos, cuentas financieras full y cotizaciones autorizadas; notificaciones operativas con procedencia; mark/dismiss sólo explícitos | Dominios no adoptados continúan cerrados; ninguna materialización por montar/navegar/foco |
| Jobs/automatizaciones/admin | Seis reglas operativas mediante scope empresarial expirable, destinatarios verificados, reloj controlado, deduplicación y overrides por empresa | Scheduler empresarial continuo, reglas financieras/comerciales y otros procesos no adoptados; no se habilita cron nuevo ni identidad técnica full |
| Vías directas/legacy | 241 RPC canónicas y contratos observados revisados pasan guard de contexto; 66 tablas canónicas y 15 adicionales de B tienen frontera restrictiva; núcleos privados sin execute API; estado desconocido aborta migración | Catálogo reconciliado; workflows no adoptados siguen cerrados. No se certifica aislamiento integral del ERP |
| Fiscal | Facturama sólo sandbox y laboratorio autorizado; política neutral por empresa, origen inmutable, exclusión fiscal02 y bloqueo concurrente preservados; headers por petición; Edge v6 y negativos 401/403 comprobados | Softmanagement conservado e inactivo; ninguna emisión o recuperación nueva validada en esta fase |

`SCOPE_ADOPTION_MANIFEST.json` lista firmas, hashes exactos de origen y tablas. El generador exige un catálogo local canónico de las 49 migraciones y orden físico de columnas. Reproduce exactamente la migración revisada; no conecta a ninguna DB. Los wrappers públicos conservan configuración histórica segura, y los helpers nuevos usan referencias calificadas/search_path vacío. Los tests de introspección siguen el núcleo privado validando propietario y ACL; no se eliminan aserciones de locks, errores o comportamiento.

Cambiar empresa remonta el subárbol y limpia selección/estado. El cliente fija headers sólo para el backend del proyecto y descarta respuestas/descargas de un epoch anterior. Revocación no selecciona otra empresa ni reduce silenciosamente un consolidado. El contexto no se persiste: con varias empresas sin preferencia autorizada se pide selección tras recarga.

## Evidencia local histórica anterior a CIERRE-02

- Replay limpio 53 migraciones, 25 suites SQL aprobadas: baseline/consumidos, MULTI-04 a 08, F1 a F10, BH1/BH2 y fiscal; nueva suite con 53 aserciones efectivas de permisos, DTO, IDs, exportación, archivo, revocación, empresa inactiva, membresía, helpers y vías directas. Datos sintéticos locales y rollback.
- 142 pruebas Node de 40 archivos (141 en corrida acumulada + archivo afectado corregido por formato); lint/typecheck, Deno check, prueba runtime sandbox, formato y build staging. Test real de menú: clic normal y Enter en 1280×720 y 1024×768.
- Navegador aislado contra Auth/PostgREST/Storage reales locales: login finance sintético, selector, Operaciones→360→archivo privado→CSV, cobranza/pago explícito, Tanda 1, recarga, cambio de empresa y logout. Captura sólo host/ruta/método/estado/finalización, nunca headers, cuerpos Auth, HAR o tokens. Foco sólo se aprueba con transición efectiva observada; ver informe de ejecución.
- Esta fase local no ejecutó SQL ni grants remotos. CIERRE-02 sí aplicó el delta y creó concesiones exclusivamente sintéticas, retiradas al cerrar. No hay emisiones/cancelaciones nuevas ni llamadas Softmanagement. La evidencia fiscal anterior no se presenta como prueba nueva. PDF de acuse acredita formato/hash/procedencia, no validación criptográfica ni correlación interna. Cierre local/HTTP de logout no demuestra revocación remota completa de todas las sesiones.

El arnés de navegador exige `LOCAL_QA_ALLOW_DISPOSABLE_FIXTURES=1`, CLI ya validada, proyecto local delivery propio, salidas temporales y API loopback. Crea exclusivamente identidades/datos sintéticos en esa pila desechable. No usa sesión del usuario ni persiste credenciales. No instalar dependencias para ejecutarlo.

## CIERRE-02 ejecutado

Replay A: 26 suites; restore B: 24 suites aplicables, incluidos los contratos nuevos y Storage. Las 45 migraciones previas están intactas. Lint/typecheck/build aprobados; Node/Deno se reutilizan porque sus entradas no cambiaron. El catálogo posterior coincide en funciones, tablas, vistas, constraints, índices, triggers, policies y membresías de roles; propietarios limitados sin login/herencia/bypass. Los dos jobs conservaron configuración y estado.

QA real: 41 casos API, siete de revocación, cinco negativos fiscales y recorridos de navegador. Listado → ficha → archivo privado → CSV, AR parcial y CSV financiero full, cinco Reportes HTTP 200, contrato Tanda 1, recarga, navegación, consolidación exacta por API y selector, IDs cruzados y logout. El observador bloqueó lecturas por una allowlist incompleta; se corrigió sólo el arnés y Finance pasó en repetición focalizada. No fue un defecto demostrado del producto. Cobranza/pago conserva su prueba local anterior; no se repitió remotamente.

Foco real pendiente: Chromium con ventana no produjo transición verificable. Logout limpió UI, mostró login y restringió Reportes; HTTP 204 seguido de `net::ERR_ABORTED`, sin afirmar finalización ni revocación global completa.

Se retiraron tres identidades Auth, sesiones, concesiones, dos objetos Storage y defaults eliminables. Permanecen dos tenants sintéticos con corte seguro, tres empresas inactivas, tres operaciones, cuatro cuentas, dos metadatos documentales cancelados, evidencia inmutable y una vinculación revocada con su membership por FK. No hay acceso efectivo. Los UUID privados y la limitación del inventario temporal están en el informe: el inventario inicial se sobrescribió y faltan UUID de ciertas concesiones/memberships eliminadas; la ausencia final y el alcance exclusivo sí se verificaron.

De 134 tablas originales, 132 conservaron digests exactos de columnas originales. No faltó ninguna fila previa; sólo hubo una ejecución programada adicional y cambios en fechas de notificaciones, compatibles con el job horario registrado. No se purgaron esos efectos concurrentes ni se hizo backfill empresarial real. La seguridad observada durante QA no certifica jobs ajenos.

## Recuperación y staging

Respaldo DB/roles/Auth (134 tablas COPY) cifrado DPAPI, restaurado aislado con hashes/conteos coincidentes. Storage privado: 15 objetos, 163317 bytes, bytes y metadatos cifrados; restauración por API local y comparación SHA-256 aprobadas. El respaldo se renovó por el trigger Storage concurrente revisado. Custodia y manifiestos privados quedan fuera de Git. No incluye secretos de plataforma/Vault root/PITR/CSD de producción. Staging observado ACTIVE_HEALTHY; drift revisado reconciliado.

El delta remoto sólo se aplicó tras pasar el guard exacto y el ensayo renovado. Se desplegó únicamente fiscal-sandbox v6: contexto empresarial por petición, mismo verify_jwt=false y autorización interna preservada. Origen staging exacto y negativos 401/403 verificados; no se probó frontend nuevo en el dominio principal ni se llamó al proveedor. Las otras funciones quedaron iguales. El único sitio conectado a automatización es rotero-erp-staging; su deploy principal se conserva. Preview automático no autoriza merge.

## Excel e identidades

Previsualización privada local, archivo fuente intacto. Mapping por hoja/columna, tipos/fórmulas/cache, huella de fila, candidatos de continuación/duplicados y totales AR/AP separados por moneda. Nada importado. Las filas no se convierten automáticamente en operaciones, pagos o asientos. Revisar el manifiesto exacto, agrupación y conciliación antes de aprobar un lote. El script portable de preview no conecta a servicios y no modifica el libro.

No se localizaron candidatos por los tres nombres exactos en la consulta acotada de metadatos editables de Auth. Eso no demuestra ausencia de sus cuentas. Los UUID y titularidad de Luis Roberto Santamaria, Jhoselin Santamaria y Karina Pineda requieren verificación administrativa independiente. Propuesta: acceso a ambas empresas y full/export/consolidación sólo después de verificar cada cuenta y aprobación; ninguna asignación ejecutada. QA/técnicas no reciben vinculación financiera completa real.

## Siguientes gates, UAT y producción (sin ejecutar)

1. Backend/DB: reconciliación completada (177 decisiones, delta aplicado y catálogo verificado). Antes de habilitar WLS falta clasificar históricos y revisar relaciones reales, sin empresa por defecto.
2. Responsable funcional + backend: completar gestión operativa/documental, dashboard/automatizaciones pendientes, matriz de acciones y clasificación explícita. Revisar evidencia por entidad, sin empresa por defecto, creador ni nombre parecido.
3. Administración de identidades: verificar UUID/titularidad de las tres personas, aprobar accesos/capacidades sin ejecutarlos durante este encargo. Completar domicilios/RFC/config fiscal verificados.
4. QA staging sintética ejecutada con los límites anteriores. Pendientes: foco real, finalización HTTP de logout, datos reales conciliados y UAT. No reabrir legacy para hacer pasar UAT ni confundir pruebas sintéticas con asignaciones reales.
5. UAT Luis Roberto: ROTERO/ROTERITO por separado y consolidado exacto, utilidad/costos/márgenes y exportaciones conciliados; Jhoselin: cambio empresa, tardías y revocación; Karina: AR/AP/pagos/créditos, exclusión laboratorio y conciliación contable/Excel. Cada uno prueba sólo tras verificación/grant aprobado. Incluir contraparte parcial sin full y usuario sin empresa.
6. Producción: autorización aparte; inventario y delta del catálogo real, ensayo/backup DB+Storage restaurado, referencias de secretos sólo servidor, CSD reales bajo custodia y validación aparte, provider/profile/env explícitos, idempotencia/incertidumbre y monitoreo. Soft sigue deshabilitado hasta validar su emisión/recuperación. No fallback entre proveedores.
7. Recuperación: snapshot previo, manifiesto por objetos/lotes y evidencia; revisión de jobs y sesiones antes de restaurar. Nunca revertir sólo ACL/cutover para reabrir bypass ni restaurar Auth globalmente sobre sesiones ajenas. Mantener cierre seguro y corregir adelante; rollback de aplicación únicamente a un conjunto DB+frontend compatible y aprobado. Migraciones aditivas no se borran ni se repara su historial. No se ejecutó producción, rollback ni restore remoto.
