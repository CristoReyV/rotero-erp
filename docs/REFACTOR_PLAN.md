# ROTERO ERP – Plan Técnico de Refactor

> **Fecha:** 2026-02-20 · **Autor:** Tech Lead / Arquitecto Frontend
> **Fuente de verdad:** `src/App.tsx` (809 líneas), analizado línea por línea.
> **Principio rector:** Zero visual regression. La UI no cambia, la estructura interna sí.

---

## 1. Estructura de Carpetas Propuesta

```
src/
├── main.tsx                          ← Entry point (ya existe, NO se toca)
├── App.tsx                           ← Se reduce a: Router + Layout wrapper (~30 líneas)
├── index.css                         ← Design tokens (ya existe, se conserva tal cual)
│
├── types/
│   ├── index.ts                      ← Re-export barrel
│   ├── modules.ts                    ← Type `Module`, tipo union de módulos
│   ├── operations.ts                 ← Operation, OperationDetail, TimelineStep
│   ├── inventory.ts                  ← InventoryLot, StockAlert
│   ├── customs.ts                    ← Pedimento
│   ├── billing.ts                    ← CFDI
│   ├── commercial.ts                 ← Deal, PipelineColumn
│   ├── security.ts                   ← UserRecord, AuditLog
│   └── dashboard.ts                  ← DashboardOperation, FiscalAlert
│
├── mocks/
│   ├── index.ts                      ← Re-export barrel
│   ├── dashboard.mock.ts             ← dashboardOperations[], fiscalAlerts[], chartData[]
│   ├── operations.mock.ts            ← operations[], timelineSteps[]
│   ├── inventory.mock.ts             ← inventoryLots[], stockAlerts[]
│   ├── customs.mock.ts               ← pedimentos[]
│   ├── billing.mock.ts               ← cfdis[]
│   ├── commercial.mock.ts            ← pipelineColumns[]
│   └── security.mock.ts              ← users[], auditLogs[]
│
├── components/
│   ├── Badge.tsx                     ← Extraído de App.tsx L95-108
│   ├── KPICard.tsx                   ← Extraído de App.tsx L77-93
│   ├── PageHeader.tsx                ← Patrón repetido: h2 + botones de acción a la derecha
│   └── PlaceholderScreen.tsx         ← "Módulo en desarrollo..." (para Finance y Reports)
│
├── layout/
│   ├── AppLayout.tsx                 ← Sidebar + Topbar + <Outlet/> (extraído de App.tsx L706-808)
│   ├── Sidebar.tsx                   ← Logo + SidebarItem list + toggle (L709-746)
│   ├── SidebarItem.tsx               ← Extraído de App.tsx L53-75
│   └── Topbar.tsx                    ← Search + tenant selector + bell + avatar (L751-788)
│
├── pages/
│   ├── DashboardPage.tsx             ← Extraído de App.tsx L112-214
│   ├── OperationsPage.tsx            ← Extraído de App.tsx L216-337 (incluye drawer state)
│   ├── InventoryPage.tsx             ← Extraído de App.tsx L339-430
│   ├── CustomsPage.tsx               ← Extraído de App.tsx L432-494
│   ├── BillingPage.tsx               ← Extraído de App.tsx L496-563
│   ├── CommercialPage.tsx            ← Extraído de App.tsx L565-602
│   ├── SecurityPage.tsx              ← Extraído de App.tsx L604-670
│   ├── FinancePage.tsx               ← PlaceholderScreen (no existe UI aún)
│   └── ReportsPage.tsx               ← PlaceholderScreen (no existe UI aún)
│
├── routes/
│   └── router.tsx                    ← createBrowserRouter config
│
├── services/                         ← Vacío por ahora, preparado para backend
│   └── .gitkeep
│
└── utils/                            ← Vacío por ahora
    └── .gitkeep

docs/
├── REFACTOR_PLAN.md                  ← Este documento
└── mockups/                          ← stitch/ renombrado (referencia visual solamente)
    ├── operational_dashboard_overview/
    ├── logistics_operations_tracking/
    ├── inventory_&_stock_(peps)/
    ├── customs_&_anexo_24_control/
    ├── billing_&_cfdi_4.0_compliance/
    ├── commercial_crm_pipeline/
    ├── bi_&_profitability_reports/
    └── system_security_&_audit_logs/
```

