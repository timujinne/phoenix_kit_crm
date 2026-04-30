# PR #1 — Follow-Up

**Author of follow-up:** Claude Opus 4.7 (1M context)
**Date:** 2026-04-30
**Status:** Working tree changes; not yet committed.

This document records the post-merge cleanup applied directly to `main`
in response to `CLAUDE_REVIEW.md`. Each entry below maps to a numbered
finding in the review.

## Addressed in this follow-up

### #2 — `RoleView.column_label/1` ignores its own scope (HIGH)

`column_label/1` and `card_field/2` now take `scope` as their first argument; HEEx call sites pass `@scope`. Same change applied to `CompaniesView` for consistency (it was passing the literal `:companies` instead of `@scope` — harmless today, footgun later).

**Files:**
- `lib/phoenix_kit_crm/web/role_view.ex`
- `lib/phoenix_kit_crm/web/companies_view.ex`

### #4 — `Paths` helper missing companies/role coverage (MEDIUM)

Added `Paths.companies/0` and `Paths.role/1`. Replaced the three literal `"/admin/crm"` `push_navigate` calls in `RoleView.mount/3` with `Paths.index()`.

Did **not** change `path:` fields inside `admin_tabs/0` or the `live` declaration in `Routes` — those are route *definitions*, not navigation paths. Routing them through `PhoenixKit.Utils.Routes.path/1` would inject locale prefixes that the route registration itself doesn't understand. The hardcoded `/admin/crm/...` strings inside `SidebarBootstrap.role_tab/1` and `Routes.build_admin_routes/1` are correct as-is.

**Files:**
- `lib/phoenix_kit_crm/paths.ex`
- `lib/phoenix_kit_crm/web/role_view.ex`

### #6 — `refresh_sidebar/0` swallows errors silently (MEDIUM)

The unregister `rescue _` and `catch :exit, _` blocks now log `Logger.warning` with the exception message / exit reason, matching the style already used by `SidebarBootstrap.run/0`.

**File:** `lib/phoenix_kit_crm.ex`

### #7 — No tests for new contexts (MEDIUM)

Added two pure-function unit-test files (`async: true`, no DB needed):

- `test/phoenix_kit_crm/column_config_test.exs` — 14 tests covering `available_columns/1`, `default_columns/1`, `validate_columns/2` (filter, ordering, empty list, cross-scope rejection), and `get_column_metadata/2`.
- `test/phoenix_kit_crm/user_role_view_test.exs` — 8 tests covering `scope_to_string/1`, `scope_from_string/1` (including the new fallback path with `capture_log`), the round-trip property, and `default_config/1`.

`mix test` now reports **33 tests, 0 failures**. Coverage of the DB-dependent functions in `RoleSettings` and `UserRoleView.{get_view_config,put_view_config}` is still pending — those require a live Postgres and `PhoenixKitCRM.DataCase`, deferred to a future PR.

**Files:**
- `test/phoenix_kit_crm/column_config_test.exs` (new)
- `test/phoenix_kit_crm/user_role_view_test.exs` (new)

### #8 — `scope_from_string/1` has no fallback clause (LOW)

Added a default clause that logs a `Logger.warning` and falls back to `:companies`. Documented the fallback in the moduledoc.

**File:** `lib/phoenix_kit_crm/user_role_view.ex`

### #13 — `add_column` accepts arbitrary column IDs into modal state (LOW)

`add_column` now filters the incoming `column_id` against `ColumnConfig.all_column_ids(scope)` before appending. Bogus IDs are silently dropped at the modal-state layer instead of waiting until the persistence layer's `validate_columns/2` filter.

**File:** `lib/phoenix_kit_crm/web/column_management.ex`

### Bonus: `test_helper.exs` crashes when `psql` is absent

The pre-existing `System.cmd("psql", ["-lqt"], …)` call raised `ErlangError :enoent` in environments without PostgreSQL on the PATH, preventing `mix test` from running at all. Wrapped the cmd in `try/rescue` and fall through to `:try_connect`, which then drops to the existing `:integration`-tag exclusion. Unit tests that don't need the DB now run cleanly even without Postgres.

**File:** `test/test_helper.exs`

## Deferred

### #1 — Hardcoded Russian strings bypass Gettext (HIGH)

Held off — the bilingual `"CRM — Companies / Юрлица"` page title looks intentional, and converting Russian module-attribute column labels to runtime Gettext lookups touches more shape than a follow-up cleanup should. Recommend addressing as a deliberate i18n PR with translation strategy decided up front (English msgids + Russian .po, or current text wrapped via Gettext keeping Russian as the default).

### #3 — `mount/3` performs DB work twice (HIGH)

Held off — the gate checks (`enabled?`, role access) genuinely need the static-render pass to issue the redirect without flicker, so the obvious `if connected?(socket)` wrap doesn't apply uniformly. Splitting gate-vs-data into `mount/3` and `handle_params/3` is a real refactor with behavior implications best done with the author's input.

### #5 — Inconsistent `admin_tabs/0` `path:` (relative vs absolute)

Held off — see #4 above; route-definition paths interact with PhoenixKit's locale routing in ways I'd want to verify against the host app's actual mount, not just smoke-test in isolation.

### #9, #10, #11, #12

- **#9** dead `update_table_columns` clause: keeping the no-payload branch as defensive scaffolding for future call sites.
- **#10** eligible-roles filter by name: needs investigation of `Role.system_roles/0`'s shape and whether system roles are renamable; if they are, the filter is broken; if not, the current code is fine.
- **#11** `Phoenix.HTML.raw` for badges: cosmetic; needs to verify the `<.badge>` core component matches the desired daisyUI classes.
- **#12** `<%= if %>` → `:if` in `column_modal.ex`: pure cosmetic, low value.

## Verification

```bash
mix compile --warnings-as-errors    # ok (no warnings)
mix format --check-formatted        # ok
mix test                            # 33 tests, 0 failures
```

Postgrex `econnrefused` log lines from `mix test` are expected in environments without Postgres — `test_helper.exs` falls through to `:try_connect`, the connect fails, integration tests get excluded via the `:integration` tag, and unit tests run normally. The `enabled?/0` rescue clause swallows the `DBConnection.ConnectionError` so the behaviour test still passes.
