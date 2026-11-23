# Entrega de ROTERO ERP para WLS

Este bloque prepara Tracking empresarial en el candidato del PR #47. Requiere
aplicar y ensayar la migración 61 junto con la actualización de `track-public`
antes de conceder `tracking.manage` en staging. CIERRE-03 conserva su evidencia
histórica en [WORKFLOWS_VALIDATION.json](WORKFLOWS_VALIDATION.json).

| Requisito | Estado y alcance de la evidencia |
| --- | --- |
| Alta, planeación y asignación | **Aprobado local** desde los comandos scoped con rol operator y proveedor sintético. La QA CIERRE-03 de interfaz fue con admin de alcance parcial. |
| Tracking público y chofer | **Aprobado local SQL** para emisión, consulta de metadatos, separación de ambos scopes, expiración, revocación, salida, llegada y entrega. Pendiente probar las Edge Functions y el navegador del preview con datos reales sintéticos. |
| Doble acción y respuesta perdida | **Aprobado local SQL** para reemitir una solicitud sin crear otro enlace y para repetir el mismo evento sin registrarlo dos veces. Dos sesiones SQL compitieron por rotar el mismo enlace, una obtuvo conflicto y quedó un sólo enlace activo. |
| Comandos de tránsito y entrega | **Aprobado local SQL**. Tránsito requiere ambos enlaces vigentes. Entrega exige un evento válido del transportista de la asignación vigente. |
| POD y cierre normal | **POD aprobado en regresión SQL** de carga, propietario, acceso, vínculo, versiones y retirada. Evidencia previa de bytes CIERRE-03 reutilizable tras comprobar equivalencia. **Cierre pendiente** de un Billing emitido legítimo para el recorrido de QA. Se comprobó la denegación sin ese requisito. |
| Empresas y roles | **Aprobado local SQL** en empresas A/B, tenant X, operación sin clasificación, empresa inactiva, revocación de concesión y acceso directo denegado. El frontend permite a operator acceder a Dashboard, Operaciones y Documentos tras el control de empresa. QA real de login con operator pendiente. Viewer sigue cerrado. |
| Finanzas y consolidación | **Aprobado local** para contratos MULTI-07/08 de acceso parcial, full explícito, exportación y consolidación. QA de aplicación conserva la evidencia sintética de CIERRE-03. Los grants por persona están pendientes de verificar identidad y recibir aprobación. |
| Documentos privados, 360 y CSV | **Aprobado local** el contrato scoped y sus regresiones. Las URLs firmadas previas vencen según su vigencia. Generación de plantillas compartidas requiere adopción propia. |
| Claims, Inventarios, Aduanas, Comercial, importación | **Pendiente funcional**. Los RPC principales responden `company_adoption_pending` durante el corte y los enlaces del menú candidato se retiran. Un acceso directo explica la indisponibilidad sin montar el módulo legacy. Listados de reportes y búsquedas ya adoptados mantienen su contrato. |
| Dashboard, búsqueda y jobs | **Aprobado local** para CIERRE-03 y seis reglas operativas bajo scope explícito. Automatización continua por empresa y reglas de otros dominios pendientes. |
| Reportes | **Aprobado local** el contrato de cuatro secciones legacy y Tanda 1 de siete claves, errores y cambios de contexto. La prueba remota anterior usó contrato vacío. Pendiente ejecutar con datos sintéticos poblados por empresa. |
| Login, recuperación, logout, notificaciones | **Aprobado en Node** para las regresiones de Auth y lecturas automáticas. Persistencia y revocación de refresh se comprueban aparte de UI/HTTP. No se ha demostrado foco real ni revocación inmediata de todos los access tokens. |
| Fiscal | **Regresión SQL aprobada** para Facturama sandbox y reconciliación de estados, REP y evidencia PDF dentro de los contratos existentes. Softmanagement se conserva inactivo. Pendientes pruebas de producción y aceptación contable. |
| Excel | **Lote local HOLD**. Archivo fuente intacto, 75 grupos de folios repetidos y 37 celdas con errores. Ningún registro tiene aprobación de importación. |

Ejecución local de este bloque: replay de las 61 migraciones, 40 aserciones de
Tracking, una carrera con dos sesiones, 67 pruebas Node, typecheck y build
staging. El ensayo local no reemplaza la restauración del catálogo real.

