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

