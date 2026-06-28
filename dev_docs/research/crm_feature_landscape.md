# CRM Feature Landscape — Research Synthesis

**Status:** Research phase. Not a commitment to scope.
**Date:** 2026-06-24
**Purpose:** Survey what major CRM platforms offer, then map it against the PhoenixKit
ecosystem to decide what `phoenix_kit_crm` should actually build (vs. reuse).

Sources: live web research across 9 platforms in 4 segments — enterprise
(Salesforce Sales Cloud, MS Dynamics 365 Sales), SMB/mid-market suites (HubSpot,
Zoho), pipeline-first (Pipedrive, Close, Freshsales), and modern/open-source
(Twenty, Attio, Monday CRM, Folk). Full per-platform inventories captured in the
research transcripts; this document is the synthesis.

---

## 0. Where the module is today (baseline)

`phoenix_kit_crm` (v0.2.3) is currently a **thin view/config layer over PhoenixKit
users + roles**, scaffolded from `hello_world`. It has **no CRM domain model**:

- 2 tables, both in **core** migration V105: `crm_role_settings` (which roles get
  CRM access) and `crm_user_role_view` (per-user column layout).
- "Organizations" = core users where `account_type = "organization"` (core V92).
- "Roles" views = core users grouped by role, with a per-user column picker.
- No Contact / Company / Deal / Lead / Activity / Pipeline schema anywhere.

So the actual CRM is greenfield. This research scopes it.

---

## 1. The universal CRM core (table-stakes — all 9 platforms agree)

Stripping every platform's signature extras, the irreducible CRM is:

### The four entities (non-negotiable)
1. **Contacts / People** — individuals.
2. **Companies / Organizations / Accounts** — orgs, with contacts linked to them.
3. **Deals / Opportunities** — the transaction: a **value** + a **stage** → **Won/Lost**.
4. **Activities** — calls, emails, meetings, tasks, notes on a **per-record timeline**.

*(A distinct **Lead** object — a pre-qualified prospect held separately until
"converted" into Contact+Company+Deal — is common but variable. Pipedrive and
Freshsales keep Leads separate; Close makes the Lead = the account; HubSpot gates
Leads to paid tiers. Minimum viable: a qualified/unqualified flag.)*

### Pipeline & deals (the heart)
- **Visual drag-and-drop Kanban** by stage — the single most defining CRM feature.
- **Customizable stages** + **multiple pipelines**.
- **Weighted value** = deal value × stage/deal probability → **forecast view**.
- **Stalled-deal detection** ("rotting"/aging/at-risk) — present in every pipeline CRM.
- **Won/Lost** outcomes + basic **sales goals/quota**.

### Activity & communication
- **2-way email sync** with templates + **open/click tracking**.
- Logged calls/meetings/tasks on the timeline; **tasks + a "what's next" view**.
- **Meeting scheduler / calendar sync**.
- **Sequences / cadences** (multi-step outreach) — depth varies, but all offer some form.

### Lead capture & qualification
- **Web forms** to capture; **CSV import**; **assignment/routing** rules.
- A path to **qualify → convert** a prospect into Contact/Deal.

### Automation
- A **trigger → condition → action** workflow engine with **delay** + **branching**.
- **Auto-assignment** of leads/deals.

### Reporting
- **Dashboards + reports** on pipeline, conversion, activity, revenue.
- A **forecast view** driven by weighted deal value; **leaderboards/goals**.

### Platform / admin
- **Custom fields** on every object.
- **Roles/permissions + record-level visibility**.
- **Import/export**, **REST API + webhooks**, **mobile**, integration marketplace.

### AI is now baseline, not premium
Across *every* segment, these are now expected core, not differentiators:
**deal-health/win-probability insights, AI email drafting, call/meeting
transcription + summarization.** A CRM shipping in 2026 is expected to have them.

---

## 2. Tiered feature map (MVP → frontier)

| Tier | Features |
|------|----------|
| **T0 — MVP** | Contacts, Companies, Deals, Activities; one Kanban pipeline w/ custom stages; manual Won/Lost; tasks + notes; CSV import; custom fields; basic list/detail + activity timeline; role-based access |
| **T1 — Standard** | Multiple pipelines; weighted forecast view; deal rotting; web-form lead capture; Leads + qualify/convert; email sync + open/click tracking; email templates; saved views + filters; dashboards/reports; assignment rules; REST API + webhooks |
| **T2 — Advanced** | Workflow automation engine (trigger/condition/action + delay/branch); sequences/cadences; lead scoring; products/line-items on deals; quotes; goals/quotas; field-level permissions; calendar + meeting scheduler; duplicate detection/merge |
| **T3 — Frontier** | AI deal-health + win-probability; AI email assist; call/meeting transcription + summary; AI research/enrichment fields; autonomous lead/SDR agents; MCP server; CPQ; territories; opportunity splits; predictive forecasting |

---

## 3. The modern paradigm (Twenty / Attio / Monday / Folk)

The next-gen CRMs diverge sharply from Salesforce/HubSpot, and these patterns are
the most relevant to an open-source Elixir build:

1. **Object/attribute data model, runtime-customizable** — custom objects + fields
   in minutes from the UI, no admin/engineer. The CRM bends to the business.
2. **Pipelines-as-views, not siloed modules** — a "pipeline" is just a Kanban view
   over a list/object. Table ↔ Kanban ↔ Calendar over the *same* records.
3. **Spreadsheet-like, keyboard-driven UI** (Notion/Linear/Airtable feel).
4. **The CRM self-populates** — email/calendar sync auto-creates & enriches
   People/Companies; waterfall enrichment fills firmographics; relationship
   intelligence surfaces "who has the strongest connection."
5. **AI is structural** — AI *fields/attributes*, research agents, AI actions
   inside the workflow engine; nearly all now ship an **MCP server**.
6. **Developer-first** — REST/GraphQL, webhooks, app SDKs, marketplaces.

### Twenty is the closest architectural reference (open-source, self-hostable)
- **5 standard objects:** People, Companies, Opportunities, Notes, Tasks.
- **Metadata-driven objects:** core tables `Object`/`Field` describe the model;
  **custom objects become REAL Postgres tables/columns** per tenant (not EAV),
  and the **GraphQL schema is regenerated at runtime** from metadata — no deploy.
- Field-type catalog worth mirroring: Text, Long Text, Number, Currency, Date,
  Datetime, Boolean, Rating, Select/Multi-Select, Email, Phone, Address,
  **Relation** (1-many / many-many), Links, JSON, Rich Text, Actor.
- ⚠️ **Security lesson:** Twenty's user-supplied serverless functions had an
  RCE CVE (CVE-2026-26720). If we ever run user code, sandbox it hard.

### Three patterns to steal
- **(a)** Twenty's *metadata → real tables → runtime-typed API*.
- **(b)** *Pipelines as views over shared objects* (Attio/Folk), not a siloed deal table.
- **(c)** Field taxonomy: **native / computed-"smart" / custom**, plus
  **interaction-derived fields** (last/total interaction, strongest connection)
  and **AI fields** as first-class column types.

