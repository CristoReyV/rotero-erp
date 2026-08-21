# F5 — Executive Control + Productivity

## Gap map

Verified reusable sources were F1 quote lifecycle, F2 incidents/readiness/POD/billing readiness, F3 document ACL and file relations, F4 invoice balances/due alerts/payments, and `audit_log`. The legacy Dashboard RPCs only provided a small operations/fiscal shape; the page added fabricated OTIF/trends. The shell contained static notifications and an Operations-only search. The canonical reset had no executable notification, notification-rule or saved-view contracts despite historical no-op migration markers.

F5 therefore adds only these genuine persistence gaps:

- `internal_notifications` and `internal_notification_rules`, preserving their historical canonical names;
- `user_saved_views`, owned by tenant + user.

The Attention Center remains derived from F1–F4 state and does not create a task mirror.

## Product contract

- `rpc_get_executive_dashboard` returns real Operations, Commercial, Finance and Documents sections plus attention and normalized activity.
- Finance receives only Finance and permitted Operations/Documents context. Commercial sections, activity, notifications, saved views and search groups are filtered before return.
- `rpc_list_attention_items` derives blockers, missing POD/documents, billing blockers, due/overdue AR/AP and Admin-only Commercial follow-up.
- Notification refresh uses stable fingerprints and a unique tenant/user/fingerprint boundary.
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

Merge does not apply migrations. F5 performed no staging write, migration push, repair, Auth/Edge change or deploy.

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
