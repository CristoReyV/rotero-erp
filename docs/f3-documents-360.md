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
