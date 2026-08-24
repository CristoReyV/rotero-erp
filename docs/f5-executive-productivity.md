# F5 — Executive Control + Productivity

## Gap map

Verified reusable sources were F1 quote lifecycle, F2 incidents/readiness/POD/billing readiness, F3 document ACL and file relations, F4 invoice balances/due alerts/payments, and `audit_log`. The legacy Dashboard RPCs only provided a small operations/fiscal shape; the page added fabricated OTIF/trends. The shell contained static notifications and an Operations-only search. Staging also retains the executable Tanda8 notification model even though its repository marker is a no-op, so F5 must reconcile with that catalog instead of assuming an empty schema.

F5 therefore adds only these genuine persistence gaps:

- `priority` on historical rules and `due_at` on historical notifications;
- `user_saved_views`, owned by tenant + user.

The Attention Center remains derived from F1–F4 state and does not create a task mirror.

## Product contract

- `rpc_get_executive_dashboard` returns real Operations, Commercial, Finance and Documents sections plus attention and normalized activity.
- Finance receives only Finance and permitted Operations/Documents context. Commercial sections, activity, notifications, saved views and search groups are filtered before return.
- `rpc_list_attention_items` derives blockers, missing POD/documents, billing blockers, due/overdue AR/AP and Admin-only Commercial follow-up.
- Notification refresh uses stable fingerprints and a unique tenant/user/fingerprint boundary.
- Database storage remains canonical Tanda8 (`target_role/area/trigger_type/is_enabled`, `related_entity_*`, `status`, `first_seen_at/last_seen_at`). F5-compatible `module/kind/entity_type/entity_id/created_at` names are normalized only in RPC JSON.
- `rpc_global_search` is tenant-scoped, requires two characters, limits each result group and returns actionable routes.
- Saved-view CRUD enforces owner, tenant and module authorization in every RPC.
- All normal F5 ERP RPCs are authenticated-only `SECURITY DEFINER` functions with `search_path=pg_catalog, public`; PUBLIC, anon and service-role execution is revoked.

## Migration and release boundary

Fresh local order is:

1. `20260821235959_f2_touch_updated_at_compat`
2. `20260822000000_f2_operation_360`
3. `20260823000000_f3_documents_360`
4. `20260824000000_f4_finance_360`
5. `20260825000000_f5_executive_productivity`
6. `20260826000000_f6_data_operations`
7. `20260827000000_f7_automations`

The release gate includes a staging-like pre-F5 fixture with 40 historical rules, 21 historical notifications, all legacy roles/triggers/areas, text entity identifiers, legacy RPC overloads, two consecutive F5 applications and preservation checks.

## Dependency reconciliation matrix

| Dependency | Original local assumption | Verified staging reality | Reconciled result |
|---|---|---|---|
| Rule identity | `role/module/kind/enabled` and alias uniqueness | `target_role/area/trigger_type/is_enabled`, expression uniqueness with nullable area | Native canonical fields; existence-based idempotent seed; operator/viewer retained |
| Rule checks | Admin/Finance and F5 kinds only | Four historical roles, nullable eight-area catalog, six legacy triggers | Checks are the union of legacy and F5 values; only conservative `priority` is added |
| Notification identity | UUID `entity_id`, alias timestamps | text `related_entity_id`, canonical first/last seen | Text is preserved; API aliases exist only at the RPC boundary |
| Lifecycle | nullable read/dismiss timestamps only | `unread/read/dismissed` plus timestamps | Read and dismiss update canonical status and remain user scoped |
| Refresh/upsert | alias columns and `created_at` ordering | unique tenant/user/fingerprint and `last_seen_at` feed | Stable upsert preserves `first_seen_at`, advances `last_seen_at`, excludes dismissed |
| Indexes | alias-column feed/rule indexes | canonical role and status feed indexes already exist | Equivalent indexes are reused; only canonical partial unread-priority index is additive |
| Tanda8 RPCs | F5 signatures considered exclusive | `(uuid,jsonb)` list and one-argument dismiss remain consumed | Existing overloads are preserved; F5 overloads normalize legacy and new rows |
| F6/F7 | F7 consumed F5 alias columns | F6 does not consume notifications; F7 is pending | F6 unchanged; pending F7 maps automation writes/reads to canonical columns and extends trigger checks |

Merge alone does not apply migrations. No migration repair, Auth/Edge change or production action is part of F5.

## Manual QA checklist

- Admin: switch every Dashboard date range, open every KPI/attention/activity deep link and confirm Commercial is present.
- Finance: confirm Commercial never appears in Dashboard, bell, activity, search, palette or saved views.
- Open Operations incident, document/POD and economics deep links and confirm the requested Operation 360 tab.
- Open Commercial deal/quote, Finance invoice and Documents file/entity links.
- Use Ctrl/Cmd+K, arrows, Enter and Escape; run Admin and Finance action sets.
- Refresh notifications twice; mark one/all read, dismiss one, navigate/focus and confirm no duplicate.
- Save, apply, rename, set default and delete a view in Operations, Commercial, Documents and Finance.

## F6 opportunities

- server-scheduled notification materialization for tenants that need alerts without an active ERP session;
- configurable notification windows/escalations and digest delivery;
- indexed search vectors if production volume outgrows bounded tenant searches;
- shared URL-state adapters for remaining non-F5 modules.
