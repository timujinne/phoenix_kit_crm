# PR #11 Review — PhoenixKit.SchemaPrefix for runtime named-schema (`--prefix`) support

- **PR:** [#11](https://github.com/BeamLabEU/phoenix_kit_crm/pull/11) (`mdon/main` → `main`, merged as `a4a2a3f`)
- **Scope:** ~80 insertions / 317 deletions across 12 files — `use
  PhoenixKit.SchemaPrefix` added to every table-backed schema, a conformance test
  enforcing it repo-wide, the `phoenix_kit` version pin bumped to `>= 1.7.189`
  (+ the resulting `mix.lock` refresh), the hand-rolled `PartyPicker` JS hook
  replaced by core's `<.search_picker>` component, and the now-dead JS deleted.
- **Reviewer:** Claude (Sonnet 5), post-merge.
- **Method:** Ecto + Phoenix LiveView lenses. Traced `PhoenixKit.SchemaPrefix`
  into core to confirm it's a no-op compile-time macro when no prefix is
  configured; traced the `<.search_picker>` swap's `icon`/event-name contract
  against core's actual component + JS hook to rule out a Tailwind-purge or
  wiring regression.

Clean mechanical PR — no findings.

---

## Verified clean (checked, no action)

- **`use PhoenixKit.SchemaPrefix` on all 7 table-backed schemas** — every schema
  with a `schema "phoenix_kit..."` block (`RoleSetting`, `Company`,
  `CompanyMembership`, `Contact`, `Interaction`, `InteractionParty`,
  `UserRoleViewConfig`) now has it directly after `use Ecto.Schema`, matching the
  new `test/schema_prefix_conformance_test.exs` grep-based guard. Read the macro
  in core (`phoenix_kit/lib/phoenix_kit/schema_prefix.ex`): it sets
  `@schema_prefix Application.compile_env(:phoenix_kit, :prefix)`, which compiles
  to `nil` (no-op, current behavior unchanged) when no `--prefix` install config
  is set — this repo has none, so nothing changes for existing installs. `Schemas
  .PartyRole` (added in the later-merged PR #10) already includes it, so the
  conformance test's repo-wide grep passes.
- **`<.search_picker>` swap (`interactions_component.ex`)** — the deleted
  `PartyPicker` JS hook's event names (`search_party` / `crm_party_results` /
  `stage_party` / `stage_text` / `crm_party_staged`) all match the new
  component's `search_event` / `results_event` / `pick_event` / `text_event` /
  `staged_event` attrs, and the existing `handle_event("search_party"/"stage_party"
  /"stage_text", ...)` clauses are untouched — server-side wiring is unchanged,
  only the client half moved into core.
- **New `icon:` key on search results** (`icon: "hero-user"` for contacts,
  `icon: "hero-identification"` for staff) — checked against core's
  `search_picker.ex` moduledoc contract (`%{kind, uuid, label, sublabel?, icon?}`,
  defaulting to `hero-user` client-side if omitted) and its compiled JS
  (`escAttr(r.icon || "hero-user")`) — the new keys are exactly what the swapped-in
  component expects.
- **No Tailwind-purge regression from deleting the old hidden safelist span** — the
  removed block also deleted a `<span class="hidden ... hero-user hero-identification
  hero-pencil hero-plus-mini">` that existed solely so those literal class strings
  appeared in a file Tailwind's `:phoenix_kit_css_sources` compiler scans (the old
  JS hook lived in `priv/static/assets/*.js`, which isn't part of that scan). All
  four classes remain as literal tokens elsewhere in this module's own `.ex` files
  regardless: `hero-user`/`hero-identification` are now literal in
  `interactions_component.ex`'s own `search_parties/4`/`staff_results/2` (this PR),
  and `hero-user`/`hero-identification`/`hero-plus-mini` are already literal in that
  file's staged-party-chip markup (lines ~675-683, pre-existing); `hero-pencil` is
  literal in `contacts_live.ex:186` and `companies_live.ex:178`. Confirmed core's
  Tailwind source-scanning compiler does a raw-text scan per `@source` directory
  (no HEEx-aware parsing), so all of these are picked up regardless of which file
  they live in.
- **`mix.lock` diff is a mechanical `phoenix_kit` version bump** — the transitive
  dependency churn (ex_aws, hackney 1.x→4.x, certifi/idna majors, new
  h2/quic/webtransport/keyfob/eqrcode, dropped httpoison/ueberauth_apple/jose)
  all resolves from core's own updated dependency tree at `1.7.189`, not from
  anything this repo's `mix.exs` added directly (the only edit there is the
  version constraint itself).

## NITPICK

- No LiveView test exercises `interactions_component.ex`'s party-search flow
  before or after this PR (pre-existing gap, not introduced here) — worth a
  follow-up `search_party`/`stage_party` LiveView test at some point, but out of
  this PR's scope.

---

## Gate status (this environment, run once for both merged PRs' combined code)

- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓ (zero warnings)
- `mix credo --strict` ✓ (no issues, 79 files)
- `PHOENIX_KIT_PATH=../phoenix_kit mix test` — **74 passed, 0 failures** (130
  excluded; Postgres unavailable here, `:integration` tests auto-exclude per the
  repo's documented stance)
- `mix dialyzer` ✓ — 3 pre-existing errors, all covered by `.dialyzer_ignore.exs`
  (0 unnecessary skips, 0 new warnings).

No findings for this PR — nothing to fix.
