# CRM Feature Inventory — what we have vs. what the others have

Gap analysis: current `phoenix_kit_crm` (v0.2.3) vs. the feature universe distilled
from ~80 CRMs (see `crm_feature_landscape.md`). Companion to that doc.

**Legend**
- ✅ **Have it** — shipped in `phoenix_kit_crm` today.
- 🟦 **Reuse-ready** — another PhoenixKit module or core already provides it; not yet
  wired into CRM (the work is integration, not greenfield).
- ❌ **Greenfield** — nothing in the ecosystem provides it; net-new build.

---

## 0. What phoenix_kit_crm has TODAY (the honest list)

It is a **thin view/config layer over PhoenixKit users + roles** — not yet a CRM.

| Feature | Status |
|---|---|
| Module on/off toggle | ✅ |
| Admin sidebar tab (CRM) + Overview/Organizations subtabs | ✅ |
| **Role opt-in** — choose which roles can access CRM; per-role user subtabs | ✅ |
| **Per-user column configuration** — pick visible columns per scope, persisted | ✅ |
| Organizations view — lists core users where `account_type="organization"` | ✅ |
| Per-role user list views | ✅ |
| Overview page — enabled-role cards + user counts | ✅ |
| Settings page (toggle + role opt-in + org-accounts gate) | ✅ |
| i18n (en/et/ru), gettext backend | ✅ |
| CSS-sources auto-wiring | ✅ |
| **No Contact / Company / Deal / Lead / Activity / Pipeline domain model** | ❌ |

The two genuinely useful, already-built pieces — **role opt-in** and **per-user
column views** — are things most CRMs *don't* ship early. Everything below is missing.

---

## 1. Core CRM objects (the spine) — table-stakes everywhere

| Feature | Status | Note |
|---|---|---|
| **Contacts / People** | ❌ | the foundational object; greenfield |
| **Companies / Organizations / Accounts** (real records) | ❌ | today only a thin "org = login user" view; real CRM companies aren't logins |
| **Leads** (+ qualify → convert) | ❌ | |
| **Deals / Opportunities** | ❌ | the heart; greenfield |
| **Activities / interaction timeline** | 🟦 | core `PhoenixKit.Activity` + `resource_uuid` filter — wire to CRM records |
| **Notes** | 🟦 | `phoenix_kit_comments` |
| **Tasks** | 🟦 | `phoenix_kit_projects` (tasks, assignees, deps) |
| **Products / line items** | 🟦 | `phoenix_kit_catalogue` |
| **Quotes / Invoices / Orders** | 🟦 | `phoenix_kit_billing` / `phoenix_kit_ecommerce` |
| **Custom fields / custom objects** | 🟦 | `phoenix_kit_entities` (13+ field types incl. `relation`, JSONB) |

## 2. Pipeline & deal management — the defining CRM surface

| Feature | Status |
|---|---|
| Visual drag-and-drop **Kanban pipeline** | ❌ |
| Customizable **stages** | ❌ |
| **Multiple pipelines** | ❌ |
| **Weighted forecast** (value × stage/deal probability) | ❌ |
| **Deal rotting / aging** (stalled-deal flag) | ❌ |
| Won/Lost outcomes + reasons | ❌ |
| Sales **goals / quotas** | ❌ |
| List ↔ Kanban ↔ Calendar views over same records | ❌ |

## 3. Activity & engagement

| Feature | Status | Note |
|---|---|---|
| Email send / templates | 🟦 | `phoenix_kit_emails` |
| 2-way email **sync** (Gmail/Outlook) | ❌ | |
| Email **open / click tracking** | ❌ | |
| Call logging | ❌ | |
| Meeting scheduler / calendar sync | ❌ | |
| **Sequences / cadences** (multi-step outreach) | ❌ | |
| Tasks + reminders / "what's next" queue | 🟦 | `phoenix_kit_projects` |
| Two-field call logging (Disposition + Sentiment) | ❌ | design-in pattern |

## 4. Lead management

| Feature | Status | Note |
|---|---|---|
| **Web forms / lead capture** | 🟦 | `phoenix_kit_entities` public forms |
| Lead **scoring** | ❌ | |
| **Assignment / routing** rules (round-robin/by-attribute) | ❌ | |
| Lead **qualify → convert** flow | ❌ | |
| Lead-source as first-class field + attribution | ❌ | |
| Duplicate detection / merge | ❌ | |

## 5. Automation & workflow

| Feature | Status |
|---|---|
| Workflow engine (**trigger → condition → action**, delay, branch) | ❌ |
| Auto-assignment | ❌ |
| Approval processes | ❌ |
| **Signal → rule → CTA/work-item → playbook** engine | ❌ |
| Process enforcement (Blueprint / BPM / state machine) | ❌ |
| Background jobs for the above | 🟦 (core Oban) |

## 6. Reporting / analytics & AI

