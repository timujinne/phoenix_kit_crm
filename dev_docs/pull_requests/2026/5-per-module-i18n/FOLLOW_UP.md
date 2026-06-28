# PR #5 — per-module i18n — Follow-up

Triaged 2026-06-28 during the quality sweep. Four of five `CLAUDE_REVIEW.md`
findings were already resolved; the fifth is a release/CHANGELOG note that is
boss-only and is surfaced rather than edited here.

## Fixed (pre-existing)

- ~~[BUG-MEDIUM] Column labels missing from the pot file~~ — all column labels
  now in the manually-maintained `priv/gettext/default.pot` section.
- ~~[IMPROVEMENT-MEDIUM] Missing rationale comment in `translate_labels`~~ —
  comment explains why long-form `Gettext.gettext/2` is used (labels come from
  module attributes; macro extraction can't see them).
  `lib/phoenix_kit_crm/column_config.ex:99-102`.
- ~~[IMPROVEMENT-MEDIUM] Test locale-switching via process-dict mutation~~ —
  tests use `Gettext.with_locale/2`; `async: true` restored.
  `test/phoenix_kit_crm/i18n_test.exs`.
- ~~[NITPICK] Redundant `gettext_domain == "default"` assertion + `then/2`
  chains~~ — removed / simplified. `i18n_test.exs`, `test/test_helper.exs`.

## Skipped (with rationale)

- **[IMPROVEMENT-MEDIUM] `decimal` 2→3 transitive bump not noted in CHANGELOG
  (v0.2.2)** — **surfaced to Max, not edited.** CHANGELOG / release notes are
  boss-only (no agent version/CHANGELOG edits). The bump is already shipped in
  `mix.lock`; documenting a past release entry is a release-owner action.

## Files touched

None — verification-only.

## Verification

Re-verified against current `lib/` on 2026-06-28; `mix compile` clean.

## Open

None. (The CHANGELOG note above is a boss-owned release item, not module work.)