## Operación y capacitación

1. **Operador de A.** Iniciar sesión con membership operator y concesiones
   específicas. Elegir A, crear la operación y completar servicio, ubicaciones y
   ventana, luego asignar proveedor y salida. Confirmar que las consultas y CSV
   excluyen los datos de B y las columnas financieras.
2. **Operador de A.** Abrir la ficha 360 y emitir un enlace público y otro para
   el chofer. Copiar la dirección mientras se muestra. Si se pierde la
   respuesta, actualizar los metadatos y rotar el enlace que figure vigente.
   Revocar el anterior al retirar acceso. Comprobar expiración tras una solicitud nueva.
3. **Chofer.** Abrir su enlace en un contexto distinto. Registrar salida,
   tránsito y llegada en orden. Confirmar entrega desde la página del chofer.
   La cola de eventos pendientes permanece en la pestaña. Mantenerla abierta
   hasta confirmar el envío y usar Reintentar envío si se pierde la respuesta.
4. **Operador de A.** Avanzar a tránsito cuando los dos enlaces y requisitos
   estén listos. Consultar la entrega, cargar el POD privado y asociarlo en el
   expediente. Intentar cierre sin Billing emitido y comprobar la explicación.
   Completar el cierre sólo cuando contabilidad aporte el requisito legítimo.
5. **Finanzas.** Con acceso parcial, comparar cobranza y sus exportaciones.
   Con full explícito en A y B, reconciliar AR/AP, documentos, pagos, créditos,
   REP y totales por empresa. Consolidar sólo el conjunto concedido. Revocar
   full en A y comprobar que B sigue accesible y el consolidado queda cerrado.
6. **QA negativa.** Repetir con usuario sin concesiones y con IDs válidos de
   B/tenant X. Verificar falta de permiso para links, adjuntos y acciones. Probar
   bloqueo al desactivar la empresa y al revocar el enlace del chofer. Registrar
   la acción, ruta sin parámetros, método, código HTTP, resultado y persistencia.
   Revisar escritorio y pantallas de 390×844 y 360×800. Para foco, ir a una pestaña
   vacía y volver. Exigir un cambio observado de foco o visibilidad, comprobar
   la actualización y verificar cero escrituras automáticas.
7. **Contabilidad/UAT.** Comparar Tanda 1 y las cuatro secciones contra el mismo
   periodo y empresa. Aceptar ausencia de datos como pendiente de carga. Probar
   exportaciones, cierre por clic del menú y acceso restringido a `/reports`
   tras salir. Registrar HTTP y finalización de petición independientemente.

## Diagnóstico de links y versiones

El link público usa referencia opaca y estados/hitos fijos. El conductor recibe
una operación, sin montos, ubicaciones privadas, documentos ni datos de otros
clientes. Sus acciones están limitadas por el estado de la operación. Una
reasignación invalida su link anterior. La revocación de la concesión impide
administrar. Los enlaces ya compartidos se retiran explícitamente; su operación
y empresa deben seguir vigentes. El navegador usa `no-store` y la Edge aplica
la misma política al contrato empresarial. Los enlaces legacy de los tenants
fuera de corte conservan comportamiento previo.

El control de despacho se basa en enlaces empresariales vigentes. Los links
históricos de un tenant en corte requieren reemisión por un administrador u
operador autorizado. Los hechos históricos permanecen conservados. Esta tarea
no agrega una administración pública de concesiones.

## Preflight para el siguiente despliegue revisable

| Mecanismo | Referencias requeridas, sin valores |
| --- | --- |
| Netlify | IDs del sitio autorizado y contexto/versiones base; `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` pública, `VITE_PUBLIC_APP_URL` y mocks deshabilitados. |
| Supabase | Project ref exacto, catálogo, historial, roles/policies, funciones y cron actuales; cuenta para inspección, aplicación/restauración y seguridad de Auth. |
| Tracking | Versiones de `track-public`, `driver-view`, `track-driver`; origen permitido; referencia de clave server-only `trackingedge` y TTL de links. |
| Documentos | Bucket privado, reglas de acceso, límites por tipo/tamaño, recuperación de bytes y metadata; clave de servicio exclusivamente al proceso autorizado. |
| Fiscal sandbox | Perfil por empresa y emisor autorizado de pruebas; `FACTURAMA_SANDBOX_USER`, `FACTURAMA_SANDBOX_PASSWORD`, `FACTURAMA_ENVIRONMENT`, `FACTURAMA_SANDBOX_ENABLED` en custodia de servidor. |
| Fiscal productivo futuro | Contrato y aprobación contable, API/productos contratados, credenciales separadas, CSD y contraseña bajo custodia, RFC/domicilio/régimen por emisor, series, impuestos y evidencia de aceptación independiente. Softmanagement permanece inactivo. |

