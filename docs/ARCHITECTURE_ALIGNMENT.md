# ROTERO ERP – Alineación Arquitectura ↔ Refactor

> **Propósito:** Puente oficial entre la [Arquitectura Funcional](file:///c:/Users/Cristo/.gemini/antigravity/brain/c8399d40-b5df-4a47-b41b-b1367da95db5/rotero_erp_architecture.md) y el [Plan de Refactor](file:///c:/Users/Cristo/Documents/WLS%20ROTERO/WLS%20Rotero%20NUEVA/ERP/DEV/docs/REFACTOR_PLAN.md).
> **Fecha:** 2026-02-20 · v1.0-ALIGN

---

## 1. Validación: Estructura de Carpetas vs Arquitectura Funcional

### Resultado: ✅ Compatible con 4 ajustes obligatorios

La estructura propuesta en `REFACTOR_PLAN.md` cubre los 9 módulos funcionales definidos en la arquitectura (§1.1), pero necesita ajustes para alinear **contratos de estados** y **preparación para reglas de negocio**.

### Ajustes Requeridos

| # | Ajuste | Justificación (referencia arquitectura) |
|---|--------|----------------------------------------|
| A1 | Agregar `src/types/common.ts` con constantes de estados (`STATUS_CODES`) además de `BadgeVariant` | Arquitectura §3.1 define estados como enums codificados (`draft`, `confirmed`, etc.), no como strings libres (RT-03) |
| A2 | Agregar `src/constants/` con `states.ts`, `roles.ts`, `nav.ts` | Los estados, roles y nav config de §3.1 y §3.2 son constantes del sistema, no tipos. Deben vivir separados |
| A3 | Agregar `src/types/finance.ts` y `src/types/reports.ts` (interfaces stub) | Arquitectura define estos módulos con submódulos (§1.1 filas 6 y 8). Aunque son placeholder hoy, los contratos deben existir |
| A4 | `src/mocks/` debe incluir `finance.mock.ts` y `reports.mock.ts` vacíos | Coherencia: cada módulo funcional tiene su mock, incluso si devuelve `[]` |

### Estructura Final Corregida

```
src/
├── main.tsx
├── App.tsx                           ← Router wrapper (~20 líneas)
├── index.css                         ← Design tokens
│
├── constants/                        ← [NUEVO] Constantes del sistema
│   ├── states.ts                     ← Enums de estado por módulo (§3.1)
│   ├── roles.ts                      ← Roles y permisos (§3.2)
│   └── nav.ts                        ← NAV_ITEMS + ROUTE_TITLES
│
├── types/
│   ├── index.ts                      ← Barrel
│   ├── common.ts                     ← BadgeVariant, BaseEntity, AuditFields
│   ├── modules.ts                    ← Type Module
│   ├── operations.ts                 ← Operation, TimelineStep
│   ├── inventory.ts                  ← InventoryLot, StockAlert
│   ├── customs.ts                    ← Pedimento
│   ├── billing.ts                    ← CFDI
│   ├── commercial.ts                 ← Deal, PipelineColumn
│   ├── security.ts                   ← UserRecord, AuditLog
│   ├── dashboard.ts                  ← DashboardOperation, FiscalAlert
│   ├── finance.ts                    ← [STUB] AccountReceivable, AccountPayable
│   └── reports.ts                    ← [STUB] ReportConfig
│
├── mocks/                            ← 1:1 con types/
│   ├── index.ts
│   ├── dashboard.mock.ts
│   ├── operations.mock.ts
│   ├── inventory.mock.ts
│   ├── customs.mock.ts
│   ├── billing.mock.ts
│   ├── commercial.mock.ts
│   ├── security.mock.ts
│   ├── finance.mock.ts              ← export const receivables = []
│   └── reports.mock.ts              ← export const reports = []
│
├── components/
│   ├── Badge.tsx
│   ├── KPICard.tsx
│   ├── PageHeader.tsx
│   └── PlaceholderScreen.tsx
│
├── layout/
│   ├── AppLayout.tsx
│   ├── Sidebar.tsx
│   ├── SidebarItem.tsx
│   └── Topbar.tsx
│
├── pages/
│   ├── DashboardPage.tsx
│   ├── OperationsPage.tsx
│   ├── InventoryPage.tsx
│   ├── CustomsPage.tsx
│   ├── BillingPage.tsx
│   ├── CommercialPage.tsx
│   ├── SecurityPage.tsx
│   ├── FinancePage.tsx               ← PlaceholderScreen
│   └── ReportsPage.tsx               ← PlaceholderScreen
│
├── routes/
│   └── router.tsx
│
├── services/                         ← Vacío ahora, 1:1 con módulos después
│   └── .gitkeep
│
└── utils/
    └── .gitkeep
```

---

## 2. Correspondencia Exacta: Módulo → Archivo → Ruta → Servicio Futuro

| # | Módulo Funcional (§1.1) | Page | Ruta | Type | Mock | Servicio Futuro | Tabla Supabase (futuro) |
|---|------------------------|------|------|------|------|-----------------|------------------------|
| 1 | Dashboard | `DashboardPage.tsx` | `/dashboard` | `dashboard.ts` | `dashboard.mock.ts` | `dashboard.service.ts` | Vista agregada (RPCs) |
| 2 | Operaciones | `OperationsPage.tsx` | `/operations` | `operations.ts` | `operations.mock.ts` | `operations.service.ts` | `orders`, `order_status_history` |
| 3 | Inventarios | `InventoryPage.tsx` | `/inventory` | `inventory.ts` | `inventory.mock.ts` | `inventory.service.ts` | `inventory_lots`, `stock_adjustments` |
| 4 | Aduanas | `CustomsPage.tsx` | `/customs` | `customs.ts` | `customs.mock.ts` | `customs.service.ts` | `pedimentos`, `anexo24_entries`, `descargas` |
| 5 | Facturación | `BillingPage.tsx` | `/billing` | `billing.ts` | `billing.mock.ts` | `billing.service.ts` | `cfdis`, `carta_porte` |
| 6 | Finanzas | `FinancePage.tsx` | `/finance` | `finance.ts` | `finance.mock.ts` | `finance.service.ts` | `accounts_receivable`, `accounts_payable`, `payments` |
| 7 | Comercial/CRM | `CommercialPage.tsx` | `/commercial` | `commercial.ts` | `commercial.mock.ts` | `commercial.service.ts` | `prospects`, `quotes`, `deals` |
| 8 | Reportes/BI | `ReportsPage.tsx` | `/reports` | `reports.ts` | `reports.mock.ts` | `reports.service.ts` | Vistas materializadas (RT-10) |
| 9 | Seguridad | `SecurityPage.tsx` | `/security` | `security.ts` | `security.mock.ts` | `security.service.ts` | `profiles`, `memberships`, `audit_logs` |

> [!IMPORTANT]
> **Regla 1:1** — Cada módulo funcional tiene exactamente: 1 page, 1 ruta, 1 type, 1 mock, 1 service futuro. Sin excepciones.

---

## 3. Reglas Técnicas Obligatorias Durante el Refactor

### 3.A — Consistencia de Estados

| Regla | Qué hacer | Referencia |
|-------|-----------|-----------|
| **RE-01** | Los códigos de estado (`draft`, `confirmed`, `in_transit`, etc.) se definen en `constants/states.ts` como objetos `as const`, NO como strings sueltos | §3.1 + RT-03 |
| **RE-02** | Cada estado tiene un mapping a `BadgeVariant` (`default`, `success`, `warning`, `danger`, `info`) definido junto al enum, NO inline en JSX | §5.1 CV-02 |
| **RE-03** | Los mock data en `mocks/*.mock.ts` DEBEN usar los códigos de `constants/states.ts`, NO strings libres como `'En Tránsito'` | RT-03 |
| **RE-04** | Las transiciones válidas de estado se documentan como comentario en `constants/states.ts`, aunque NO se enforzan en frontend (enforcement es server-side) | RN-08 |

**Ejemplo esperado en `constants/states.ts`:**

```
// Formato conceptual — NO es código a implementar ahora:
export const ORDER_STATES = {
  draft:       { label: 'Borrador',      badge: 'default' },
  confirmed:   { label: 'Confirmada',    badge: 'info' },
  planned:     { label: 'Planificada',   badge: 'info' },
  loading:     { label: 'En Carga',      badge: 'warning' },
  dispatched:  { label: 'Despachada',    badge: 'warning' },
  in_transit:  { label: 'En Tránsito',   badge: 'info' },
  in_customs:  { label: 'En Aduana',     badge: 'warning' },
  delivered:   { label: 'Entregada',     badge: 'success' },
  invoiced:    { label: 'Facturada',     badge: 'success' },
  collected:   { label: 'Cobrada',       badge: 'success' },
  cancelled:   { label: 'Cancelada',     badge: 'danger' },
} as const;
```

### 3.B — Contratos de Datos

| Regla | Qué hacer | Referencia |
|-------|-----------|-----------|
| **RD-01** | Cada type en `types/` incluye una interfaz `BaseEntity` con `id`, `tenant_id`, `created_at`, `updated_at`, `created_by` | RT-01 + CD-06 |
| **RD-02** | La `BaseEntity` se define en `types/common.ts` y se extiende en cada entidad específica | RT-01 |
| **RD-03** | Los mocks actuales NO tienen `BaseEntity` fields (porque son mock). Eso está OK — los campos se agregan cuando se conecte backend | Pragmatismo |
| **RD-04** | IDs de referencia siguen formato consistente: `ROT-YY-NNN` (órdenes), `A-NNNN` (facturas), `NN-NN-NNNN` (pedimentos) | CD-04 |
| **RD-05** | Montos como `string` en mocks (display-ready: `'$12,500'`), como `number` en types de backend (centavos o con 2 decimales) | CD-02 |

**`BaseEntity` en `types/common.ts`:**

```
// Se define ahora, se usa cuando se conecte backend:
export interface BaseEntity {
  id: string;              // UUID
  tenant_id: string;       // UUID — multi-tenant (RN-01, RN-07)
  created_at: string;      // ISO 8601
  updated_at: string;      // ISO 8601
  created_by: string;      // UUID del usuario
  is_deleted?: boolean;    // Soft delete (RT-01)
}
```

### 3.C — Separación UI / Lógica

| Regla | Enforcement | Referencia |
|-------|-------------|-----------|
| **SU-01** | Las Pages (`pages/*.tsx`) SOLO renderizan UI. No contienen fetching, transformación de datos, ni lógica de negocio | RT-05, RT-06 |
| **SU-02** | Los datos entran a las Pages via import de `mocks/` (hoy) o via hooks/services (futuro). El cambio de fuente NO debe requerir reescribir la Page | RT-06 |
| **SU-03** | Los componentes (`components/*.tsx`) son puros: reciben props, renderizan. Sin side effects, sin state global | RT-05 |
| **SU-04** | La navegación se maneja exclusivamente via React Router (`NavLink`, `useNavigate`), nunca via `useState` | Eliminación de acoplamiento |
| **SU-05** | El estado local de un Page (ej: `selectedOp` en Operations) se queda local en ese Page. NO se sube a Layout ni a App | Mínimo privilegio |

### 3.D — Preparación para Servicios Futuros

| Regla | Qué preparar ahora | Qué NO hacer ahora |
|-------|--------------------|--------------------|
| **SF-01** | Crear carpeta `services/` con `.gitkeep` | NO crear archivos service vacíos |
| **SF-02** | Los mocks exportan funciones async: `getMockOperations(): Promise<Operation[]>` | NO conectar a Supabase |
| **SF-03** | Cada Page importa data de mocks via función, NO via import directo del array | NO crear hooks `useOperations()` |
| **SF-04** | Documentar en comentario de cada mock: `// TODO: Replace with operations.service.ts → rpc_list_operations` | NO implementar el RPC |
| **SF-05** | Los types ya incluyen `BaseEntity` como interface disponible | NO extender entidades mock con BaseEntity |

> [!TIP]
> **Por qué SF-02 y SF-03 importan:** Cuando se conecte backend, el cambio será:
> `import { getMockOperations } from '@/mocks/operations.mock'` →
> `import { getOperations } from '@/services/operations.service'`
> — Un cambio de 1 línea por Page, sin tocar JSX.

---

## 4. Dependencias Futuras (NO implementar ahora)

### 4.1 Backend (Supabase)

| Componente | Módulos que lo necesitan | Cuándo implementar | Referencia |
|-----------|------------------------|--------------------|-----------|
| `supabase-js` client | Todos | Sprint post-refactor | RT-06 |
| RPC functions (`rpc_*`) | Todos los CRUD | Sprint post-refactor | RT-02 |
| RLS policies (`tenant_id`) | Todas las tablas | Sprint post-refactor | RN-01, RN-07 |
| Realtime subscriptions | Dashboard, Operations | Sprint +2 | Para tracking en vivo |
| Storage (bucket) | Billing (XML/PDF) | Sprint +2 | RF-05 |

### 4.2 Auth

| Componente | Propósito | Referencia |
|-----------|----------|-----------|
| `supabase.auth` | Login/logout real | §3.2 |
| `rpc_get_my_context` | Obtener tenant_id, role, CEDIS | RN-07 |
| Route guards | Proteger rutas por rol | §3.2 matriz de permisos |
| Session persistence | Rehydrate en refresh | Experiencia de usuario |

> [!WARNING]
> **El usuario hardcoded "Jorge Dominguez / Director Operativo" en Topbar se conserva durante todo el refactor.** Se reemplaza SOLO cuando se implemente auth real.

### 4.3 Integraciones Externas

| Integración | Módulo | Regla | Estado |
|-------------|--------|-------|--------|
| PAC (timbrado SAT) | Billing | RF-01, RN-05 | No implementar |
| Validación RFC 69-B | Billing | RF-03 | No implementar |
| GPS / Tracking | Operations | §2.1 paso 6 | No implementar |
| DOF tipo de cambio | Billing | RF-07 | No implementar |
| SECIIT export | Customs | RF-06 | No implementar |

---

## 5. Diagrama Textual de Arquitectura Final

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         ROTERO ERP – BETA                                │
│                     Arquitectura Frontend Modular                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─ main.tsx ──────────────────────────────────────────────────────────┐ │
│  │  <RouterProvider router={router} />                                 │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│  ┌─ routes/router.tsx ───────▼─────────────────────────────────────────┐ │
│  │  createBrowserRouter([                                              │ │
│  │    { path: '/', element: <AppLayout/>, children: [                  │ │
│  │        /dashboard, /operations, /inventory, /customs,               │ │
│  │        /billing, /finance, /commercial, /reports, /security         │ │
│  │    ]}                                                               │ │
│  │  ])                                                                 │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│  ┌─ layout/ ─────────────────▼─────────────────────────────────────────┐ │
│  │  ┌────────────┐  ┌─────────────────────────────────────────────────┐│ │
│  │  │            │  │ Topbar.tsx                                      ││ │
│  │  │ Sidebar    │  │ [titulo dinámico] [search] [tenant] [bell] [av]││ │
│  │  │ .tsx       │  ├─────────────────────────────────────────────────┤│ │
│  │  │            │  │                                                 ││ │
│  │  │ NavLink ×9 │  │  <AnimatePresence>                             ││ │
│  │  │ (activo =  │  │    <Outlet />  ← Page del módulo activo        ││ │
│  │  │  pathname) │  │  </AnimatePresence>                            ││ │
│  │  │            │  │                                                 ││ │
│  │  └────────────┘  └─────────────────────────────────────────────────┘│ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│  ┌─ pages/ ──────────────────▼─────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  DashboardPage ──→ imports ──→ mocks/dashboard.mock.ts              │ │
│  │  OperationsPage ─→ imports ──→ mocks/operations.mock.ts             │ │
│  │  InventoryPage ──→ imports ──→ mocks/inventory.mock.ts              │ │
│  │  CustomsPage ────→ imports ──→ mocks/customs.mock.ts                │ │
│  │  BillingPage ────→ imports ──→ mocks/billing.mock.ts                │ │
│  │  CommercialPage ─→ imports ──→ mocks/commercial.mock.ts             │ │
│  │  SecurityPage ───→ imports ──→ mocks/security.mock.ts               │ │
│  │  FinancePage ────→ PlaceholderScreen                                │ │
│  │  ReportsPage ────→ PlaceholderScreen                                │ │
│  │                       │                                             │ │
│  │                       ▼ usa                                         │ │
│  │              components/ (Badge, KPICard, PageHeader)               │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│  ┌─ types/ ──────────────────▼─────────────────────────────────────────┐ │
│  │  common.ts ←── BaseEntity, BadgeVariant                             │ │
│  │  modules.ts, operations.ts, inventory.ts, customs.ts,               │ │
│  │  billing.ts, commercial.ts, security.ts, dashboard.ts,              │ │
│  │  finance.ts (stub), reports.ts (stub)                               │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                              │                                           │
│  ┌─ constants/ ──────────────▼─────────────────────────────────────────┐ │
│  │  states.ts ←── ORDER_STATES, CFDI_STATES, PEDIMENTO_STATES,         │ │
│  │                CRM_STATES, FINANCE_STATES (de §3.1)                 │ │
│  │  roles.ts ←── ROLES, PERMISSIONS (de §3.2) [futuro enforcement]     │ │
│  │  nav.ts ←── NAV_ITEMS, ROUTE_TITLES                                 │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
│  ┌─ FUTURO (post-refactor) ────────────────────────────────────────────┐ │
│  │  services/*.service.ts ← Supabase RPCs (RT-02, RT-06)              │ │
│  │  hooks/useAuth.ts ← Session, tenant context (RN-07)                 │ │
│  │  middleware/guards.ts ← Route protection por rol (§3.2)             │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Checklist Técnico Obligatorio Pre-Desarrollo

> Este checklist se valida ANTES de pasar a implementar backend, auth, o features nuevas. Cada item debe responderse con ✅ o ❌.

### A — Estructura y Archivos

| # | Verificación | Comando/Acción |
|---|-------------|----------------|
| A1 | `src/App.tsx` tiene ≤30 líneas | `wc -l src/App.tsx` |
| A2 | `src/pages/` tiene exactamente 9 archivos `.tsx` | `ls src/pages/*.tsx \| wc -l` |
| A3 | `src/types/` tiene 11 archivos (9 módulos + common + index) | `ls src/types/*.ts \| wc -l` |
| A4 | `src/mocks/` tiene 10 archivos (9 módulos + index barrel) | `ls src/mocks/*.ts \| wc -l` |
| A5 | `src/constants/` tiene 3 archivos (`states`, `roles`, `nav`) | `ls src/constants/*.ts` |
| A6 | `src/layout/` tiene 4 archivos | `ls src/layout/*.tsx` |
| A7 | `src/components/` tiene ≥3 archivos | `ls src/components/*.tsx` |
| A8 | `src/services/` existe con `.gitkeep` | `ls src/services/` |
| A9 | `stitch/` ya NO existe en `src/` (movido a `docs/mockups/`) | `ls stitch/` should fail |

### B — Routing

| # | Verificación | Cómo probar |
|---|-------------|------------|
| B1 | Las 9 rutas se resuelven correctamente por URL | Navegar a `/dashboard`, `/operations`, etc. directo |
| B2 | Refresh en cualquier ruta NO redirige a `/dashboard` | F5 en `/customs` → sigue en `/customs` |
| B3 | Sidebar highlight activo corresponde a URL actual | Visual: navegar, verificar highlight |
| B4 | Browser back/forward funciona | Navegar 3 rutas, luego Alt+← y Alt+→ |
| B5 | Ruta inválida redirige a `/dashboard` | Navegar a `/nonexistent` |
| B6 | `AnimatePresence` anima transiciones | Navegar entre módulos, ver fade |

### C — Consistencia con Arquitectura §3.1 (Estados)

| # | Verificación | Cómo probar |
|---|-------------|------------|
| C1 | `constants/states.ts` define los 5 enums de estado (Order, CFDI, Pedimento, CRM, Finance) | Abrir archivo, verificar cobertura |
| C2 | Cada estado tiene `label` (español) y `badge` (BadgeVariant) | Visual en archivo |
| C3 | Mocks usan códigos de `states.ts`, no strings sueltos | Grep en mocks/ por strings vs imports |

### D — Consistencia con Arquitectura §5 (UI Checklist)

| # | Regla Arquitectura | Verificación visual |
|---|-------------------|-------------------|
| D1 | CV-01: Headers de tabla `bg-slate-50, text-[10px], uppercase` | Revisar las 7 pantallas |
| D2 | CV-02: Badges con colores consistentes per variant | Revisar Ops, Inventory, Customs, Billing, Security |
| D3 | CV-07: Header de página con título izq + acciones der | Revisar las 7 pantallas |
| D4 | CF-01: Click en fila abre drawer (al menos en Operations) | Click en row de Operations |
| D5 | CN-02: Sidebar highlight siempre correcto | Navegar todas las rutas |
| D6 | CN-05: Drawer se cierra al cambiar módulo | Abrir drawer en Ops, navegar a Inventory |

### E — Separación de Concerns

| # | Verificación | Cómo probar |
|---|-------------|------------|
| E1 | Ningún archivo en `pages/` importa de `supabase` | `grep -r "supabase" src/pages/` → 0 results |
| E2 | Ningún archivo en `pages/` tiene `fetch`, `axios`, o llamadas de red | `grep -r "fetch\|axios" src/pages/` → 0 results |
| E3 | Ningún componente en `components/` usa `useState` (son puros) | `grep -r "useState" src/components/` → 0 results |
| E4 | Mock data NO está inline en JSX de pages | `grep -rn "\[{" src/pages/` → 0 results (arrays inline) |
| E5 | Todos los types se importan desde `@/types` | Verificar imports en pages |

### F — Build y Lint

| # | Verificación | Comando |
|---|-------------|--------|
| F1 | `npm run dev` inicia sin errores | Terminal limpia |
| F2 | `npm run build` genera dist sin errores | `npm run build` → exit 0 |
| F3 | Zero dependencias no usadas en `package.json` | `express`, `better-sqlite3`, `dotenv`, `@google/genai` eliminados |
| F4 | Alias `@/` resuelve a `src/` | Verificar en vite.config.ts y tsconfig.json |

---

## Verificación del Plan

### Cómo verificar que el refactor está completo

Dado que este refactor es puramente de reorganización de código (sin lógica nueva ni backend), la verificación es **100% visual + build**:

1. **Build test:**
   ```
   npm run build
   ```
   Debe completarse sin errores. Esto valida que TODOS los imports son correctos y que TypeScript compila.

2. **Dev server test:**
   ```
   npm run dev
   ```
   Debe iniciar sin warnings ni errores en terminal.

3. **Verificación visual manual (el usuario navega la app):**
   - Abrir `http://localhost:5173/dashboard` — verificar KPIs, gráfico, tabla, alertas
   - Navegar a `/operations` — verificar tabla, click en fila, drawer lateral se abre con timeline y fiscal validation
   - Navegar a `/inventory` — verificar tabla de lotes, gauge de rotación, alertas de stock
   - Navegar a `/customs` — verificar KPIs de saldos, tabla de pedimentos
   - Navegar a `/billing` — verificar KPIs, barra de búsqueda, tabla de CFDIs
   - Navegar a `/commercial` — verificar 4 columnas del kanban pipeline
   - Navegar a `/security` — verificar tabla de usuarios, timeline de logs
   - Navegar a `/finance` y `/reports` — verificar placeholder "Módulo en desarrollo..."
   - Probar browser back/forward
   - Probar refresh en `/customs` (debe quedarse en customs, no redirigir)
   - Probar sidebar collapse/expand

> [!NOTE]
> No hay tests automatizados en este proyecto actualmente. La verificación es exclusivamente visual y de build. Agregar testing framework está explícitamente en la **No-Go List** de este refactor.