### Regla de naming

| Elemento | Convención | Ejemplo |
|----------|-----------|---------|
| Componentes | PascalCase.tsx | `KPICard.tsx` |
| Pages | PascalCase + `Page` suffix | `DashboardPage.tsx` |
| Types | PascalCase interfaces, camelCase archivos | `operations.ts` → `export interface Operation` |
| Mocks | camelCase + `.mock.ts` suffix | `operations.mock.ts` |
| Services | camelCase + `.service.ts` suffix | `operations.service.ts` (futuro) |
| Barrel exports | `index.ts` | Solo re-exports, zero lógica |

---

## 2. Plan de Refactor Incremental (10 pasos)

> **Regla de oro:** Después de CADA paso, el `npm run dev` debe correr sin errores y la UI debe verse **idéntica** al estado actual. Si no, se revierte el paso antes de continuar.

### Paso 1 — Mover `stitch/` a `docs/mockups/`

**Qué:** Renombrar `stitch/` → `docs/mockups/`
**Por qué:** Separar referencia visual de código fuente.
**Archivos tocados:** Solo file system, cero código.
**Verificación visual:** `npm run dev` sigue corriendo, no depende de stitch/.
**Riesgo:** Ninguno.

---

### Paso 2 — Crear `types/` con contratos de datos

**Qué:** Crear archivos de tipos extraídos de la data hardcoded en App.tsx.
**Por qué:** Establecer contratos antes de mover nada. Los tipos se usan como guía para los pasos siguientes.
**Archivos creados:** 8 archivos en `src/types/`
**Archivos tocados en App.tsx:** Ninguno todavía (los tipos se crean aparte, se importan después).
**Verificación visual:** `npm run dev` sin cambios. `npm run lint` pasa sin errores de tipos.
**Riesgo:** Ninguno.

---

### Paso 3 — Crear `mocks/` extrayendo data hardcoded

**Qué:** Mover los arrays inline `[{ id: 'ROT-24-001', ... }]` a archivos `.mock.ts` tipados.
**Por qué:** Desacoplar datos de presentación. Cada mock importa sus tipos de `types/`.
**Archivos creados:** 7 archivos en `src/mocks/`
**Cambio en App.tsx:** Los arrays inline se reemplazan por `import { operations } from '../mocks/operations.mock'`. El JSX no cambia, solo el source del dato.
**Verificación visual:** Cada pantalla debe mostrar exactamente los mismos datos. Comparar visualmente tabla por tabla.
**Riesgo:** Bajo. Si un import falla, la pantalla mostrará tabla vacía (se nota inmediatamente).

---

### Paso 4 — Extraer componentes compartidos: `Badge`, `KPICard`, `PageHeader`

**Qué:**
- Cortar `Badge` (L95-108) → `src/components/Badge.tsx`
- Cortar `KPICard` (L77-93) → `src/components/KPICard.tsx`
- Crear `PageHeader` (patrón repetido en L222-232, L341-351, L434-443, L498-503, L567-572, L607-611)
- Crear `PlaceholderScreen` para módulos no implementados

**Cambio en App.tsx:** Reemplazar definiciones inline por imports. Verificar que los 6 usos de Badge y 5 usos de KPICard siguen funcionando.
**Verificación visual:** Revisar cada pantalla que usa Badge (Ops, Inventory, Customs, Billing, Security) y KPICard (Dashboard, Billing).
**Riesgo:** Bajo. Componentes puros sin estado, copy-paste directo.

---

### Paso 5 — Extraer Layout: `Sidebar`, `SidebarItem`, `Topbar`, `AppLayout`

