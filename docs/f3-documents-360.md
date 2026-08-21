# F3 — Documents 360

## Gap map verified before implementation

| Area | Reused contract | Gap closed in F3 |
| --- | --- | --- |
| Files | `document_files`, `document_relations` and the historical document RPC names | Local migrations contained only release markers, so F3 makes the canonical contracts reproducible, validates entity tenancy and exposes cursor/filter support. |
| Storage | Private `tenant-documents` bucket | Tight module-aware Storage RLS, tenant-safe UUID paths, bucket-derived upload contract, real-object validation and orphan compensation. |
| Operation | `operation_documents` and Operation 360 | Real file upload/selection, canonical requirement attachment, POD resolution and evidence referencing a registered document ID. |
| Commercial | F1 quote/customer/provider entities | Entity panels and an explicit quote-to-operation relation for files marked `operationally_relevant`. Source relations are preserved; no other commercial file transfers silently. |
| Generated | Templates, versions, snapshots and generation lifecycle | Generated workspace, operation/commercial source selection, immutable snapshots, preview/print/cancel and customer-safe commercial generation. |
| Notifications | No reproducible local notification rule contract for these events | Deferred to F5. F3 emits audit events through the existing audit writer and preserves the missing-document/POD summary as the future rule input. |

## Canonical lifecycle and access

- File statuses remain `active`, `superseded` and `cancelled`; physical deletion is not a user action.
- “Pendientes” represents superseded files needing review because the canonical model has no `pending` state.
- Admin has tenant-wide access. Finance is limited to billing, finance and permitted operation context; it cannot read commercial-only files.
- Operator/viewer behavior remains module-scoped, with viewer read-only.
- External tracking and driver capability routes do not receive document access.
- Signed URLs expire after 300 seconds and are never persisted.

## Deferred

- Rich template/WYSIWYG editing.
- Rules-based missing-document and POD notifications (F5).
- Office uploads until the canonical bucket MIME allow-list permits them.
- Public/external document capabilities; these require a separately designed token contract.

## Special rollout rule for the compatibility bridge

Staging already has F2 applied, while `20260821235959_f2_touch_updated_at_compat.sql` is intentionally ordered immediately before F2 so a fresh canonical reset can create `public.tanda1_touch_updated_at()` before F2 reconciles its triggers. The bridge is conditional and is a no-op when that helper already exists.

For the future F3 database release, first run the linked migration list and then the dry-run below:

```powershell
supabase migration list --linked
supabase db push --linked --dry-run --include-all --skip-vault
```

The exact expected pending set is:

1. `20260821235959_f2_touch_updated_at_compat.sql`
2. `20260823000000_f3_documents_360.sql`

Abort if any other migration appears. `--include-all` is required only because this intentional compatibility bridge is older than F2, which is already recorded on staging. Do not use migration repair. Merging F3 does not authorize or execute this database release.

Local database advisors retain pre-existing performance warnings for the baseline `memberships_select_own` policy and overlapping read/manage policies on F1 or historical catalog tables. The F3 document and Storage objects add no advisor finding; those inherited warnings are outside this release scope.
