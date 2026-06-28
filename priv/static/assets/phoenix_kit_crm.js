// Prebuilt LiveView hooks for phoenix_kit_crm. Declared via `js_sources/0`;
// core's `:phoenix_kit_js_sources` compiler concatenates this (IIFE-wrapped)
// into the host's `phoenix_kit_modules.js` and folds `window.PhoenixKitCRMHooks`
// into `window.PhoenixKitHooks`.
window.PhoenixKitCRMHooks = window.PhoenixKitCRMHooks || {};

// CrmWhenWarnings — DISPLAY-ONLY helper for the interaction "When" field.
// Storage stays server-side (profile-tz -> UTC). This compares the field to the
// browser's live clock/timezone and writes advisory warnings into a sibling
// [data-when-warning] element:
//   • the time is in the past (the prefill went stale while the form sat open),
//   • the time is in the future,
//   • this device's timezone differs from the user's profile timezone.
// The field's value is a wall-clock time in the user's PROFILE timezone, whose
// offset (hours) is passed via data-profile-offset.
(function () {
  function fmtOffset(h) {
    return "UTC" + (h >= 0 ? "+" + h : h);
  }
  function esc(s) {
    var d = document.createElement("div");
    d.textContent = s;
    return d.innerHTML;
  }

  window.PhoenixKitCRMHooks.CrmWhenWarnings = {
    mounted() {
      this.warnEl = document.getElementById(this.el.dataset.warningTarget || "");
      this.setNowEl = document.getElementById(this.el.dataset.setnowTarget || "");
      this._h = () => this.refresh();
      this.el.addEventListener("input", this._h);
      this.timer = setInterval(this._h, 20000); // catch drift while the form sits open
      this.refresh();
    },
    updated() {
      this.refresh();
    },
    destroyed() {
      this.el.removeEventListener("input", this._h);
      clearInterval(this.timer);
    },
    refresh() {
      var offset = parseInt(this.el.dataset.profileOffset || "0", 10);
      var warns = [];

      var browserOffset = -new Date().getTimezoneOffset() / 60;
      if (browserOffset !== offset) {
        warns.push(
          "Your timezone is set to " +
            fmtOffset(offset) +
            ", but this device is " +
            fmtOffset(browserOffset) +
            ". Times are saved using your profile timezone."
        );
      }

      var val = this.el.value;
      var isNow = false;
      if (val) {
        // Field is profile-local wall-clock → its true UTC instant.
        var fieldUtc = Date.parse(val + ":00Z") - offset * 3600 * 1000;
        if (!isNaN(fieldUtc)) {
          // Round DOWN to whole minutes (the field has minute precision, so this
          // is the wall-clock minute difference — "4 min ago" until the 5th ticks).
          var diffMin = Math.floor((Date.now() - fieldUtc) / 60000);
          if (diffMin >= 1) {
            warns.push(
              "This is " +
                diffMin +
                " minute" +
                (diffMin === 1 ? "" : "s") +
                " in the past."
            );
          } else if (diffMin < 0) {
            warns.push("This time is in the future.");
          } else {
            isNow = true; // same minute as the current time
          }
        }
      }

      if (this.warnEl) {
        this.warnEl.innerHTML = warns
          .map(function (w) {
            return "<div>⚠ " + esc(w) + "</div>";
          })
          .join("");
      }

      // "Set to now" is only useful when the field isn't already "now".
      if (this.setNowEl) this.setNowEl.classList.toggle("hidden", isNow);
    },
  };
})();

