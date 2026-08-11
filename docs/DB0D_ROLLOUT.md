# DB.0D staging reconciliation rollout

## Scope

DB.0D is a forward-only catalog reconciliation. It does not recreate the
canonical baseline, modify rows, normalize the complete staging schema or touch
class-D families. Merging its PR does not apply SQL.

Read-only staging metadata confirmed 17 remote versions through
`20260526120000`; the canonical baseline, M4.1 and DB.0D remain absent remotely.
No operational rows were inspected.

| Object | Observed staging state | DB.0D result | Risk |
| --- | --- | --- | --- |
| `public.users` | View over `auth.users`; SELECT for `authenticated` and `service_role`; no SQL dependents | Revoke both direct grants; retain the view | Low, reversible |
| `tanda1_user_is_member(uuid)` | `search_path=public`; auth/service execution | `pg_catalog, public`; authenticated only | Medium |
| `tanda1_user_has_role(uuid,text[])` | `search_path=public`; auth/service execution | `pg_catalog, public`; authenticated only | Medium |
| `tracking_hash_token(text)` | Default PUBLIC execution; no configured path | `pg_catalog, public, extensions`; service_role only | Medium |
| `tracking_validate_token(text,text)` | Default PUBLIC execution; `search_path=public` | `pg_catalog, public, extensions`; service_role only | Medium |
| `rpc_get_public_tracking(text)` | anon/auth/service execution; `search_path=public` | service_role only; safe path | Medium |
| `rpc_get_driver_view(text)` | anon/auth/service execution; `search_path=public` | service_role only; safe path | Medium |
| `rpc_post_driver_event(...)` | anon/auth/service execution; `search_path=public` | service_role only; safe path | Medium |

The three RPCs remain the database consumers of `track-public`, `driver-view`
and `track-driver`. DB.0D changes neither function bodies nor capability-token
semantics. The observed definitions contained no `SQLERRM` and no public JSON
key for token hash/prefix material.

No policy, constraint, trigger, table or row is changed. Critical Tracking and
membership tables had no direct grants to anon/authenticated/service_role in the
metadata check, so no policy rewrite was justified. Fiscal/PAC, payroll,
documents, storage, notifications, daily control, currency, extended
operations and the 31 additional staging tables remain untouched.

## Prechecks

The migration fails with sanitized errors if any of the seven required
signatures or the `anon`, `authenticated` and `service_role` roles are absent.
If `public.users` exists it must be a view. Its absence in a fresh canonical
database is accepted explicitly.

There are no data-dependent constraints or DML, so no row precheck is required.
Future changes that add NOT NULL, CHECK, UNIQUE or FK contracts must first use
aggregate-only read-only checks and must stop on drift.

## Local evidence

- Fresh reset: canonical baseline + 17 markers + M4.1 + DB.0D.
- Contract suites: baseline, consumed contracts, INV.1, M4.1 and DB.0D.
- Staging-like harness: sanitized `public.users`, observed grants/search paths,
  seven required signatures and a representative class-D table.
- Rollback: `docs/rollbacks/DB0D_ROLLBACK.sql` restores only the observed grants
  and search paths; it does not recreate or delete data.
- Baseline fingerprint: `36fb58e9f12c05a93f0e4d85955a48ad274c53625d51a168145f1b47463b0a75`
  with 845 entries.
- Post-M4.1 and post-DB.0D fresh fingerprint:
  `2bbe5e6e7f36c2b21113385cb9d7d75d4d225b260ef1bf2c2ace7ea7e6e380bc`
  with 845 entries. DB.0D adds zero fresh catalog entries because the canonical
  objects were already hardened.
- Staging-like pre-state and post-rollback snapshot:
  `b0c18d563e936599996ee178e0ea44653d3c561f9a04060051faabb4cc28c568`.

## Future rollout phases

### Phase A — Backup

Before any future write, capture and verify:

- logical backup;
- schema-only snapshot;
- `supabase_migrations.schema_migrations` history;
- grants, functions and policies;
- sanitized fingerprint;
- Edge smoke baseline.

DB.0C2 reported **Last backup: No backups**. Rollout is prohibited until a
restorable backup is verified.

### Phase B — Merge code

Merge the reviewed DB.0D PR to `main`. This does not execute SQL automatically.

### Phase C — Align history

Only after separate explicit approval, the candidate command is:

```text
supabase migration repair 20260223000000 --status applied --linked
```

Then run `migration list`. The expected state at that moment is baseline plus
17 matching markers, with M4.1 and DB.0D still local-only.

### Phase D — Dry-run pending migrations

Confirm the only pending versions are:

1. `20260803142928_reconcile_tracking_rpc_contracts_m4_1.sql`
2. `20260811005659_db0d_staging_reconciliation.sql`

Abort if any other version appears.

### Phase E — Apply

Using a separately approved controlled mechanism, apply only M4.1 and DB.0D.
Do not execute the baseline or markers.

### Phase F — QA

Validate:

- admin, operator, finance and viewer;
- cross-tenant denial;
- `track-public`, `driver-view` and `track-driver` Edge smoke tests;
- Tracking create/list/revoke;
- `public.users` inaccessible to authenticated/service_role direct clients.

### Phase G — Abort criteria

Abort on any of the following:

- backup not verifiable;
- unexpected migration history;
- more than two pending migrations;
- failed aggregate data precheck;
- unexpected functions or grants;
- Edge smoke failure;
- RBAC QA failure.

## Rollback boundary

Use the rollback only after an approved DB.0D staging rollout and only if its
prechecks match. It restores historical staging grants, including the broader
Edge/helper access, so it must not be executed on a canonical fresh database.
After rollback, repeat catalog fingerprint, grants and Edge/RBAC smoke tests.
