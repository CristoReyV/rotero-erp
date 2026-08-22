# F6 — Data Operations 360

## Gap map

F6 reuses the canonical F1 customer/provider contracts, F2 broker-first operation planning, F3 document visibility, F4 Finance balances/exports, F5 URL-state/productivity patterns, and `audit_log`. Before F6, CSV support was export-only, did not neutralize spreadsheet formulas, and there was no durable import identity, chunk idempotency, saved mapping, import history, server preview/apply boundary, or shared bulk-selection pattern.

F6 adds only the missing persistence contracts:

- nullable `external_key` identities for customers, logistics providers and operations, unique per tenant when present;
- `data_import_batches`, `data_import_chunks` and user-owned `data_import_mappings`;
- authenticated RPCs for preview, confirmed apply, history, mapping CRUD, paginated export, safe operation bulk updates and action audit.

Quotes are intentionally excluded from import because their approval/conversion lifecycle requires explicit commercial actions. They remain available for Admin export with customer-safe fields.

## Import contract

- Admin-only workspace and server enforcement.
- CSV UTF-8 with BOM support, comma/semicolon detection, quoted fields, escaped quotes, CRLF/LF and Unicode.
- Maximum file: 2 MB and 1,000 data rows. Validation/apply chunks: 200 rows.
- Seven stages: entity, file, mapping, server validation, preview, explicit confirmation and result.
- Preview does not write. The batch begins only after the confirmation checkbox.
- Stable file SHA-256 + entity + mode idempotency, transaction advisory lock and unique batch/chunk keys.
- Customer/provider identity order: external key, RFC, exact display name. Ambiguous matches are errors.
- Operation import requires `external_key`, a tenant-resolved customer, complete route/window/cargo and valid currency. It always writes `planned` + `third_party`; advanced statuses, own-fleet assumptions and lifecycle transitions are rejected.
- Existing operations past Draft/Planned are skipped instead of overwritten.
- Validation returns row-level Spanish errors/warnings. Error CSV and error-only retry are available.

The server does not persist the CSV body or normalized contact, route, cargo, economics or notes. Durable chunk responses retain row/result identity and counts only. Audit metadata contains entity/mode/counts, never row payloads.

## Export and bulk actions

Exports use keyset pagination in pages of 500 and stop at 5,000 synchronous rows. Filters are tenant-scoped. Document export applies the F3 module ACL. Finance may export only Operations/Documents/AR/AP; it cannot export Commercial data.

CSV cells beginning with `=`, `+`, `-` or `@` (after optional whitespace) are prefixed with an apostrophe before quoting to prevent spreadsheet-formula execution.

- Operations: Admin may export selected rows, set `low|normal|high` priority or append a bounded note through one audited RPC. No status transition is available in bulk.
- Documents: selected metadata export only; no binary URL, signed URL or lifecycle mutation.
- Finance: selected AR/AP export and currency-separated balance summary only.
- Commercial: selected quote export contains customer-safe price/service/route data and excludes provider cost and margin.

## Security and release boundary

All normal F6 ERP RPCs are `SECURITY DEFINER` with `search_path=pg_catalog, public`. Execution is authenticated-only; PUBLIC, anon and service-role execution is revoked. Import/history/mapping/bulk-write RPCs enforce Admin. Tables have RLS and no direct client DML privileges. No Auth, Edge, Tracking, Storage policy, key or fiscal execution contract changes are included.

Fresh local migration order after F5 is:

1. `20260821235959_f2_touch_updated_at_compat`
2. `20260822000000_f2_operation_360`
3. `20260823000000_f3_documents_360`
4. `20260824000000_f4_finance_360`
5. `20260825000000_f5_executive_productivity`
6. `20260826000000_f6_data_operations`

Merge does not apply migrations. No staging write, migration push/repair, Netlify deploy or production action is part of F6.

## Manual QA checklist

- Admin: download each template; import Unicode customers/providers; import a valid operation; verify preview makes no write and confirmation creates Planned/third-party data.
- Validate duplicate external keys, invalid RFC/email/currency/date/numeric fields, ambiguous relations, cross-tenant relation attempts, advanced operation status and own-fleet input.
- Repeat the same confirmed chunk and verify one durable result and no duplicate row.
- Save/apply/delete mappings with two Admin users and verify owner isolation.
- Export each dataset with search/status/date filters; verify the 5,000-row boundary and formula neutralization in Excel/Sheets.
- Finance: verify Operations/Documents/AR/AP exports work while Customers/Providers/Quotes/Data workspace stay unavailable.
- Select rows in Operations, Documents, AR/AP and Quotes; verify only the documented actions appear and audit records contain counts only.
- Confirm customer-safe quote CSV contains no provider cost or margin.

## F7 opportunities

- asynchronous large-file jobs and object-storage handoff for imports/exports beyond synchronous limits;
- configurable import schemas/versioned mapping transformations;
- approval workflows for sensitive economic bulk changes;
- background duplicate-candidate review and merge tools;
- scheduled exports and integration connectors after an explicit keys/Edge/security release.
