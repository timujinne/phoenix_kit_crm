# CRM v2 — Parties: Suppliers & Clients, integration with Catalogue and Warehouse

**Status:** Proposal (awaiting review)
**Date:** 2026-07-12
**Supersedes / extends:** `crm_v1_interaction_tracker.md` (§4.2 future `crm_contact_relationships` edge)
**Related modules:** `phoenix_kit_crm`, `phoenix_kit_catalogue`, `phoenix_kit_warehouse`, core `phoenix_kit` (migrations)

---

## 0. TL;DR

- **CRM becomes the party master.** "Supplier" and "client" are **roles** on existing CRM companies/contacts, stored in a new `phoenix_kit_crm_party_roles` edge table — not a new entity, not a status value. One party can be supplier *and* client simultaneously (the Odoo `supplier_rank`/`customer_rank` and SAP Business-Partner-roles property).
- **Catalogue keeps commercial supplier-item data.** A new `phoenix_kit_cat_item_supplier_info` junction (supplier × item → supplier SKU, unit cost, currency, lead time, MOQ) replaces the broken scalar `items.primary_supplier_uuid`. This is Odoo's `product.supplierinfo` / SAP info-record: per-item procurement facts never live on the party.
- **`cat_suppliers` is demoted, not deleted.** It becomes a local fallback for catalogue-standalone installs and gains a nullable `crm_company_uuid` cross-reference. An opt-in mix task backfills its rows into CRM companies with the `supplier` role (SAP CVI migration pattern). Both tables are empty today — **the window to do this without data migration pain is now.**
- **Warehouse changes zero schema lines.** It already resolves suppliers exclusively through the Catalogue facade (`Catalogue.list_suppliers/0`, `get_supplier/1`); the facade internally federates CRM when the CRM module is loaded. Client orders enter warehouse через its existing `SourceKinds` host-callback registry.
- **Cross-module linking rule (to codify as ADR):** inside a module's own tables → hard FK; across optional-module boundaries → soft UUID + resolver + write-time name snapshot.

---

## 1. Current state (verified 2026-07-12)

### 1.1 CRM (`phoenix_kit_crm` v0.2.4, tables in core migration V138)

- `phoenix_kit_crm_contacts` — person; nullable `user_uuid` → `phoenix_kit_users` (partial unique); `email` varchar, **non-unique, not citext**; `metadata` JSONB.
- `phoenix_kit_crm_companies` — org; name/status/website/email/phone/address/industry/notes/metadata. **Nothing marks a company as customer or supplier** — `status` is lifecycle only (`active`/`inactive`/`trashed`), `industry` is free text.
- `phoenix_kit_crm_company_memberships` — contact↔company M:N; `role_in_company`/`department` model **employment** ("CEO"), not commercial relationship.
- `phoenix_kit_crm_interactions` — subject is always a **contact** (`contact_uuid NOT NULL`); companies are read-only rollups.
- `phoenix_kit_crm_interaction_parties` — exclusive arc contact XOR staff, `raw_name` always kept, `party_snapshot` JSONB.
- Soft-dependency precedent: `PhoenixKitCRM.StaffLink` integrates the optional staff module via `Code.ensure_loaded?/1` + `function_exported?/3`, no `mix.exs` dep. **This exact pattern is reused below.**

### 1.2 Catalogue (`phoenix_kit_catalogue` v0.10.0+, tables in core V87+)

- `phoenix_kit_cat_suppliers` — thin directory: name (non-unique!), description, website, **one free-text `contact_info` varchar(500)** ("email or phone"), notes, status, `data` JSONB. No structured email/phone/address, no tax id, no payment terms, no dedup, **no link to users or CRM**.
- `phoenix_kit_cat_manufacturer_suppliers` — bare M:N manufacturers↔suppliers.
- `phoenix_kit_cat_items` — has `belongs_to :primary_supplier` in the schema (`schemas/item.ex:95-99`), cast in changeset, rendered in the item form…
- **⚠️ Bug (Phase 0):** no core migration through V139 creates `primary_supplier_uuid` on `phoenix_kit_cat_items`; the live DB has no such column. Code is ahead of schema — saving a primary supplier from the UI fails at the DB layer. Independently confirmed twice during this analysis.
- **No procurement economics anywhere:** no per-supplier price, SKU, lead time, MOQ, currency.
- Both `cat_suppliers` and `crm_companies` currently hold **0 rows** in the dev DB.

