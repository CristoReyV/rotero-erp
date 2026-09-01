# MOBILE.1 — Responsive hardening

## Alcance y estrategia

MOBILE.1 endurece únicamente la presentación frontend. Conserva servicios, queries, filtros, selección, mutaciones, deep links, formatters y permisos existentes. No cambia backend, Supabase, Auth, Edge, Tracking, Fiscal ni contratos de datos.

La referencia principal es un teléfono cercano a 390 px, con contrato estático para 320, 360, 375, 390, 414 y 430 px. Tablet y desktop conservan sus flujos. Las diferencias estructurales usan CSS; `useMediaQuery` se reserva para elegir la representación inicial Lista/Board y para no montar popovers desktop dentro de sheets móviles.

## Arquitectura responsive

- El shell usa `dvh`, `min-w-0`, `max-w-full` y gutters de 12 px a 320 px, 16 px desde 360 px y spacing desktop sin cambios.
- No se oculta overflow en `body`. Las tablas desktop permanecen dentro de ramas `md:block`; tabs y kanban tienen scroll interno con `overscroll-x-contain`.
- `MobileSheet` es el overlay móvil compartido para Saved Views y notificaciones. Usa portal, cierre accesible, Escape, bloqueo temporal del scroll, scroll interno, `dvh` y safe area inferior.
- Inputs, selects y textareas respetan el ancho de su contenedor. Referencias y textos largos usan `min-w-0`, truncado o salto de palabra según el contexto.

## Dark mode

Las superficies principales reutilizan `surface`, `surface-card`, `surface-elevated` y `tech-border`. Finance ya no usa una isla `slate-50/70` para filtros. Los tintes funcionales conservan semántica con fondos translúcidos en dark mode y el texto secundario sube de contraste sin convertir toda la jerarquía en blanco.

## Patrones por módulo

### Finance

- AR/AP comparten el mismo `AccountsWorkspace`, datos y handlers.
- Móvil renderiza tarjetas compactas con contraparte, estado, saldo, moneda, operación/referencia, vencimiento, selección, pago y apertura del expediente.
- Desktop conserva la tabla multidimensional existente y su scroll interno.
- El expediente financiero existente pasa a drawer full-height en móvil; crear cuenta y registrar pago usan formularios de una columna, scroll interno, `dvh` y acciones alcanzables.

### Operations

- KPIs continúan en dos columnas y reducen padding, icono y altura sin perder la métrica.
- Nueva operación es la CTA primaria; Saved Views y actualizar son secundarios.
- Tabs conservan scroll interno. Búsqueda permanece visible y estado se despliega desde `Filtros` en móvil.
- Las tarjetas existentes se refinan con densidad menor, texto acotado y lenguaje proveedor-first. Desktop conserva tabla y Operation 360.

### Commercial

- Tabs del módulo tienen scroll interno y estado seleccionado accesible.
- Nuevo Deal y Filtros forman la fila prioritaria; búsqueda y Board/Lista/Mapa ocupan filas propias en móvil.
- Lista es la representación inicial móvil mientras el usuario no elija otra. Reutiliza los mismos deals y abre el drawer existente.
- Board permanece disponible con lanes de ancho acotado y scroll horizontal contenido en su región. Desktop conserva el grid kanban.
- Mapa no inventa coordenadas: informa que no existen ubicaciones canónicas y remite a Lista/Board.
- Deal detail y filtros son drawers full-width/full-height en móvil con `dvh`, safe areas y cierre visible.
- Directorios de clientes/proveedores ya usaban filas compactas; se reforzaron anchos mínimos, wrapping de controles y formularios móviles donde fueron tocados.

## Overlays, dialogs y formularios

Saved Views y notificaciones cambian de popover desktop a bottom sheet móvil. Las acciones icon-only tienen nombre accesible y objetivo táctil de 44 px. Los drawers de Finance y Deal usan `role=dialog`, título asociado y scroll interno. Los formularios principales de Finance, Operations, Deals y Clientes cambian a superficie full-height en móvil y conservan el modal centrado en desktop.

## Checklist de QA manual

Probar en dark mode y orientación vertical, primero cerca de 390 px:

