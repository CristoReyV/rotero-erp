# BH1 — Integration hardening

## Runtime inventory

The canonical reset contains 66 public tables, 233 public `rpc_*` identities and 60 private helpers. The frontend has 21 routed pages, 22 domain service modules and 147 distinct active Supabase RPC names.

| Product area | Route | Main services | Cross-module truth |
|---|---|---|---|
| F1 Commercial | `/commercial` (Admin) | `commercial`, `rates` | customer/provider, quote lifecycle and approved economics |
| F2 Operations | `/operations` | `operations` | assignment/readiness, incidents, POD and operation economics |
| F3 Documents | `/documents` | `documents` | private bucket, tenant path, relations and 300 s signed URL |
| F4 Finance | `/finance`, `/billing` | `finance`, `billing` | explicit AR/AP, payments, credit and per-currency balances |
| F5 Productivity | `/dashboard` | `executive` | attention, search, notifications, digest and saved views |
| F6 Data Operations | `/data` (Admin) | `dataOperations` | tenant external keys, idempotent chunks and safe CSV |
| F7 Automations | `/security/automations` (Admin) | `automation` | one materializer; hourly and daily jobs only |
| F8 Rates/Partner360 | `/commercial?view=rates` | `rates` | exact match, immutable snapshots and partner dossiers |
| F9 Compliance | `/commercial?view=compliance` | `compliance` | one derived eligibility truth shared by assignment/readiness |
| F10 Claims | `/claims` (Admin) | `claims` | separate incident/claim lifecycle and operational exposure |

Finance remains limited to Dashboard, read-only Operations, contextual Documents, Billing/Finance and Reports. Commercial, Rates, Partner360, Compliance, Contracts, Claims, Inventory, Customs, Tracking administration and Security remain Admin-only.

## Findings and fixes

Triage: **P0 1 / P1 5 / P2 4 / P3 2**.

- **P0 fixed — executable stale mutations.** Staging had active Commercial note/checklist and Customs descargo mutations plus old overloads with default PUBLIC execution, mutable search paths and raw `SQLERRM`. BH1 makes active ACLs authenticated-only, revokes obsolete overloads from every API role, sets safe paths and returns stable safe codes.
- **P1 fixed — staging schema/RPC drift.** Seven active F1/F6 RPCs referenced canonical `contact_*` fields while staging retained `primary_contact_*`. A non-destructive compatibility surface backfills existing values and restores list/upsert/quote/import/export without changing identities.
- **P1 fixed — ten additional linted functions.** Invitation crypto is extension-qualified; descargo ordering no longer requires a staging-only sequence; notes/checklists tolerate both historical shapes; demo settings uses `tenant_id`; stale dashboard overloads use real columns and no fabricated chart; the obsolete assignment overload no longer emits database text.
- **P1 fixed — Partner360 actions.** New Quote/BUY Rate/AR/AP links now carry actions and exact customer/provider context. Quote, Rate and Finance consumers apply those parameters; Finance sends canonical counterpart IDs and payment-term due dates.
- **P1 fixed — dead Finance links.** Finance opens Operations by `operationId` and Billing by `cfdiId`; Billing consumes, preserves and clears that selected-record URL state.
- **P1 fixed — Incident → Claim navigation.** Route context is passed explicitly to the Claims mutation and the form visibly preselects operation/customer/provider. The service no longer reads `window.location`; the backend remains the authority and preserves the incident.
- **P2 fixed — bundle.** Route-level native React lazy loading removes the >500 kB warning and isolates heavy workspaces without a dependency.
- **P2 fixed — permanent frontend/RPC gate.** A static contract resolves all 147 active frontend RPC names to migration definitions and locks the corrected deep-link producer/consumer pairs.
- **P2 fixed — integrated invariant harness.** `bh1_cross_module_invariants.sql` covers tenant isolation, Claims/Finance separation, Partner360 source agreement, Finance payload isolation, cron and Tracking boundaries.
- **P2 fixed — canonical reset compatibility.** The migration branches only where staging table shapes differ; the clean canonical reset remains valid and all existing tests pass.

Deferred:

- **P2:** Partner360 detail RPCs aggregate unbounded operation/rate histories. Split summary and paginated detail in BH2; changing the response now would break current consumers.
- **P2:** consolidate legacy `contact_*`, historical `primary_contact_*` and F8 structured contacts after a reviewed data migration. BH1 restores correctness without destructive convergence.
- **P3:** standardize compact page source formatting and generic service error helpers; no user-visible correctness benefit justifies churn here.
- **P3:** tune presentation-level empty-state copy after beta feedback.

## Cross-module audit

- Quote/rate/operation exact currency, immutable BUY/SELL snapshots, no fake FX and quote lifecycle remain covered by F1/F2/F8 suites.
- Selective Quote→Operation document transfer, private relations, canonical POD and orphan compensation remain covered by F3 and F2/F3 integration contracts.
- F9 assignment/readiness/override use the same derived compliance helper; seeded requirements do not retroactively block partners.
- Operation Finance handoff remains explicit, locked and per-currency. Claims exposure and settlement do not create AR/AP/payment rows.
- Incident and Claim stay separate; linking a claim preserves incident status and carries operation/customer/provider context.
- Customer360/Provider360 obtain Claims through the canonical F10 partner endpoint; Finance cannot call either dossier.
- F7 evaluation remains idempotent with exactly `0 * * * *` and `15 12 * * *`; Finance payloads exclude Commercial/Compliance/Claims.
- Saved Views remain tenant+user scoped. Invalid modules are backend-denied; Claims uses its dedicated Admin-only RPCs. URL enums fall back safely.
- Money totals remain grouped by MXN/USD. No FX engine or mixed-currency total was introduced. Business-date semantics remain unchanged; expiry/rate/cron timezone redesign is deferred because it requires a product decision.
- All document consumers remain on F3 private metadata/relations and short-lived signed URLs. Legacy operation evidence URLs were not expanded or exposed.
- CSV exports for newer modules use `serializeCsv`; formula injection remains covered by the shared CSV test.

