# AGENTS.md

Guidance for AI agents working on the `phoenix_kit_crm` plugin module.

## Project overview

PhoenixKit CRM module — early skeleton scaffolded from `phoenix_kit_hello_world`. Implements the `PhoenixKit.Module` behaviour for auto-discovery by a parent Phoenix application. The Companies subtab is intentionally a placeholder until the legal-entity schema lands; the role opt-in flow and per-user view configuration are already wired and exercised in production.

Registers one admin tab (`CRM`) with subtabs:

- **Overview** (`/admin/crm`) — placeholder card with the enabled/disabled badge and a deep-link to settings
- **Companies** (`/admin/crm/companies`) — table/card view with toggleable columns, gated by `crm_companies_enabled`
- **Role subtabs** (`/admin/crm/role/:role_uuid`) — one per opted-in role; registered at runtime into `PhoenixKit.Dashboard.Registry` under the `:phoenix_kit_crm_roles` namespace

Plus a settings tab at `/admin/settings/crm`.

## What this module does NOT have (yet)

The skeleton is deliberately minimal. Track these gaps when extending:

- **No legal-entity schema** — `CompaniesView` renders an empty list and shows a
  Russian/English placeholder banner. The eventual `Company` schema, context, and
  changeset go under `lib/phoenix_kit_crm/`.
- **No `Errors` dispatcher** — no atom-to-gettext error module. When context
  functions start returning `{:error, atom}` shapes, copy
  `phoenix_kit_locations/lib/phoenix_kit_locations/errors.ex` as the reference.
- **No activity logging** — once mutations land, follow the `PhoenixKit.Activity`
  pattern from `phoenix_kit_hello_world` (guard with `Code.ensure_loaded?/1`,
  rescue exceptions, action shape `"crm.<verb>"`).
- **No production migrations in this repo** — module-owned tables are added via
  versioned migrations in `phoenix_kit` core (V90+). See "Database" below.
- **No integration tests** — only behaviour and path tests run today. Schema
  tests should use `PhoenixKitCRM.DataCase` with the `:integration` tag.

## Common commands

```bash
mix deps.get                # Install dependencies
mix compile                 # Compile

mix test                    # Unit tests (excludes :integration when DB is absent)
mix test test/phoenix_kit_crm_test.exs  # Behaviour tests only

mix format                  # Format (uses Phoenix LiveView import rules)
mix credo --strict          # Lint
mix dialyzer                # Static type checking
mix precommit               # compile + format + credo --strict + dialyzer
mix quality                 # format + credo --strict + dialyzer
mix quality.ci              # format --check-formatted + credo --strict + dialyzer

mix test.setup              # createdb + migrate the test repo
mix test.reset              # drop + recreate + migrate the test repo
```

## Dependencies

This is a **library** (no endpoint, no router). Direct deps:

- `phoenix_kit` (`~> 1.7`) — Module behaviour, Settings, RepoHelper, Dashboard tabs, admin layout, `Users.Roles`
- `phoenix_live_view` (`~> 1.1`) — admin LiveViews
- `ecto_sql` (`~> 3.13`) — schemas and changesets (`RoleSetting`, `UserRoleViewConfig`)
- `lazy_html` (test only) — required by `Phoenix.LiveViewTest`

## Architecture

### File layout

```
lib/phoenix_kit_crm.ex                                # Main module (PhoenixKit.Module behaviour)
lib/phoenix_kit_crm/
├── paths.ex                                          # Centralized URL helpers (always go through Routes.path/1)
├── routes.ex                                         # Parameterized admin routes (per-role view)
├── role_setting.ex                                   # Schema: phoenix_kit_crm_role_settings
├── role_settings.ex                                  # Context: list_enabled, list_eligible_roles, set_enabled
├── user_role_view_config.ex                          # Schema: phoenix_kit_crm_user_role_view
├── user_role_view.ex                                 # Context: get/put view config keyed by (user_uuid, scope)
├── column_config.ex                                  # Available columns + defaults per scope
├── sidebar_bootstrap.ex                              # Registers per-role tabs into Dashboard.Registry
└── web/
    ├── crm_live.ex                                   # Overview LiveView (placeholder card)
    ├── settings_live.ex                              # Settings LiveView (toggles, role opt-in, Companies opt-in)
    ├── companies_view.ex                             # Companies LiveView (table/card with column modal)
    ├── role_view.ex                                  # Per-role users LiveView
    ├── column_management.ex                          # Shared mixin for column-modal events
    └── column_modal.ex                               # Column picker modal component
```

### Settings keys