### 1.3 Warehouse (`phoenix_kit_warehouse`, docs say "scaffold" — stale; substantially implemented)

- Six tables as Ecto schemas: `stock` (unique item×location balance), `inventory_documents`, `internal_orders`, `supplier_orders`, `goods_receipts`, `goods_issues`. Document lines live in `lines` JSONB with write-time snapshots (name/SKU/price).
- **Full procurement chain already works:** internal order → `SupplierOrders.generate_from_internal_order/2` (one draft PO per resolved supplier) → goods receipt → `StockLedger.receive_quantity/3`.
- `supplier_orders.supplier_uuid` and `goods_receipts.supplier_uuid` are **soft UUIDs resolved only through Catalogue** (`supplier_orders.ex:559-561, 647-661`): item's `primary_supplier_uuid` wins, else manufacturer's linked suppliers. **Zero references to CRM.**
- No customer entity; outbound host orders plug in via `source_refs` JSONB + the `SourceKinds` callback registry (`source_kinds.ex`) — the module degrades gracefully with none configured.
- **⚠️ Gap (Phase 0):** the module ships **no migrations** (`migration_module/0` not implemented) — its six tables cannot be created reproducibly. Blocks everything downstream.

### 1.4 Who owns what today

| Concern | CRM | Catalogue | Warehouse |
|---|---|---|---|
| Supplier identity | — | ✅ `cat_suppliers` (thin, flat) | soft `supplier_uuid` → catalogue |
| Supplier×item data (SKU/price/lead/MOQ) | — | — (only broken scalar pointer) | snapshots in `lines` JSONB |
| Client identity | — | — | — (host hook only) |
| Party↔login link | ✅ nullable `user_uuid` | — | — |
| Cross-module link style | guarded soft-dep (StaffLink) | hard FK intra-module only | soft UUID + `source_refs` |

---

## 2. How mature systems solve this

| System | Party model | Supplier/customer typing | Supplier×product data |
|---|---|---|---|
| **Odoo** | one `res.partner` | `supplier_rank` / `customer_rank` ints (both >0 = both roles); auto-incremented by confirmed POs/SOs | `product.supplierinfo`: (partner, product) → product_code, price, min_qty, delay, currency, validity |
| **SAP S/4HANA** | one Business Partner | roles `FLVN00/01` (vendor), `FLCU00/01` (customer) — one BP holds both | purchasing info records (vendor × material → price, lead time, MOQ) |
| **Dynamics 365** | Dataverse `msdyn_party` | Account/Contact/Vendor each carry `msdyn_partyid`; a party can be customer and vendor | vendor pricing on trade agreements |
| **ERPNext** | separate Customer/Supplier doctypes (**counter-example**) | doctype = the type; shared Contact/Address via Dynamic Link | Item Supplier child table (supplier + supplier part no), Item Price lists |
| **Zoho / Cin7 (SMB)** | contacts split customer/vendor, Zoho supports **merging** into one | flags | per-product supplier price on the product↔supplier edge |

**Convergence:** (1) one party master; (2) typing as roles/flags so a party can be both; (3) commercial per-product facts on a **(supplier × product) junction**, never on the party. Migration precedent for "standalone supplier directory → party model" is SAP CVI: dedup → match/create party → keep a cross-reference column during transition → demote the old master.

---

## 3. Options considered