## DB lint classification

Staging remains at 17 errors until BH1 is released. The canonical reset with BH1 has zero error-level findings.

| # | Object | Finding / origin | Reachability and risk | BH1 action |
|---:|---|---|---|---|
| 1 | `rpc_export_data_page` | F6 uses missing customer `contact_name` | Active export; P1 | compatibility columns |
| 2 | `rpc_apply_bulk_import` | F6 inserts missing customer field | Active import; P1 | compatibility columns |
| 3 | `rpc_list_descargo_lines` | legacy `sequence_no` absent | Active Customs; P1 | deterministic non-destructive sequence bridge |
| 4 | `rpc_create_invitation` | unqualified `gen_random_bytes` | Active Admin; P1 | canonical extension-qualified implementation |
| 5 | `rpc_dashboard_recent_activity` | obsolete overload uses removed operation fields | Legacy overload; P2 | corrected and API roles revoked |
| 6 | `rpc_add_deal_note` | audit UUID receives text | Active Commercial mutation; P1/security | UUID audit + safe ACL/path |
| 7 | `rpc_list_deal_notes` | `author_id`/`author_user_id` drift | Active Commercial; P1 | shape-safe author lookup |
| 8 | `rpc_demo_configure_module` | settings uses missing `id` | Active Inventory/Customs setup; P1 | `tenant_id`, safe result/path |
| 9 | `rpc_assign_operation` | obsolete overload audit type/raw error | Unused; v3 is active; P0 | safe body, no SQLERRM, all API roles revoked |
| 10 | `rpc_toggle_deal_checklist_item` | audit UUID receives text | Active Commercial mutation; P1/security | UUID audit + authenticated-only ACL |
| 11 | `rpc_list_deal_checklist` | `created_at`/`updated_at` drift | Active Commercial; P1 | shape-safe timestamp |
| 12 | `rpc_dashboard_overview` | obsolete overload uses fake `quantity` KPI | Unused/revoked; P2 | real columns, empty chart |
| 13 | `rpc_upsert_quote` | customer contact record mismatch | Active Quote; P1 | compatibility columns |
| 14 | `rpc_list_providers` | provider contact field mismatch | Active Commercial; P1 | compatibility columns |
| 15 | `rpc_list_customers` | customer contact field mismatch | Active Commercial; P1 | compatibility columns |
| 16 | `rpc_upsert_customer` | customer contact field mismatch | Active Commercial; P1 | compatibility columns |
| 17 | `rpc_upsert_provider` | provider contact field mismatch | Active Commercial; P1 | compatibility columns |

Expected after release: **17 fixed / 0 remaining error-level lint findings**. This expectation is validated on the canonical reset, not claimed as staging state before push.

## Advisor and query classification

Read-only staging advisor groups (pre-BH1):

| Group | Count | Classification / action |
|---|---:|---|
| authenticated SECURITY DEFINER executable | 333 WARN | mixed intentional RPC-first and inherited helpers; active touched RPCs checked individually, no mechanical conversion |
| anon SECURITY DEFINER executable | 70 WARN | inherited/capability mix; SEC.4 excluded, defer full allowlist reconciliation |
| mutable function search path | 44 WARN | inherited; touched functions fixed, broad remediation deferred |
| RPC-only RLS without policies | 7 INFO | intentional table-deny/RPC-only model |
| leaked-password protection | 1 WARN | Auth/SEC.4 boundary; deferred |
| multiple permissive policies | 76 WARN | inherited policy architecture; no BH1 mutation |
| auth RLS initplan | 55 WARN | inherited performance debt; batch by policy family in BH2 |
| duplicate index | 1 WARN | inspect with workload before removal; no destructive cleanup |
| unindexed foreign keys | 133 INFO | broad inherited set; no index added without a demonstrated hot query |
| unused indexes | 119 INFO | staging usage is not sufficient evidence for deletion |

Hot-path review found tenant predicates and purpose-built indexes in current F2–F10 list functions. No safe new index had enough workload evidence. The obvious payload risk is the unbounded Partner360 dossier, deferred above.

## Bundle and validation

- Before: initial application chunk **1,025.90 kB / 277.48 kB gzip**, warning present.
- After: initial application chunk **360.98 kB / 114.61 kB gzip**; largest routed workspace is Tracking Public **167.48 kB / 48.70 kB gzip**; warning removed.
- Fresh reset order: baseline → F1 → compat → F2 → F3 → F4 → F5 → F6 → F7 → F8 → F9 → F10 → BH1.
- Required manual QA after release: Partner360 new Quote/Rate/AR/AP, Finance→Operation/Billing, Incident→Claim form context, one customer/provider contact created on the historical staging shape, and first-load navigation for lazy routes.

## Release note

BH1 is one new additive migration: `20260831000000_bh1_integration_hardening`. No staging write, deployment, Auth, Edge, Tracking implementation, key, production or SEC.4 change is part of this PR.