- `crm_enabled` — module on/off (set via `enable_system/0` / `disable_system/0`)
- `crm_companies_enabled` — Companies subtab visibility (gated in `admin_tabs/0` via `visible:` and re-checked in `CompaniesView.mount/3`)

### Tab registration

- Static tabs (Overview, Companies, settings) come from `admin_tabs/0` and `settings_tabs/0`. Companies uses `visible: fn _scope -> Settings.get_boolean_setting("crm_companies_enabled", false) end`.
- **Per-role tabs are runtime-registered** by `PhoenixKitCRM.SidebarBootstrap` into `PhoenixKit.Dashboard.Registry` under `:phoenix_kit_crm_roles`. Bootstrap runs:
  1. At boot, via `children/0` as a one-shot `Task` (`restart: :temporary`).
  2. After every `RoleSettings.set_enabled/2`, via `PhoenixKitCRM.refresh_sidebar/0` (which unregisters then re-bootstraps).
- The matching parameterized route `/admin/crm/role/:role_uuid` is declared in `PhoenixKitCRM.Routes` because dynamic tabs registered into the Dashboard Registry at runtime do not trigger router compilation.

> **Known limitation:** if `PhoenixKit.Dashboard.Registry.load_admin_defaults/0` is invoked at runtime, the `:phoenix_kit_crm_roles` namespace is wiped. Role tabs reappear on the next `set_enabled/2` call or on application restart. This is an accepted trade-off for not running a persistent watcher GenServer.

### Per-user column configuration

`PhoenixKitCRM.ColumnConfig` defines available columns + defaults per scope. Scopes:

- `:companies` — placeholder columns until the Company schema lands
- `{:role, role_uuid}` — mirrors standard PhoenixKit user fields (email, username, full_name, status, registered, last_confirmed, location)

Selections are persisted via `PhoenixKitCRM.UserRoleView` (keyed by `(user_uuid, scope_string)`). The column-modal UI lives in `PhoenixKitCRM.Web.ColumnModal` and is wired into LiveViews through `use PhoenixKitCRM.Web.ColumnManagement`.

### Critical conventions (inherited from the template)

- **Module key**: lowercase with underscores (`"crm"`); used everywhere for permission lookups and `module_key()` references.
- **Tab IDs**: prefixed with `:admin_` (`:admin_crm`, `:admin_crm_companies`, `:admin_settings_crm`).
- **URL paths in tabs**: hyphens, not underscores. The behaviour test at `test/phoenix_kit_crm_test.exs` enforces this.
- **Navigation**: always use `PhoenixKitCRM.Paths` (or `PhoenixKit.Utils.Routes.path/1` directly). Never hardcode `/admin/crm/...` in templates.
- **`enabled?/0`**: rescues errors and returns `false` so the module degrades gracefully when the DB isn't available (e.g. during boot).
- **LiveViews** use `use PhoenixKitWeb, :live_view` — this imports PhoenixKit core components (`<.icon>`, `<.button>`, `<.input>`, `TableDefault`, etc.), Gettext, and the admin layout. Do **not** switch to `use Phoenix.LiveView` directly.
- **JavaScript hooks**: must be inline `<script>` tags; register on `window.PhoenixKitHooks`.
- **LiveView assigns** available in admin pages: `@phoenix_kit_current_scope`, `@phoenix_kit_current_user`, `@current_locale`, `@url_path`.

### Routing

> **Never hand-register CRM LiveView routes in the parent app's `router.ex`.** PhoenixKit injects them into its own `live_session :phoenix_kit_admin` automatically. Routes outside that session lose the admin layout and crash on cross-page navigation.

Two patterns coexist in this module:

1. **`live_view:` on tabs** (Overview, Companies, settings) — auto-generated routes from `admin_tabs/0` / `settings_tabs/0`.
2. **Route module** (`PhoenixKitCRM.Routes`) — hand-written `live` declarations for parameterized routes. Both `admin_routes/0` and `admin_locale_routes/0` must be defined and use unique `:as` aliases (e.g. `crm_role_view` and `crm_role_view_locale`).

`admin_routes/0` and `admin_locale_routes/0` quoted blocks are spliced inside `live_session :phoenix_kit_admin do … end` — they may only contain `live` declarations.

### Tailwind CSS scanning

`css_sources/0` returns `[:phoenix_kit_crm]`. CSS source discovery is automatic at compile time — the `:phoenix_kit_css_sources` compiler scans this module's templates and writes into `assets/css/_phoenix_kit_sources.css` in the parent app.

## Database

This module owns two tables. **Production migrations live in `phoenix_kit` core**, not here. When adding the `Company` schema (or any other CRM-owned table), create the next versioned migration (`VNN_*.ex`) under `phoenix_kit/lib/phoenix_kit/migrations/postgres/`.

