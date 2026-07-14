# PR #10 Review — CRM Phase 1: party roles (suppliers & clients)

- **PR:** [#10](https://github.com/BeamLabEU/phoenix_kit_crm/pull/10) (`timujinne/feature/crm-party-roles` → `main`, merged as `3eddfcf`)
- **Scope:** ~970 insertions across 9 files — a new `PartyRoles` context + `PartyRole`
  schema (soft-ref polymorphic role rows on companies/contacts), a shared
  `PartyRoleHelpers` module, Roles checkboxes on both forms, role badges + filter
  tabs on both list pages, and unit tests for the context and helpers.
- **Reviewer:** Claude (Sonnet 5), post-merge.
- **Method:** Ecto + Phoenix LiveView lenses. Every context function traced to its
  callers; the underlying table cross-checked against the actual `phoenix_kit`
  core migrations (not just this repo) since CRM DDL ships there, per `AGENTS.md`.

Design is sound — idempotent grant/revoke, soft-ref integrity via changeset (not a
polymorphic FK), a `metadata` field deliberately never cast from UI input, and solid
unit-test coverage of the context/helpers logic. One finding is release-blocking.

---

## BUG — CRITICAL

### 1. No migration ships the `phoenix_kit_crm_party_roles` table — every `PartyRoles` call raises at runtime

`lib/phoenix_kit_crm/schemas/party_role.ex:355` declares
`schema "phoenix_kit_crm_party_roles"`, and the whole feature (`grant_role/3`,
`revoke_role/2`, `has_role?/2`, `list_roles/1`, the list-page badges/filters, the
Roles checkboxes on both forms) reads/writes that table. Per `AGENTS.md`, CRM's DDL
ships in `phoenix_kit` **core**, not this repo — every existing CRM table has a
matching `VNN_*.ex` migration there. `phoenix_kit_crm_party_roles` does not:

```
grep -rn "phoenix_kit_crm_party_roles" <phoenix_kit core checkout>   # zero hits
```

checked against the local core checkout at HEAD (`867bc5b2`, core version
`1.7.192`, latest migration `v99.ex`) and across `git log --all` / all local
branches — no migration, no WIP branch, nothing. The unique index the schema's
changeset relies on (`phoenix_kit_crm_party_roles_uniq`) doesn't exist either.

**Impact:** on any install (this repo's own test DB included, once integration
tests run against a real Postgres), opening the Roles section of a company/contact
form, saving it, or visiting the Suppliers/Clients tab raises
`Postgrex.Error: relation "phoenix_kit_crm_party_roles" does not exist`. The
feature does not work today — it can only have passed review because this
environment (like CI, per the documented stance) has no Postgres, so the
`:integration`-tagged tests that would hit this table never ran.

**Fix:** add a versioned migration (`vNN_*.ex`, next after `v99`) to `phoenix_kit`
core creating `phoenix_kit_crm_party_roles` (`uuid` PK, `roleable_type`,
`roleable_uuid`, `role`, `is_active`, `valid_from`, `valid_to`, `metadata` jsonb,
timestamps) with the composite unique index the changeset expects, then bump the
`>= 1.7.x` pin in this repo's `mix.exs` once core ships it. **Not fixed in this
pass** — it requires a change in the `phoenix_kit` core repo, which is out of this
review's scope; flagging so it blocks any release of this PR's feature.

---

## IMPROVEMENT — HIGH

### 2. Party-role grant/revoke activity log entries always record `actor_uuid: nil`

`PhoenixKitCRM.Web.PartyRoleHelpers.sync_roles/2` (called from both
`company_form_live.ex` and `contact_form_live.ex`) drove
`PartyRoles.grant_role/3` / `revoke_role/2`, which called
`Activity.log(action, resource_type: ..., resource_uuid: ..., metadata: ...)` with
**no `actor_uuid` key at all** — `PhoenixKitCRM.Activity.log/2` defaults it to `nil`
via `Keyword.get(opts, :actor_uuid)`. Every sibling mutation in this codebase
(`crm.company_created`, `crm.contact_saved`, `Interactions.log_interaction/3` via
`opts[:actor_uuid]`) threads the acting user's uuid through
`Activity.actor_opts(socket)` / an explicit `actor_uuid` opt — party roles was the
one mutation type where the Events feed would always show "actor unknown" for who
granted or revoked a commercial role.

**Fix applied:** `grant_role/4` and `revoke_role/3` now take an `opts` keyword list
(`actor_uuid: ...`) threaded into the activity log entry; `sync_roles/3` accepts and
forwards an `actor_uuid` argument; both LiveViews now call
`sync_roles(roleable, socket.assigns.roles_selected, Activity.actor_uuid(socket))` (a
private `actor_uuid(socket)` fallback already existed in `contact_form_live.ex` for
the same purpose). Locked in with new `party_roles_test.exs` cases asserting the
logged `actor_uuid` on grant, revoke, and through `sync_roles/3`, plus a
no-duplicate-log case for the idempotent re-grant path.

---

## IMPROVEMENT — MEDIUM

### 3. `contact_form_live`'s partial-role-failure path showed stale checkbox state — `contact_form_live.ex` (the non-`:ok` branch of `do_save/8`)

When `sync_roles/2` returned `{:partial, _}` (a grant/revoke failed), the form
re-rendered via `restore_form/6`, which never reassigns `:roles_selected` — so the
checkboxes kept showing whatever the user submitted, not what was actually
persisted. The sibling `company_form_live.ex` gets this right: its `finish_save/4`
`{:partial, _failed}` clause re-reads `active_role_values(company)` from the DB so
the checkboxes reflect reality. Low real-world impact (a re-save would just retry
the failed op), but the two near-identical forms diverged on the same new code
path.

**Fix applied:** the partial-failure branch in `contact_form_live.ex` now also
`assign(:roles_selected, active_role_values(contact))`, matching
`company_form_live.ex`.

---

## NITPICK

- **`companies_live.ex` / `contacts_live.ex`** — `@role_filters ~w(supplier client)`
  omits `"partner"`, so a company/contact can be granted the `partner` role via the
  form checkboxes but has no dedicated filter tab on the list pages (it still shows
  as a badge, since `active_roles_map/2` isn't restricted to `@role_filters`). Likely
  deliberate Phase-1 scoping (the PR title says "suppliers & clients") rather than
  an oversight — flagging in case `partner` was meant to get a tab too.

---

## Resolution — fixes applied this pass

#1 requires a change outside this repo (`phoenix_kit` core) and is left for the
maintainer/a follow-up PR there — this repo's code is otherwise correct and will
work once that migration ships. #2 and #3 were fixed with locking tests.

| # | Fix | Test |
|---|---|---|
| 1 | Not fixed here — needs a core migration in `phoenix_kit` | n/a |
| 2 | `grant_role/4`, `revoke_role/3` thread `actor_uuid` into the activity log; `sync_roles/3` forwards it; both LiveViews pass `Activity.actor_uuid(socket)` | `party_roles_test.exs` — grant/revoke/sync_roles all assert the logged `actor_uuid`; idempotent re-grant asserts no duplicate log |
| 3 | `contact_form_live`'s partial-failure branch re-reads `active_role_values(contact)` | covered by existing partial-failure flash assertions; no DB in this environment to add a new LiveView case (see Gate status) |

**Gate status (this environment):**
- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓ (zero warnings, before and after the fixes)
- `mix credo --strict` ✓ (no issues, 79 files)
- `PHOENIX_KIT_PATH=../phoenix_kit mix test` — **74 passed, 0 failures** (130
  excluded). Postgres is unavailable in this environment, so every `:integration`
  test — including all of `party_roles_test.exs`, the exact suite that would have
  caught finding #1 — auto-excludes per the repo's documented stance. The new
  actor_uuid assertions were written against the existing test patterns
  (`PhoenixKitCRM.ActivityLogAssertions`) but could not be executed here.
- `mix dialyzer` ✓ — 3 pre-existing errors, all covered by `.dialyzer_ignore.exs`
  (0 unnecessary skips, 0 new warnings from either PR or from this pass's fixes).

## Out-of-repo to verify

- **Finding #1** — add the `phoenix_kit_crm_party_roles` migration to `phoenix_kit`
  core, then confirm `PHOENIX_KIT_PATH=../phoenix_kit mix test.setup && mix test`
  passes the full `:integration` suite against a real Postgres before this feature
  ships to users.