**Qué:**
- Cortar `SidebarItem` (L53-75) → `src/layout/SidebarItem.tsx`
- Extraer sidebar completo (L709-746) → `src/layout/Sidebar.tsx`
- Extraer topbar (L751-788) → `src/layout/Topbar.tsx`
- Crear `AppLayout.tsx` que compone Sidebar + Topbar + children/Outlet

**Estado que migra:**
- `isSidebarOpen` (boolean) → vive en `AppLayout` o en `Sidebar`
- `activeModule` (Module) → este estado TODAVÍA se pasa como prop. NO se elimina aún, se migra a router en Paso 7.
- `moduleTitle` (useMemo) → se mueve a `Topbar` como prop

**Cambio en App.tsx:** Se reduce a `<AppLayout>` + `renderScreen()` dentro. ~50 líneas.
**Verificación visual:** El sidebar debe expandir/colapsar. El topbar debe mostrar título dinámico. Transiciones de AnimatePresence intactas.
**Riesgo:** Medio. El estado `activeModule` cruza layout ↔ content. Manejar via props temporalmente.

---

### Paso 6 — Extraer Pages (cada pantalla a su archivo)

**Qué:** Mover cada `*Screen` component a `src/pages/*Page.tsx`:
- `DashboardScreen` (L112-214) → `DashboardPage.tsx`
- `OperationsScreen` (L216-337) → `OperationsPage.tsx` (lleva consigo su `useState<any>(null)` para selectedOp)
- `InventoryScreen` (L339-430) → `InventoryPage.tsx`
- `CustomsScreen` (L432-494) → `CustomsPage.tsx`
- `BillingScreen` (L496-563) → `BillingPage.tsx`
- `CommercialScreen` (L565-602) → `CommercialPage.tsx`
- `SecurityScreen` (L604-670) → `SecurityPage.tsx`
- `FinancePage.tsx` y `ReportsPage.tsx` → usan `PlaceholderScreen`

**Estado local que viaja con cada page:**
- `OperationsPage`: `selectedOp` (useState) — se queda local en el componente. NO se sube.
- Todas las demás: stateless (solo render mock data).

**Cambio en App.tsx:** El switch-case `renderScreen()` importa de `pages/`. App.tsx baja a ~40 líneas.
**Verificación visual:** Navegar por cada módulo del sidebar y verificar que la pantalla completa se ve exactamente igual.
**Riesgo:** Medio. El drawer de OperationsPage usa AnimatePresence — verificar que sigue animando correctamente cuando se extrae.

---

### Paso 7 — Instalar React Router y crear rutas

**Qué:**
- `npm install react-router-dom`
- Crear `src/routes/router.tsx` con `createBrowserRouter`
- Reemplazar el `useState<Module>` + switch-case por rutas URL reales
- Sidebar links cambian de `onClick={() => setActiveModule('x')}` a `<NavLink to="/x">`

**Mapa de rutas:**

| Ruta | Page | Título en Topbar |
|------|------|-----------------|
| `/` | Redirect → `/dashboard` | — |
| `/dashboard` | `DashboardPage` | Dashboard Operativo |
| `/operations` | `OperationsPage` | Operaciones y Logística |
| `/inventory` | `InventoryPage` | Inventarios y Almacén |
| `/customs` | `CustomsPage` | Aduanas y Anexo 24 |
| `/billing` | `BillingPage` | Facturación y CFDI 4.0 |
| `/finance` | `FinancePage` | Finanzas Corporativas |
| `/commercial` | `CommercialPage` | Comercial y CRM |
| `/reports` | `ReportsPage` | Reportes y BI |
| `/security` | `SecurityPage` | Seguridad y Configuración |
| `*` | Not Found / Redirect | — |

**Cambios clave:**
- `main.tsx`: envuelve `<App />` con `<RouterProvider router={router} />`
- `AppLayout.tsx`: usa `<Outlet />` en lugar de `renderScreen()`
- `Sidebar.tsx`: usa `useLocation()` para highlight activo + `<NavLink>` en vez de onClick
- `Topbar.tsx`: deriva título de `useLocation().pathname` con un map estático
- Se ELIMINA: `useState<Module>`, `setActiveModule`, `renderScreen()`, `moduleTitle` useMemo

