# CIERRE-02: catálogo reconciliado

El candidato sigue en draft. Pasaron el replay limpio y el ensayo sobre restore.
Se aplicaron exactamente las ocho migraciones revisadas a staging (45 → 53),
con catálogo posterior idéntico al ensayo. La QA sintética real, su retirada y
sus límites están en `REMOTE_VALIDATION.json`. WLS permanece sin habilitación.

## Comparación y decisiones

Se comparó A, las mismas 45 migraciones aplicadas remotamente; B, el catálogo
real de staging restaurado; y C, el candidato original de 53 migraciones.
A tiene 351 funciones public/private y 245 funciones públicas ejecutables por
authenticated; B tiene 478 y 360. Frente a A hay 135 funciones adicionales
(92 RPC), 34 distintas (29 RPC) y ocho ausentes (siete RPC).
Los anteriores 85/26 mezclaban parte del delta del candidato con la referencia.

`DECISIONS.json` contiene las 177 decisiones por firma: diferencias, procedencia
exacta cuando se encontró, consumidores de repositorio, llamadas SQL, dependencias
de catálogo, decisión y cobertura. No encontrar una llamada frontend no significa
que un contrato esté sin uso. Una procedencia no demostrada se indica expresamente.
`OBJECT_DELTAS.json` conserva diferencias exactas de columnas, ACL, relaciones,
índices, triggers, vistas, tipos y policies. Los inventarios A/B/C completos se
conservan como evidencia local sanitizada; sus hashes están en `VALIDATION.json`.

Las decisiones principales son:

- Conservar el getter/listado enriquecido de B fuera del corte empresarial;
  dentro del corte usar la implementación canónica filtrada y DTO explícito.
  Los campos financieros, notas y snapshots no llegan al usuario operativo.
- Normalizar los otros contratos comunes revisados y restaurar los ausentes
  desde main, conservando las definiciones observadas en núcleos privados cerrados.
- Conservar las variantes de Tracking dependientes de su contrato de token.
  `rpc_list_route_points` mantiene JSON en A y filas en B; ambos rechazan contexto
  empresarial. Esto no constituye adopción empresarial de Tracking.
- Retener privados los OID de tres sobrecargas cortas que producen ambigüedad con
  los DEFAULT canónicos: dashboard alerts, dashboard overview y audit log.
  Los payloads públicos resuelven el contrato canónico. No se usa DROP.
- Denegar las RPC extra no adoptadas antes de cualquier trabajo en contexto
  empresarial. Fuera del corte se conserva el núcleo observado, con identidad,
  tenant y permisos legacy; no se afirma adopción financiera de esos workflows.
- Cerrar individualmente los helpers de datos a llamadas API ordinarias;
  conservar helpers puros y metadatos de la propia membership. Estos últimos no
  conceden acceso empresarial ni autorización financiera completa.
- Conservar inertes y sin permisos los overloads históricos de invitaciones;
  no reaparece aprovisionamiento Auth ni manejo de contraseñas por esas funciones.

## Orden y controles

La reconciliación inicia la migración 46, todavía no aplicada al preparar el
delta. No se modificó ninguna de las 45 migraciones históricas, ni sus versiones.
Sólo admite las instantáneas A45 o B45 revisadas mediante un fingerprint de
definiciones, propietarios, permisos efectivos, tablas, vistas, relaciones,
triggers, tipos y policies. Los roles compartidos se controlan aparte: API sin
membership en propietarios, propietarios limitados sin login, herencia ni bypass.
Un nuevo cuerpo, columna, función, ACL o concesión de propietario aborta.

`delivery_source_drift` permanece activo. La normalización revisada ocurre antes
de sus comprobaciones. El registro privado de contratos no es editable por API;
acepta únicamente la definición, configuración, propietario, resultado y ACL
registrados. Alterar su ACL invalida la admisión.

La revalidación detectó después un único cambio semántico concurrente: el trigger
`storage.enforce_versioning_status_transition` sobre buckets. No cambiaron cuerpos
ni privilegios efectivos de la aplicación; la ordenación distinta de ACL en los
JSON no representa una concesión. Se revisó su función invocadora completa, sin
SQL ni llamadas externas, y se fijó en `STORAGE_PLATFORM_CONTRACT.json`. No se
atribuye el actor del cambio sin auditoría. B acepta sus dos instantáneas exactas;
si el trigger existe, exige además su cuerpo, propietario, lenguaje, ACL,
configuración y columna esperados. Cambiar ese cuerpo también aborta. El respaldo
de esquema/datos se renovó y la nueva restauración pasó las ocho migraciones y
la prueba de transiciones sobre una tabla temporal, sin modificar un bucket.

`POLICY_ROLE_ADAPTATIONS.json` fija 85 policies históricas de usuarios, cada una
con su expresión original y destinatario nuevo. Se conservan command, USING,
WITH CHECK y permisividad; se sustituye PUBLIC por anon/authenticated/service_role.
Así los propietarios limitados usan sus policies específicas, sin heredar las
consultas de membership o helpers de las policies de usuarios. No se conceden
lecturas amplias de memberships ni permisos financieros a esos propietarios.

Se añaden columnas de compatibilidad nullable, sin inventar empresa, autor,
licencia o fecha histórica. Los defaults añadidos sólo afectan altas futuras.
Se conservan columnas legacy, precisión, estados y datos. Siete índices cubren
FK documentales observadas sin índice. La excepción canónica de INSERT del
servicio a tracking_access_log se limita a sus cuatro columnas permitidas.

