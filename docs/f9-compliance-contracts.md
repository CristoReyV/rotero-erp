# F9 — Contracts, Compliance & Renewals 360

## Reuse and gaps

F9 reuses F3 private `document_files`, `document_relations`, uploads and 300-second signed access; F7 rules, notifications, Attention Center, digest and its two cron jobs; F8 Customer/Provider 360, contacts, rates and lanes; F2 assignment/readiness; F5 Dashboard/Search/deep links; F6 CSV formula-injection protection; and the canonical audit log. It creates no second file, notification or task store.

The missing persistence was a configurable requirement catalog, historical partner evidence reviews, historical contracts/revisions and operation-specific provider overrides. Those are added as `partner_compliance_requirements`, `partner_compliance_records`, `partner_contracts` and `provider_compliance_overrides`. All four use RLS, no direct client privileges and Admin-only mutation RPCs.

## Business contract

- Requirements are data, never executable expressions. Generic seeded templates are visible but optional and non-blocking. Existing partners therefore remain operational after migration.
- Evidence states are `pending`, `accepted`, `rejected` and `waived`; `missing`, `pending_review`, `valid`, `expiring`, `expired`, `rejected` and `waived` are derived at read time.
- A pending record blocks only when Admin explicitly configured the requirement as required, blocking and assignment-blocking. This is the documented conservative policy.
- Waivers require actor, reason and a future `waiver_until`. They never become acceptance and expire automatically through derivation.
- Evidence replacement inserts a new record. Accepted history and the F3 binary remain unchanged.
- Contracts are draft/active/terminated/archived. Renewal creates a new active revision linked through `renewed_from_id` and archives, but does not rewrite, the prior contract.
- `rpc_get_partner_compliance_status` delegates to the single private evaluator used by Partner360, matrix, rates badges, readiness, assignment gate, dashboard and automations.

## Operation and quote policy

Only `is_required AND is_blocking AND blocks_operation_assignment` requirements can make a provider ineligible. The F9 operation trigger rejects a normal F2 assignment with safe code `provider_compliance_blocked`; reasons are available through the operational eligibility RPC. Admin may record a mandatory-reason override for exactly one operation/provider. It does not change global partner status.

F1 conversion already inserts a `planned` operation, preserves the commercial provider intention and does not set `assigned_at`. F9 intentionally permits that insert. Readiness remains false and subsequent assignment is rejected until the provider is eligible or the exact Admin override exists. Existing assigned operations are neither unassigned nor retroactively rewritten.

F8 BUY comparison remains exact on lane/service/date/currency and continues to show every matching rate. It composes evaluator badges `Vigente`, `Atención` and `Bloqueado`, including safe reasons. Commercial exploration and draft quote rate application remain warnings; the hard gate is operational assignment.

## F7 and security

F9 adds four predefined codes: `partner_document_expiring`, `partner_document_expired`, `partner_contract_expiring` and `rate_expiring`. Stable fingerprints remain `tenant + user + rule + entity`. Materialization uses the existing F7 run lifecycle, writes only Admin notifications and resolves rows when source truth disappears. The existing digest consumes the same canonical feed. Finance receives no compliance/rate rule, notification, digest, dashboard, search or Commercial route.

Fresh reset retains exactly:

- `rotero-f7-automation-hourly` — `0 * * * *`
- `rotero-f7-daily-digest` — `15 12 * * *`

No third job, HTTP, Edge or Vault dependency is added. Auth, Edge Functions, capability Tracking and public/driver RPCs are unchanged. Compliance files remain in the private F3 bucket; exports contain metadata only and never signed URLs.

## Collision and release boundary

The read-only staging scan compared identity types, input names/modes/defaults, result, `search_path`, owner and OID. F9 replaces exactly one existing identity: `public.rpc_get_operation_dispatch_readiness(uuid)` (staging OID `22358`), preserving `p_operation_id`, zero defaults and `jsonb` result. Assignment is integrated through an additive trigger, while Dashboard, Search, F7 materialization, Partner360 and Rates use additive RPCs/composition. The other scanned identities were not replaced.

Migration: `20260829000000_f9_compliance_contracts.sql`. Merge or Draft PR creation does not apply F8/F9. No staging write, `db push`, migration repair, deploy or production action is authorized.

## Manual QA after an authorized release

1. Admin opens `/commercial?view=compliance`, reviews each matrix filter and follows customer/provider deep links.
2. Configure one provider requirement as required + blocking + assignment-blocking; verify pending/missing/rejected/expired block, accepted/active waiver allow, and expired waiver blocks.
3. Upload F3 evidence, select existing evidence, review it, replace it and open both historical files through short-lived signed access.
4. Create, activate, renew and terminate a contract; verify the prior revision remains historical.
5. Compare BUY rates and confirm all exact matches remain visible with compliance badge/reason and no BUY data reaches customer/public/driver paths.
6. Attempt blocked F2 assignment as Operator; then record an Admin override with reason for that exact operation/provider and retry.
7. Evaluate automations twice; confirm no fingerprint duplicate, automatic resolution and exactly two unchanged cron jobs.
8. Verify Finance has no compliance workspace, Partner360, rates, dashboard card, search result, notification or digest item.
9. Export CSV and verify spreadsheet-leading formulas are escaped and no signed URL is present.

## F10 opportunities

- Optional responsibility queues by contact without duplicating contacts or notification storage.
- Configurable requirement packs reviewed for a specific ROTERO market or service; no legal claims without human approval.
- E-signature/legal execution only as a separately approved product and security vertical.
- Controlled metadata import for requirement catalogs after defining F6 idempotency keys; never bulk review, waive or override.