1. Validar HEAD, PR draft y preview de staging. Obtener acceso de administración
   de sólo lectura al proyecto exacto. Comparar catálogo e historial con CIERRE-03,
   probar los hashes A/B admitidos y verificar el delta 61.
2. Crear respaldo vigente cifrado de schema/roles/datos/Auth y Storage, con
   manifiesto y hash de bytes. Restaurarlo en pila desechable aislada. Comprobar
   datos, permisos, Storage, restauración y migración 61 antes de tocar staging.
3. Desplegar primero `track-public` compatible con ambos contratos y verificar
   caché/orígenes. Aplicar una vez la migración 61 con el SHA revisado. Comparar
   catálogo/roles/datos con el ensayo y verificar Edge endpoints. Sin activar
   empresas reales.
4. Comprobar identidades QA, habilitación sintética y expiración. Recuperar la
   custodia previa si sigue disponible y verificarla antes de iniciar sesión.
   Hace falta un operador real sintético. Conceder lo mínimo a identidades
   verificadas sólo dentro del tenant QA exclusivo. Registrar IDs inicialmente
   y al cierre. Cerrar contextos y revocar sesiones de QA propias.
5. Ante anomalía, detener emisión nueva y retirar por ID los grants/enlaces QA
   recién emitidos. Mantener el corte empresarial. Corregir hacia adelante con
   un delta aditivo y un frontend compatible, o ensayar recuperación aislada
   desde el respaldo para decidir una retirada coordinada. No reparar el
   historial ni reabrir permisos legacy. Merge y despliegue final sólo tras UAT
   aprobada y confirmación explícita del entorno, SHA, plan y responsables.

## Decisiones y datos que debe aportar WLS

- Titularidad de UUID de Luis Roberto Santamaria, Jhoselin Santamaria y Karina
  Pineda. Aprobación explícita de grants full/export/consolidación por empresa
  y asignaciones laborales mínimas de los demás operadores.
- Evidencia por registro histórico de empresa y contrapartes. Aprobación de
  agrupación, continuaciones, folios e importes por moneda. Cada pago necesita
  importe, fecha, cuenta y aplicación respaldados por evidencia.
- Un recorrido válido con Billing emitido para cerrar UAT y aceptación contable
  de AR/AP, documentos, REP y conciliación. Aprobación aparte para timbrado real.
- Prioridad comercial de Claims, plantillas y demás módulos pendientes. Dejar
  visibles como pendientes hasta que sus contratos de empresa sean adoptados.
- Recuperar los accesos administrativos de staging por un canal soportado.
  Cerrar por separado la sesión administrativa de CIERRE-02 mediante revocación
  selectiva y confirmar custodia QA. Ningún secreto entra en Git ni en evidencias.

## Lote del concentrado y retirada

El previsualizador preserva archivo/hoja/fila/celda, huella, fórmulas y cache,
empresa propuesta por hoja y candidatos de continuación. El manifiesto local
queda fuera de Git. Para aprobar, conciliar clientes y proveedores contra IDs
verificados, documentos por emisor/referencia/moneda, impuestos/retenciones y
todas las aplicaciones. La clave de huella evita duplicar la instantánea. Una
versión distinta exige revisión contra claves de negocio, no una nueva alta
por defecto. El ensayo previo debe distinguir filas netas de controles
derivados. Se retira el lote por IDs y dependencias, conservando auditoría,
recibos y versiones. No existe un lote contabilizado.

Las identidades de CIERRE-03 se conservan hasta la entrega humana. Antes de
retirar, inventariar y revocar por UUID accesos, capacidades, consolidación,
vinculaciones y scopes dedicados. Cerrar sólo sus sesiones, retirar fixtures
eliminables por IDs y conservar auditoría, versiones y dependencias FK. El
tenant ROTERO QA compartido permanece excluido de estas pruebas.
