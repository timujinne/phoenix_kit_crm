# PR #12 Review — Backfill task: import catalogue suppliers into CRM party roles

- **PR:** [#12](https://github.com/BeamLabEU/phoenix_kit_crm/pull/12)
  (`timujinne/feature/import-suppliers-backfill` → `main`, merged as `78fe1bc`)
- **Scope:** one new mix task,
  `mix phoenix_kit_crm.import_suppliers_from_catalogue`, that reads
  `phoenix_kit_cat_suppliers` via raw SQL, matches each row to an existing CRM
  company by email then normalized website, creates a company otherwise,
  grants the `supplier` party role, and stamps `crm_company_uuid` back onto the
  catalogue row. Dry-run by default (`--apply` to write). The branch already
  went through one review-fix round before merge (case-insensitive email
  matching, per-row rescue, a V151 column guard) — this is a post-merge
  review of the final merged state.
- **Reviewer:** Claude (Sonnet 5), post-merge.
- **Method:** Ecto lens (`elixir:ecto-thinking`). Read `PartyRoles.grant_role/4`
  and `Company.changeset/2` in full to confirm the task's calls match their
  actual contracts; traced every action atom `process_supplier_row/4` can
  produce through to `print_report/1`'s totals footer to check the two stay in
  sync (they didn't — see below); ran the repo's actual gate
  (`mix precommit`) rather than trusting the PR's own claimed test counts, and
  checked the `phoenix_kit` version floor bump against the guard message it
  backs.
- **Findings:** 2 BUG-HIGH (both pre-existing gate breaks on `main`, unrelated
  to each other — a dialyzer PLT gap and a Credo aliasing miss), 1 BUG-MEDIUM
  (report undercounts errors), 1 IMPROVEMENT-MEDIUM (a design-doc step not yet
  implemented, deliberately deferred). All four are addressed below; the two
  gate breaks and the report bug have fixes + tests applied, the design-doc
  gap is recorded but intentionally left for when its consumer exists.

---

## BUG - HIGH

**This PR broke `mix dialyzer` on `main` — it's the first mix task in this repo, and `plt_add_apps` never included `:mix`.**

`lib/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue.ex` is the
**first** file under `lib/mix/tasks/` this repo has ever had. Dialyzer's PLT is
built from `plt_add_apps: [:phoenix_kit]` (`mix.exs`) — `:mix` itself was never
in that list, because until this PR nothing in `lib/` called into the `Mix`
namespace. The result, run against the merged tree:

```
lib/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue.ex:1:callback_info_missing
Callback info about the Mix.Task behaviour is not available.
lib/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue.ex:44:14:unknown_function
Function Mix.Task.run/1 does not exist.
lib/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue.ex:71:11:unknown_function
Function Mix.shell/0 does not exist.
lib/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue.ex:387:11:unknown_function
Function Mix.shell/0 does not exist.
Total errors: 7, Skipped: 3, Unnecessary Skips: 0
... Halting VM with exit status 2
```

`mix precommit`/`mix quality`/`mix quality.ci` all end in `dialyzer`, so the
repo's own release gate (AGENTS.md "Full release checklist" step 3, "zero
warnings/errors") currently fails on `main` at `78fe1bc`. This slipped through
because piping `mix dialyzer`/`mix precommit` through `| tail -N` (a natural
thing to do to keep output manageable) silently discards the real exit code —
only `tail`'s own (always-zero) exit status surfaces, so a red gate can look
green in a truncated log. Worth remembering for future gate runs in this repo.

**Fix applied:** added `:mix` to `plt_add_apps` in `mix.exs`
(`plt_add_apps: [:phoenix_kit, :mix]`). Re-ran `mix dialyzer` clean afterward —
back down to `Total errors: 3, Skipped: 3` (the pre-existing Gettext/Expo
opaque-struct warnings already covered by `.dialyzer_ignore.exs`, same count
the PR #11 review recorded), `done (passed successfully)`.

---

## BUG - HIGH

**`mix credo --strict` also fails on `main` at `78fe1bc`** — the new
`IntegrationTest` module aliases the task as `Task`
(`alias Mix.Tasks.PhoenixKitCrm.ImportSuppliersFromCatalogue, as: Task`) but
one call site in `setup_all` still spells out the fully-qualified name,
which Credo's `--strict` "nested modules could be aliased" check flags —
confirmed by stashing my fixes and re-running `mix credo --strict` against
the bare merge commit: exit code 2, same warning. Combined with the dialyzer
break above, **both halves of `mix precommit`'s quality gate were red on
`main` before this review.**

**Fix applied:** `Task.crm_company_uuid_column?(repo, prefix)` instead of the
fully-qualified call. `mix credo --strict` now exits 0, "found no issues".

---

## BUG - MEDIUM

**The totals footer undercounts errors — a rescued exception isn't counted, only a failed create.**

`process_supplier_row/4`'s rescue clause (grant-role failure, stamp failure, any
unexpected exception) tags the row `action: :error`. Separately,
`maybe_create_company/3` tags a failed company-creation changeset
`action: :error_creating`. `print_report/1`'s footer only read the
`:error_creating` bucket:

```elixir
errors = Map.get(counts, :error_creating, 0)
```

A row that hit the rescue path showed up in the per-row table (as a lowercase
`"error"`, via the catch-all `action_label/1` clause — inconsistent with the
uppercase `"ERROR"` label used for `:error_creating`) but was invisible in the
`Total: N | ... | errors: N` summary line — an operator scanning just the
footer after a large `--apply` run could see `errors: 0` while a row above it
silently failed a role grant or a stamp write.

**Fix applied:** sum both buckets into the footer's `errors` count, and give
`:error` the same `"ERROR"` per-row label as `:error_creating` for consistency.
Made `print_report/1` public (`@doc false`, matching the existing
`process_supplier_row/4` / `crm_company_uuid_column?/2` pattern) so a
DB-free unit test can lock in the footer math directly —
`test/mix/tasks/phoenix_kit_crm.import_suppliers_from_catalogue_test.exs`,
`describe "print_report/1"`.

---

## IMPROVEMENT - MEDIUM

**The task doesn't implement the design doc's third per-row step — rewriting `item_supplier_info.supplier_uuid`.**

`dev_docs/design/crm_v2_parties_suppliers_clients.md` §4.5 specs this backfill
as three actions per matched/created row: match-or-create the CRM company,
grant the `supplier` role, stamp `cat_suppliers.crm_company_uuid` — **and**
rewrite `phoenix_kit_cat_item_supplier_info.supplier_uuid` (the item↔supplier
junction table, core migration V149) from the local `cat_suppliers.uuid` to
the new CRM company uuid. The merged task does the first three and never
touches `item_supplier_info`.

**Not fixed, on purpose:** the resolver that would actually *read*
`item_supplier_info.supplier_uuid` as a CRM-vs-local soft ref (design doc's
"Phase 2 — Supplierinfo + resolver", `Suppliers` facade federation) isn't
present anywhere in the vendored `phoenix_kit` core checked out here — only
the V149/V151 migrations exist, no resolver module. Writing the rewrite step
now, ahead of its consumer, risks guessing at a contract that hasn't landed
yet. The design doc itself notes both tables are empty in current deployments
("the window to do this without data migration pain is now"), so there's no
live data this gap could leave inconsistent today. Flagging so it's on record
before `cat_suppliers`/`item_supplier_info` carry real rows: the next time
this task (or its Phase-2 resolver) is touched, the rewrite step needs to be
added, or the design doc needs an explicit note that it was deferred.

---

## Verified clean (checked, no action)

- **`grant_role/4` call shape** — the task calls `PartyRoles.grant_role(company,
  "supplier")` with no `attrs`/`opts`, so no `actor_uuid` is threaded into the
  activity log. Read `PartyRoles`' moduledoc: `actor_uuid` is for attributing a
  logged-in user's action; a one-time backfill script has no such actor, so a
  nil actor on the `crm.party_role_granted` log entries is correct here, not an
  omission.
- **Idempotency across partial-failure re-runs** — `already_linked?/1` only
  skips rows with a non-null/non-empty `crm_company_uuid`. If `--apply` creates
  a company and grants the role but then the `stamp_crm_uuid` write fails (rare:
  a DB blip between the two calls), a re-run recomputes match/create instead of
  skipping. For rows with an extractable email or website, this is safe:
  `find_company_by_email`/`find_company_by_website` will match the
  already-created company deterministically and `grant_role/4` is a documented
  no-op on an already-active role. For rows with **neither** an email nor a
  website to match on, a re-run would create a second company. This is a narrow
  window (a stamp failure right after a successful create+grant in the same
  run) on a task explicitly documented as a one-time backfill; not worth adding
  transactional machinery for.
- **`find_company_by_email` duplicate/case handling** — `fragment("lower(?)",
  c.email) == ^String.downcase(email)` matches regardless of stored case or
  citext-vs-varchar column type (V151 promotes the column to citext; older
  installs are plain varchar); `order_by(asc: :inserted_at) |> limit(1)` on a
  column with no unique constraint means a duplicate-email match resolves to
  the oldest row instead of raising `Ecto.MultipleResultsError` — confirmed via
  the "matches by email (case-insensitive)" integration test.
- **`find_company_by_website` raw-SQL regex** — uses raw SQL (not an Ecto
  fragment) specifically because Ecto fragments treat `?` as a bind-parameter
  placeholder, which collides with the `?` quantifier in `^https?://`; the
  prefix/table name is interpolated from `Application.get_env(:phoenix_kit,
  :prefix, "public")` (compile/runtime config, not row data), and the actual
  row value flows through `$1` — no injection surface.
- **V151 guard message accuracy** — `crm_company_uuid_column?/2` checks
  `information_schema.columns` for `phoenix_kit_cat_suppliers.crm_company_uuid`
  and the guard message cites `phoenix_kit >= 1.7.197`; `mix.exs`'s dependency
  floor (`pk_dep(:phoenix_kit, "~> 1.7 and >= 1.7.197")`) matches exactly — the
  guard and the enforced dependency version agree.
- **Dry-run truly writes nothing** — `maybe_create_company(_, _, false)` short
  circuits to `{:would_create, nil}` before touching `Companies.create_company`,
  and `do_process_supplier/4`'s `if apply? && company do` guards both the role
  grant and the stamp write. Confirmed by the "dry-run writes nothing"
  integration tests (added in the pre-merge review round) asserting no company
  row and no stamped `crm_company_uuid`.

## NITPICK

- No test exercises the `:error` rescue path end-to-end (i.e. actually forcing
  `grant_supplier_role` or `stamp_crm_uuid` to raise inside
  `process_supplier_row/4`) — only the footer-counting fix above is
  unit-tested against a synthetic result list. Forcing a real raise would need
  fault injection (e.g. a role name that fails `PartyRole.changeset/2`
  validation); out of scope for this pass.

---

## Gate status (this environment, after fixes)

- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓ (zero warnings)
- `mix hex.audit` / `deps.unlock --check-unused` ✓
- `mix credo --strict` ✓ (818 mods/funs, no issues — was exit 2 before the
  alias fix above)
- `mix dialyzer` ✓ — `Total errors: 3, Skipped: 3, Unnecessary Skips: 0`, all
  pre-existing and covered by `.dialyzer_ignore.exs` (was `Total errors: 7`,
  exit status 2, before the `plt_add_apps` fix above)
- `mix precommit` ✓ end-to-end, exit code 0
- `mix test` — **90 passed, 0 failures** (139 excluded; Postgres unavailable in
  this environment, `:integration` tests auto-exclude per the repo's
  documented stance — the new `print_report/1` footer test and all
  normalization-helper tests ran and passed)

Both `mix credo --strict` and `mix dialyzer` were failing on `main` at
`78fe1bc` **before** this review (verified by stashing the fixes and
re-running against the bare merge commit) — this PR broke the repo's own
release gate; see the two BUG - HIGH findings above.
