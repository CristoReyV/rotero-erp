# F8 — Rates, Lanes & Partner 360

F8 adds the missing broker pricing chain without creating a parallel CRM: provider → exact lane/service → BUY rate → customer SELL rate → quote snapshot → margin → existing F1 operation conversion.

## Reused contracts and gaps

F1 remains canonical for customers, providers, quote lifecycle and conversion; F2 for operations; F3 for private partner/quote documents and customer-safe generated quotes; F4 for AR/AP; F5 for admin-only Commercial routes and command actions; F6 for external keys and CSV safety; F7 remains unchanged. No reusable lane, versioned rate, multi-contact or Provider 360 contract existed.

## Domain

- `commercial_lanes` uses the existing place JSON vocabulary and a normalized tenant/scope/origin/destination identity. Facility is included in the normalized key so legitimate sites are not merged.
- `commercial_rate_cards` is the stable BUY/SELL identity and enforces exactly one typed counterparty.
- `commercial_rate_versions` and fixed `commercial_rate_charges` preserve economics. A version or charge referenced by `crm_quote_rate_snapshots` is immutable.
- Eligibility is exact on tenant, active provider/card/lane, lane ID, service ID, date and currency. There is no fuzzy fallback or live FX.
- Applying BUY changes provider cost only; applying SELL changes customer sell only. Both create an immutable snapshot and are draft-only.
- `business_contacts` adds tenant-safe multi-contact records while legacy contact columns remain untouched. Payment terms are suggestions for new Finance handoffs only.

## Security and release boundary

All F8 tables use RLS and have no direct client privileges. Normal RPCs are `SECURITY DEFINER`, use `pg_catalog, public`, authorize `admin` internally and grant only `authenticated`; PUBLIC, anon and service_role are denied. BUY pricing is absent from Tracking/driver/customer-facing contracts, and F3's quote-document filter remains canonical.

The pre-implementation read-only staging `pg_proc` collision scan returned zero rows for all 16 new public RPC identities. No existing function is replaced. Migration: `20260828000000_f8_rates_partner_360.sql`.

F7 `rate_expiring` is deferred: adding it would modify the predefined automation architecture and is not required for the complete F8 pricing workflow. Rate import is also deferred; F8 provides an admin-only CSV export and does not weaken F6 idempotency.

Merge does not release to staging. A future authorized release must take a verified backup, confirm pending migration history and apply through the established release process. No `db push`, migration repair, Auth/Edge/Tracking mutation or deploy is part of F8.

## Manual QA after an authorized release

1. As Admin, open `/commercial?view=rates`, create exact lane, BUY and SELL rates, then create a second version.
2. Compare a draft quote and apply BUY and SELL separately; confirm customer price is never overwritten by BUY and a snapshot is recorded.
3. Confirm approved/rejected/converted quotes reject rate application.
4. Open customer/provider deep links and review contacts, native-currency Finance summaries, rates, operations, performance and activity.
5. Confirm Finance has no Commercial route, command, search result or F8 RPC access.
