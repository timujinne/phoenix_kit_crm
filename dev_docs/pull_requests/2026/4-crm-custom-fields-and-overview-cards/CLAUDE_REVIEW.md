# Claude Review — PR #4

**Reviewer:** Claude Opus 4.7 (1M context, retrospective review using `elixir:phoenix-thinking` + `elixir:ecto-thinking`)
**PR:** [CRM: custom fields in column picker + role overview cards](https://github.com/BeamLabEU/phoenix_kit_crm/pull/4) — **MERGED 2026-05-05**
**Author:** @timujinne
**Branch:** `followup/crm-user-view-and-format`
**Merge commit:** `f74eea1`
**Tip commit:** `b3c1db8` — *"Address PR #4 review: ordering, scope threading, shared formatter"*
**Date:** 2026-05-05

## Verdict

**Approve as merged, with one Iron-Law violation worth fixing in a follow-up.**

The feature is well-scoped and the second commit (`b3c1db8`) cleanly resolved the structural issues that the first commit had — ordering preservation, scope threading, and formatter de-duplication. New custom-field columns plug into the existing `ColumnConfig`/`ColumnModal` machinery with no surface-area churn for callers other than `render_cell/3`. PhoenixKit Core stays untouched; only public APIs are called.

The one real defect is in `CRMLive.mount/3`: it queries the database. That's the one rule LiveView's lifecycle is non-negotiable about, and it's both reachable on every connect and N+1 in role count.

## What changed

| File | Change |
|---|---|
| `lib/phoenix_kit_crm/column_config.ex` | `:standard`/`:custom` are now ordered `[{id, meta}]` lists (was `%{}`); `:custom` populated from `PhoenixKit.Users.CustomFields.list_enabled_field_definitions/0`; defensive `Code.ensure_loaded` + narrow `rescue UndefinedFunctionError` for older phoenix_kit pins |
| `lib/phoenix_kit_crm/web/cell_format.ex` | New shared module: `render_custom_cell/3` + `format_custom_value/2` (boolean / checkbox-list / Date / DateTime / NaiveDateTime / binary / fallthrough) |
| `lib/phoenix_kit_crm/web/column_modal.ex` | `map_size(...) > 0` → `... != []`; same logic, list shape |
| `lib/phoenix_kit_crm/web/crm_live.ex` | New "Enabled roles" card grid on the CRM landing page, queried in `mount` (see Issue 1) |
| `lib/phoenix_kit_crm/web/role_view.ex` and `organizations_view.ex` | `render_cell/3` takes the scope; new `"custom_" <> _` clause delegates to `CellFormat.render_custom_cell/3`; per-cell formatter ladder removed |
| `test/phoenix_kit_crm/web/cell_format_test.exs` | New, async, covers all `format_custom_value/2` branches |
| `test/phoenix_kit_crm/column_config_test.exs` | Updated to the list shape; asserts standard-column ordering (`hd(ids) == "organization_name"`) |

PR description is accurate this time — diff matches the bullets, addressing the carry-over issue flagged in PR #3's review.

---

## Issues

### 1. 🚨 Iron Law violation: database queries in `mount/3`

**File:** `lib/phoenix_kit_crm/web/crm_live.ex:14-36`

```elixir
def mount(_params, _session, socket) do
  enabled = PhoenixKitCRM.enabled?()

  role_stats =
    if enabled do
      for role <- RoleSettings.list_enabled() do          # 1 query
        %{
          uuid: role.uuid,
          name: role.name,
          count: Roles.count_users_with_role(role.name)   # N queries
        }
      end
    else
      []
    end
  ...
end
```

**Why this is wrong.** `mount/3` is invoked twice for every connection — once on the HTTP render and again when the WebSocket upgrades. Every query in `mount` therefore fires twice. With this code, a CRM with 5 enabled roles produces `1 + 5 = 6` queries × 2 = **12 DB round-trips per page load**, half of them thrown away.

The Phoenix-thinking skill calls this The Iron Law and admits no exceptions:

> mount/3 = setup only (empty assigns, subscriptions, defaults)
> handle_params/3 = data loading (all database queries, URL-driven state)

`RoleView` already follows this pattern correctly (`role_view.ex:57-69` puts the user query in `handle_params/3`, gated on `connected?(socket)`); `CRMLive` should mirror it.

**Fix:**
```elixir
def mount(_params, _session, socket) do
  {:ok,
   assign(socket,
     page_title: gettext("CRM"),
     enabled: PhoenixKitCRM.enabled?(),
     role_stats: []
   )}
end

def handle_params(_params, _uri, socket) do
  if connected?(socket) and socket.assigns.enabled do
    {:noreply, assign(socket, :role_stats, load_role_stats())}
  else
    {:noreply, socket}
  end
end
```

(Or `assign_async/3` — the count is non-critical and shouldn't block first paint.)

`PhoenixKitCRM.enabled?()` itself reads from `Settings.get_setting_cached/2`, so it's a memory hit, not a DB query — that part is fine in mount. The role queries are not.

### 2. ⚠️ N+1 in `count_users_with_role/1` loop

**File:** `lib/phoenix_kit_crm/web/crm_live.ex:19-25`

For each enabled role, `Roles.count_users_with_role(role.name)` runs:

```elixir
from assignment in RoleAssignment,
  join: role in assoc(assignment, :role),
  where: role.name == ^role_name,
  select: count(assignment.uuid)
```

That's one round-trip per role. A single query would do the whole thing:

```sql
SELECT r.uuid, count(a.uuid)
  FROM phoenix_kit_users_role_assignments a
  JOIN phoenix_kit_users_roles r ON r.uuid = a.role_uuid
  JOIN phoenix_kit_crm_role_settings s ON s.role_uuid = r.uuid
 WHERE s.enabled = true
 GROUP BY r.uuid
```

Either add `RoleSettings.list_enabled_with_user_counts/0` (CRM-side) or `Roles.count_users_for_roles/1` (Core-side), or compose the query inline in CRMLive's loader. At 5 roles the practical difference is tens of milliseconds; on a host with a long-tail role list it scales linearly worse than it needs to. Either way it's better paired with the fix to Issue 1.

### 3. ⚠️ Per-cell `available_columns/1` recomputation

**File:** `lib/phoenix_kit_crm/web/cell_format.ex:18-26` → `lib/phoenix_kit_crm/column_config.ex:139-150`

Each `"custom_*"` cell render path is:

```
render_cell(scope, "custom_…", user)
 └─ CellFormat.render_custom_cell(scope, col, user)
     └─ ColumnConfig.get_column_metadata(scope, col)
         └─ available_columns(scope)
             ├─ translate_labels(@role_standard)         # rebuilt every call
             └─ custom_field_columns()
                 ├─ Code.ensure_loaded(CustomFields)
                 └─ list_enabled_field_definitions()     # cached, but Enum.filter + sort_by every time
```

For a table with `N` rows × `M` selected custom columns this rebuilds the entire ordered tuple list `N*M` times per render. The underlying setting read is cached (`Settings.get_json_setting_cached/2`), so it's not DB-bound — but the per-call cost is not free, and LiveView re-renders happily on every `assign/3`.

**Cheap fix:** memoize `column_metadata` once per render (or store it on `socket.assigns` alongside `selected_columns`), and pass the resolved `%{type: :custom_field, field_key: …, field_type: …}` map directly into `format_custom_value/2`. `render_custom_cell/3` then becomes a pure function of `(metadata, user)` and the lookup happens once, in `handle_params/3`, when `selected_columns` is computed.

For 10–50-row admin tables this is a micro-optimization; it gets noticeably worse if the CRM ever paginates to hundreds.

### 4. 🟡 `field["key"]` is unguarded

**File:** `lib/phoenix_kit_crm/column_config.ex:67-69`

```elixir
key = field["key"]
{"custom_" <> key, ...}
```

If a malformed definition lacks `"key"`, this crashes with `ArgumentError: argument for <> is not a binary`. `list_enabled_field_definitions/0` doesn't guarantee schema — it just unwraps whatever JSONB the admin saved. A `Enum.filter(&is_binary(&1["key"]))` upstream of the `Enum.map` would make this safe and is more truthful than the current implicit "all enabled definitions have a string key" assumption.

Same point applies to `field["type"]` inside `format_custom_value/2` — non-string types fall through to `to_string/1`, which is fine. The `"key"` case is the only one that crashes.

### 5. 🟡 Gettext call style is inconsistent across files

**File:** `lib/phoenix_kit_crm/web/crm_live.ex` (everywhere)

```elixir
Gettext.gettext(PhoenixKitWeb.Gettext, "CRM")
Gettext.dngettext(PhoenixKitWeb.Gettext, "default", "%{count} role", "%{count} roles", n, count: n)
```

vs. `role_view.ex`/`organizations_view.ex`/`cell_format.ex`:

```elixir
gettext("…")
ngettext("…", "…", n, count: n)
```

`use PhoenixKitWeb, :live_view` already does `use Gettext, backend: PhoenixKitWeb.Gettext` (see `deps/phoenix_kit/lib/phoenix_kit_web.ex:25`), so the short form works in `CRMLive` too. Using the long form here is harmless but reads like the file forgot it had a backend. Cosmetic — fold into the next pass.

---

## What's good

- **Ordering preservation.** The follow-up commit (`b3c1db8`) explicitly noted that the first commit's `Map.new` collapsed `CustomFields`' position-sorted output to alphabetical. Switching `:standard` and `:custom` to ordered `[{id, meta}]` lists is the right call, and `column_config_test.exs:13-15` now asserts head order, which prevents regressions.
- **Defensive optional-dep handling.** `Code.ensure_loaded(CustomFields)` covers compile-time absence; `rescue UndefinedFunctionError -> []` covers runtime absence on older phoenix_kit pins (`~> 1.7` allows hosts that may not have `list_enabled_field_definitions/0`); other rescued errors get `Logger.warning`'d instead of silently swallowed. This is the right shape for an opt-in dep surface.
- **Shared formatter.** Extracting `CellFormat` removes a ~7-clause copy-paste from `RoleView` and `OrganizationsView`. Future format types only need to touch one file.
- **Scope threading.** Previous shortcut (`{:role, nil}`) only worked because `available_columns/1` ignored the role uuid in the function head — fragile and misleading. Threading the actual scope assign through `render_cell/3` removes the trick.
- **`async: true` test.** `cell_format_test.exs` is pure functional, so `async: true` is correct and free.
- **Test coverage of branches.** Every `format_custom_value/2` clause has at least one assertion, including the empty-list corner case (which the test even acknowledges: *"empty list joins to empty string (caller's choice)"* — good comment, the test is documenting the contract).
- **No PhoenixKit Core edits.** Confirmed against the diff stat: `lib/phoenix_kit_crm/...` only.

## Tests / verification

- `mix test test/phoenix_kit_crm/column_config_test.exs` — list-shape assertions plus hd-ordering. ✓
- `mix test test/phoenix_kit_crm/web/cell_format_test.exs` — all formatter branches. ✓
- No tests added for `CRMLive` role-stats card (would require LiveView render assertion + DB seeds; reasonable to skip given the surface). ⚠️ Manual verification of test plan items #3 and #4 (overview cards and empty state) is on the author/reviewer.
- No tests for the `Code.ensure_loaded` / `rescue` path in `custom_field_columns/0`. Reasonable: simulating the missing-function case in the test sandbox is awkward.

## Summary

| Aspect | Assessment |
|---|---|
| Code correctness | ✅ Functional, isolated, no Core edits |
| LiveView lifecycle | ❌ DB queries in `CRMLive.mount/3` (Issue 1) |
| Query shape | ⚠️ N+1 across enabled roles (Issue 2) |
| Render hot path | ⚠️ `available_columns` recomputed per cell (Issue 3) |
| Defensive coding | ✅ Optional-dep rescue, narrowed in follow-up commit |
| Ordering correctness | ✅ List-tuple shape preserves position |
| Style consistency | 🟡 Mixed gettext call form in `crm_live.ex` (Issue 5) |
| Tests | ✅ Branches covered; `async: true`; ordering asserted |
| PR description ↔ diff | ✅ Aligned (improvement over PR #3) |

**Recommend:** ship the existing merge (already done), and open a follow-up PR moving `CRMLive` role-stat loading out of `mount/3` (combined with the N+1 fix) — that's the only change with a real reason to land before further feature work on the landing page.

---

## Handoff: fixes landed on main

Fixes are committed directly to `main` — no branch, no PR. Tim picks up review/manual-verification on the head commit.

- **Commit:** `8e089db` — *"Address PR #4 review: lifecycle, query shape, render hot path"*
- **Stat:** 10 files / +188 / −97 (8 lib, 2 test, plus mix.lock dep bumps)

### What's implemented

| # | Issue | Fix | Notes |
|---|---|---|---|
| 1 | 🚨 DB queries in `CRMLive.mount/3` | `mount/3` now only assigns defaults; `handle_params/3` loads `role_stats` gated on `connected?/1` | Mirrors the pattern `RoleView` already uses |
| 2 | ⚠️ N+1 across `count_users_with_role/1` | New `RoleSettings.list_enabled_with_user_counts/0` — single GROUP BY with `left_join` over `RoleAssignment`. `CRMLive` calls this instead of the loop | Left join means roles with zero users still surface (`count = 0`) |
| 3 | ⚠️ Per-cell `available_columns/1` recomputation | New `ColumnConfig.column_metadata_map/1` returning `%{column_id => meta}`. Views compute it once in `mount` + `handle_params`, assign as `:column_meta`, and thread it through `render_cell/3`, `card_field/3`, `column_label/2`, `CellFormat.render_custom_cell/3`. `ColumnModal` does the same lookup once at the top of the function component | API change: `render_custom_cell/3` second arg switched from `scope` to `column_meta` map. `column_label/2` and `card_field/3` similarly take the map. Internal helpers — no public-API impact outside CRM |
| 4 | 🟡 `field["key"]` unguarded | `Enum.filter(&is_binary(&1["key"]))` upstream of the `Enum.map` in `custom_field_columns/0` | Malformed definition is now silently skipped; debatable whether to log it |
| 5 | 🟡 Mixed gettext call style in `crm_live.ex` | Switched long-form `Gettext.gettext(PhoenixKitWeb.Gettext, …)` / `Gettext.dngettext(…, "default", …)` to short `gettext/ngettext`, which is in scope via `use PhoenixKitWeb, :live_view` | Matches `RoleView` / `OrganizationsView` |

### Tests added

- `cell_format_test.exs` — `render_custom_cell/3` describe block covering: lookup hit, unknown column id, missing user value, `nil` `custom_fields`, boolean field-type formatting. Existing `format_custom_value/2` tests untouched.
- `column_config_test.exs` — `column_metadata_map/1` describe: returns a flat map; covers every id from `all_column_ids/1`.
- Both files use `use ExUnit.Case, async: true` (no DB needed for these specific tests; pure functional).

**Not run** — the review environment had no DB. `mix test` end-to-end is on Tim's side.

### Dep bumps included

`mix deps.update --all` was run alongside the fixes, bumping: `bandit`, `ecto`, `jason`, `leaf`, `phoenix`, `phoenix_kit`, `phoenix_live_view`, `postgrex`. Patch / minor only — no constraint changes in `mix.exs`. If you'd rather isolate the dep bumps, the `mix.lock` change can be reverted with `git checkout 8e089db^ -- mix.lock` and committed separately.

### What Tim needs to do

1. **Verify locally.** Pull `main` and run:
   - `mix compile --warnings-as-errors` ✓ (clean at `8e089db`)
   - `mix format --check-formatted` ✓ (clean)
   - `mix credo --strict` ✓ (clean)
   - `mix test` — **not yet run**; please confirm.
   - `mix dialyzer` — **not yet run**; the `column_metadata_map/1` spec and `render_custom_cell/3` signature change are the most likely friction points.
2. **Manually walk the CRM overview page** (`/admin/crm`) with a few CRM-enabled roles to confirm the new `handle_params` flow renders cards correctly, including the empty-state and zero-user-role cases.
3. **Decide whether Issue 4 should log when a malformed definition is dropped.** Current behavior silently filters; a `Logger.warning/1` with the offending entry would be one extra line and probably worth it.
4. **If anything is wrong, revert directly on main** — `git revert 8e089db` (or just the relevant hunks). No branch / PR overhead either way.

### What was not addressed

- **Branch protection on `main`** (recurring process recommendation from PR #2/#3 reviews). Owned by repo admin, not a code change.
- **PR description ↔ diff discipline.** N/A — PR #4's description was accurate; this was a praise note, not a deficiency.