// PartyPicker — the "involved parties" typeahead. The dropdown is rendered and
// shown ENTIRELY client-side (instant: opening, the "Add … as free text" row,
// and the spinner), so nothing visual waits on the server. The server only runs
// the actual contact/staff DB search and returns rows via `push_event`
// ("crm_party_results"). Picks/Enter push back to the component, which owns the
// staged-party chips. Icon/loading classes are kept in the CSS bundle by a
// hidden safelist span in the component template.
(function () {
  function esc(s) {
    var d = document.createElement("div");
    d.textContent = s == null ? "" : String(s);
    return d.innerHTML;
  }
  function escAttr(s) {
    return esc(s).replace(/"/g, "&quot;");
  }
  function iconClass(kind) {
    if (kind === "staff") return "hero-identification";
    if (kind === "contact") return "hero-user";
    return "hero-pencil";
  }

  window.PhoenixKitCRMHooks.PartyPicker = {
    mounted() {
      this.dd = document.getElementById(this.el.dataset.dropdown);
      // Push events to the component that owns this input (LiveView resolves the
      // nearest data-phx-component from the element).
      this.target = this.el;
      this.results = [];
      this.searching = false;
      this.limit = 8; // PAGE size; bumped by "Load more"
      this.hasMore = false;
      this.loadingMore = false;

      this.el.addEventListener("input", () => this.onInput());
      this.el.addEventListener("keydown", (e) => this.onKeydown(e));
      this.el.addEventListener("focus", () => {
        if (this.el.value.trim()) this.render();
      });

      this._docClick = (e) => {
        if (!this.el.contains(e.target) && !this.dd.contains(e.target)) this.close();
      };
      document.addEventListener("click", this._docClick);

      // mousedown (not click) so a pick registers before the input's blur closes things.
      this.dd.addEventListener("mousedown", (e) => this.onPick(e));

      this.handleEvent("crm_party_results", (payload) => {
        if (this.stagingNow) return; // a pick is in flight; don't repaint results
        if (this.el.value.trim() !== (payload.q || "")) return; // stale response
        var incoming = payload.results || [];
        if (this.loadingMore) {
          // "Load more" — append only rows not already shown, so what the user
          // has already seen keeps its exact position (the server re-orders as
          // the limit grows; we don't propagate that to the visible list).
          var seen = {};
          this.results.forEach((r) => {
            seen[r.kind + ":" + r.uuid] = true;
          });
          this.results = this.results.concat(
            incoming.filter((r) => !seen[r.kind + ":" + r.uuid])
          );
        } else {
          this.results = incoming;
        }
        this.hasMore = !!payload.has_more;
        this.searching = false;
        this.loadingMore = false;
        this.render();
      });

      // Server confirms the pick was staged (chip rendered) — clear the input.
      this.handleEvent("crm_party_staged", () => {
        this.stagingNow = false;
        clearTimeout(this.stageT);
        this.clear();
      });
    },

    destroyed() {
      document.removeEventListener("click", this._docClick);
      clearTimeout(this.t);
      clearTimeout(this.stageT);
    },

    onInput() {
      var q = this.el.value.trim();
      if (!q) {
        this.close();
        return;
      }
      this.searching = true;
      this.results = []; // drop stale results while a new query is in flight
      this.limit = 8; // reset paging for a new query
      this.hasMore = false;
      this.loadingMore = false;
      this._restoreScroll = null;
      this.render();
      clearTimeout(this.t);
      this.t = setTimeout(() => this.search(q), 180);
    },

    search(q) {
      this.pushEventTo(this.target, "search_party", { q: q, limit: this.limit });
    },

    loadMore() {
      this.limit += 8;
      this.loadingMore = true;
      this._restoreScroll = this.scrollEl ? this.scrollEl.scrollTop : null;
      this.render(); // swaps the "Load more" row for a spinner, keeps results + scroll
      clearTimeout(this.t);
      this.search(this.el.value.trim());
    },

    onKeydown(e) {
      if (e.key === "Enter") {
        e.preventDefault();
        var q = this.el.value.trim();
        if (q) {
          this.pushEventTo(this.target, "stage_text", { name: q });
          this.staging();
        }
      } else if (e.key === "Escape") {
        this.close();
      }
    },

    onPick(e) {
      var btn = e.target.closest("[data-pick]");
      if (!btn) return;
      e.preventDefault();
      if (btn.dataset.pick === "more") {
        this.loadMore();
        return;
      }
      if (btn.dataset.pick === "text") {
        var q = this.el.value.trim();
        if (!q) return;
        this.pushEventTo(this.target, "stage_text", { name: q });
      } else {
        this.pushEventTo(this.target, "stage_party", {
          kind: btn.dataset.kind,
          uuid: btn.dataset.uuid,
          label: btn.dataset.label,
        });
      }
      this.staging();
    },

    // While the pick round-trips to the server (stage + re-render the chip),
    // show a spinner in the dropdown instead of leaving a blank gap.
    staging() {
      this.stagingNow = true;
      clearTimeout(this.t); // cancel any pending search
      var tAdding = esc(this.el.dataset.tAdding || "Adding…");
      this.dd.innerHTML =
        '<div class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/60">' +
        '<span class="loading loading-spinner loading-xs"></span>' +
        tAdding +
        "</div>";
      this.open();
      clearTimeout(this.stageT);
      this.stageT = setTimeout(() => {
        this.stagingNow = false;
        this.clear();
      }, 3000); // fallback if the confirm never arrives
    },

    render() {
      var q = this.el.value.trim();
      if (!q) {
        this.close();
        return;
      }
      // i18n strings passed from the server via data-* (gettext-translatable).
      var tSearching = esc(this.el.dataset.tSearching || "Searching…");
      var tAddPrefix = esc(this.el.dataset.tAddPrefix || "Add");
      var tAddSuffix = esc(this.el.dataset.tAddSuffix || "as free text");

      var tMore = esc(this.el.dataset.tMore || "Load more");
      var tLoadingMore = esc(this.el.dataset.tLoadingMore || "Loading…");

      // Pinned top: the search spinner.
      var top = "";
      if (this.searching) {
        top +=
          '<div class="flex items-center gap-2 px-3 py-2 text-sm text-base-content/60 border-b border-base-200">' +
          '<span class="loading loading-spinner loading-xs"></span>' +
          tSearching +
          "</div>";
      }

      // Scrollable result list (capped height) + the Load-more row.
      var list = "";
      this.results.forEach((r) => {
        list +=
          '<button type="button" data-pick="result" data-kind="' +
          escAttr(r.kind) +
          '" data-uuid="' +
          escAttr(r.uuid) +
          '" data-label="' +
          escAttr(r.label) +
          '" class="flex items-center justify-between w-full px-3 py-2 hover:bg-base-200 text-left">' +
          '<span class="flex items-center gap-2 min-w-0">' +
          '<span class="' +
          iconClass(r.kind) +
          ' w-4 h-4 shrink-0 text-base-content/50"></span>' +
          '<span class="truncate">' +
          esc(r.label) +
          "</span></span>" +
          '<span class="text-xs text-base-content/50 shrink-0 ml-2 truncate">' +
          esc(r.sublabel) +
          "</span></button>";
      });
      if (this.loadingMore) {
        list +=
          '<div class="flex items-center justify-center gap-2 px-3 py-2 text-xs text-base-content/50">' +
          '<span class="loading loading-spinner loading-xs"></span>' +
          tLoadingMore +
          "</div>";
      } else if (this.hasMore) {
        list +=
          '<button type="button" data-pick="more" class="w-full px-3 py-2 text-xs text-center text-primary hover:bg-base-200">' +
          tMore +
          "</button>";
      }

      // Pinned bottom: the "add as free text" row.
      var bottom =
        '<button type="button" data-pick="text" class="flex items-center gap-2 w-full px-3 py-2 hover:bg-base-200 text-left border-t border-base-200">' +
        '<span class="hero-plus-mini w-4 h-4 shrink-0 text-base-content/50"></span>' +
        "<span>" +
        tAddPrefix +
        ' "' +
        esc(q) +
        '" ' +
        tAddSuffix +
        "</span></button>";

      this.dd.innerHTML =
        top + '<div data-scroll class="max-h-56 overflow-y-auto">' + list + "</div>" + bottom;

      this.scrollEl = this.dd.querySelector("[data-scroll]");
      if (this._restoreScroll != null && this.scrollEl) {
        this.scrollEl.scrollTop = this._restoreScroll;
        // keep the saved position across the intermediate "Loading…" render;
        // only release it once the new results have rendered.
        if (!this.loadingMore) this._restoreScroll = null;
      }
      this.open();
    },

    open() {
      this.dd.classList.remove("hidden");
    },
    close() {
      this.dd.classList.add("hidden");
      this.dd.innerHTML = "";
    },
    clear() {
      this.el.value = "";
      this.results = [];
      this.searching = false;
      this.stagingNow = false;
      clearTimeout(this.stageT);
      this.close();
      this.el.focus();
    },
  };
})();
