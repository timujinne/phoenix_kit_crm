# PR #7 — CRM pages i18n — Follow-up

Triaged 2026-06-28 during the quality sweep. Every `CLAUDE_REVIEW.md` item was
verified against current code and is already resolved. No new work required.

## Fixed (pre-existing)

- ~~`ColumnManagement` macro's undocumented `use Gettext` requirement~~ —
  moduledoc now documents it; both host views carry
  `use Gettext, backend: PhoenixKitCRM.Gettext`.
  `lib/phoenix_kit_crm/web/column_management.ex:10-13`,
  `organizations_view.ex:13`, `role_view.ex:9`.
- ~~Macro-injected flash strings not extractable~~ — `"Columns updated"` /
  `"Failed to save columns"` use the bare `gettext/1` macro so
  `mix gettext.extract` picks them up. `column_management.ex:109,114`.
- ~~Residual `PhoenixKitWeb.Gettext` references~~ — none remain
  (`grep PhoenixKitWeb.Gettext lib/` → no matches); full migration to
  `PhoenixKitCRM.Gettext`.
- ~~Translation coverage (en/et/ru) for new msgids~~ — all filled.
  `priv/gettext/{en,ru,et}/LC_MESSAGES/default.po`.

## Skipped (with rationale)

- `mix gettext.extract --check-up-to-date` reports drift by design — a CI-gate
  concern, not a code issue; noted as a future-ticket only.

## Files touched

None — verification-only.

## Verification

Re-verified against current `lib/` on 2026-06-28; `mix compile` clean.

## Open

None.