| Feature | Status | Note |
|---|---|---|
| Dashboards / reports | 🟦 | core has some admin reporting; not CRM-specific |
| Forecast view (weighted) | ❌ | |
| Leaderboards / goal tracking | ❌ | |
| AI deal-health / win-probability | 🟦 | `phoenix_kit_ai` (engine available, not wired) |
| AI email drafting / assist | 🟦 | `phoenix_kit_ai` |
| Call / meeting **transcription + summary** | ❌ | |
| AI research / enrichment fields | ❌ | (ai could power it) |

## 7. Platform / admin

| Feature | Status | Note |
|---|---|---|
| Custom fields | 🟦 | `phoenix_kit_entities` |
| Custom objects | 🟦 | `phoenix_kit_entities` |
| Roles / permissions | ✅ | core + CRM role opt-in |
| **Per-user column / view config** | ✅ | already shipped |
| Record-level visibility / sharing | 🟦 | core scope/permissions (partial) |
| Import / export (CSV) | ❌ | |
| REST API | 🟦 | core router/API patterns |
| Webhooks | ❌ | |
| Mobile (responsive) | 🟦 | core admin is responsive; no native app |
| Activity / audit log | ✅ | core `Activity` |
| Multi-currency | 🟦 | `phoenix_kit_billing` currencies |
| i18n / multilang | ✅ / 🟦 | CRM has gettext; multilang content via entities/catalogue patterns |

## 8. The extensible-CRM spine (the 8 cross-industry extension points)

These are the abstractions that let one CRM become any vertical without forking
(re-derived independently in waves 2 & 3).

| Extension point | Status | Note |
|---|---|---|
| 1. **Polymorphic deal w/ subtypes** + outcome vocabularies + computed economics | ❌ | core design decision |
| 2. **Catalog/inventory entity** the deal is filed against | 🟦 | `catalogue` / `entities` |
| 3. **Typed, role-bearing contact↔deal edges** | ❌ | |
| 4. **Record-minting intake forms** + structured-feed ingestion | 🟦 | `entities` forms (ingestion = new) |
| 5. **Config-driven pipelines + stage-entry/exit automation hooks** | ❌ | |
| 6. **Merge-template + e-signature** as a stage action | 🟦 | `phoenix_kit_document_creator` (Google Docs/PDF); e-sign = new |
| 7. **Segment / population-based drip campaigns** | 🟦 | `phoenix_kit_newsletters` (lists, Oban delivery) |
| 8. **Outbound system-of-record sync adapter** | 🟦 | `phoenix_kit_sync` (P2P sync primitives) |

## 9. Advanced / vertical primitives (post-MVP module menu — all greenfield unless noted)

| Capability | Status | Likely home |
|---|---|---|
| Household / group **rollup** object | ❌ | new |
| Typed **reciprocal relationship graph** (+ relationship scoring / warm-intro) | ❌ | new |
| **Bookable resource + availability calendar + Booking/Registration** | ❌ | new (hospitality/field-service/health) |
| **Recurring subscription / membership lifecycle** | 🟦 | `phoenix_kit_billing` subscriptions (extend) |
| **Decrementing credit / pass balances** | ❌ | new |
| **Composite computed scores** (health/risk/eligibility scorecards) | ❌ | new (customer success) |
| **High-volume event / time-series store** | ❌ | new (usage/behavior ingestion) |
| **Case / Service-Request / Application state machine + SLA timers + routing** | ❌ | new |
| **Multi-dimensional attribution + splittable txns + soft credits** | ❌ | new (nonprofit/advancement) |
| **Property / Service-Location distinct from customer + installed assets** | ❌ | new (field service) |
| **Polymorphic transaction subtypes + schedule objects** | 🟦 | `billing` patterns |
| **Self-service portal + external identity** | 🟦 | core auth (extend) |
| **Compliance-as-infrastructure** (WORM archiving, audit, consent, e-sign, licensing) | 🟦/❌ | `emails`+core (partial) |
| **Mass topic-based notification** (subscriber/topic/bulletin) | 🟦 | `newsletters` |
| **Production / inventory ERP** (BOM/work-order/stock/MRP) | ❌ | **separate ERP module** (not CRM); reuse catalogue/billing/gantt/Oban |
| **Sales Agreements + account-based forecasting** (run-rate manufacturing CRM) | ❌ | new (CRM layer) |
| **Conversation intelligence / sequences / dialer** (T3 sales-engagement) | ❌ | new |

---

## Scoreboard

- ✅ **Have it:** ~6 features — all admin/config (role opt-in, per-user views, toggle,
  i18n, activity log, permissions). **Zero CRM domain.**
- 🟦 **Reuse-ready:** ~25 features — a large fraction of the universal core + spine is
  *already in the ecosystem* (entities, comments, emails, catalogue, billing, ai,
  projects, newsletters, sync, document_creator, Oban, core). The work is *wiring*, not
  inventing.
- ❌ **Greenfield:** the CRM heart — **Contacts, Companies, Leads, Deals, Pipeline/Kanban,
  forecast, lead routing, the automation/workflow engine, and the 8-point spine glue.**

**Read:** the differentiated build is small and well-bounded — the **core objects +
pipeline + the extensible spine**. Most everything else is reuse. This is exactly why
**Option C (hybrid)** fits: hand-build the spine, reuse the rest.
