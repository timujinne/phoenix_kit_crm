# Claude Review — PR #5

**Reviewer:** Claude Opus 4.7 (1M context, retrospective review using `elixir:phoenix-thinking` + `elixir:elixir-thinking`)
**PR:** [Add per-module Gettext backend for sidebar tab labels](https://github.com/BeamLabEU/phoenix_kit_crm/pull/5) — **MERGED 2026-05-08**
**Author:** @timujinne
**Branch:** `feature/per-module-i18n`
**Tip commit:** `922ce7b` — *"Add per-module Gettext backend for sidebar tab labels"*
**Date:** 2026-05-08

## Verdict

**Approve as merged. One real translation gap to clean up in a follow-up; everything else is style/process.**

The structural change is right: stop translating tab labels at module-evaluation time (which silently froze the boot-time locale into the registry), and instead carry plain `msgid` strings + a `gettext_backend:` reference so `Tab.localized_label/1` can resolve per-request. Ownership of the catalogue moves from the host app's `PhoenixKitWeb.Gettext` into the package's own `PhoenixKitCRM.Gettext`, which is the only sustainable model for a publishable module.

The graceful-degradation story (`Tab.new!` silently dropping `gettext_backend:` on `phoenix_kit ≤ 1.7.105`, i18n tests auto-excluded when `Tab.localized_label/1` isn't loaded) is a clean way to publish the consumer side ahead of the upstream API landing. No regression on older `phoenix_kit` because the old `gettext()` wrappers were already producing boot-locale English in practice.

The one substantive defect is a translation-coverage gap: column labels declared in `@role_standard` / `@organizations_standard` (`Email`, `Username`, `Full Name`, …) are routed through `Gettext.gettext(PhoenixKitCRM.Gettext, &1)` at runtime, but those msgids are **not** in `priv/gettext/default.pot`, so they fall back to English in ru/et regardless of locale.

## What changed

| File | Change |
|---|---|
| `lib/phoenix_kit_crm/gettext.ex` | New `PhoenixKitCRM.Gettext` module — `use Gettext.Backend, otp_app: :phoenix_kit_crm` |
| `lib/phoenix_kit_crm.ex` | All four `Tab` registrations (3 admin + 1 settings) converted from `%Tab{}` struct literal to `Tab.new!(...)` with `gettext_backend: PhoenixKitCRM.Gettext`. `gettext()` wrappers around `"CRM"`, `"Overview"`, `"Organizations"` stripped to plain strings. `use Gettext, backend: PhoenixKitWeb.Gettext` removed at the module level |
| `lib/phoenix_kit_crm/column_config.ex` | Backend swapped `PhoenixKitWeb.Gettext` → `PhoenixKitCRM.Gettext`, including the explicit `Gettext.gettext(PhoenixKitCRM.Gettext, &1)` long-form call inside `translate_labels/1` |
| `lib/phoenix_kit_crm/web/column_modal.ex`, `web/cell_format.ex` | Backend swapped `PhoenixKitWeb.Gettext` → `PhoenixKitCRM.Gettext`. `gettext()` macro call sites unchanged |
| `priv/gettext/default.pot` + `priv/gettext/{en,ru,et}/LC_MESSAGES/default.po` | New — 19 msgids: 3 manually-maintained Tab labels + 16 auto-extracted from `column_modal.ex` + `cell_format.ex`. `ru` fully translated; `et` translates Tab labels + `Overview`/`Organizations`, leaves `column_modal`/`cell_format` strings empty (graceful fallback to msgid) |
| `mix.exs` | `:gettext` added to `extra_applications`, `{:gettext, "~> 1.0"}` added to deps, `priv` added to `package files:`, `@version` 0.2.1 → 0.2.2 |
| `mix.lock` | `phoenix` 1.8.6 → 1.8.7 (patch), `leaf` 0.2.12 → 0.2.13 (patch), `decimal` 2.3.0 → **3.0.0** (major) — drive-by deps update. See Issue 4 |
| `test/test_helper.exs` | Conditional ExUnit exclude for `:requires_phoenix_kit_i18n_api` based on `function_exported?(PhoenixKit.Dashboard.Tab, :localized_label, 1)` |
| `test/phoenix_kit_crm/i18n_test.exs` | New — 4 smoke tests: every tab carries the expected backend; ru/et resolve known msgids; unknown locale falls back to msgid |
| `CHANGELOG.md` | New `[0.2.2]` entry |

PR description matches the diff. The "Deliberately untouched" section is accurate and well-reasoned (`settings_live.ex` uses host `:live_view` so the host's Gettext backend wins by macro injection; `sidebar_bootstrap.ex` builds dynamic role tabs from runtime user input, so a `gettext_backend:` field would be meaningless there).

---

## Issues

### 1. ⚠️ Column labels in `ColumnConfig` are translated but not extractable

**Files:** `lib/phoenix_kit_crm/column_config.ex:24-42` + `:99-103`

```elixir
@role_standard [
  {"email", %{label: "Email", required: false, type: :email}},
  {"username", %{label: "Username", required: false, type: :string}},
  {"full_name", %{label: "Full Name", required: false, type: :string}},
  {"status", %{label: "Status", required: false, type: :status}},
  {"registered", %{label: "Registered", required: false, type: :datetime}},
  {"last_confirmed", %{label: "Last Confirmed", required: false, type: :datetime}},
  {"location", %{label: "Location", required: false, type: :location}}
]
# ...
defp translate_labels(list) do
  Enum.map(list, fn {k, v} ->
    {k, Map.update!(v, :label, &Gettext.gettext(PhoenixKitCRM.Gettext, &1))}
  end)
end
```

The labels (`"Email"`, `"Username"`, `"Full Name"`, `"Status"`, `"Registered"`, `"Last Confirmed"`, `"Location"`, plus `"Organization"`/`"Contact"` from `@organizations_standard`) reach `Gettext.gettext/2` at runtime. But because they're stored in a module attribute and looked up dynamically — *not* wrapped in the `gettext()` macro — `mix gettext.extract` can't see them. Confirmed against the committed pot:

```
$ grep msgid priv/gettext/default.pot
msgid "CRM"
msgid "Overview"
msgid "Organizations"
msgid "All columns selected"
msgid "Apply"
msgid "Available"
msgid "Cancel"
msgid "Click to add"
msgid "Custom"
msgid "Customize columns"
msgid "Defaults"
msgid "Drag selected columns to reorder, or click an available column to add it."
msgid "Drag to reorder"
msgid "No"
msgid "No columns selected"
msgid "Remove"
msgid "Selected"
msgid "Standard"
msgid "Yes"
```

None of `Email`, `Username`, `Full Name`, `Status`, `Registered`, `Last Confirmed`, `Location`, `Organization`, `Contact` are present. With `Gettext.put_locale(PhoenixKitCRM.Gettext, "ru")`, every column header in the role/organizations table renders English — silently. The customize-columns modal renders translated `"Customize columns"` / `"Apply"` / `"Cancel"` (since those use the macro), but the column list inside the modal stays English.

This is not a structural bug — the wiring works — it's a coverage gap. The `Selected` column header on the right side of the picker reads "Email", "Username", … in English; in ru, the surrounding chrome reads Russian, the column names don't. Visibly mixed.

**Two options to fix:**

- **(a) Add the labels to the manually-maintained section of `default.pot`** alongside the Tab labels, and run `mix gettext.merge priv/gettext`. The author already documented this as the maintenance contract: *"Tab labels are not extracted automatically by `mix gettext.extract` … so those entries are maintained manually."* The same argument applies to these column labels.
- **(b) Wrap the labels with `gettext()` at definition site** so extraction picks them up. This means moving the literals out of the module attribute into a function — `gettext()` requires a literal string at the call site. Bigger refactor; not worth doing solely for extraction.

(a) is the right call. Same authoring discipline as the Tab labels; one PR to add the missing msgids to the pot + ru/et po files.

Per `feedback_publish_means_publish.md`: this is a real translation hole on shipped 0.2.2; fix-forward in 0.2.3 rather than reverting.

### 2. 🟡 Pot/po process: locale-fragile asserts pass against pre-merge phoenix_kit

**File:** `test/phoenix_kit_crm/i18n_test.exs:15`

```elixir
use ExUnit.Case, async: false
```

`async: false` is required because `Gettext.put_locale/2` mutates a process-dictionary key that's keyed by backend module — but this also serializes every test in the file. Fine for now (4 tests), but the typical way to make these async is to push the locale through an opt arg on the called function or rely on Gettext's own `with_locale/2`. If this file grows, consider:

```elixir
Gettext.with_locale(PhoenixKitCRM.Gettext, "ru", fn ->
  assert Tab.localized_label(tab) == "Обзор"
end)
```

…which scopes the locale switch and would let the suite go back to `async: true` once the assertions don't share global state.

The smaller cosmetic point: `assert tab.gettext_domain == "default"` (line 40) tests Core's struct default value, not anything this PR contributes. Either drop it or replace with a positive assertion that the domain matches the file under `priv/gettext/<locale>/LC_MESSAGES/<domain>.po`.

### 3. 🟡 Long-form `Gettext.gettext/2` call in `column_config.ex` is one-off; not aligned with the rest of the package

**File:** `lib/phoenix_kit_crm/column_config.ex:99-103`

```elixir
defp translate_labels(list) do
  Enum.map(list, fn {k, v} ->
    {k, Map.update!(v, :label, &Gettext.gettext(PhoenixKitCRM.Gettext, &1))}
  end)
end
```

Everywhere else in this PR we use the short macro form (`gettext("…")`). Here we have to use the long form because the input is data-driven (a string captured from a module attribute), not a literal — short-form is a compile-time macro that requires literal msgids. So technically correct, but worth a comment explaining why this one site looks different from the rest of the file (and why `mix gettext.extract` can't see it). One line:

```elixir
# Long-form call (not the macro) — labels come from module-attribute data,
# not literal strings, so `gettext()` can't be used and `mix gettext.extract`
# won't pick these up. The msgids are maintained manually in `default.pot`.
```

This is a CLAUDE.md-style "no-comments-by-default" exception: the comment explains a non-obvious *why*, not a *what*.

### 4. 🟡 Major `decimal` bump rolled in alongside the i18n work

**File:** `mix.lock`

```
- "decimal": {:hex, :decimal, "2.3.0", ...}
+ "decimal": {:hex, :decimal, "3.0.0", ...}
```

`decimal` 2 → 3 is a major-version bump. PhoenixKit pins via `ecto`/`postgrex` so this PR isn't picking it up directly, but it's still a transitive dep change that has nothing to do with the i18n feature being shipped. The PR description doesn't mention it.

This pattern (drive-by dep refresh during a feature PR) was also flagged in PR #4's handoff, with the same reasoning: it makes bisecting future regressions noisier. For a patch release, prefer either (a) keeping the lock untouched on feature PRs and bumping deps in their own PR, or (b) calling out the bump explicitly in the PR description so reviewers can sanity-check the major-version transitive.

Decimal 3.0 release notes are mostly internal restructure — unlikely to break anything CRM uses — but the discipline matters.

### 5. 🟢 Process nit: `then(fn e -> ... end)` chain in `test_helper.exs`

**File:** `test/test_helper.exs:105-108`

```elixir
exclude =
  []
  |> then(fn e -> if repo_available, do: e, else: [:integration | e] end)
  |> then(fn e -> if i18n_api_available, do: e, else: [:requires_phoenix_kit_i18n_api | e] end)
```

Equivalent to:

```elixir
exclude =
  [
    if(!repo_available, do: :integration),
    if(!i18n_api_available, do: :requires_phoenix_kit_i18n_api)
  ]
  |> Enum.reject(&is_nil/1)
```

…which scans straighter. Either is fine. Filed under cosmetics.

---

## What's good

- **Right diagnosis, right fix.** The old `label: gettext("CRM")` form translated at module-load time, freezing the locale into the registry. That meant every host app saw English regardless of the user's locale, no matter how cleanly the host's locale plug was wired up. Stripping the wrapper and routing translation through `Tab.localized_label/1` (which reads `Process.get(Gettext.Backend.locale_key(...))` per request) is the only correct shape. Documented clearly in the PR description.
- **Backend ownership moved into the package.** `use Gettext, backend: PhoenixKitWeb.Gettext` is removed from `phoenix_kit_crm.ex`, `column_config.ex`, `column_modal.ex`, and `cell_format.ex`. The package no longer reaches into the host's macro namespace for its own translations — the right boundary for a publishable module.
- **`Tab.new!(...)` over `%Tab{...}` struct literal.** Goes through Core's constructor, which presumably validates the `gettext_backend:` field exists and is a Gettext backend module. On older `phoenix_kit` releases that don't know about the field, it's silently dropped (acceptable: graceful-degrade). On the future release that ships PR #522, the field gets enforced. Either way the consumer code is forward-compatible.
- **Conditional test exclude.** `function_exported?/3` runtime check on `PhoenixKit.Dashboard.Tab.localized_label/1` is cleaner than a hard version pin in `mix.exs`. Tests auto-enable when the host bumps `phoenix_kit` past PR #522 — no follow-up edit on this side.
- **Russian catalogue fully translated; Estonian deliberately partial.** The author explicitly notes (in the PR body and as empty `msgstr ""` in `default.po`) that Estonian translations for `column_modal`/`cell_format` strings are deferred to someone with idiomatic Estonian — which produces fallback-to-msgid (English) at runtime rather than empty strings. Correct fallback choice.
- **`Deliberately untouched` reasoning.** `settings_live.ex` (host's web module owns Gettext via macro injection) and `sidebar_bootstrap.ex` (dynamic role names are user data, not msgids) — both calls are correct. Documenting them in the PR description prevents the next reviewer from filing them as oversights.
- **CHANGELOG entry.** Concise, names the upstream PR dependency, calls out graceful degradation. No restructuring or feature creep.
- **`async: true` not promised.** The i18n tests sensibly use `async: false` because they touch process-keyed locale state. No false claim of async-safety.

## Tests / verification

- `mix test test/phoenix_kit_crm/i18n_test.exs` — auto-skipped on `phoenix_kit 1.7.105`; runs and passes against the future PR #522 release.
- `mix test` overall — i18n tests excluded via the test_helper conditional; nothing else affected.
- `mix gettext.extract` — would *not* refresh the Tab-label msgids (those live as plain strings in `Tab.new!(label: ...)` not in macro calls). The author has documented this in the pot file's header comment, so the manual-merge contract is explicit.
- `mix gettext.extract` would also miss the `@role_standard` / `@organizations_standard` labels — see Issue 1.
- No tests asserting the column-config labels translate (because they don't, currently — see Issue 1).

## Summary

| Aspect | Assessment |
|---|---|
| Code correctness | ✅ Per-module backend wired correctly, no host-app coupling |
| Lifecycle | ✅ No changes to mount/3 / handle_params/3 — pre-existing patterns preserved |
| Translation coverage | ❌ `ColumnConfig` standard column labels not in pot (Issue 1) |
| Graceful degradation | ✅ Conditional test exclude, `Tab.new!` field-drop tolerance |
| Backend ownership | ✅ Catalogue lives under `priv/gettext/`, owned by the package |
| API discipline | ✅ `Tab.new!` over struct literal — forward-compatible |
| Documentation | ✅ "Deliberately untouched" reasoning + manual-pot maintenance contract documented in pot header |
| Tests | 🟡 Smoke-level only; `gettext_domain == "default"` asserts Core default (Issue 2) |
| Dep hygiene | 🟡 `decimal` 2 → 3 transitive bump unannounced (Issue 4) |
| PR description ↔ diff | ✅ Aligned; behaviour matrix is precise |

**Recommend:** ship the existing merge (already done at `922ce7b`). Open one follow-up PR to:

1. Add `Email`, `Username`, `Full Name`, `Status`, `Registered`, `Last Confirmed`, `Location`, `Organization`, `Contact` to `priv/gettext/default.pot` under the manually-maintained Tab-labels section, then `mix gettext.merge priv/gettext` and translate in `ru/et`.
2. Add the explanatory comment in `column_config.ex#translate_labels/1` explaining why the long-form `Gettext.gettext/2` call is used there.

These are bug-fix grade — patch release `0.2.3` is justified.

The `decimal` bump and the `then`-chain refactor in `test_helper.exs` are not worth a follow-up on their own; fold into whatever lands next.