---

## 4. PhoenixKit reality check — reuse map (the key insight)

`phoenix_kit_crm` should **not** reinvent the ecosystem. Much of the universal CRM
core is already built in sibling modules / core. The genuinely CRM-specific surface
is small.

| CRM capability | Already in the PhoenixKit ecosystem? | Reuse path |
|---|---|---|
| **Custom objects + fields (metadata-driven)** | ✅ **`phoenix_kit_entities`** — dynamic content types, 13+ field types incl. **`relation`**, JSONB storage, form builder, hierarchical `parent_uuid`, multilang, soft-delete | This is our "Twenty data model." Strong candidate to back custom CRM objects |
| **Companies / Organizations** | ◐ core users `account_type="organization"` (V92) + current CRM Organizations view | Decide: keep as auth-users, or model standalone Company records (most CRM companies are NOT logins) |
| **Contacts / People** | ◐ core `Users` (account_type person); `phoenix_kit_staff` People | Likely a NEW standalone Contact (most contacts aren't users) — but can link to a user when one exists |
| **Activity timeline** | ✅ **core `PhoenixKit.Activity`** (used by every module) + `resource_uuid` filter | Reuse directly for the per-record timeline |
| **Notes / comments** | ✅ **`phoenix_kit_comments`** (hard-dep pattern proven by staff) | Reuse for deal/contact notes |
| **Products / catalogue** | ✅ **`phoenix_kit_catalogue`** (items, pricing chain) | Reuse for deal line-items / products |
| **Quotes / Invoices / Orders / Subscriptions** | ✅ **`phoenix_kit_billing`** (+ `ecommerce`) | Reuse for quote→order→invoice |
| **Email send/templates/tracking** | ✅ **`phoenix_kit_emails`** (SES pipeline, templates, delivery logs) | Reuse for email engagement |
| **AI (enrichment, scoring, email assist, translation)** | ✅ **`phoenix_kit_ai`** (OpenRouter, prompts, completions, translation pipeline) | Reuse for AI fields / scoring / drafting |
| **Tasks + dependencies + assignees** | ◐ **`phoenix_kit_projects`** (tasks, assignments, polymorphic assignee, Gantt) | Possible reuse for CRM tasks/activities |
| **Roles / permissions / per-user views** | ✅ core + **current CRM module** (role opt-in, column config) | Already built — keep |
| **Background jobs (sequences, sync, scoring)** | ✅ core **Oban** | Reuse for cadences + enrichment workers |
| **Forms / public submissions** | ✅ **`phoenix_kit_entities`** public forms | Reuse for web-to-lead capture |

### What's genuinely greenfield (CRM-specific, nothing covers it)
1. **Deals / Opportunities** + **Pipeline/Stages** + **Kanban board** + weighted
   forecast + rotting — *the heart of a CRM, and nothing in the ecosystem has it.*
2. **Lead** object + qualify/convert flow + lead scoring.
3. **Sales sequences/cadences** (multi-step outreach orchestration).
4. **Contact ↔ Company ↔ Deal relationship graph** as a first-class CRM surface.
5. The **CRM-specific glue**: tying reused modules (emails, catalogue, billing,
   activity) onto deal/contact records as one coherent workspace.

---

## 5. The strategic fork in the road (decision for Max)

How much of the data model do we own vs. delegate to `phoenix_kit_entities`?

- **Option A — Standalone domain (Pipedrive/Close style).** Own
  `Contact`/`Company`/`Deal`/`Pipeline`/`Stage`/`Activity` Ecto schemas (core
  migrations, like every other module). Fixed, opinionated, fast to build, typed.
  *Con:* custom objects/fields would need separate work later.

- **Option B — Metadata-driven on `phoenix_kit_entities` (Twenty/Attio style).**
  CRM objects are entities; everything is custom-fieldable from day one. Most
  "modern" and DRY.
  *Con:* pipeline/deal mechanics (weighted forecast, rotting, stage probability)
  are awkward to express purely as generic entities; performance + query ergonomics.

- **Option C — Hybrid (recommended).** Own the **opinionated core objects**
  (Contact, Company, Deal, Pipeline/Stage) as real schemas for the mechanics that
  need to be fast and typed — *and* lean on `phoenix_kit_entities` for **custom
  objects + custom fields** so users can extend without code. Reuse
  `Activity`/`comments`/`emails`/`catalogue`/`billing`/`ai` for the rest.
  This matches how the ecosystem is already factored and gives both a real
  pipeline CRM and the modern "extend it yourself" story.

---

## 6. Recommended MVP (T0) — for discussion

Smallest thing that is a *real* CRM, maximizing ecosystem reuse:

1. **Contact** + **Company** schemas (standalone records; optional link to a core
   user / staff person when one exists). Company ≠ login account.
2. **Deal** + **Pipeline** + **Stage** with a **drag-and-drop Kanban** and a
   weighted forecast total; manual Won/Lost; deal rotting flag.
3. **Activity timeline** per Contact/Company/Deal via **core `PhoenixKit.Activity`**;
   **notes via `phoenix_kit_comments`**.
4. **Tasks** (reuse `phoenix_kit_projects` if it fits, else minimal own).
5. **CSV import** + **custom fields** (via `phoenix_kit_entities`).
6. Keep the existing **role opt-in + per-user column views**.

Deliberately deferred to later tiers: email sync, sequences, lead scoring, AI
fields, quotes/CPQ, multiple pipelines, web-form capture (then reuse entities forms).

---

## 7. Open questions to resolve before building

1. **Companies = auth users or standalone records?** (Current module assumes
   users; real CRMs need non-user companies.) — biggest model decision.
2. **Option A / B / C** for the data model (see §5).
3. Is **Contact** distinct from core `User` and `staff.Person`, or unified?
4. Which **reuse deps** are acceptable as hard deps (comments, emails, catalogue,
   billing, ai, projects, entities) vs. soft/optional?
5. Multi-tenant scope: single-org install vs. Twenty-style per-workspace isolation?

---

# Wave 2 — deeper survey (~35 more platforms)

Second research pass across five segments, each focused on what's *distinctive*
vs. the universal core in §1: open-source/self-hostable, relationship-intelligence,
sales-engagement/revenue-intelligence, vertical/industry, and remaining commercial.

## 8. Open-source / self-hostable CRMs — the storage spectrum (THE key finding)

EspoCRM, SuiteCRM, Vtiger, Odoo CRM, Frappe/ERPNext CRM, Krayin, Corteza, Monica.
Because runtime-customizable objects/fields is *our* central design question, how
these projects store user-defined data is the single most important input:

| Storage strategy | Platforms | One-line |
|---|---|---|
| **Real tables, one column per field** (DDL on customize) | EspoCRM, Odoo, Frappe/ERPNext, Vtiger | metadata registry drives `CREATE/ALTER TABLE`; queries stay native-relational |
| **Base table + "custom" sidecar table** | SuiteCRM (`_cstm`), Vtiger (`cf`) | core columns in `<module>`, custom columns isolated in a joined sidecar |
| **EAV / single shared record table** | Krayin, Corteza (default) | generic value store, no DDL on customize, but joins/perf/queryability suffer |
| **Fixed opinionated schema (not customizable)** | Monica | hand-modeled domain; no runtime objects |

**Reference architectures:**
- **EspoCRM** — entire app is **JSON metadata** (`entityDefs`/`clientDefs`/`scopes`/
  `aclDefs`…) in a layered override hierarchy (core→module→custom→instance) merged
  into one cached blob; admin Entity Manager writes JSON then a **Rebuild issues DDL**
  → real table per entity, real column per field. *Explicitly not EAV.*
- **Frappe DocType** — one metadata artifact declares **Model + View + Controller +
  Permissions + REST API** at once; **one real table per DocType**, meta-circular
  (DocType is itself a DocType). Runtime customization via Custom Field + Property
  Setter overlays (upgrade-safe). Natively multi-tenant (site-per-DB).
- **Odoo** — DB-resident metadata registry (`ir.model` + `ir.model.fields`); Studio
  writes rows then runs DDL to add real `x_studio_` columns at runtime.
- **Corteza** — EAV by default (all records in one `compose_record` table) **but** a
  Data Access Layer (2022.9+) can promote a hot module to a dedicated real-column
  table without app changes — the cleanest demonstration of the storage spectrum.
- **Monica** — deliberate counter-example: fixed hand-modeled schema (relationships,
  "how you met", gifts, debts, journal) — proof a curated schema beats a generic
  engine when the domain is known.

### Architecture lessons for an Elixir/Phoenix metadata-driven CRM
1. **Prefer real columns generated from metadata over classic EAV** — all 4 market
   leaders keep a metadata registry driving `CREATE/ALTER TABLE`. Ecto analogue: a
   field-definition registry + migration step materializing real columns + runtime
   schemaless queries.
2. **Hard-namespace core vs custom fields** — sidecar table or `_c`/`x_` prefix with
   non-destructive overlay (upgrade-safe).
3. **If EAV, copy Corteza's escape hatch** — and in Postgres a **GIN-indexed `jsonb`
   "extras" column is a far better middle ground than 3-table EAV**, with hot keys
   later materialized into real columns. *(Note: `phoenix_kit_entities` is JSONB-based
   — this is exactly that middle ground, good for the custom long-tail, not for hot
   core objects.)*
4. **One metadata artifact drives table + form + list + REST + permissions** (DocType
   lesson) — derive Ecto schema, LiveView form, JSON:API contract, policy checks from
   one canonical entity definition.
5. **Layouts/views are separate metadata from fields** — multiple/role-specific
   layouts over one schema.
6. **Relationships as first-class metadata** — belongsTo/hasMany/manyMany(+junction)/
   hasOne/**polymorphic parent**; polymorphic "linked to any entity"
   (activities/comments/attachments) must be designed in early.
7. **Layered override + merge for portability** (don't let users edit core metadata).
8. **Decide multi-tenancy before the metadata store** — Postgres schemas
   (Triplex/apartment) are Elixir's clean middle path.
9. **One automation layer** — lifecycle hooks → Ecto changeset pipelines + `Ecto.Multi`
   + PubSub/Oban; a sandboxed Formula mini-DSL is the differentiating-but-harder piece.
10. **Hybrid beats "everything is metadata" (Monica's lesson)** — hand-model the core
    CRM entities (Contact/Company/Deal/Activity) as first-class Ecto schemas for
    perf/type-safety; reserve the dynamic-entity engine for the long tail of
    user-defined custom objects. **→ This directly validates Option C (§5).**

## 9. Relationship-intelligence / "automatic" CRMs — the self-filling paradigm

Affinity, Salesflare, Nimble, Copper, Streak, Clay. Reframes a modern CRM as an
**interaction-graph engine + waterfall-enrichment pipeline + in-context surfaces** —
the object model (§1) is the *easy* part. To populate itself a CRM needs, in order:
1. **Deep team-wide email + calendar metadata sync** — interaction metadata (who,
   whom, frequency, recency) as first-class queryable data, not just an activity log.
2. **Email-signature parsing** — detect → classify lines into fields → upsert (the
   headline auto-fill; Salesflare's flagship).
3. **Identity resolution / contact graph** — match-or-create-or-merge; suggested-record
   UX (Salesflare/Copper) keeps it clean.
4. **Waterfall enrichment** (Clay) — ordered pluggable providers, **first-match-wins**,
   pay-per-hit; ~30%→80%+ coverage; cheapest provider is the user's own email signal.
5. **Social/web enrichment + an AI research agent** (Nimble social; Clay's *Claygent*
   returns structured field values from free-text web research) — slots in as a provider.
6. **Interaction-derived (computed) fields** — last-contacted, frequency, days-since,
   account "heat" (Salesflare's 7-day rolling hot/on-fire).
7. **Relationship-strength scoring + warm-intro paths** (Affinity's moat) — per-pair
   score (10–100) from recency×frequency×consistency, decaying, **team-wide**. ⚠️ Even
   a simple v1 score requires the data model to capture **per-pair, per-user interaction
   aggregates from day one** — retrofitting the collective graph later is expensive.
8. **In-context surfaces** — Gmail/Outlook sidebar, browser extension on any page/
   LinkedIn (Affinity Pathfinder, Nimble Prospector), or CRM-inside-Gmail (Streak,
   Copper). Argues for a sidebar/embed delivery model + strong public REST.
9. **AI summarization + next-step over captured history** — high-value only *because*
   capture is complete; AI on partial manual data is the failure mode they market against.

## 10. Sales-engagement + revenue-intelligence — the T3 frontier

Outreach, Salesloft, Gong, Clari, Apollo, Groove. Mostly NOT CRMs — they layer on top
— so this is the advanced tier modern CRMs are absorbing. Patterns to design *toward*:
- **Signal → Play → prioritized task** (Salesloft Conductor/Rhythm, Outreach Omni) —
  the architectural heart of "AI sales": model **Signals** (typed external events
  attributed to person/account/deal) and **Plays** (signal → queued 1:1 task with a
  rationale) as **first-class entities**, ranked into one per-rep queue by urgency×impact.
- **Sequences/cadences (deep)** — multi-step, multi-channel; **cadence membership is a
  first-class object** with states (in-progress/completed/removed) + **Do-Not-Contact
  as a hard global cross-sequence block** (compliance — build into the schema from day one).
- **Two-field call logging** — separate **Disposition** (what happened) from
  **Sentiment** (outcome); both admin-customizable + queryable. Most CRMs conflate them.
- **Conversation intelligence** (Gong/Salesloft Conversations) — record/transcribe
  calls + meetings, AI summaries + action items, trackers (keywords), talk-ratio,
  sentiment, MEDDPICC/BANT auto-extraction, deal-risk signals.
- **Revenue intelligence** (Clari/Gong) — pipeline inspection, deal scoring/risk,
  "deals slipping", forecast roll-ups, activity auto-capture into CRM.
- **Prospecting DB** (Apollo) — B2B contact database + intent data.

→ Verdict: defer these for MVP, but the **Signal/Play model**, **cadence-membership +
DNC schema**, and **Disposition/Sentiment split** are cheap to design in early.

## 11. Vertical / industry CRMs — what verticalization demands of the core

Bullhorn (recruiting), Follow Up Boss + kvCORE/BoldTrail (real estate), Bloomerang +
Neon (nonprofit), Bigin + Keap (SMB packaging). Every vertical = generic CRM + a few
custom objects + custom pipelines per object + flexible relationships + automation.

- **Recruiting** (Bullhorn): the "person" splits into **Candidate** and **ClientContact**
  (linked, not merged); a recruiting chain a generic CRM lacks —
  **JobOrder → JobSubmission → Sendout → Placement** (Submission = internal review,
  Sendout = sent to client; one JobOrder → many Placements); **field correlation**
  (Placement fields auto-default from the parent JobOrder); custom objects on 6 core
  entities (≤10 each); resume parsing + matching engine + pay/bill back office.
- **Real estate** (Follow Up Boss, kvCORE/BoldTrail): a **Property/Listing** object +
  a **behavioral Event** type linking contact↔property (viewed/saved/searched/
  valuation-request/open-house) that drives automation; **separate Buyer/Seller
  pipelines** with commission/GCI + close date; **lead-source** as a first-class field +
  **routing rules** (round-robin/by-attribute); saved-search → listing-alert plumbing;
  **Smart Lists** = self-updating filters that double as daily call queues. (FUB =
  focused CRM + rich integration surface; BoldTrail = own-the-whole-stack suite — a
  good core should support both postures.)
- **Nonprofit** (Bloomerang, Neon): a **gift = transaction with subtypes**
  (donation/pledge/pledge-payment/recurring share one table + type discriminator);
  classified by **configurable allocation dimensions** (Bloomerang = flat
  Fund/Campaign/Appeal FKs; Neon = self-referential Campaign trees); **soft credits**
  (a gift credited to multiple constituents — labeled M:N, recognition ≠ money);
  **schedule objects** (a pledge = recurring schedule with finite installment count);
  **memberships** first-class (Level→Term, join-vs-renew) in Neon; **Households** roll up
  giving.
- **SMB packaging** (Bigin vs Keap — opposite strategies, same lessons):
  - **Multiple pipelines, NOT one funnel** — Bigin runs ≤15 **Team Pipelines**, each with
    its own stages/fields/automation/**access permissions** (+ sub-pipelines). Don't
    hardcode a single sales funnel.
  - **Cross-pipeline handoff is a must-have** — Bigin **Connected Pipelines**: hitting a
    stage in pipeline A **auto-creates a linked record in pipeline B, carries chosen
    fields forward, and keeps them persistently linked** (sales → onboarding → renewals).
    Keap solves the same via tag-driven enrollment.
  - **Keap = verticalize via tags + visual automation** — tags are the *state* (applied
    automatically by automations), Campaign Builder is the behavior; light
    verticalization with zero schema forks. Commerce/marketing (Orders/Invoices/
    Subscriptions/Landing pages) are **optional bolt-on modules** over the core.
  - **Bigin = simplify by subtraction + a "Toppings" extension marketplace** — small
    fixed module set, cut the heavyweight stuff, push niche needs to extensions.

### What verticalization demands of the core (8 primitives)
A core that can become recruiting/real-estate/nonprofit *without forking* needs:
1. **Custom objects as first-class** (not just custom fields) — verticals add new record
   *types* (Candidate/JobOrder/Placement; Listing; Gift/Pledge/Membership), created by
   configuration. (Attio/HubSpot model: "specialize through setup, not product variants.")
2. **Custom pipelines per object**, with per-pipeline **stages/fields/permissions** —
   "a pipeline is just a list switched into kanban view" (decouple storage from view:
   table/kanban/calendar over the same records).
3. **Flexible relationships** — typed, directional, with cardinality + **labels**
   ("Decision Maker", "Buyer's Agent", "Solicitor"), **M:N junctions**, and
   **self-referential** (Campaign nests; Company parent-child). HubSpot association model.
4. **Field correlation / inheritance** between related records (Bullhorn correlated
   fields; Bigin field carry-over) — "creating B linked to A copies these fields from A."
5. **Polymorphic transaction/event schema** — one money object with a type field +
   child-payment records (recurring schedules spawning children) vs. a schema per money type.
6. **Automation hooks on lifecycle events** — record/stage/property/tag triggers →
   action sequences (email/SMS/task/apply-tag/charge/create-linked-record/wait/branch).
7. **Tags/segments + saved dynamic lists** — universal segmentation; smart lists double
   as work queues.
8. **Extension/marketplace surface (REST API + optional modules)** — keep commerce/
   marketing as layered modules so the same core ships minimal (Bigin) *or* suite (Keap).

→ Strongest reinforcement of **Option C**: the dynamic-entity half (custom objects +
flexible relationships) is precisely what makes verticalization a *config pack*, not a fork.

## 12. Remaining commercial — process/BPM tier + the simplicity floor

SugarCRM, Insightly, Capsule, Less Annoying, Nutshell, Creatio, Apptivo, ActiveCampaign.
- **Process-enforcement has altitudes:** Zoho Blueprints (state machine) < SugarBPM
  (BPMN + **reusable Business Rules as shareable policy objects**) < **Creatio**
  (executable BPMN 2.0 **+ adaptive case management** + full custom-object model, CRM as
  an assembled app). Steal: model business *policy* as first-class shareable objects,
  not inline per-workflow logic; consider supporting structured (BPMN) AND adaptive
  (stage/case) processes.
- **The customization spectrum** (how to position our build): Less Annoying (custom
  fields/groups only) → **Capsule DataTags** (tag-conditional field sets) →
  Insightly/Sugar/Creatio (full custom objects/modules + relationships). SugarCRM's
  **Vardefs/Viewdefs metadata + Module Builder-vs-Studio split** = direct reference.
- **MVP floor (empirically pinned):** Less Annoying — a profitable vendor — ships only
  Contacts + Tasks + Calendar + Notes + one Pipeline + Custom Fields/Groups, **zero AI
  by design**. That's our lower bound; "no AI" is a defensible stance.
- **Inverted (marketing-led) model:** ActiveCampaign — Contact + behavioral/score data
  is primary, deal pipeline is a layer on top; best-in-class **visual automation builder**
  (branch/split/**goal**/go-to/wait + inline scoring) as *the* product.
