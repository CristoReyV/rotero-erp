# F7 — Automations, escalations and daily digest

F7 reuses F5 internal_notifications, Notification Center, Attention Center,
Dashboard and deep links. It also reuses F2 operational readiness/incidents/
documents, F3 document attachment truth, F4 remaining invoice balances, F1
quote lifecycle, audit_log, memberships and the existing tenant timezone.
It does not create a second task or notification feed.

## Canonical flow and gaps closed

automation_rules stores configuration for twelve predefined rule codes; it
never stores SQL. private.f7_materialize_automation_notifications evaluates
current F1–F4 truth, expands only to eligible Admin/Finance memberships and
upserts into F5 notifications with a stable
tenant + user + rule + entity fingerprint. It changes no business state.

F7 adds minimal lifecycle metadata to each automated notification:
first_seen_at, last_seen_at, resolved_at, escalation state and safe metadata.
A condition that disappears is resolved, not deleted. Reappearance after
resolution starts a new cycle. Dismissal stays dismissed while the same cycle
remains active; a new escalation or resolved-then-active cycle makes it visible
again. Dismissal never disables its rule.

Operation staleness uses operation updates, assignment history, tracking
events, incidents, evidence, crossings and operation documents. Only planned,
assigned and in_transit are eligible, and a future operational window/departure
is excluded. POD uses only proof_of_delivery; the generic required-document
rule explicitly excludes POD.

Finance candidates use private.f4_invoice_totals, so partial payments display
only the remaining native-currency balance. Paid and void accounts resolve.
Commercial rules and metadata are materialized only for Admin users. Finance
receives only Finance plus permitted Operations/Documents notifications and
digest items.

## Scheduler and timezone

Canonical Supabase local proved CREATE EXTENSION IF NOT EXISTS pg_cron with
pg_cron 1.6.4. The migration installs it and idempotently owns exactly:

- rotero-f7-automation-hourly at 0 * * * *;
- rotero-f7-daily-digest at 15 12 * * *.

Both commands invoke owner-only functions in private; PUBLIC, anon,
authenticated and service_role cannot execute them. They iterate tenants
explicitly, use transaction advisory locks, call no HTTP/Edge/Vault contract,
and never depend on auth.uid().

Digest identity is tenant + user + tenant-local business date. The existing
tenant_settings.timezone is authoritative, with America/Mexico_City only as the
established fallback. A repeated run updates the same digest.

The code and cron contract are release-pending until the F3–F7 migrations are
applied through the controlled database release. This PR does not write
staging, push migrations, activate remote cron, deploy Netlify or merge.

The verified local forward order is:

1. 20260821235959_f2_touch_updated_at_compat
2. 20260822000000_f2_operation_360
3. 20260823000000_f3_documents_360
4. 20260824000000_f4_finance_360
5. 20260825000000_f5_executive_productivity
6. 20260826000000_f6_data_operations
7. 20260827000000_f7_automations

## Security, audit and lifecycle

User-facing RPCs are authenticated-only, validate current tenant membership
and role, use safe search paths and never return raw database errors. Admin can
configure rules, inspect health and run the whole tenant manually. Finance
cannot configure, inspect global health or run a tenant-wide evaluation; the
existing F5 refresh only updates that Finance user's role-safe notification
projection.

Rule changes, manual evaluation, digest evaluation and non-zero escalation
summaries reuse audit_log. Hourly no-op evaluations do not generate audit
noise. automation_runs stores only counts, timestamps, status, safe summary and
a stable error code.

Snooze is intentionally deferred. Adding custom time controls would broaden
the notification lifecycle; F7 prioritizes deterministic resolution,
dismissal-loop protection and escalation.

External delivery adapters (email, WhatsApp and SMS) are deferred. The daily
digest is internal ERP data only.

## Manual QA after a controlled release

1. As Admin, open **Administración → Automatizaciones**, verify twelve rules,
   edit a threshold, save, and confirm the audit entry.
2. Select **Evaluar ahora** and verify counts plus the latest successful run.
3. Create/fix one Operations, Commercial, Finance and document condition;
   confirm one notification per user/rule/entity and automatic resolution.
4. Dismiss an alert, re-evaluate without changing state, and confirm it stays
   dismissed; advance its escalation/state and confirm the defined redisplay.
5. Verify Finance has no Commercial rule, route, alert, metadata or digest
   item.
6. Verify **Resumen del día** uses the tenant date and real notification totals.
7. Read the two cron jobs and recent automation_runs; do not invoke network
   adapters or change Auth/Edge/Tracking.