Los lectores scoped que usan un tipo de fila se componen por nombre mediante
jsonb_populate_record, evitando asignar por posición columnas físicas distintas
de staging. No se reordena ninguna tabla ni se usa ese mecanismo para escribir.

## Validación y límites

- Replay completo: 53 migraciones; 25 suites anteriores más la suite CIERRE-02.
- Restore real + ocho migraciones: 23 suites aplicables más la prueba Storage, con datos existentes
  preservados. Baseline vacío y MULTI-04/05 fresh se ejecutan en A; B usa las
  comprobaciones de integridad, ACL/RLS, capacidades y revocación de M06/M07/M08
  y delivery, sin exigir que desaparezcan los datos restaurados.
- CIERRE-02 verifica los 169 contratos observados, 88/90 denegaciones ejecutadas
  en A/B, 16 equivalencias de helpers de entrada en B y deriva de ACL.
- El recorrido delivery también prueba los ocho helpers de membership con actor
  sintético, pertenencia propia y tenant ajeno, sin convertirlos en permisos full.
- Las 134 tablas COPY coinciden en sus columnas originales tras el delta.
  Storage: 15 objetos privados, 163317 bytes, cifrados con DPAPI y restaurados
  localmente con verificación de hashes. Ningún manifiesto de datos entra a Git.
- La segunda restauración usa postgres con Auth/REST/Storage detenidos. Se
  conservaron las definiciones de ambos jobs, inactivos localmente; no se acredita
  ejecución por reloj. No hubo llamadas a Facturama o Softmanagement.

Los ajustes de pruebas no relajan integridad: proporcionan issued_by/paid_at y
Auth sintéticos válidos; verifican rollback contra los conteos previos, no contra
una base vacía; satisfacen temporalmente las dependencias de policies para medir
RLS. B impide RFC de cliente duplicado por índice único: se conserva esa regla y
se prueba su rechazo, mientras A conserva la prueba de ambigüedad de clientes.
El worker fiscal offline limpia el sujeto inexistente del negativo anterior.

Los workflows no adoptados permanecen cerrados: planificación/asignación y
transiciones completas, administración documental, búsqueda de otros dominios,
materialización/mark/dismiss, nómina, automatización empresarial, inventario y
flujos administrativos no admitidos. Jobs guardados no equivalen a jobs adoptados.
La lectura completa, exportación financiera y consolidación siguen requiriendo
concesiones distintas y vinculación verificada. No hay asignaciones reales a QA,
técnicos ni personas; la excepción sintética autorizada abajo se retiró al cerrar.

La cuenta QA anterior comparte tenant con otras dos cuentas Auth y su única
empresa está inactiva. No se habilita ni se modifica ese entorno. El usuario
autorizó después un laboratorio exclusivamente sintético de CIERRE-02: tenant,
dos empresas, identidades para permisos parciales y full/consolidado, y un tenant
mínimo de contraste. Su preparación exige revisión previa de hooks/defaults/jobs,
custodia DPAPI, concesiones mínimas y retirada por IDs. Las vinculaciones de
fixtures representan combinaciones de permisos, nunca verificaciones o asignaciones
de personas reales. Se ejecutó con dos tenants y tres empresas sintéticos, tres
identidades nuevas y concesiones mínimas. Se retiraron cuentas/sesiones, grants,
objetos privados y defaults eliminables. Permanecen raíces/evidencias inmutables,
empresas inactivas y una vinculación revocada con su membership; los tenants
sintéticos conservan el corte seguro para no reabrir vías legacy ni jobs.

Pasaron API con admin sin grants, parcial, full/consolidado; UI listado → ficha →
archivo → CSV, AR parcial y CSV financiero full; cinco Reportes HTTP 200, recarga,
navegación y logout normal. Revocación y empresa inactiva deniegan de inmediato.
No se observaron materialización, mark/dismiss ni mutaciones de negocio en esos
recorridos; no es una certificación de jobs ajenos. El arnés bloqueó inicialmente
RPC de lectura por una allowlist incompleta: se corrigió sólo el observador y se
repitió Finance de forma focalizada. No se atribuye ese fallo al producto.

El foco real permanece pendiente: Chromium con ventana no produjo una transición
de visibilidad verificable. Logout mostró HTTP 204 y `net::ERR_ABORTED`, limpió UI
y restringió Reportes; la finalización HTTP y revocación global no se presuponen.
La retirada administrativa verificó cero cuentas/sesiones de esas tres identidades.

El inventario auxiliar inicial se sobrescribió al verificar la retirada. Se
conservan UUID de raíces, identidades y evidencia, y los IDs de defaults en SQL
de limpieza acotado; no se recuperaron UUID de ciertas concesiones/memberships
temporales ya eliminadas. La ausencia final y el alcance exclusivo sí se verificaron.

Sobre 134 tablas originales, 132 conservaron exactamente sus digests por columnas
originales. No faltó ninguna fila previa: los otros cambios fueron una ejecución
programada a las 05:00 UTC y fechas first_seen_at/last_seen_at de notificaciones,
compatibles con el job horario preservado y registrado por cron. No se limpiaron
ni revirtieron esos efectos concurrentes. No hubo backfill empresarial real.

No se habilita WLS ni se asignan personas reales. Excel continúa en HOLD.
El aislamiento integral del ERP, UAT, otros roles, datos poblados y producción
permanecen pendientes. Softmanagement sigue conservado e inactivo; Facturama,
exclusivamente sandbox.