- **Projects-in-CRM:** Insightly (heavy: Milestones/Gantt + opportunity→project) vs.
  Capsule (light: Projects + sequential **Tracks** playbooks). *(We already have
  `phoenix_kit_projects` — relevant reuse.)*

## 13. Cross-wave conclusions

1. **The object model is the easy, solved part.** Every advanced capability —
   self-filling, relationship intelligence, AI sales, verticalization — is built *on
   top of* Contacts/Companies/Deals/Activities. Get those right and extensible first.
2. **Extensibility (custom objects + flexible relationships) is the highest-leverage
   architectural decision** — it's what lets one CRM become a real-estate / recruiting /
   nonprofit CRM, and what every modern + open-source CRM invests in most.
3. **Don't ship classic EAV.** Real-columns-from-metadata (Espo/Frappe/Odoo) or a
   GIN-indexed JSONB extras column (what `phoenix_kit_entities` already is) — not a
   3-table EAV.
4. **A handful of schema decisions are cheap now and expensive later** — design these in
   even if unbuilt: polymorphic "linked to any record" (activities/notes/attachments),
   per-pair/per-user interaction aggregates (relationship scoring), Signal/Play entities,
   cadence-membership + global DNC, Disposition/Sentiment call split, configurable
   lookup/allocation dimensions, soft-credit-style recognition links.

