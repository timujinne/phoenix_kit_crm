# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-04-30

First public release of the CRM module for PhoenixKit. Implements the
`PhoenixKit.Module` behaviour for auto-discovery; ships an admin
sidebar tab with Overview, optional Companies subtab, per-role user
listings, and a settings page. Most of the moving pieces are
backbone — the Companies legal-entity schema is a deliberate
placeholder, ready to land in 0.2.x.

### Added

- **Module behaviour & auto-discovery** — `PhoenixKitCRM` implements
  `PhoenixKit.Module`: `module_key/0`, `module_name/0`, `enabled?/0`,
  `enable_system/0`, `disable_system/0`, `version/0`,
  `permission_metadata/0`, `admin_tabs/0`, `settings_tabs/0`,
  `route_module/0`, `css_sources/0`, `children/0`. Discovered at
  startup via the `@phoenix_kit_module` beam attribute — the host app
  needs no router edits.
- **Admin pages** — Overview LiveView at `/admin/crm`, Companies
  subtab at `/admin/crm/companies` (gated by `crm_companies_enabled`),
  per-role user listings at `/admin/crm/role/:role_uuid`, and the
  settings page at `/admin/settings/crm`. All use
  `use PhoenixKitWeb, :live_view` so they render inside the admin
  layout with the standard core components (`<.icon>`, `<.button>`,
  `TableDefault`, …).
- **Role opt-in flow** — `PhoenixKitCRM.RoleSettings` context
  (`list_enabled/0`, `list_eligible_roles/0`, `set_enabled/2`,
  `enabled?/1`) backed by `phoenix_kit_crm_role_settings`
  (`role_uuid` PK, FK to `phoenix_kit_user_roles`). System roles
  (Owner, Admin) are excluded from the eligible set; the rest can be
  toggled per role from the CRM settings page.
- **Per-user, per-scope view configuration** —
  `PhoenixKitCRM.UserRoleView` context backed by
  `phoenix_kit_crm_user_role_view` (`(user_uuid, scope)` unique;
  JSONB `view_config`; UUIDv7 PK). Scope is
  `:companies | {:role, role_uuid}`. `PhoenixKitCRM.ColumnConfig`
  declares available + default columns per scope and validates input.
- **Column-management mixin** —
  `use PhoenixKitCRM.Web.ColumnManagement` injects the seven event
  handlers (`show_column_modal`, `hide_column_modal`, `add_column`,
  `remove_column`, `reorder_selected_columns`,
  `update_table_columns`, `reset_to_defaults`) shared between
  `RoleView` and `CompaniesView`. The reusable
  `PhoenixKitCRM.Web.ColumnModal` function component drives drag-to-
  reorder selected columns + click-to-add available columns; UX
  matches the `PhoenixKit.Users` table column picker.
- **Companies subtab placeholder** — `CompaniesView` renders the
  table/card view with column picker and a "schema in development"
  banner. The legal-entity schema lands in a future release.
- **Runtime sidebar bootstrap** —
  `PhoenixKitCRM.SidebarBootstrap` (one-shot `Task` via
  `children/0`, `restart: :temporary`) registers per-role tabs into
  `PhoenixKit.Dashboard.Registry` under the `:phoenix_kit_crm_roles`
  namespace. Re-run from `PhoenixKitCRM.refresh_sidebar/0` after each
  `RoleSettings.set_enabled/2` call. No watcher GenServer.
- **Route module** — `PhoenixKitCRM.Routes` declares the
  parameterized `live "/admin/crm/role/:role_uuid"` route that
  resolves the runtime-registered role tabs. Defines
  `admin_routes/0` and `admin_locale_routes/0` with unique `:as`
  aliases; spliced into `phoenix_kit`'s `live_session
  :phoenix_kit_admin`.
- **`PhoenixKitCRM.Paths`** — centralized URL helpers (`index/0`,
  `companies/0`, `role/1`, `settings/0`) routed through
  `PhoenixKit.Utils.Routes.path/1` for prefix/locale handling.
- **Settings keys** — `crm_enabled` (module on/off, also reflected
  on the admin Modules page), `crm_companies_enabled` (Companies
  subtab visibility).
- **Test infrastructure** — `PhoenixKitCRM.Test.Repo`,
  `PhoenixKitCRM.DataCase` (auto-tags `:integration`, sandbox
  setup), `test_helper.exs` (db-availability check via `psql -lqt`,
  `uuid_generate_v7()` SQL function setup, ExUnit start). Integration
  tests are auto-excluded when the test DB is absent.
- **Tests** — 33 in total: behaviour and tab-shape tests
  (`phoenix_kit_crm_test.exs`), pure-function tests for
  `ColumnConfig` (`available_columns`, `default_columns`,
  `validate_columns`, `get_column_metadata`, cross-scope rejection)
  and `UserRoleView` (`scope_to_string`, `scope_from_string`
  including the malformed-input fallback path, the round-trip
  property, `default_config`).
- **`mix test.setup` / `mix test.reset`** aliases and `cli/0`
  `preferred_envs` so the alias auto-runs in `:test`. `:lazy_html`
  test-only dep for `Phoenix.LiveViewTest`.
- **Documentation** — `README.md` covers features, install, routes,
  database, settings keys, and dev workflow. `AGENTS.md` is the
  AI-agents guide modeled on `phoenix_kit_hello_world` and
  `phoenix_kit_staff` — covers the actual scaffold, runtime sidebar
  bootstrap pattern + known limitation, per-user column config,
  conventions, route-module + tab hybrid, test infrastructure, and
  versioning. PR review template + first review at
  `dev_docs/pull_requests/2026/1-add-crm-module/`.

### Notes

- Migrations for `phoenix_kit_crm_role_settings` and
  `phoenix_kit_crm_user_role_view` live in `phoenix_kit` core (V105),
  not in this repo. The parent app applies them via
  `mix phoenix_kit.install` / `mix phoenix_kit.update`.
- `enabled?/0` rescues errors and returns `false` so the module
  degrades gracefully when the DB isn't available (boot race,
  migration in progress).
- `refresh_sidebar/0` logs `Logger.warning` on Registry errors instead
  of silently rescuing — Registry API drift surfaces in logs rather
  than leaving stale role tabs.
- `UserRoleView.scope_from_string/1` falls back to `:companies` and
  logs a warning on malformed input — defends against data corruption
  causing render-time crashes.