**Verificación visual:**
1. Navegar con sidebar: URL cambia, pantalla cambia, highlight activo correcto
2. Browser back/forward funciona
3. Refresh en `/operations` carga la pantalla correcta (no redirige a dashboard)
4. AnimatePresence sigue funcionando en transiciones (key = pathname)

**Riesgo:** Alto. Este es el paso con mayor superficie de cambio. DO NOT combine con otros pasos.

---

### Paso 8 — Actualizar alias `@` en vite.config.ts

**Qué:**
- Cambiar `alias: { '@': path.resolve(__dirname, '.') }` → `alias: { '@': path.resolve(__dirname, 'src') }`
- Actualizar todos los imports relativos `'../components/Badge'` → `'@/components/Badge'`
- Agregar `paths` en `tsconfig.json`

**Verificación visual:** `npm run dev` sin errores. `npm run lint` pasa.
**Riesgo:** Bajo. Es refactor mecánico de paths.

---

### Paso 9 — Limpiar dependencias no usadas

**Qué:** Ejecutar `npm uninstall` para paquetes no usados.
**Verificación:** `npm run build` exitoso. Nada se rompe.
**Riesgo:** Bajo.

(Ver sección 4 para lista exacta.)

---

### Paso 10 — Cleanup final y verificación

**Qué:**
- Verificar que `src/App.tsx` es <40 líneas
- Verificar que no quedan `any` types en componentes (excepto icon props de Lucide)
- Verificar que cada archivo exporta exactamente lo necesario
- Eliminar `process.env.GEMINI_API_KEY` de vite.config.ts (no se usa)
- Actualizar `.gitignore` si es necesrario
- Run final: `npm run dev` + `npm run build` + `npm run lint`

**Verificación visual:** Recorrer las 9 rutas. Verificar sidebar, topbar, cada tabla, el drawer, el kanban, los KPIs.

---

## 3. Routing — Diseño Detallado

### Librería elegida: `react-router-dom` v7

**Justificación:**
- Estándar de facto para React SPA
- Soporta layout routes con `<Outlet />`
- `createBrowserRouter` para route config centralizada
- `NavLink` para active states nativos
- Sin dependencias absurdas

### Router config (`src/routes/router.tsx`):

```
createBrowserRouter([
  {
    path: '/',
    element: <AppLayout />,          // Sidebar + Topbar + AnimatePresence(<Outlet />)
    children: [
      { index: true, element: <Navigate to="/dashboard" replace /> },
      { path: 'dashboard',   element: <DashboardPage /> },
      { path: 'operations',  element: <OperationsPage /> },
      { path: 'inventory',   element: <InventoryPage /> },
      { path: 'customs',     element: <CustomsPage /> },
      { path: 'billing',     element: <BillingPage /> },
      { path: 'finance',     element: <FinancePage /> },
      { path: 'commercial',  element: <CommercialPage /> },
      { path: 'reports',     element: <ReportsPage /> },
      { path: 'security',    element: <SecurityPage /> },
    ]
  },
  { path: '*', element: <Navigate to="/dashboard" replace /> }
])
```

### Sidebar → Router mapping:

```
// Sidebar nav config (array estático, no hardcoded JSX)
const NAV_ITEMS = [
  { path: '/dashboard',   icon: LayoutDashboard, label: 'Dashboard' },
  { path: '/operations',  icon: Truck,           label: 'Operaciones' },
  { path: '/inventory',   icon: Package,         label: 'Inventarios' },
  { path: '/customs',     icon: Gavel,           label: 'Aduanas' },
  { path: '/billing',     icon: FileText,        label: 'Facturación' },
  { path: '/finance',     icon: Wallet,          label: 'Finanzas' },
  { path: '/commercial',  icon: Users,           label: 'Comercial' },
  { path: '/reports',     icon: BarChart3,       label: 'Reportes / BI' },
  { path: '/security',    icon: Settings,        label: 'Seguridad' },
]
```

