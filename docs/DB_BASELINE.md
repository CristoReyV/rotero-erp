# Baseline canónico de base de datos

## Estado y propósito

DB.0A confirmó que la línea anterior de 33 migraciones no podía reconstruir una base vacía. Dependía de tablas fundacionales ausentes, incluía timestamps cortos y versiones duplicadas, y fallaba antes de crear el esquema requerido.

DB.0B separa dos conceptos:

- `supabase/migrations_legacy/`: evidencia histórica preservada; no es ejecutable ni canónica.
- `supabase/migrations/`: línea activa reproducible, formada por un baseline revisado y markers de historia remota.

Este trabajo no alinea staging y no autoriza `migration repair`, `db push` ni aplicaciones remotas.

## Inventario canónico revisado

| Objeto o familia | Clase | Decisión DB.0B |
| --- | --- | --- |
| `tenants`, `memberships` | A. Canónico seguro | Límite multi-tenant, cuatro roles ERP y unicidad usuario/tenant. |
| `customers`, `logistics_providers`, `service_catalog_items` | A. Canónico seguro | Catálogos broker-first con aislamiento por tenant. |
| `operations` | B. Canónico corregido | Contrato broker-first consolidado; FKs circulares se agregan después de crear tablas. `third_party` sigue siendo el default. |
| `crm_deals` y auxiliares | B. Canónico corregido | Contrato comercial mínimo y conversión enlazada a operación. |
| `drivers`, `vehicles` | A. Canónico seguro | Catálogos opcionales; permiten proveedor contratado y no son obligatorios para `third_party`. |
| `tracking_tokens`, `tracking_events`, `tracking_route_points`, `tracking_access_log` | B. Canónico corregido | Constraints e índices consolidados; tablas sin acceso directo y RPCs separados por superficie ERP/Edge. |
| `billing_cfdis`, `billing_carta_porte` | B. Canónico corregido | Workbench ERP local, sin SAT/PAC productivo. |
| `operation_billing`, `finance_invoices`, `finance_payments` | A. Canónico seguro | Control administrativo y financiero básico, sin timbrado ni pagos externos. |
| `audit_log`, `invitations`, `tenant_settings` | B. Canónico corregido | Sin datos iniciales; invitaciones no escriben en `auth.users` desde SQL canónico. |
| `inventory_lots`, `customs_*` | A. Canónico seguro | Catálogos mínimos preservados porque hay consumidores actuales. |
| helpers RBAC | B. Canónico corregido | `SECURITY DEFINER`, autorización interna y `search_path` explícito. |
| RPC de identidad, operaciones y tracking | B. Canónico corregido | Contratos mínimos para consumidores verificados y compatibilidad pre-M4.1. |
| triggers, constraints, índices, RLS y grants | A/B | Definiciones deterministas y grants RPC-first explícitos. |
| `public.users` | C. Legacy excluido | La vista remota exponía el catálogo global de `auth.users`; no se crea. |
| RPC legacy que crea o modifica `auth.users` | C. Legacy excluido | Auth permanece bajo Supabase Auth; no se canoniza SQL de provisión manual. |
| fiscal/PAC avanzado (`billing_api_*`, documents fiscales, complementos, notas de crédito, catálogos SAT) | D. No determinable | Los cuerpos remotos no se recuperaron y no se simulan. Requieren contrato separado antes de entrar. |
| nómina, plantillas documentales, storage, notificaciones y control center DB de versiones remotas no recuperadas | D. No determinable | No se recrean a partir de nombres de versión. |
| RPC secundarios de dashboard, reportes, CRM avanzado, inventario, aduanas y finanzas | D. No determinable | Las implementaciones legacy se conservan como evidencia, pero requieren reconciliación contractual en DB.0C. |

Clases: A = canónico seguro; B = canónico con corrección necesaria; C = legacy excluido; D = contrato no determinable con evidencia actual.

## Decisión sobre `public.users`

No existe consumidor directo de `public.users` en `src`. Los únicos consumidores locales encontrados estaban dentro de SQL legacy. La UI administrativa usa `rpc_list_members`; el baseline implementa ese RPC con estas garantías:

- exige membresía `admin` u `operator` en el tenant solicitado;
- une `memberships` con `auth.users` únicamente dentro de un `SECURITY DEFINER` autorizado;
- devuelve sólo `user_id`, rol, fecha, email y nombre de miembros del tenant;
- no concede `SELECT` sobre `auth.users` ni crea una vista global.

`rpc_get_my_context` sólo consulta la fila de `auth.users` correspondiente a `auth.uid()`. No existe grant directo para `anon` o `service_role` sobre estos RPC ERP.

## Seguridad canónica

