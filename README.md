# PhoenixKitCRM

CRM module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) — implements the `PhoenixKit.Module` behaviour for auto-discovery by a parent Phoenix application.

This is an early skeleton scaffolded from
[phoenix_kit_hello_world](https://github.com/BeamLabEU/phoenix_kit_hello_world).
The Companies subtab is a placeholder until the legal-entity schema lands;
roles and per-user view configuration are already wired up.

## Features

- **Admin sidebar** — `CRM` parent tab with **Overview** and (opt-in) **Companies** subtabs.
- **Role opt-in** — choose which non-system roles can access CRM; enabled roles get their own subtab under `/admin/crm/role/:role_uuid`.
- **Per-user column config** — each admin can pick which columns to show on the Companies and per-role pages; layout is persisted in `phoenix_kit_crm_user_role_view`.
- **Settings page** — toggle the module, opt roles in/out, and enable/disable the Companies section.
- **Auto-discovery** — no parent-app router edits; PhoenixKit picks the module up via the `@phoenix_kit_module` beam attribute.

## Installation

Add to the parent PhoenixKit app's `mix.exs`:

```elixir
# Local development
{:phoenix_kit_crm, path: "../phoenix_kit_crm"}

# or, once published / pinned to a tag
{:phoenix_kit_crm, "~> 0.1"}
```

Then `mix deps.get`. The module appears in **Admin > Modules** and the
sidebar automatically; toggle it on to expose `/admin/crm`.

## Routes

| Path                                   | LiveView                              |
|----------------------------------------|---------------------------------------|
| `/admin/crm`                           | `PhoenixKitCRM.Web.CRMLive`           |
| `/admin/crm/companies`                 | `PhoenixKitCRM.Web.CompaniesView`     |
| `/admin/crm/role/:role_uuid`           | `PhoenixKitCRM.Web.RoleView`          |
| `/admin/settings/crm`                  | `PhoenixKitCRM.Web.SettingsLive`      |

The `Companies` and per-role routes are gated by settings — the section
appears only after it's toggled on under **Admin > Settings > CRM**.

## Database

Two module-owned tables are required:

- `phoenix_kit_crm_role_settings` — which roles have CRM access enabled
- `phoenix_kit_crm_user_role_view` — per-user, per-scope view configuration

Following the PhoenixKit convention, **migrations live in `phoenix_kit`
core**, not in this repo. The parent app applies them via
`mix phoenix_kit.install` / `mix phoenix_kit.update`.

## Settings keys

- `crm_enabled` — module on/off (also reflected on the Modules page)
- `crm_companies_enabled` — Companies subtab visibility

## Development

```sh
mix deps.get
mix compile
mix test            # unit tests; integration tests excluded if no DB
mix precommit       # compile + format + credo --strict + dialyzer
```

For integration tests, create the test database once:

```sh
createdb phoenix_kit_crm_test
mix test.setup      # ecto.create + ecto.migrate against the test repo
```

See [`AGENTS.md`](AGENTS.md) for the development conventions, file layout,
and testing setup.

## License

MIT — see [LICENSE](LICENSE).
