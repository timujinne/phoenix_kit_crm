# PR #8 Review — interaction-tracker buildout + Phase 1/2 quality sweep

- **PR:** [#8](https://github.com/BeamLabEU/phoenix_kit_crm/pull/8) (`mdon/main` → `main`, merged as `0eb0344`)
- **Scope:** ~8,900 insertions / 91 deletions across 67 files — the contacts/companies/interactions
  buildout (contexts, schemas, LiveViews, components, attachments, PubSub) plus tests.
- **Reviewer:** Claude (Opus 4.8), post-merge.
- **Method:** Phoenix LiveView + Ecto lenses. Each finding verified against the producing/consuming
  code (callers grepped, snapshots traced into core Storage). Severities per `AGENTS.md`.

The PR is overwhelmingly net-new feature code and is in good shape — soft-delete round-trips, PubSub
producer/consumer shapes, atom-exhaustion safety, form hardening, and timeline preloads (no N+1) all
check out. Findings below are the exceptions, strongest first.

---

## BUG — MEDIUM

### 1. `version/0` reports the wrong version — `lib/phoenix_kit_crm.ex:45`
`def version, do: "0.1.0"` while `mix.exs` `@version` (and the CHANGELOG top entry) is `0.2.3`. The
two version sources documented in `AGENTS.md` have drifted: `@version` climbed 0.1.0 → 0.2.3 but the
`@impl PhoenixKit.Module` callback was never bumped. This callback is surfaced in the admin module
list, so the UI reports a stale module version.
**Fix:** source it from the project so they can't drift —
`def version, do: unquote(Mix.Project.config()[:version])` (compile-time capture) — or, at minimum,
bump the literal to match and add the version-sync test `AGENTS.md` already anticipates.

### 2. Trashed contacts leak into the company member roster + interactions rollup — `lib/phoenix_kit_crm/companies.ex:17-30` (`list_memberships/1`)
The query filters only by `company_uuid` and preloads `:contact`, with **no status filter**. Trashing
a contact only flips `status` → `"trashed"`; its `CompanyMembership` rows are left intact. So a trashed
contact keeps appearing in:
- the company's **Members roster** — `company_show_live.ex:52`, and
- the company's **aggregated interactions feed** — `company_interactions_component.ex:38`
  (`member_contact_uuids/1` → `Interactions.list_for_contacts/1`), surfacing the trashed contact's
  interactions too.

Every other list/count/search path correctly excludes `"trashed"`; this one is the gap.
**Fix:** join `Contact` and add `where: contact.status != "trashed"` (or reject trashed after preload).
Lock it in with a `companies_test.exs` case that trashes a member and asserts it drops out.

### 3. `set_as_avatar` trusts a client-supplied file uuid with no scope check — `lib/phoenix_kit_crm/web/media_component.ex:86` + `lib/phoenix_kit_crm/attachments.ex:493-498`
`handle_event("set_as_avatar", %{"uuid" => uuid}, …)` passes `uuid` straight to `Attachments.set_avatar/2`,
which only verifies the **record** isn't trashed and that `file_uuid` is a non-empty binary. It never
confirms the uuid is one of the record's own *Images*-folder files (or even an image). A forged
`set_as_avatar` event can therefore point any record's avatar at an arbitrary file uuid anywhere in
`phoenix_kit_files`; `avatar_url/1` then renders that file's thumbnail (a public URL) on the record
header and in lists. Note the asymmetry: the sibling `remove_file` → `Attachments.detach/2` *is*
folder-scoped. Impact is bounded (admin-scoped; integrity + thumbnail info-leak, not RCE) but it is a
real authorization gap.
**Fix:** in `set_avatar/2` (or the handler) confirm the file is home/linked in the record's Images
folder and is `file_type == "image"` before writing the pointer.

### 4. `update_interaction/4` silently re-derives "frozen" party snapshots and can wipe all parties — `lib/phoenix_kit_crm/interactions.ex:137-171, 218-243` *(latent — no caller today)*
Two problems in the update path (note: `update_interaction/4` has **zero callers** right now — there is
no interaction-edit UI yet — so this is a future trap, not a live bug):
- `replace_parties/2` unconditionally `delete_all`s every party and re-inserts them with
  `build_snapshot/1` recomputed from *current* contact data plus a fresh `captured_at`. This discards
  the snapshot frozen at log time, directly contradicting `InteractionParty`'s moduledoc ("freezes the
  party's profile as it was at log time … true to that moment even after the person changes role or is
  deleted"). Editing an interaction's body would silently rewrite all party snapshots to today's
  role/company.
- The `party_inputs \\ []` default means `update_interaction(interaction, attrs)` with no parties
  **deletes every party**. A public function shouldn't treat "omitted" as "clear all".
**Fix (when an edit path is built):** carry forward existing snapshots for unchanged parties, and
distinguish "not provided" (keep) from `[]` (clear), e.g. accept `nil` to skip reconciliation.

---

## IMPROVEMENT — HIGH

### 5. DB query in `mount/3` (Iron Law) — `lib/phoenix_kit_crm/web/contact_form_live.ex:17`
`mount/3` calls `Companies.list_companies()` (a real `Repo.all`). `mount/3` runs **twice** (static HTTP
render + WebSocket connect), so every form open issues the query twice. There is no auth/redirect
reason to keep it in mount — it's pure data loading.
**Fix:** move the load into `handle_params/3` (or into `assign_new_form/1` / `assign_edit_form/1`, both
already called from `handle_params`).

### 6. Inline uploader trusts client content-type / extension; `accept: :any`, no size limit, no magic-byte check — `lib/phoenix_kit_crm/web/interactions_component.ex:230-298`
`allow_upload(:attachments, accept: :any, max_entries: 10, …)` then `store_upload/3` derives `ext` from
`entry.client_name` and `mime` from `entry.client_type` (the **untrusted** browser-supplied type),
feeding `file_type(mime)` + `ext` into core `Storage.store_file_in_buckets/6`. Core stores under a
hash-derived path (so there is **no path traversal** here — verified), but it also sets the served
MIME from that same client extension, with no server-side content sniffing anywhere. Combined with
`accept: :any` and no `max_file_size` (relies on LiveView's 8 MB default), an authenticated user can
upload `evil.html` / `evil.svg` and get a public URL served as `text/html` / `image/svg+xml` — i.e.
stored-XSS *if* those URLs are same-origin. This mirrors a convention used across core (core's own
MediaSelectorModal feeds the same function), so it's hardening rather than a CRM-only regression, and
exploitability depends on core's serving origin.
**Fix:** restrict `accept:` to the expected types, set an explicit `max_file_size`, and rely on
server-side content validation rather than `entry.client_type`.

---

## IMPROVEMENT — MEDIUM

### 7. Unescaped `LIKE`/`ILIKE` wildcards + null-byte crash in search — `lib/phoenix_kit_crm/contacts.ex:140`, `lib/phoenix_kit_crm/companies.ex:119`
`like = "%#{q}%"` then `ilike(c.name, ^like)`. The value is parameterized (no SQLi), but `%`, `_`, `\`
in user input are not escaped → wildcard injection (typing `%` matches everything; `a_b` matches
`axb`), and `q` is not stripped of null bytes, so a `\x00` in the search box reaches Postgres ILIKE
and raises (the documented "null bytes crash Postgres" gotcha).
**Fix:** `String.replace(q, "\x00", "")` and escape `%`/`_`/`\` before building the pattern.

### 8. `column_modal/1` runs a DB query on every render, even when hidden — `lib/phoenix_kit_crm/web/column_modal.ex:34`
The stateless component calls `ColumnConfig.available_columns(@scope)` in its body, which runs
`CustomFields.list_enabled_field_definitions()` (a DB query). The `<.modal>` content is always in the
DOM (`show` only toggles CSS), so the host table page issues this custom-fields query on every
re-render whose assigns change (search keystroke / sort / paginate) while the picker is mounted.
**Fix:** load `available_columns` once in the host LiveView and pass it in, or gate the call on `@show`.

### 9. `role_view.ex` mount re-loads data that `handle_params` recomputes — `lib/phoenix_kit_crm/web/role_view.ex:17-54`
`mount/3` calls `ColumnConfig.column_metadata_map(scope)` (a DB read building `available_columns/1`),
but `handle_params/3:69` recomputes it — so the mount copy is wasted work on every connect. The
`enabled?` + `get_role_by_uuid` pair in mount is defensible (it gates the auth redirect); the
`column_metadata_map` load is not.
**Fix:** keep only the auth gate in mount; drop `column_metadata_map` (reloaded in `handle_params`).

### 10. LiveComponent `update/2` reloads everything with no change guard — `company_interactions_component.ex:20-35`, `interactions_component.ex:44-55`, `events_component.ex:47`, `media_component.ex:38-52`
Each `update/2` unconditionally re-runs its full data load (the company rollup is ~5-7 queries:
`member_contact_uuids` + `list_for_contacts` with `[:contact, :parties]` preload + file batch). Because
the host re-passes assigns on any of its own refreshes — e.g. the `send(self(), {:avatar_changed})` /
`{:put_flash, …}` round-trips from `media_component` — the heavy timelines reload even when nothing
relevant changed.
**Fix:** guard the heavy loads on a changed key, or reload only on an explicit trigger assign.

### 11. `get_by_user_uuid/1` and `list_by_uuids/1` lack the UUID-format guard the other accessors have — `lib/phoenix_kit_crm/contacts.ex:72-74, 46-47`; `lib/phoenix_kit_crm/companies.ex:51-52` *(latent)*
`get_contact`, `get_company`, `list_involving`, `list_memberships`, etc. all `Ecto.UUID.cast` first and
return `nil`/`[]` on a malformed id. `get_by_user_uuid` only guards `nil`; a malformed (non-nil) string
raises `Ecto.Query.CastError`. Same for a bad element in `list_by_uuids`. Inputs are server-derived
today (low real risk) but it's a latent raise and an inconsistency.
**Fix:** cast-guard like the sibling accessors.

### 12. PartyPicker JS `destroyed()` leaves the staging fallback timer running — `priv/static/assets/phoenix_kit_crm.js:176-179`
`destroyed()` clears the search debounce (`this.t`) but not `this.stageT`, the 3s fallback set in
`staging()`. If the hook is torn down mid-pick, `stageT` still fires `this.clear()` against detached
DOM. Harmless in effect but a stray timer.
**Fix:** add `clearTimeout(this.stageT)` to `destroyed()`.

### 13. Free-text `subject` written into activity metadata — `lib/phoenix_kit_crm/interactions.ex:211` *(judgment call)*
`log_interaction/3` records `"subject" => interaction.subject` in activity metadata. The code correctly
omits `target_uuid` and the free-text `body` (the reasoning in the comments is sound), but `AGENTS.md`'s
rule — "Never put PII (email / phone / free-text body) in activity metadata" — arguably covers `subject`
too, since it's user-typed free text that can carry PII (e.g. "Call re: his medical leave"). The authors
made a deliberate choice to keep the short subject; flagging for an explicit decision rather than
asserting a defect. **Not fixed** pending the maintainer's call on whether subject is exempt.

---

## NITPICK

- **`lib/phoenix_kit_crm/schemas/contact.ex:24-25`** — comment claims the `"trashed"` sentinel is
  "Allowed by the changeset's status validation list below," but `@statuses` is `~w(active inactive)`;
  trashing works only because `SoftDelete` uses `Ecto.Changeset.change/2`, bypassing validation. The
  comment is misleading.
- **`lib/phoenix_kit_crm/web/media_component.ex:394`** — `@phoenix_kit_current_user` is used in render
  with no `attr`/`assign_new`, so a host that omits it gets a render-time `KeyError` (the sibling
  `interactions_component` declares it as an `attr`).
- **`lib/phoenix_kit_crm/web/role_view.ex:94-95`** — `maybe_reload_role/2` assigns `:selected_columns`
  / `:column_meta` that `handle_params/3:68-69` immediately overwrites. Dead assigns; drop them.
- **`lib/phoenix_kit_crm/attachments.ex:322-327`** — `list_files_by_interaction/1` doc says "Two
  queries total … no FolderLinks," but the implementation also queries `FolderLink` + linked files
  (3-4 queries). Code is correct; the comment is stale.
- **`lib/phoenix_kit_crm/web/company_show_live.ex`** — unlike `ContactShowLive`, it never subscribes to
  PubSub, so its rollup/Events tabs don't live-update when a member's interaction changes. Likely
  intentional for a read-only rollup; noting for a deliberate decision.
- **`lib/phoenix_kit_crm/pub_sub.ex:17-26`** — topics are global (`"crm:contact:#{uuid}:interactions"`),
  not tenant-partitioned. The moduledoc frames this as a framework-wide gap mirroring other PhoenixKit
  modules, and the unguessable UUID bounds fan-out. Not introduced/regressed by this PR.

---

## Verified clean (checked, no action)

- **Soft-delete trash/restore round-trip** — prior status stashed in `metadata["trashed_from_status"]`,
  restored when still valid, falls back to `"active"`, stash cleared; `statuses()` excludes `"trashed"`
  so restore can't land back in trash; double-trash guarded in both contexts.
- **PubSub producer/consumer** — producer broadcasts `{:crm, event, %{interaction_uuid: uuid}}`; the sole
  consumer (`contact_show_live.ex:88`) matches; `involved_contact_uuids/1` is correct (subject + party
  uuids, nils dropped, deduped); update path broadcasts `old ++ new` so dropped contacts still refresh;
  subscribe/unsubscribe are symmetric and `connected?`-guarded.
- **No render-time N+1** — `i.parties` / `i.contact` are preloaded in `list_involving`/`list_for_contacts`;
  attachments are batch-loaded into a map; `company_cell` reads the preloaded membership.
- **No atom exhaustion** — no `String.to_atom`/`to_existing_atom` on params anywhere; scope is a tuple.
- **Forms** — name required + changeset-validated; blank-email-with-login rejected; typed input
  preserved on validation error; catch-all `handle_event/3` swallows forged events.
- **Mass-assignment** — `Contact.user_uuid` not castable (set via `link_user_changeset` only);
  `party_snapshot` overwritten server-side, never trusted from input.
- **Main module** — `enabled?/0` rescues → `false`; `children/0` Task is `restart: :temporary`; all
  `admin_tabs/0` paths hyphenated (satisfies the behaviour test); package `files` list all resolve.
- **JS XSS** — all interpolated values pass through `esc()` / `escAttr()` before `innerHTML`.

## Surfaced by the gate (not in the original review)

### 14. `mix dialyzer` emits 2 warnings — PR #8 broke the dialyzer gate — IMPROVEMENT-MEDIUM *(pre-existing, left as-is)*
Running the repo's gate (`mix precommit` → `quality.ci` → `dialyzer`) on PR #8's code
surfaces two warnings that pre-date this review (both in PR-#8-added files, in functions
none of the fixes below touch). There is no `.dialyzer_ignore` and `quality.ci` runs
`dialyzer` plainly, so the gate is currently red on `main`:

- **`contact_form_live.ex:201`** (`restore_form/6`) — `guard_fail`: `assign(:department, dept || "")`
  where dialyzer proves `dept` is always `binary()`, so the `|| ""` branch is dead.
- **`interactions_component.ex:369`** (`changeset_message/1`) — `pattern_match_cov`: the
  defensive catch-all `changeset_message(_)` is unreachable because the sole caller always
  passes an `%Ecto.Changeset{}`.

**Left unfixed deliberately:** both are intentional defensive idioms in a heavily-defensive
codebase, in code outside this review's fix scope. The first is a zero-risk one-token change
(`dept || ""` → `dept`); the second is a judgment call (removing a deliberate-but-dead
fallback). Flagging for the maintainer to decide — easy to apply if a green dialyzer gate is
wanted.

---

## Resolution — fixes applied this pass

All of #1–#12 were fixed, each with a locking test where one is meaningful. #13 (the `subject`
PII question) was left for a maintainer decision as noted. #14 (above) was left as-is.

| # | Fix | Test |
|---|---|---|
| 1 | `version/0` → `"0.2.3"` (matches mix.exs) | `phoenix_kit_crm_test.exs` asserts `version() == Mix.Project.config()[:version]` |
| 2 | `list_memberships/1` joins `Contact` and excludes `status == "trashed"` | `companies_test.exs` — trashed member drops from the roster |
| 3 | `set_avatar/3` now takes the resource type + `avatar_candidate?/3`; only an image in the record's own Images folder is accepted | `attachments_test.exs` — arbitrary uuid → `:not_record_image`, trashed → `:record_trashed` |
| 4 | `update_interaction` default `party_inputs` → `nil` (keep); `replace_parties` carries forward frozen snapshots by party identity | `interactions_test.exs` — nil keeps, snapshot preserved across an edit, `[]` clears |
| 5 | `contact_form_live` company load moved from `mount/3` into the form assigners | existing form tests |
| 6 | composer upload: curated `accept` allowlist (no html/svg/xml) + explicit `max_file_size` (25 MiB) | n/a (config) |
| 7 | `search_*` escape `% _ \` and strip null bytes (`like_pattern/1`) | contacts + companies tests — `%` matches literally, null byte tolerated |
| 8 | `column_modal` only queries `available_columns` when `@show` is true | n/a (render-gated) |
| 9 | `role_view` mount no longer loads `column_metadata_map` (handle_params does, on connect) | existing role tests |
| 10 | `update/2` guards: company-rollup keyed on company uuid; media keyed on `{uuid, kind}`; interactions reload on a host `refresh_token` (preserves PubSub live refresh) | existing LiveView tests |
| 11 | `get_by_user_uuid/1` + both `list_by_uuids/1` cast-guard malformed uuids | contacts + companies tests |
| 12 | JS `destroyed()` clears `stageT` | n/a (JS) |

**Gate status (this environment):**
- `mix format --check-formatted` ✓
- `mix compile --warnings-as-errors` ✓
- `mix credo --strict` ✓ (no issues)
- `mix deps.unlock --check-unused` ✓
- `mix dialyzer` — 2 warnings, both pre-existing PR #8 (finding #14); the fixes add **zero** new warnings
- `PHOENIX_KIT_PATH=../phoenix_kit mix test` — **68 passed, 0 failed, 101 excluded.** Postgres
  is unavailable in this environment, so the `:integration` tests (incl. the new DB-backed
  ones) auto-excluded per the repo's documented stance. All test files compiled; the new
  pure `version/0` test ran and passed. The new integration tests follow existing passing
  patterns but were not executed here (no DB).

---

## Out-of-repo to verify

- **Cascade depth on permanent delete** — schema `on_delete: :delete_all` doesn't recurse, so deleting a
  contact relies on DB-level `ON DELETE CASCADE` for `interaction_parties.interaction_uuid` and
  `.contact_uuid`. Migrations live in `phoenix_kit` core — worth confirming the installer sets those.
</content>
</invoke>