Los helpers `tanda1_user_is_member` y `tanda1_user_has_role`, y todos los RPC `SECURITY DEFINER`, usan un `search_path` que inicia en `pg_catalog, public`; los contratos criptográficos agregan `extensions` al final. Todos los objetos se referencian con schema.

La arquitectura es RPC-first:

- `anon`, `authenticated` y `service_role` no reciben DML directo sobre tablas `public`;
- `authenticated` ejecuta únicamente RPC ERP con autorización interna;
- `service_role` ejecuta los tres contratos de tracking usados por Edge Functions y los helpers privados de validación/hash;
- `anon` no ejecuta RPC internos ni de tracking directamente;
- RLS permanece habilitado como defensa adicional y sus policies reflejan aislamiento tenant y roles;
- ninguna respuesta pública devuelve `SQLERRM`, hashes de token o secretos.

El baseline conserva las firmas pre-M4.1 de creación de token de tres y cinco argumentos, sin defaults ambiguos. PR #10 puede reemplazarlas y agregar wrappers de cuatro argumentos.

## Historia remota representada

Los 17 archivos posteriores al baseline son markers intencionalmente no-op. Conservan versión y nombre registrados remotamente, declaran que no se recuperó el cuerpo original y no pretenden reproducirlo. Los efectos revisados y aprobados que pertenecen al alcance DB.0B se consolidaron en el baseline; un nombre de versión por sí solo no autoriza a inventar objetos faltantes.

No se crearon markers para migraciones locales nunca registradas remotamente.

## Crear una base local nueva

Requisitos: Docker y Supabase CLI. Desde la raíz del repositorio:

```powershell
npx --yes supabase@latest start
npx --yes supabase@latest db reset --local --no-seed
```

El reset debe aplicar primero `20260223000000_canonical_baseline.sql`, registrar después los 17 markers y omitir por completo `migrations_legacy`.

## Pruebas contractuales

Ejecutar el test dentro del contenedor local con parada ante el primer error:

```powershell
Get-Content supabase/tests/db_baseline_contract.sql -Raw |
  docker exec -i <LOCAL_DB_CONTAINER> psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres
```

El test usa `BEGIN/ROLLBACK`, genera únicamente fixtures sintéticos y valida catálogo, constraints, índices, RLS, policies, grants, firmas, `SECURITY DEFINER`, `search_path`, roles e aislamiento. No imprime literales ni hashes de token.

## Fingerprint sanitizado

```powershell
./scripts/db-schema-fingerprint.ps1 -OutputPath <SANITIZED_OUTPUT_PATH>
```

Para comparar contra otro snapshot schema-only sanitizado:

```powershell
./scripts/db-schema-fingerprint.ps1 -ExpectedPath <EXPECTED_PATH>
```

El fingerprint incluye sólo catálogo `public`: tablas, columnas, tipos, constraints, índices, RLS, policies, firmas/configuración de funciones, grants y triggers. Excluye filas, owners, UUID, emails, tokens, hashes y secretos.

## Compatibilidad con PR #10

La migración de PR #10 no forma parte de esta rama. La validación autorizada consiste en extraer su SQL y test a un directorio temporal fuera del repositorio, aplicarlos después del baseline y markers, y destruir el entorno local. El orden futuro esperado es:

1. revisar y aprobar DB.0B;
2. decidir en DB.0C cómo reconciliar staging sin inventar historia;
3. rebasar o recrear PR #10 sobre la línea canónica;
4. repetir reset, test de baseline y test M4.1;
5. sólo con autorización separada diseñar el rollout remoto.

## Staging, repair y rollback

Staging conserva su historia actual. No debe ejecutarse `migration repair`, modificar `schema_migrations` ni marcar versiones hasta comparar el fingerprint canónico, revisar los objetos D y aprobar un mapa explícito de equivalencias.

Rollback local de DB.0B: descartar la rama sin mergear y detener Supabase local. El legado permanece intacto en Git. Un rollback remoto no aplica porque DB.0B no escribe en servicios remotos.

## Riesgos y DB.0C

- Los cuerpos originales de 17 versiones remotas siguen sin recuperarse.
- Los módulos fiscal/PAC, documentos, nómina, notificaciones y reporting avanzado no están canonizados.
- Varios RPC secundarios del frontend siguen siendo deuda contractual; el baseline no inventa implementaciones a partir de código legacy contradictorio.
- La línea canónica y staging aún no tienen equivalencia demostrada.
- PR #10 debe mantenerse draft hasta confirmar su nueva base y repetir el harness.

DB.0C debe producir un catálogo esperado firmado/revisado, mapear cada objeto remoto a A/B/C/D, resolver RPC secundarios por consumidor, definir estrategia de alineación sin `repair` prematuro y preparar un rollout reversible con respaldo y dry-run.
