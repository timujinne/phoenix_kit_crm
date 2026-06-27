# PR #4 — CRM custom fields & overview cards — Follow-up

Triaged 2026-06-28 during the quality sweep. All five `CLAUDE_REVIEW.md` findings
were verified against current code and are already resolved (fixed before this
sweep, in the merged PR or a later commit). No new work required.

## Fixed (pre-existing)

- ~~[BUG-CRITICAL] DB queries in `mount/3`~~ — `mount/3` assigns defaults only;
  `handle_params/3` loads `role_stats` gated on `connected?/1`.
  `lib/phoenix_kit_crm/web/crm_live.ex:14-30`.
- ~~[BUG-HIGH] N+1 in `count_users_with_role/1` loop~~ — replaced by
  `list_enabled_with_user_counts/0` (single GROUP BY + left_join).
  `lib/phoenix_kit_crm/role_settings.ex:49-66`.
- ~~[BUG-HIGH] Per-cell `available_columns/1` recomputation~~ —
  `column_metadata_map/1` computes once per render, threaded as `:column_meta`.
  `lib/phoenix_kit_crm/column_config.ex:129-132`, `role_view.ex:51,68`,
  `cell_format.ex:20-30`.
- ~~[BUG-MEDIUM] `field["key"]` unguarded~~ —
  `Enum.filter(&is_binary(&1["key"]))` upstream of the map.
  `lib/phoenix_kit_crm/column_config.ex:66`.
- ~~[NITPICK] Gettext call style inconsistent in `crm_live.ex`~~ — short-form
  `gettext`/`ngettext` throughout. `lib/phoenix_kit_crm/web/crm_live.ex`.

## Skipped (with rationale)

None.

## Files touched

None — verification-only; all findings were already resolved.

## Verification

Re-verified against current `lib/` on 2026-06-28; `mix compile` clean. Suite:
78 pass / 3 fail — the 3 failures are pre-existing `role_settings_integration_test`
setup bugs (seeded-role conflicts), unrelated to this PR, scheduled for Phase 2 / C8.

## Open

None.