**A. Supplier stays in catalogue; CRM links to it.**
Cheapest, but backwards: party identity owned by a downstream commercial module; a supplier-who-is-also-client fragments across two tables; `contact_info` free text never becomes structured; supplier×item data still homeless. Rejected.

**B. CRM owns the party (roles on companies/contacts); catalogue keeps supplier×item commercial data; soft-UUID resolver federates the two; `cat_suppliers` = standalone fallback. ← Recommended.**
Matches the industry convergence; every module stays independently installable; warehouse untouched; reuses two existing in-house patterns (StaffLink guarded soft-dep, warehouse write-time snapshots).

**C. Shared `phoenix_kit_parties` table in core.**
"Cleanest" single source of truth, but: violates the ownership rule (every table in core migrations belongs to a specific module); forces a party concept on catalogue-only installs; core release cadence becomes the bottleneck; duplicates what CRM *is*. Rejected now; Option B's stable party UUID + resolver makes a later escalation mechanical if a true cross-module "customer 360" is ever needed.

---

## 4. Design (Option B)

### 4.1 CRM: `phoenix_kit_crm_party_roles` (core migration V140)

Polymorphic role edge — a role can attach to a **company or a contact** (sole-trader suppliers are contacts), so `roleable_uuid` carries no DB FK (polymorphic; integrity in Ecto changesets, consistency audited by an admin task).

```elixir
create table(:phoenix_kit_crm_party_roles, primary_key: false) do
  add :uuid,          :uuid,   primary_key: true, default: fragment("uuid_generate_v7()")
  add :roleable_type, :string, size: 20, null: false    # "company" | "contact"
  add :roleable_uuid, :uuid,   null: false               # → crm_companies | crm_contacts (no FK)
  add :role,          :string, size: 30, null: false     # "supplier" | "client" | "partner" | ...
  add :is_active,     :boolean, default: true, null: false
  add :valid_from,    :date
  add :valid_to,      :date                              # role lifecycle: former supplier etc.
  add :metadata,      :map, default: %{}                 # payment terms, tax id, account no, currency…
  timestamps(type: :utc_datetime_usec)
end
create unique_index(:phoenix_kit_crm_party_roles, [:roleable_type, :roleable_uuid, :role])
create index(:phoenix_kit_crm_party_roles, [:role, :is_active])
create index(:phoenix_kit_crm_party_roles, [:roleable_type, :roleable_uuid])
```

- Initial vocabulary `~w(supplier client partner)`; extensible without migration.
- Role-scoped commercial attributes (payment terms, default currency, tax/registration number) start in `metadata` JSONB; promote to typed columns when stable. This keeps the *party* clean and puts procurement attributes on the *role*, mirroring SAP (identity on BP, purchasing data on the FLVN role).
- Context `PhoenixKitCRM.PartyRoles`: `grant_role/3`, `revoke_role/2`, `has_role?/2`, `list_suppliers/1`, `list_clients/1`, `get_supplier/1` (hydrates company/contact + role metadata into a normalized map for the resolver contract, §4.3).
- Why an edge table and not `supplier_rank`-style columns: roles must attach to two roleable types, carry validity windows and per-role metadata, and extend without migrations. Rows > columns here; Odoo's ranks work because Odoo has exactly one partner table.
- UI: Companies/Contacts forms gain a "Roles" multi-select; new filtered tabs "Suppliers" and "Clients" on the CRM index pages; role badges in tables.
- This **broadens** v1's earmarked `crm_contact_relationships`: commercial roles (this table) and interpersonal relationships (future contact↔contact/company edge) are orthogonal axes and stay separate tables.

### 4.2 Catalogue: `phoenix_kit_cat_item_supplier_info` (core migration V141)

The `product.supplierinfo` equivalent — item-scoped, therefore catalogue-owned. Replaces the un-migrated `items.primary_supplier_uuid` scalar (no data exists, so no data migration: go straight to the junction and repoint the item form UI).