### Topbar title derivation:

```
// Mapa estático en Topbar.tsx
const TITLES: Record<string, string> = {
  '/dashboard':   'Dashboard Operativo',
  '/operations':  'Operaciones y Logística',
  '/inventory':   'Inventarios y Almacén',
  '/customs':     'Aduanas y Anexo 24',
  '/billing':     'Facturación y CFDI 4.0',
  '/finance':     'Finanzas Corporativas',
  '/commercial':  'Comercial y CRM',
  '/reports':     'Reportes y BI',
  '/security':    'Seguridad y Configuración',
}
```

### AnimatePresence con Router:

```
// En AppLayout.tsx
const location = useLocation();

<AnimatePresence mode="wait">
  <motion.div
    key={location.pathname}       // ← la clave cambia con la ruta
    initial={{ opacity: 0, y: 10 }}
    animate={{ opacity: 1, y: 0 }}
    exit={{ opacity: 0, y: -10 }}
    transition={{ duration: 0.2 }}
  >
    <Outlet />
  </motion.div>
</AnimatePresence>
```

---

## 4. Limpieza de Dependencias

### Remover ahora (no se usan en ningún lado del código):

| Paquete | Tipo | Razón para eliminar |
|---------|------|-------------------|
| `express` | dependency | No hay server-side code en el proyecto |
| `@types/express` | devDependency | No hay server-side code |
| `better-sqlite3` | dependency | No se importa en ningún archivo |
| `dotenv` | dependency | Vite maneja env nativo, no se usa dotenv |
| `@google/genai` | dependency | No se importa en ningún archivo React |

```bash
npm uninstall express @types/express better-sqlite3 dotenv @google/genai
```

### Conservar (se usan activamente):

| Paquete | Versión | Dónde se usa |
|---------|---------|-------------|
| `react` | 19.0.0 | Core framework |
| `react-dom` | 19.0.0 | DOM rendering |
| `@vitejs/plugin-react` | 5.0.4 | Vite plugin |
| `vite` | 6.2.0 | Build tool |
| `tailwindcss` | 4.1.14 | Styling |
| `@tailwindcss/vite` | 4.1.14 | Vite integration |
| `autoprefixer` | 10.4.21 | CSS post-processing |
| `lucide-react` | 0.546.0 | Iconos en toda la UI |
| `motion` | 12.23.24 | AnimatePresence, drawer, transiciones |
| `typescript` | 5.8.2 | Type checking |
| `@types/node` | 22.14.0 | Node types para vite.config |
| `tsx` | 4.21.0 | TS execution (scripts) |

### Agregar en Paso 7:

| Paquete | Versión | Propósito |
|---------|---------|----------|
| `react-router-dom` | ^7.x | Routing |

### Criterio de limpieza futuro:
> **Regla: "2-Sprint Rule"** — Si un paquete no se usa en producción después de 2 sprints, se elimina. No se conservan paquetes como "por si después".

---

## 5. Contratos de Datos (TypeScript types)

> Extraídos EXACTAMENTE de los object literals que aparecen en App.tsx. No se inventa ningún campo.

### `src/types/modules.ts`

```typescript
export type Module =
  | 'dashboard'
  | 'operations'
  | 'inventory'
  | 'customs'
  | 'billing'
  | 'finance'
  | 'commercial'
  | 'reports'
  | 'security';
```

### `src/types/dashboard.ts`

```typescript
import type { BadgeVariant } from './common';

export interface DashboardOperation {
  id: string;          // 'ROT-24-001'
  client: string;      // 'Logística Monterrey SA'
  status: string;      // 'En Tránsito'
  route: string;       // 'Laredo → CDMX'
  eta: string;         // 'Hoy, 14:00'
  variant: BadgeVariant;
}

export interface FiscalAlert {
  type: 'danger' | 'warning' | 'info';
  title: string;       // 'Pedimentos por vencer'
  description: string; // '2 Pedimentos (A1-9302...) requieren...'
}
```

### `src/types/operations.ts`