- Finance: no hay scroll horizontal de página; filtros pertenecen al sistema dark; AR/AP son legibles; selección y pago funcionan; expediente abre y cierra; acciones caben.
- Operations: KPIs son compactos en dos columnas; CTA y acciones caben; tabs solo desplazan su franja; búsqueda/filtros funcionan; tarjetas y Operation 360 son legibles.
- Commercial: la página no se desplaza horizontalmente; Saved Views cabe como sheet; tabs son utilizables; Lista abre Deal detail; Board desplaza solo su región; filtros y detail ocupan el viewport correctamente.
- Global: abrir notificaciones, Saved Views, menús, dialogs y formularios; comprobar cierre, scroll interno, teclado virtual, foco, contraste y safe area inferior.

Spot checks a 320 px:

- Confirmar gutters de 12 px, ausencia de colisiones en headers/CTAs y cero scroll horizontal de documento.
- Confirmar dos columnas de KPI, tarjetas Finance sin corte, controles Commercial en tres filas y overlays con cierre visible.
- Probar referencias, RFC, correos y nombres largos; deben truncarse o envolver sin ensanchar la página.

La QA visual final corresponde a dispositivo real; MOBILE.1 no usa browser automation, Chromium, screenshots ni deploy de staging.

## Hallazgos de QA en dispositivo real

MOBILE.1A atiende escapes horizontales en Requiere atención, Actividad reciente y Registrar cobro; estados de toque que mostraban una superficie blanca en Operaciones; tarjetas semánticas con bajo contraste; demora visual al cambiar la etapa comercial; y valores internos que llegaban a etiquetas de Operaciones, Facturación, Finanzas, Reclamaciones y Documentos.

## Correcciones MOBILE.1A

- Los contenedores críticos usan `min-w-0`, `max-w-full`, wrapping y grids que colapsan a una columna. Drawers y formularios conservan scroll vertical interno y acciones alcanzables a 320 px.
- Las filas de Operaciones tienen estados `active`, `focus`, `selected` y hover desktop basados en tema, sin destello blanco en dark mode.
- El cambio de etapa comercial espera la mutación, actualiza el detalle visible tras el éxito y vuelve a consultar el estado canónico. Un fallo no adelanta el estado local.
- Los títulos visibles se simplificaron a términos de negocio en español, sin renombrar rutas, componentes ni contratos.

## Contrato de color semántico

Los tonos compartidos son `neutral`, `info`, `success`, `warning` y `danger`. Cada tono define acento, fondo sutil y borde para light/dark. El panel ordinario conserva la superficie canónica; el significado se comunica con borde, icono, texto o badge. Un tinte semántico se reserva para elementos pequeños. Los paneles Carta Porte, Ejecución controlada, Sin integración, Detalle interno, Frontera fiscal y advertencias operativas siguen este contrato.

## Contrato de etiquetas visibles

Los valores persistidos y las llamadas internas no cambian. La presentación usa mapas pequeños por dominio para motivos de preparación, reclamaciones, documentos, fiscal y finanzas. Entre otros: `missing_planning_data` se muestra como Planeación incompleta; `missing_assignment`, como Proveedor sin asignar; `proof_of_delivery`, como Prueba de entrega (POD); `generated_pdf`, como PDF generado; y `active`, como Activo. Las rutas fiscales se convierten a una frase como “Faltan: Conceptos y método de pago”. Los valores desconocidos reciben una descripción segura y no exponen nombres de RPC o identificadores similares.

## QA manual pendiente tras MOBILE.1A

- Repetir en dispositivo real a 320 y 390 px, light/dark: Requiere atención, Actividad reciente, tarjetas y selección de Operaciones, detalle de Facturación, Registrar cobro, cambio de etapa comercial, Reclamaciones y Documentos.
- Confirmar que nombres, referencias, correos y metadatos largos no crean scroll horizontal de página a 360, 375, 414 y 430 px.
- Confirmar contraste de texto normal, secundario, badges, foco y estados deshabilitados en las superficies semánticas.
- Confirmar que el cambio de etapa comercial converge en control, badge, detalle y lista sin recarga manual, y que un error conserva la etapa anterior.
- Revisar que ninguna etiqueta visible muestre enums, `snake_case`, rutas JSON o nombres de funciones internas.