---

## 14. Sharpened recommendation (post-wave-2)

The full survey strongly converges on **Option C (Hybrid)** from §5, and the
open-source research (§8 lesson #10) validates it explicitly:

> Hand-model the **core CRM entities** — `Contact`, `Company`, `Deal`,
> `Pipeline`/`Stage`, `Activity` — as **first-class Ecto schemas** (core migrations,
> like every other module) for the typed, fast mechanics (weighted forecast, rotting,
> stage probability, the Kanban). **Reserve `phoenix_kit_entities`** (already a
> GIN-friendly JSONB dynamic-object engine with a `relation` field type) **for
> user-defined custom objects + custom fields** — the long tail that lets the CRM be
> specialized into verticals without forking.

Plus the reuse map from §4 (Activity, comments, emails, catalogue, billing, ai,
projects, Oban) for everything that isn't CRM-specific.

**Companies/Contacts decision (§5):** model them as **standalone CRM records**, not
auth users — with an *optional* link to a core `User` / `staff.Person` when one exists.
(The current "Organizations = users with account_type=organization" approach is too
narrow; most CRM companies and contacts are never login accounts.)

**Design-in-now, build-later checklist** (cheap to reserve, per §13.4): polymorphic
record links for activities/notes; per-pair interaction aggregates; Signal/Play
entities; cadence-membership + global DNC; Disposition/Sentiment; configurable lookup
dimensions.

**MVP (T0)** stands as §6, with these wave-2 refinements:
- Custom fields/objects via `phoenix_kit_entities` (don't hand-roll EAV).
- Polymorphic activity/note links from the first migration.
- Lead-source as a first-class field on Contact/Deal; simple manual routing.

---

# Wave 3 — industry/vertical variety (~30 more platforms across diverse fields)

Third pass, deliberately spanning *industries* to capture the full range of
specialized CRM functionality. Each entry = only what the field ADDS beyond the
universal core. (Two segments — automotive/education/legal and the deep
inventory/MRP production data model — are still in flight and append below.)

## 15. Healthcare & life sciences (Veeva, Salesforce Health Cloud)
- **Pharma (Veeva):** an **HCP↔HCO affiliation network** (account/affiliation graph),
  **territory alignment + cycle/call planning**, sample drops + signature capture
  (PDMA compliance), closed-loop marketing.
- **Provider/payer (Health Cloud):** a **FHIR-aligned clinical data model** mirroring
  the EHR (ClinicalEncounter, HealthCondition, MedicationStatement…); **care
  coordination** (Care Plan → Problems/Goals/Activities, Care Team, Care Gaps, Care
  Programs/Enrollees); **payer objects** (utilization management CareRequest/CarePreauth,
  MemberPlan/Coverage, Claims, Benefits Verification); **consent + PHI compliance**
  (AuthorizationFormConsent, Shield encryption/audit, BAA).
- *Demands:* affiliation/relationship network + an EHR-style clinical record mirror +
  consent/compliance layer + scheduling.

## 16. Hospitality / events / fitness / membership (Tripleseat, Mindbody, Revinate, Wild Apricot)
- **Events/catering (Tripleseat):** an **Event** = a deal that also has a **date, a
  bookable room, and a guest count**; **Function space** as a schedulable resource with
  a conflict-detecting calendar; **BEO** as a structured versioned child document built
  from a menu/package catalog; deposits/milestone payments.
- **Fitness (Mindbody):** the billing taxonomy is the lesson — **Membership** (recurring
  entitlement) vs **Package** (decrementing credits) vs **Autopay** (the billing
  schedule) vs **Contract** (commitment term); **Class** = bookable resource w/ capacity
  + roster; **Booking** = Client×resource×time; waitlists; late-cancel/no-show policies.
- **Hotel (Revinate):** a **unified Guest Profile built by identity resolution/merge**
  across many fragmented stays; value = aggregated transactional rollups (lifetime spend,
  RFM); **date-event-triggered** pre-arrival/post-stay messaging.
- **Associations (Wild Apricot):** tiered **Membership** with a full renewal lifecycle
  (active→expiring→grace→lapsed→renewed); **bundle/group memberships** (one payer, many
  sub-members); events+registration w/ member pricing; **CE credits/certifications**;
  chapters; self-service member portal.
- *Demands (12 primitives):* bookable-resource+availability calendar; booking/registration
  join object; recurring-subscription/membership lifecycle; decrementing credit balances;
  unified-profile rollup + identity merge; transaction-event-triggered automation;
  milestone+recurring billing; composable line-item catalogs; structured versioned child
  documents; org hierarchy/sub-groups; self-service portal; policy/rules engine.

## 17. Field service / home services / construction (ServiceTitan, Jobber, Housecall Pro, JobNimbus, Buildertrend)
- **Property / Service-Location as a first-class object DISTINCT from the customer** —
  one customer owns many sites; jobs/equipment/history/pricing attach to the **site**.
  (The single most load-bearing departure from a flat CRM.)
- **Installed Equipment/Asset** tracked per location (serialized); **Technicians/Crews**
  as schedulable resources; **dispatch** (resource-on-time-on-**map**, route optimization,
  capacity/zone limits); **Visit distinct from Job** (one job → many visits); **recurring
  Service Agreements** that auto-generate visits + invoices; **Job→Estimate→Invoice→
  Payment lifecycle** off a **Price Book**; **mobile-first, offline** field execution;
  call→job→revenue source attribution (DNI).
- **Data-model precision (ServiceTitan):** a strict **Customer → Location → Equipment**
  hierarchy — one customer → many locations; a location → exactly one billing customer;
  **equipment lives on the location, not the payer**; *jobs book against the location*.
  This is what cleanly handles property managers / landlords / multi-site commercial.
- **Customizable per-workflow boards (JobNimbus):** separate **Contact Workflow** (sales)
  vs **Job Workflow** (production) Kanban boards with contractor-defined stages.
- **Construction PM (Buildertrend, Procore):** the **Project becomes a months-long central
  object** (not a closed deal) with construction-native children — **Selections/Allowances**
  (finish choices w/ budget impact), **Change Orders** (budget + schedule deltas), **Daily
  Logs**, **Gantt w/ dependencies**, and (commercial) **RFIs / Submittals / Drawings** as
  formal correspondence objects — plus **multi-party portals** (owner + subs + GC) with
  scoped visibility, and a bid/prequalification preconstruction pipeline.

## 18. Financial services / wealth / insurance (Redtail, Wealthbox, Salesforce FSC, AgencyBloc, Applied Epic, Total Expert)
- **Household / family as a first-class rollup object** (AUM = SUM of member account
  balances); attribute inheritance (address flows down). M:N membership (one person in
  multiple households — FSC AccountContactRelation shared contacts).
- **Typed reciprocal relationship graph** (FSC `ReciprocalRole` — standardized role pairs,
  auto-created inverse edges). **Two separable edge types**: servicing-role (contact→user/
  team) vs kinship/fiduciary (contact→contact); regulatory roles (POA, Trusted Contact/
  FINRA 4512).
- **Domain assets as first-class** (not deals): **Financial Account** (type/custodian/
  balance/roles, **feed-vs-manual provenance** + unlinked/reconcile state); **Policy**
  (carrier/coverage/premium/**renewal**/**commission**, group→member→dependent→policy);
  **Loan** (a **milestone lifecycle** application→underwriting→clear-to-close→funded,
  owned by an external LOS — CRM normalizes external status into trigger fields).
- **Commission as a two-sided junction** (inbound from carrier/upline, outbound to
  downline; rate structures/splits; missing-commission detection). Policy carries a
  **transaction ledger** (new-business/renewal/endorsement/cancel/audit — Applied Epic).
- **Rollup/aggregation engine** (FSC Rollup-By-Lookup) to household/book level.
- **Recurring review cadences as workflow templates** (annual review, RMD, renewals).
- **Compliance as infrastructure:** WORM 17a-4 comms archiving (Smarsh), Field Audit
  Trail, record-level sharing (CDS), KYC/AML, content-approval gating + auto-propagating
  disclosures (NMLS/Equal Housing), producer licensing/appointments/CE.

## 19. Customer success / e-commerce / government / advancement (Gainsight, ChurnZero, Klaviyo, Gorgias, Salesforce PSS, Granicus, Blackbaud) — the "post-sale / lifecycle / case" cluster
The inverse of a sales CRM — organized around *ongoing state + signals*, not won/lost
deals. **The 11 distinctive primitives (load-bearing for our build):**
1. **Composite computed scores as a first-class, time-varying object** — a **scorecard**
   of weighted measures w/ current/previous + history (CS health, churn risk, prospect
   capacity/propensity, eligibility). Not a static field.
2. **High-volume event / time-series store separate from the relational activity log** —
   usage telemetry (Gainsight Adoption Explorer), e-comm behavior (Klaviyo events/metrics),
   311 streams. Append-only (entity+metric+ts+props+value), externally ingestible. *The
   single biggest data-engineering departure.*
3. **Signal → rule → work-item (CTA/Play) → templated task-sequence (playbook) engine** —
   the universal automation shape (Gainsight CTA+Playbook, ChurnZero Plays, Klaviyo Flows,
   Gorgias Rules+Macros, Action Plans). Same shape as wave-2's Salesloft Signal→Play.
4. **Recurring-revenue / subscription & renewal objects** (+ nonprofit recurring gifts) —
   term, ARR/MRR, seats/entitlements, renewal date, churn/expansion. An *ongoing,
   renewable* object, not a closed deal.
5. **Case / Service-Request / Application state machine + SLA timers + routing** — 311,
   permits/licenses, FOIA, benefits, support tickets, legal matters. Configurable state
   machine + deadlines (Entitlement→SlaProcess→MilestoneType→CaseMilestone) + Omni-Channel
   routing. Distinct from a linear sales pipeline.
6. **Multi-dimensional attribution + splittable transactions + soft credits** — Blackbaud
   **Campaign/Fund/Appeal/Package** + gift splits + soft credits (one gift, several axes,
   credited to multiple parties). Generalizes nonprofit (wave-2) and pharma rebates.
7. **Dynamic, continuously-evaluated segments** (vs static lists) over events + computed
   fields, that themselves trigger automation on entry/exit.
8. **Lifecycle / journey staging** — non-linear, recurring (onboarding→adoption→renewal→
   advocacy; donor cultivation; application stages), with transition criteria; separate
   from the win/lose pipeline.
9. **Constituent/customer/member self-service portal + external identity** — the *subject
   of the record* authenticates and transacts (citizen/donor/customer portals).
10. **Subject-rich profiles + relationship graphs** — households, businesses, affiliations,
    employer→matching-gift links, multiple typed "codes" on one record.
11. **Mass topic-based notification** (Granicus govDelivery subscriber/topic/bulletin) as
    a channel distinct from 1:1 CRM email.
- Plus a **rules/decision engine (BRE)** — Expression Sets + Decision Matrices/Tables for
  eligibility/policy calculation (kin to Zoho Blueprints / Creatio BPM from wave 2).

## 20. Manufacturing CRM↔ERP (Salesforce Manufacturing Cloud, NetSuite, Dynamics, SAP) — the factory commercial layer
- **The CRM→ERP boundary IS the Sales Order.** Before it = CRM/demand; after = ERP/supply.
- **CRM layer owns:** the **Sales Agreement** (the one production-adjacent object that
  belongs in CRM — a *standing, time-phased volume+price commitment* with planned-vs-actual
  per product per period = "run-rate business"; header→product→product-schedule);
  **account-based forecasting** (account×product×period blending agreements + order actuals
  + pipeline); rebate/partner/warranty programs.
- **ERP layer owns:** BOM + Routing/Work Centers; **Work/Production Orders** (status
  lifecycle, WIP, consumption/output); **stock w/ lots/serials/bins/warehouses**; **MRP**
  (net demand vs supply → planned orders); ATP/CTP delivery promising.
- **Chain:** Opportunity/Quote → **Sales Order** → [Make-to-Stock vs Make-to-Order] →
  Work Order → Build → Fulfillment → Invoice.
- *(Deep production data model — how to actually model BOM/work-order/stock in Ecto —
  comes from the inventory/MRP agent, appended below when it lands.)*

## 21. Cross-industry primitive catalog (the wave-3 synthesis)
Across ~10 industries, the same extensible primitives recur. A core that ships these can
become any of these verticals as a **config pack**, not a fork. Grouped:

**Data-model primitives**
- **First-class domain objects** (Policy / Financial Account / Loan / Gift / Job / Listing /
  Encounter / Application) — NOT "deals"; each with lifecycle + often **feed-vs-manual
  provenance** + a **transaction/event ledger**.
- **Polymorphic transaction subtypes + schedule objects** — gift/pledge/recurring share one
  table; a schedule spawns child payments (nonprofit, CS, billing).
- **Household / group as a rollup object** — M:N membership, attribute inheritance, value
  rollups (AUM, giving, household spend).
- **Typed reciprocal relationship graph** — standardized role pairs, auto-inverse edges,
  M:N junctions, self-reference; **two edge types** (contact→user servicing vs
  contact→contact kinship); affiliation networks.
- **Property/Service-Location distinct from customer + installed-asset tracking.**
- **Bookable resource + availability calendar + Booking/Registration join.**
- **Composable line-item / product catalog** that composes onto events/bookings/quotes.
- **Multi-dimensional attribution + splittable transactions + soft credits.**

**Behavioral / compute primitives**
- **High-volume event / time-series store** (separate from the activity log).
- **Composite computed scores** (scorecards — health/risk/capacity/eligibility), time-varying.
- **Dynamic continuously-evaluated segments** as automation triggers.
- **Interaction-derived fields** (last-contacted, frequency, account "heat") + relationship
  scoring (wave-2 carryover).

**Workflow / process primitives**
- **Signal → rule → work-item (CTA) → playbook** engine (the universal automation shape).
- **Case/Application state machine + SLA timers + routing** (distinct from sales pipeline).
- **Recurring subscription/membership/agreement lifecycle** + renewal cadence.
- **Lifecycle/journey staging** (non-linear, recurring).
- **Rules/decision engine** (BRE / Blueprints / BPM) for eligibility/policy calc.
- **Field correlation/inheritance** between related records (parent→child defaults).

**Platform primitives**
- **Self-service portal + external identity** (record subject transacts).
- **Compliance-as-infrastructure** — WORM archiving, audit trail, consent, record-level
  sharing, disclosure gating, credentials/licensing.
- **Mass topic-based notification** (subscriber/topic/bulletin).
- **External-system-of-record integration** that normalizes external status into internal
  trigger fields (LOS/custodian/EHR/PMS/store).

## 22. Wave-3 conclusion (impact on the recommendation)
Wave 3 does **not** change the §14 recommendation (Option C hybrid) — it *reinforces* it
and adds nuance:
- The **dynamic-entity engine** (`phoenix_kit_entities`) is what makes "first-class domain
  objects + typed relationships + per-object pipelines" a config pack rather than a fork —
  exactly what verticalization needs. ✅
- BUT wave 3 reveals a class of **cross-cutting platform primitives** that are NOT just
  "custom objects" and would need first-class design if we ever go beyond a sales CRM:
  an **event/time-series store**, a **scorecard/compute engine**, a **signal→rule→CTA→
  playbook automation engine**, a **case/SLA state machine**, and a **rules/decision
  engine**. These are the difference between a *sales* CRM and a *platform* CRM.
- **Scope discipline:** the MVP (§6) stays a focused **sales** CRM (Contacts/Companies/
  Deals/Pipeline/Activities). The wave-3 primitives are a **menu of post-MVP modules**,
  each mapping to a real PhoenixKit reuse or a new module — e.g. recurring/subscription →
  `billing`; case/SLA → a new module; events/scores → new; portal → core auth; rollups →
  a compute helper. Design the core's **custom-object + relationship + automation-hook**
  layer so these can attach later without a rewrite.
- **For Max's factory ask:** production/inventory (BOM/work-order/stock/MRP) is **ERP, not
  CRM** — a separate module beyond the Sales-Order boundary; the CRM owns **Sales
  Agreements + account forecasting**. (Deep production data-model mapping pending the
  inventory/MRP agent.)

## 24. Deep production / inventory data model (Katana, Odoo MRP, ERPNext, Fishbowl, Cin7) — for the factory build
The most build-relevant report: how to actually model production/inventory in
Elixir/Ecto. Two transferable big ideas: **Odoo's double-entry move ledger** +
**ERPNext's metadata-driven DocType model**.

### The irreducible production object set
1. **Item / Variant** (template→variant): base `stock_uom`, `category_id`, role flags
   (stockable/sellable/purchasable/manufacturable), `tracking` (none|lot|serial),
   `costing_method` (fifo|avg|standard|fefo), `default_bom_id`.
2. **UoM + UoM Category + Conversion** — convert only *within* a category (prevents
   kg→m); allow a second pricing/**catch-weight** UoM (stocked by count, priced by weight).
3. **Attribute / Attribute Value** — Cartesian variant generation.
4. **BOM + BOM Line (+ Operation + By-product)** — `boms` (output item/qty, `type:
   normal|phantom`, version/effectivity), `bom_lines` (component, qty, **scrap %**,
   **`sub_bom_id`** = multi-level), `bom_operations` (routing), `bom_byproducts`
   (`cost_share` %). Keep a denormalized **exploded-items** projection for MRP speed.
5. **Work Center / Resource + Routing Operation** (`cost_per_hour`, capacity, setup time, OEE).
6. **Manufacturing Order + Work Order/Job Card** — *consumption & output are stock moves,
   not bespoke columns.* MO state machine (draft→confirmed→progress→done).
7. **Typed Location (`usage` enum) + Warehouse tree** — usage = internal|view|supplier|
   customer|production|inventory_adjust|transit|scrap; tree via nested-set/`ltree`/closure.
   The typed location is what makes double-entry work.
8. **Stock Move (IMMUTABLE, double-entry ledger) + Move Line** — `stock_moves`
   (item, qty, uom, **source_location ≠ dest_location**, state, polymorphic
   source_doc_type/id, procure_method); move_lines carry exact lot/serial/package/qty.
   *Every change is a move between two typed locations* — receipts, builds, scrap, counts
   are one code path. On-hand is **derived/cached, never the source of truth**.
9. **Quant / Bin cache** per (item, location, lot): quantity, reserved, in_date —
   a materialized projection of the move ledger.
10. **Lot / Serial** (expiry, mfg date) — the traceability join keys.
11. **Reorder rule / Orderpoint** (min/max/multiple/route).
12. **Valuation layer** (FIFO/AVCO queue: qty, unit_cost, value, remaining) + optional
    perpetual journal hook.
13. **SO / PO / Supplier + procurement group** — `procurement_group_id`/`origin` chain
    ties generated MOs/POs back to the demand that spawned them (full genealogy).
- **MRP algorithm:** time-phased per item — `Gross Req − Scheduled Receipts −
  Projected-on-hand + Safety = Net Req` → planned order (lot-sized, lead-time-offset);
  child-level releases become parent gross requirements (BOM explosion). Reorder-point is
  the lighter alternative. MPS above MRP; ATP/CTP for promising.

### Ecto / metadata-driven mapping (the gold for our build)
- **Immutable ledger fits Ecto + functional/event style perfectly.** `stock_moves`
  append-only; never mutate quantities. On-hand = sum of moves (or read the `stock_quants`
  cache refreshed in the **same `Ecto.Multi`** as the move insert). "Post move + update
  quant + write valuation layer" in one Multi so double-entry + cache can't diverge.
  Back-dated corrections = re-projection (Oban-friendly), not destructive update.
- **Double-entry enforced by a DB check constraint** (`source_location_id !=
  dest_location_id`) + the typed `usage` enum — reproduces Odoo's "books always balance."
- **Metadata-driven schema (ERPNext DocType analogy → `phoenix_kit_entities`):** define
  Item/BOM/BOM-Line/Work-Order/Stock-Move as configured entity types with typed fields;
  child tables (bom_lines, move_lines) = child entities keyed by parent ref + order index.
  `Link`→`belongs_to`, `Table`→`has_many`+order col, `Select`→`Ecto.Enum`. Tenants add a
  custom Item field or Stock-Entry purpose without a migration — **while hot-path objects
  (moves, quants) stay real, indexed Postgres tables** for speed. (This is exactly the
  Option-C hybrid split, applied to ERP.)
- **Polymorphic source doc** on each move (`{source_doc_type, source_doc_id}`) — same
  shape as core's existing `resource_uuid` linking.
- **Traceability = recursive CTE** over moves joined on `lot_id` (forward where-used /
  backward what-went-in) — no separate genealogy store.
- **State machines** → Ecto enum + transition fns; **scheduling/Gantt** → reuse the
  existing **`phoenix_live_gantt`** for the production scheduler.
- **Reuse map:** items/UoM overlap `phoenix_kit_catalogue`; SO/PO/invoicing overlap
  `phoenix_kit_billing`/`ecommerce`; Gantt = `phoenix_live_gantt`; jobs = core Oban.
  Production (BOM/work-order/stock/MRP) is genuinely new — an **ERP module beyond the
  Sales-Order boundary**, NOT part of the CRM.

### Bottom line for the factory ask
This is **ERP, not CRM**. The CRM owns the commercial layer up to the **Sales Order**
(incl. Manufacturing-Cloud-style **Sales Agreements** + account forecasting, §20). A
factory build is a **separate production/inventory module** whose load-bearing ideas are
Odoo's **typed-location double-entry immutable move ledger** and ERPNext's
**metadata-driven DocType model** — both of which map cleanly onto Elixir/Ecto +
`phoenix_kit_entities`, and reuse catalogue/billing/gantt/Oban.

## 23. Automotive / education / legal — "specialized-deal-variant" fields
Three fields whose shared lesson is that **the "deal" itself becomes a domain object**.

- **Automotive (VinSolutions, DealerSocket):** **Vehicle (VIN-keyed inventory)** as a
  first-class record (pricing layers, days-in-inventory aging) with a M:N
  "vehicle-of-interest" link to the contact; **Trade-in/Appraisal** sub-object (KBB/vAuto
  valuation round-trip, computed equity); **Desking worksheet** = a deal that *computes
  payments not price* (finance/lease/cash variants, lender rates/residuals/rebates, F&I
  line items, embedded credit app); **Up/showroom log** (walk-in traffic, DL-scan); **DMS
  sync** (the DMS is the system of record); **equity mining** (owner-base upgrade pipeline);
  **ADF/XML** portal-lead ingestion + source attribution.
- **Legal (Clio Grow, Lawmatics):** the **Matter** is the legal "deal" (practice area,
  status pipeline, responsible attorney); a lead = a Matter in an Intake/PNC state until
  **converted**; **typed related parties on one matter** (client/opposing-counsel/co-
  counsel/witness — each an independent Contact, the role routes them into document slots
  + signer positions); **conflict checks** (search across ALL contacts/matters/notes →
  PDF, auto-approve/deny/flag); **intake forms that mint Contact+Matter**; **document
  automation → e-sign engagement letters** as a stage action; per-practice-area pipelines;
  scheduling that auto-advances the stage; **sync to practice-management** on conversion.
- **Education (Slate, Salesforce Education Cloud):** the **Application** is the "deal",
  moving through the admissions funnel (inquiry→applied→admitted→deposited→enrolled);
  Slate models it via **rounds/periods + bins + queries + a reader/review workflow** with
  scoring rubrics + decision codes; **populations** (named segment memberships with entry/
  exit timestamps) are the drip-trigger substrate; **identity-scoped self-service portals
  + applicant status pages + checklist/materials**; a single durable **person with
  time-bounded M:N affiliations** (program/term/role) — not per-stage record copies.

### The 8 cross-field extension points (the capstone synthesis)
A core that exposes these **as configuration, not code** models vehicle-deals, matters,
and applications — and by extension most verticals — **without forking**:
1. **Polymorphic "deal" with variant subtypes + per-subtype outcome vocabularies +
   pluggable computed economics** — not a single hard-coded `amount`. (desking payment
   engine / matter / application; outcomes Hired·Not-hired / Admit·Deny·Deposit / Sold·Lost.)
2. **Catalog/inventory entity the deal is filed *against*** — Vehicle / Program-Term /
   practice-area — a queryable record with a M:N "interested-in / applied-to" link, external
   sync, per-item attributes (price/aging; capacity/term).
3. **Typed, role-bearing contact↔deal edges** — multiple parties per deal, role is *data*
   consumed by document-routing + e-sign + CC; each party an independent Contact.
4. **Record-minting intake forms** — forms/portals that create Contact + deal-variant,
   with conditional logic, field→object mapping, **structured-feed ingestion** (ADF/XML ≈
   application submission), and source attribution baked in.
5. **Configuration-driven pipelines with stage-entry/exit automation hooks** + weighted
   forecasting (value × conversion-rate; days-in-stage aging), attachable per deal-subtype.
6. **Merge-template + e-signature as a stage-triggered action** (record fields → document
   incl. role-routed party fields; audit trail; auto-reminders).
7. **Population/segment-based bulk drip communications** (distinct from 1:1 activity logging).
8. **Outbound system-of-record sync adapter** — external-ID mapping, field mapping, dedupe/
   merge, conversion-event push (terminal "won" stage → push), optional bidirectional
   close-status sync (DMS / practice-management / SIS).

> These 8 are the same extension points wave-2's verticalization analysis (§11) reached —
> independently re-derived from three unrelated industries. That convergence is the
> strongest signal in the whole study: **custom deal-subtypes + catalog objects + typed
> role edges + record-minting forms + configurable pipelines-with-hooks + doc/e-sign +
> segment campaigns + sync-adapter** is the extensible-CRM spine.

---

## WAVE 3 COMPLETE. Full study = ~80 platforms across 3 waves / 9 market segments / 15+
industries, plus the production/inventory ERP layer. The §14 recommendation (Option C
hybrid) stands and is now exhaustively corroborated; §21–§23 give the cross-cutting
primitive catalog and the 8 extension points that define the extensible-CRM spine.