```typescript
import type { BadgeVariant } from './common';

export interface Operation {
  id: string;          // 'OP-8492'
  client: string;      // 'Autopartes de México'
  type: string;        // 'FTL - Seco'
  status: string;      // 'En Tránsito'
  route: string;       // 'Laredo → MTY'
  owner: string;       // 'J. Perez'
  variant: BadgeVariant;
}

export interface TimelineStep {
  time: string;        // '10:00 AM'
  event: string;       // 'Salida de Almacén'
  desc: string;        // 'Laredo Distribution Center'
  done?: boolean;
  current?: boolean;
  future?: boolean;
}
```

### `src/types/inventory.ts`

```typescript
export interface InventoryLot {
  sku: string;         // 'SKU-10294'
  desc: string;        // 'Widget Industrial A'
  lote: string;        // '#9921'
  date: string;        // '12/Oct/23'
  stock: number;       // 450
  cost: string;        // '$1,200'
  low?: boolean;       // true when stock is critically low
}

export interface StockAlert {
  sku: string;         // 'SKU-44021'
  message: string;     // '4 unidades' | 'Próximo a caducar'
  severity: 'danger' | 'warning';
}
```

### `src/types/customs.ts`

```typescript
export interface Pedimento {
  id: string;          // '23-40-3921'
  date: string;        // '12/Oct/23'
  material: string;    // 'Steel Raw Material'
  balance: number;     // 450
  status: string;      // 'Activo' | 'Auditado' | 'Cerrado'
  discharge: string;   // 'Auto' | 'Manual' | 'Final'
}
```

### `src/types/billing.ts`

```typescript
export interface CFDI {
  folio: string;       // 'A-4022'
  client: string;      // 'Logistics MX S.A.'
  uuid: string;        // '...8a9f'
  amount: string;      // '$12,500'
  status: string;      // 'Timbrado' | 'Pendiente' | 'Error'
  cp: string;          // 'Validado' | 'Requerido' | 'Error RFC'
}
```

### `src/types/commercial.ts`

```typescript
export interface Deal {
  name: string;        // 'Logística Monterrey'
  value: string;       // '$150k'
  prob: string;        // '60%' | 'Won'
}

export interface PipelineColumn {
  title: string;       // 'Prospecto'
  count: number;       // 3
  deals: Deal[];
}
```

### `src/types/security.ts`

```typescript
export interface UserRecord {
  name: string;        // 'Maria Gonzalez'
  role: string;        // 'Compliance Officer'
  status: string;      // 'Activo' | 'Inactivo'
  last: string;        // 'Hace 5 min'
}

export interface AuditLog {
  time: string;        // '10:42 AM'
  user: string;        // 'J. Perez'
  event: string;       // 'Login Exitoso'
  color: string;       // 'bg-emerald-500' (Tailwind class)
}
```

### `src/types/common.ts`

```typescript
export type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'info';
```

### `src/types/index.ts` (barrel)

```typescript
export * from './common';
export * from './modules';
export * from './dashboard';
export * from './operations';
export * from './inventory';
export * from './customs';
export * from './billing';
export * from './commercial';
export * from './security';
```

---

## 6. Checklist Final

### ✅ Definition of Done del Refactor