Module-owned tables today:

- `phoenix_kit_crm_role_settings` — primary key is `role_uuid` (FK to `phoenix_kit_user_roles`); columns `enabled`, `inserted_at`, `updated_at`.
- `phoenix_kit_crm_user_role_view` — `(user_uuid, scope)` is unique; `view_config` is a JSON map; UUIDv7 primary key.

The role-settings schema uses `@primary_key {:role_uuid, :binary_id, autogenerate: false}` — there's no separate `id` / `uuid` column. Be careful when writing new queries.

## Testing

### Setup

This module owns its own test database (`phoenix_kit_crm_test`) and a test repo (`PhoenixKitCRM.Test.Repo`). Create the DB once:

```bash
createdb phoenix_kit_crm_test
mix test.setup     # ecto.create + ecto.migrate
```

If the DB is absent, integration tests auto-exclude via the `:integration` tag (see `test/test_helper.exs`) — unit tests still run.

The critical config wiring is in `config/test.exs`:

```elixir
config :phoenix_kit, repo: PhoenixKitCRM.Test.Repo
```

Without this, all DB calls through `PhoenixKit.RepoHelper` crash with "No repository configured".

### Test infrastructure

- `test/support/test_repo.ex` — `PhoenixKitCRM.Test.Repo`
- `test/support/data_case.ex` — auto-tags `:integration`, sets up the SQL sandbox
- `test/test_helper.exs` — checks DB availability via `psql -lqt`, creates `uuid_generate_v7()`, starts `PhoenixKit.PubSub.Manager` and `PhoenixKit.ModuleRegistry`

### Current coverage

Only behaviour and path tests today (`test/phoenix_kit_crm_test.exs`):

- `module_key/0`, `module_name/0`, `enabled?/0`, `enable_system/0`, `disable_system/0`
- `permission_metadata/0` (key matches `module_key`, `hero-` icon prefix)
- `admin_tabs/0` (permission threading, hyphenated paths, main tab points to `CRMLive`)
- `settings_tabs/0` (CRM settings tab points to `SettingsLive`)
- `Paths.index/0` and `Paths.settings/0`

### Stability check

```bash
for i in $(seq 1 10); do mix test; done
```

## Versioning & releases

This project follows [Semantic Versioning](https://semver.org/). The version must be updated in **two** places when bumping:

1. `mix.exs` — `@version` module attribute
2. `lib/phoenix_kit_crm.ex` — `def version, do: "x.y.z"`

(There is no version compliance test today; add one when the test surface grows.)

Tags use **bare version numbers** (no `v` prefix):

```bash
git tag 0.1.0
git push origin 0.1.0
gh release create 0.1.0 --title "0.1.0 - YYYY-MM-DD" --notes "..."
```

### Full release checklist

1. Update version in `mix.exs` and `lib/phoenix_kit_crm.ex`.
2. Add a `CHANGELOG.md` entry.
3. Run `mix precommit` — ensure zero warnings/errors.
4. Commit: `"Bump version to x.y.z"`.
5. Push to `main` and **verify the push succeeded** before tagging.
6. `git tag x.y.z && git push origin x.y.z`.
7. `gh release create x.y.z --title "x.y.z - YYYY-MM-DD" --notes "..."`.

**Never tag before all changes are committed and pushed.** Tags are immutable pointers.

## Pull requests

PR review files go in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/`. Use `{AGENT}_REVIEW.md` (e.g. `CLAUDE_REVIEW.md`).

Severity levels:

- `BUG - CRITICAL` — crashes, data loss, security issues
- `BUG - HIGH` — incorrect behavior that affects users
- `BUG - MEDIUM` — edge cases, minor incorrect behavior
- `IMPROVEMENT - HIGH` — significant code-quality or performance issue
- `IMPROVEMENT - MEDIUM` — better patterns or maintainability
- `NITPICK` — style, naming, minor suggestions

### Commit message rules

Start with action verbs: `Add`, `Update`, `Fix`, `Remove`, `Merge`. **Do not include AI attribution or `Co-Authored-By` footers** unless the user asks for it.

## Cross-module integration

CRM consumes `PhoenixKit.Users.Roles` (eligible-role listing excludes the system Owner and Admin roles) and `PhoenixKit.Users.Auth.User` (referenced by UUID in `phoenix_kit_crm_user_role_view`). Keep the public surface (`PhoenixKitCRM.RoleSettings`, `PhoenixKitCRM.UserRoleView`, `PhoenixKitCRM.ColumnConfig`) stable — sibling modules may start consuming it.
