# SEC.4B — Tracking credential resolver hardening

## Runtime contract

`driver-view`, `track-public` and `track-driver` share one privileged client
factory. Before SEC.4B it resolved credentials in this order:

1. `SUPABASE_SECRET_KEYS["trackingedge"]`;
2. the manually supplied singular compatibility variable;
3. the legacy project service-role variable.

SEC.4B makes `SUPABASE_SECRET_KEYS["trackingedge"]` the only accepted source.
The singular variable had no versioned consumer or hosted Supabase default and
is removed together with the service-role fallback. The dedicated key must be a
non-empty, whitespace-free modern secret with an `sb_secret_` prefix and a
minimum non-trivial length.

If URL or dedicated credential configuration is unavailable or malformed, the
three functions return HTTP `503` with the safe status
`tracking_service_unavailable`. They do not attempt anonymous access, inspect
another privileged key, include configuration details or emit a stack trace.

## Preserved capability boundary

- `verify_jwt=false` remains explicit for all three functions because their
  callers authenticate with a transient capability, not an ERP session.
- Capability hashing, scopes, expiration, revocation, rotation, tenant checks,
  audit behavior and route formats are unchanged.
- The functions still call only the existing Tracking RPCs. No database
  migration or privilege broadening is part of SEC.4B.
- Credential values, capability literals, request bodies and Authorization
  headers are not logged.

## Regression gates

`scripts/codex/tests/sec4b-tracking-credential.tests.ts` covers the resolver
matrix, rejects the singular and service-role sources, checks all three Edge
contracts, enforces `verify_jwt=false`, and fails if a forbidden credential
source reappears in Tracking runtime code. Canonical M4 SQL and handoff suites
remain the behavioral authority for capability lifecycle and data isolation.

Legacy project keys are not disabled by SEC.4B. Their consumer inventory and
any future disablement require a separate, explicitly authorized release gate.

## Read-only legacy-key consumer inventory

| Surface | Classification | Evidence |
| --- | --- | --- |
| Tracking Edge runtime | Modern secret-key consumer | Only `SUPABASE_SECRET_KEYS["trackingedge"]` is accepted. |
| Frontend source | Legacy anon consumer | `src/lib/supabase.ts` consumes `VITE_SUPABASE_ANON_KEY`. |
| Netlify staging-site metadata | Legacy anon consumer | Production deploy context declares `SUPABASE_ANON_KEY` and `VITE_SUPABASE_ANON_KEY`; values were not read or printed. |
| Other Edge/functions runtime | No versioned legacy-key consumer found | Scoped source search found no service-role environment read outside the removed Tracking path. |
| Scripts and CI | No versioned legacy-key consumer found | Scripts use management credentials where required; no repository CI secret/variable metadata was configured. |
| Historical docs and migrations | Legacy reference, not runtime consumer | Several protected historical files describe the Postgres `service_role` role or old key pattern and remain evidence only. |
| External integrations outside the repository | Unknown/external | No authoritative registry proves that every external consumer has migrated. |

Legacy-key disablement is therefore **not ready**. The frontend/Netlify anon
consumer must migrate, and unknown external consumers must be resolved, before
any separate disablement authorization can be considered.