```elixir
create table(:phoenix_kit_cat_item_supplier_info, primary_key: false) do
  add :uuid, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
  add :item_uuid, references(:phoenix_kit_cat_items, column: :uuid, type: :uuid,
        on_delete: :delete_all), null: false              # intra-module: hard FK
  add :supplier_uuid, :uuid, null: false                  # cross-module: SOFT (CRM company/contact OR cat_supplier)
  add :supplier_name_snapshot, :string, size: 255         # write-time snapshot, survives renames
  add :supplier_sku,   :string, size: 100                 # supplier's own article code
  add :unit_cost,      :decimal, precision: 14, scale: 4
  add :currency,       :string, size: 3
  add :lead_time_days, :integer
  add :min_order_qty,  :decimal, precision: 14, scale: 4
  add :is_primary,     :boolean, default: false, null: false
  add :valid_from,     :date
  add :valid_to,       :date
  add :position,       :integer, default: 0, null: false
  add :metadata,       :map, default: %{}
  timestamps(type: :utc_datetime_usec)
end
create index(:phoenix_kit_cat_item_supplier_info, [:item_uuid])
create index(:phoenix_kit_cat_item_supplier_info, [:supplier_uuid])
create unique_index(:phoenix_kit_cat_item_supplier_info, [:item_uuid],
  where: "is_primary = true", name: :cat_item_supplier_info_primary_uniq)
```

Also in V141: `ALTER TABLE phoenix_kit_cat_suppliers ADD COLUMN crm_company_uuid uuid` (nullable, soft cross-reference stamped by the backfill task, §4.5).

### 4.3 The supplier resolver contract (catalogue-owned facade)

Warehouse already treats catalogue as the supplier source of truth — keep that facade and federate CRM behind it:

```elixir
defmodule PhoenixKitCatalogue.Catalogue.Suppliers do
  # list = CRM parties with active supplier role (when CRM loaded) ++ local cat_suppliers fallback
  def list_suppliers(opts \\ []), do: merge(crm_suppliers(opts), local_suppliers(opts))

  # hydrate uuid → %{uuid, name, email, phone, website, source: :crm | :local}
  def resolve(uuid) do
    cond do
      crm_loaded?() && (rec = PhoenixKitCRM.PartyRoles.get_supplier(uuid)) -> {:ok, rec, :crm}
      rec = get_local_supplier(uuid) -> {:ok, rec, :local}
      true -> :error
    end
  end

  defp crm_loaded? do
    Code.ensure_loaded?(PhoenixKitCRM.PartyRoles) and
      function_exported?(PhoenixKitCRM.PartyRoles, :get_supplier, 1)
  end
end
```

- Same guarded soft-dep pattern as `PhoenixKitCRM.StaffLink` — no `mix.exs` dependency in either direction.
- **Warehouse needs zero changes**: `Catalogue.list_suppliers/0` / `get_supplier/1` transparently return CRM parties when CRM is present.
- Snapshot discipline: every writer of a soft `supplier_uuid` stores `supplier_name_snapshot` at write time (warehouse already snapshots into `lines`); posted documents stay readable after party renames/merges.

### 4.4 Linking rules (to be extracted into an ADR)

| Reference | Style |
|---|---|
| within one module's own tables | hard FK with explicit `on_delete` |
| `party_roles.roleable_uuid` (company XOR contact) | soft UUID (polymorphic) |
| `item_supplier_info.supplier_uuid`, `cat_suppliers.crm_company_uuid` | soft UUID (optional-module boundary) |
| warehouse `supplier_uuid`, `item_uuid` | soft UUID (unchanged) |
| module↔module code | `Code.ensure_loaded?` + `function_exported?` guard, no mix dep |

Add a periodic consistency-check admin task (orphaned soft UUIDs report) so app-layer integrity is auditable.

### 4.5 Migration of `cat_suppliers` → CRM (SAP CVI pattern, opt-in)