| # | Criterio | Verificación |
|---|---------|-------------|
| 1 | `App.tsx` tiene ≤40 líneas | Contar líneas |
| 2 | Zero componentes definidos dentro de `App.tsx` | Grep por `const.*=>` en App.tsx |
| 3 | Zero mock data hardcoded en archivos de `pages/` | Grep por arrays `[{` inline en pages/ |
| 4 | Toda mock data vive en `src/mocks/` | `ls src/mocks/` tiene 7 archivos |
| 5 | Todos los tipos viven en `src/types/` | `ls src/types/` tiene 9 archivos |
| 6 | Cada Page es un archivo independiente en `src/pages/` | 9 archivos .tsx |
| 7 | Layout separado en `src/layout/` | 4 archivos .tsx |
| 8 | Componentes compartidos en `src/components/` | ≥3 archivos .tsx |
| 9 | Router funcional con 9 rutas | Navegar a cada ruta directamente por URL |
| 10 | Browser back/forward funciona | Testing manual |
| 11 | Sidebar highlight activo corresponde a la ruta | Navegar y verificar |
| 12 | Refresh en cualquier ruta NO redirige a dashboard | Refresh en /customs carga /customs |
| 13 | AnimatePresence funciona en transiciones | Navegar entre módulos |
| 14 | Drawer lateral en Operations funciona | Click row → drawer slide-in → close |
| 15 | `npm run dev` sin errores | Terminal limpia |
| 16 | `npm run build` exitoso | Dist generada sin errores |
| 17 | `npm run lint` sin errores | Zero type errors |
| 18 | No quedan dependencias no usadas en package.json | Verificar tras uninstall |
| 19 | `stitch/` movido a `docs/mockups/` | Verificar filesystem |
| 20 | Alias `@/` apunta a `src/` y funciona | Import resolution correcta |

### 🚫 No-Go List (NO tocar en este refactor)

| # | Qué NO hacer | Por qué |
|---|-------------|---------|
| 1 | **No conectar Supabase ni ningún backend** | Este refactor es puramente frontend. Backend viene después. |
| 2 | **No implementar auth real** | Sin backend no hay auth. El user hardcoded "Jorge Dominguez" se queda. |
| 3 | **No cambiar la UI visual** | Zero cambios de color, padding, border-radius, font-size, o layout. El diseño ya está aceptado. |
| 4 | **No agregar nuevas pantallas ni features** | Finance y Reports quedan como placeholders. No se implementan. |
| 5 | **No agregar state management global** (Zustand, Redux, Context) | No hay necesidad aún. Las pantallas son stateless o tienen estado local trivial. |
| 6 | **No agregar testing framework** (Jest, Vitest) | Es prematuro. Tests se agregan cuando hay lógica de negocio real. |
| 7 | **No refactorizar la lógica del drawer lateral** | Funciona. Se extrae tal cual, sin mejorar. |
| 8 | **No agregar i18n** | Los strings están en español mexicano y se conservan tal cual. |
| 9 | **No agregar lazy loading / code splitting** | Con 9 pages estáticas no vale la pena. Se agrega cuando haya peso real. |
| 10 | **No tocar `index.css` ni los design tokens** | Ya están correctos. |
| 11 | **No tocar `main.tsx`** excepto agregar RouterProvider | El entry point se conserva mínimo. |
| 12 | **No modificar el contenido de `docs/mockups/`** | Son archivos de referencia visual estáticos, no se editan. |

---

## Resumen de Esfuerzo Estimado

| Paso | Descripción | Archivos nuevos | Archivos editados | Riesgo | Esfuerzo |
|------|------------|----------------|-------------------|--------|----------|
| 1 | Mover stitch → docs/mockups | 0 | 0 (filesystem) | Ninguno | 2 min |
| 2 | Crear types/ | 9 | 0 | Ninguno | 15 min |
| 3 | Crear mocks/ | 8 | App.tsx (imports) | Bajo | 20 min |
| 4 | Extraer Badge, KPICard, PageHeader | 4 | App.tsx (imports) | Bajo | 15 min |
| 5 | Extraer Layout (Sidebar, Topbar) | 4 | App.tsx (reduce) | Medio | 30 min |
| 6 | Extraer Pages (7 screens) | 9 | App.tsx (reduce a ~40L) | Medio | 25 min |
| 7 | React Router | 1 + edits | main.tsx, AppLayout, Sidebar, Topbar | **Alto** | 45 min |
| 8 | Alias @ en vite/tsconfig | 0 | vite.config, tsconfig, all imports | Bajo | 15 min |
| 9 | Limpiar dependencias | 0 | package.json | Bajo | 5 min |
| 10 | Verificación final | 0 | Cleanup suelto | Bajo | 15 min |
| | **TOTAL** | **~35 archivos** | **~10 archivos** | | **~3 horas** |
