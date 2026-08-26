# BH2 — Daily-use UX & data hardening

BH2 is beta hardening, not a product vertical. It keeps Auth, Edge, Tracking capabilities, Fiscal API and deployments unchanged.

## Pagination contracts

Partner360 summary RPCs return the partner, primary/all contacts, server-side totals, per-currency aggregates and no full history arrays. `rpc_list_partner_history_page` serves quotes, operations, rates, activity, compliance, contracts and claims in pages of 25 (maximum 100). Every page is ordered by immutable `timestamp DESC, id DESC`; its cursor is scoped to tenant, partner type/id and history type. Invalid or cross-tenant cursors fail closed. List rows contain summaries only.

The UI starts on the first page and uses explicit **Cargar más**. It de-duplicates notification continuation rows, preserves Partner360's active tab in `partnerTab`, and resets history when the selected partner changes. F3 Documents retains its existing keyset pagination and signs a private URL only on explicit open/download. F6 export continues requesting every filtered server page up to its existing 5,000-row safety cap, so UI pagination never truncates CSV output. Saved Views keep filters/sort but no cursor.

Other audited surfaces:

- Notifications now use a user-scoped keyset page and explicit continuation.
- Automation Health already retrieves only the last automation/digest run; no new cron or history materializer was needed.
- Partner Claims, Compliance records and Contracts use the shared Partner360 continuation contract.
- F10 claim detail events, F8 rate-version detail and generated-document lists remain bounded by their current detail/list contracts; a dedicated archive viewer is deferred until beta volume proves it necessary.
- Operations, Quotes, Customers, Providers, Rates, Finance and Claims top-level directory pagination is deferred because changing their established response shapes needs a separate consumer migration. BH2 removes the known Partner360 payload hotspot without mixing paging schemes.

## Contact convergence

Read precedence is deterministic:

1. active structured `business_contacts`, with the marked primary first;
2. canonical `contact_*` projection when no structured contact exists;
3. historical `primary_contact_*` only through BH1's one-time compatibility backfill into `contact_*`.

Structured writes lock the customer/provider row, guarantee at most one active primary through the existing partial unique indexes, automatically choose a first primary, and deterministically promote the oldest active contact when the primary is disabled. The selected structured primary is projected one-way to canonical `contact_*` in the same transaction. BH2 never writes historical `primary_contact_*`, adds no circular trigger and deletes no contact data.

Read-only staging counts before BH2 were:

| Partner | Total | canonical `contact_*` | legacy `primary_contact_*` | structured | fallback needed | duplicate primary |
|---|---:|---:|---:|---:|---:|---:|
| Customer | 7 | 6 | 6 | 0 | 6 | 0 |
| Provider | 4 | 4 | 4 | 0 | 4 | 0 |

No personal contact value was read or logged.

## Timezone product contract

`tenant_settings.timezone` is the authority. An invalid/missing zone safely falls back to `America/Mexico_City`; the helper uses the PostgreSQL timezone catalog and no dynamic SQL.

- Calendar commitments remain `date`: invoice due date, quote/rate validity date, compliance validity/waiver date, contract start/end and settlement date.
- Event instants remain `timestamptz`: creation/update, assignment, uploads, payments, claim response/resolution SLA, automation runs and notification events.
- “Today”, due/overdue and expiry comparisons must evaluate the instant in the tenant timezone before converting to `date`.
- Claim SLA remains instant-based. F7 digest already uses tenant-local business date. Partner360 Finance overdue totals now use the same tenant date.
- Reports with instant ranges keep half-open timestamp boundaries. No column type was changed.

Mexico City and UTC boundary behavior is covered by SQL tests. Broad replacement of older `current_date` calls is deferred to avoid rewriting stable historical RPCs without an exact consumer contract.

## UX and state fixes

- Debounced server search: Rates, Quotes, Customers, Providers and Documents.
- Stale-response guards: Partner360 summary, notification pages and global command search.
- Critical contact submit remains disabled while saving, shows progress, recovers after error and closes only after confirmed success.
- Existing Quote, Rate, Claim, Finance payment and assignment forms already disable their primary mutation action; no second toast library was added.
- Partner360 differentiates loading, empty and safe error states; raw database errors are mapped in its service.
- Partner tab, selected entity and deep-link query state remain URL-backed. Closing existing drawers continues clearing only their own parameter.
- Existing create/edit modals remount or explicitly reset entity state. Inactive historical relations remain visible in details while active-only reference lists are used for new records.
- Obvious responsive paths retain horizontal tab/table overflow and bounded modal widths. Icon-only notification/contact controls now have button types and accessible labels.
- Existing currency/date/status helpers remain authoritative; BH2 introduces no FX or DB status rename.

## Performance and security

Partner history indexes cover the new customer/provider keysets for quotes, operations and rate cards. Existing tenant/entity indexes cover audit, compliance, contracts and claims. Local `EXPLAIN` must show bounded index-backed plans before release.

New RPCs are `SECURITY DEFINER` with `search_path=pg_catalog, public`, validate all cursor scope, contain no dynamic sort/SQL or `SQLERRM`, grant only `authenticated`, and re-check Admin or the existing Admin/Finance notification role. Finance receives no Partner360/contact/commercial history. PUBLIC, anon and service_role cannot execute the new endpoints.

No advisor-wide cleanup, unused-index removal or policy rewrite is part of BH2.

## Manual QA after merge

- Customer360 and Provider360: switch tabs, reload, back/forward, load three pages and verify no duplicate/lost row.
- Create two contacts, change primary, disable it and confirm deterministic promotion plus legacy fallback on an untouched partner.
- Open Compliance, Contracts and Claims continuations; verify private documents sign only after click.
- Open/close each major create modal twice and edit two different records; confirm values do not leak.
- Exercise slow search/network transitions and confirm an older response never replaces a newer query.
- Verify disabled/progress/error/success feedback for Quote, Rate, Claim, payment, assignment, compliance review, contract and upload.
- Check narrow layouts for Partner360 tabs, notification panel, main tables and modal action wrapping.
- Validate “today” around midnight for the tenant timezone.

## Deferred / prerequisites

Fiscal integration remains untouched. Before integration it still requires an approved provider/runtime contract, legitimate staging credentials stored outside Git, sandbox endpoints, certificate/key custody, idempotency rules, webhook verification, cancellation/status mapping, audit/retention rules and a dedicated non-production release plan. Runtime Finance QA still requires a legitimate Finance credential.