`mix phoenix_kit_crm.import_suppliers_from_catalogue` — idempotent, **dry-run by default**, produces a review report before writing. Per row: match existing CRM company by normalized email/website (from `contact_info`/`website`) → else create company from name/website/notes; grant `supplier` role; stamp `cat_suppliers.crm_company_uuid`; rewrite `item_supplier_info.supplier_uuid` to the CRM uuid. `cat_suppliers` rows stay in place (dormant fallback); the table is retired in a later major once telemetry shows the resolver never returns `:local`. Both tables are empty in our deployments today, so for us this task is a no-op — new supplier data should be entered in CRM from day one.

### 4.6 Client side

- Identity: `client` role rows on the same `party_roles` table; CRM "Clients" tab + role filter.
- Warehouse: register a `SourceKinds` entry so client orders flow through the existing seam — `%{kind: "crm_client", search/resolve/build_lines: {PhoenixKitCRM.WarehouseIntegration, …}}`; client orders appear in `source_refs` as `%{"type" => "crm_client", "uuid" => party_uuid}`. No schema change.
- Catalogue: nothing for v1; a future client price list can build on per-catalogue markup/discount.
- Future sales outbound (goods issue → customer shipment) gets its own document type with a soft `customer_uuid`, rather than overloading production write-offs.
- Newsletters tie-in (from the parallel newsletters expansion spec): CRM clients with consent can be synced into newsletter contact lists by email — the party UUID + normalized email make that mapping trivial.

---

## 5. Rollout phases

| Phase | Scope | Repos touched | Risk |
|---|---|---|---|
| **0 — Hygiene (blockers)** | (a) Fix `primary_supplier_uuid` skew — skip the scalar, ship the junction (§4.2) and repoint item form; (b) implement warehouse `migration_module/0` so its six tables ship; (c) email normalization on `crm_contacts`/`crm_companies` (citext), per the parallel users-architecture analysis | core, catalogue, warehouse | low |
| **1 — CRM party roles** | V140 table + `PartyRoles` context + roles UI (additive, no cross-module wiring) | core, crm | low |
| **2 — Supplierinfo + resolver** | V141 junction + `crm_company_uuid` column + `Suppliers` facade federation + item-form UI | core, catalogue | medium (first cross-module resolver — codify ADR + consistency task) |
| **3 — Backfill (opt-in)** | mix task §4.5; dry-run + report | crm | medium (empty tables today → trivial for us) |
| **4 — Clients + warehouse seam** | Clients UI; `crm_client` SourceKind registration; host config | crm, host | low |
| **5 — Future** | company-subject interactions (relax `interactions.contact_uuid NOT NULL`); typed custom-field definitions on contact/company; supplier attributes promoted from role metadata to columns; deals/leads; retire `cat_suppliers` | crm, catalogue | higher |

**Definition of done (Phases 1–2):** CRM-only install works with no catalogue calls; catalogue+warehouse without CRM resolve suppliers from `cat_suppliers` exactly as today; all-three install resolves warehouse PO suppliers from CRM parties with supplier×item facts driving the picker; one company can hold both supplier and client roles; `mix quality` green; integration tests cover the three install combinations.

---

## 6. Risks & open questions

1. **Warehouse DDL ownership** — must be decided in Phase 0: module-owned `migration_module/0` (recommended, mirrors other modules) vs host-owned.
2. **First cross-module resolver in the ecosystem** — without the ADR + consistency task, orphaned soft UUIDs accumulate silently.
3. **Backfill matching heuristics** — `contact_info` free text makes email/website matching fuzzy; dry-run report is mandatory. (Moot while tables are empty.)
4. **Contact-centric interactions** — supplier companies can't be interaction subjects until Phase 5; acceptable interim (company pages stay rollups).
5. **Role vocabulary governance** — free-string `role` needs a single source of allowed values (`@roles` module attr + changeset validation) to avoid "supplier"/"vendor" drift.
6. **`manufacturer_suppliers` M:N** — unchanged for now (resolves through the same facade); revisit when manufacturers also become CRM parties (out of scope here).
