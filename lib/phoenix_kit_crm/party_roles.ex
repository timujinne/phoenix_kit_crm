defmodule PhoenixKitCRM.PartyRoles do
  @moduledoc """
  Context for CRM party roles — marks an existing company or contact as a
  `supplier`, `client`, or `partner` (see `PhoenixKitCRM.Schemas.PartyRole`).

  Mutations are logged here (not in the LiveViews) because `grant_role/3`
  and `revoke_role/2` are called from both the company form and the contact
  form's Roles section — a single log point keeps the audit trail consistent
  regardless of caller, mirroring `PhoenixKitCRM.Interactions`. There is no
  live-updating tab for roles yet, so unlike interactions this context does
  not broadcast over PubSub.
  """

  import Ecto.Query, warn: false

  alias PhoenixKit.RepoHelper
  alias PhoenixKitCRM.Activity
  alias PhoenixKitCRM.Schemas.{Company, Contact, PartyRole}

  defp repo, do: RepoHelper.repo()

  # ── Grant / revoke ──────────────────────────────────────────────────

  @doc """
  Grants `role` to a company or contact. Idempotent: granting an already-active
  role is a no-op (returns the existing row); granting a previously-revoked
  role reactivates it (clears `valid_to`). `attrs` may set `:valid_from` /
  `:valid_to` — never pass caller-supplied `metadata` here from a UI path.
  """
  @spec grant_role(Company.t() | Contact.t(), String.t(), map()) ::
          {:ok, PartyRole.t()} | {:error, Ecto.Changeset.t()}
  def grant_role(roleable, role, attrs \\ %{}) do
    type = roleable_type(roleable)
    uuid = roleable.uuid
    attrs = stringify_keys(attrs)

    case repo().get_by(PartyRole, roleable_type: type, roleable_uuid: uuid, role: role) do
      nil ->
        %PartyRole{}
        |> PartyRole.changeset(
          Map.merge(attrs, %{
            "roleable_type" => type,
            "roleable_uuid" => uuid,
            "role" => role
          })
        )
        |> repo().insert()
        |> log_on_ok("crm.party_role_granted", type, uuid)

      %PartyRole{is_active: true} = existing ->
        {:ok, existing}

      %PartyRole{is_active: false} = existing ->
        existing
        |> PartyRole.changeset(Map.merge(attrs, %{"is_active" => true, "valid_to" => nil}))
        |> repo().update()
        |> log_on_ok("crm.party_role_granted", type, uuid)
    end
  end

  @doc """
  Revokes `role` from a company or contact — sets `is_active` false and stamps
  `valid_to` with today's date. Never deletes the row (role history is kept).
  A no-op if the role isn't currently held (returns `{:error, :not_found}`) or
  is already inactive.
  """
  @spec revoke_role(Company.t() | Contact.t(), String.t()) ::
          {:ok, PartyRole.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def revoke_role(roleable, role) do
    type = roleable_type(roleable)
    uuid = roleable.uuid

    case repo().get_by(PartyRole, roleable_type: type, roleable_uuid: uuid, role: role) do
      nil ->
        {:error, :not_found}

      %PartyRole{is_active: false} = existing ->
        {:ok, existing}

      %PartyRole{} = existing ->
        existing
        |> PartyRole.changeset(%{"is_active" => false, "valid_to" => Date.utc_today()})
        |> repo().update()
        |> log_on_ok("crm.party_role_revoked", type, uuid)
    end
  end

  defp log_on_ok({:ok, %PartyRole{} = party_role} = ok, action, roleable_type, roleable_uuid) do
    Activity.log(action,
      resource_type: resource_type(roleable_type),
      resource_uuid: roleable_uuid,
      metadata: %{"role" => party_role.role, "roleable_type" => roleable_type}
    )

    ok
  end

  defp log_on_ok(error, _action, _type, _uuid), do: error

  defp resource_type("company"), do: "crm_company"
  defp resource_type("contact"), do: "crm_contact"

  # ── Queries ─────────────────────────────────────────────────────────

  @doc "Whether the company/contact currently has an active `role`."
  @spec has_role?(Company.t() | Contact.t(), String.t()) :: boolean()
  def has_role?(roleable, role) do
    type = roleable_type(roleable)
    uuid = roleable.uuid

    PartyRole
    |> where(
      [pr],
      pr.roleable_type == ^type and pr.roleable_uuid == ^uuid and pr.role == ^role and
        pr.is_active == true
    )
    |> repo().exists?()
  end

  @doc "All role rows (active and inactive) held by a company/contact, role ascending."
  @spec list_roles(Company.t() | Contact.t()) :: [PartyRole.t()]
  def list_roles(roleable) do
    type = roleable_type(roleable)
    uuid = roleable.uuid

    PartyRole
    |> where([pr], pr.roleable_type == ^type and pr.roleable_uuid == ^uuid)
    |> order_by([pr], asc: pr.role)
    |> repo().all()
  end

  @doc """
  Companies holding an active `role`, name ascending. Excludes trashed
  companies by default.

  ## Options
    * `:include_inactive` — include revoked role rows too
    * `:include_trashed` — include trashed companies too
  """
  @spec list_companies_with_role(String.t(), keyword()) :: [Company.t()]
  def list_companies_with_role(role, opts \\ []) do
    uuids = roleable_uuids("company", role, opts)

    Company
    |> where([c], c.uuid in ^uuids)
    |> maybe_exclude_trashed(opts)
    |> order_by([c], asc: c.name)
    |> repo().all()
  end

  @doc "Contacts holding an active `role`, name ascending. Same options as `list_companies_with_role/2`."
  @spec list_contacts_with_role(String.t(), keyword()) :: [Contact.t()]
  def list_contacts_with_role(role, opts \\ []) do
    uuids = roleable_uuids("contact", role, opts)

    Contact
    |> where([c], c.uuid in ^uuids)
    |> maybe_exclude_trashed(opts)
    |> order_by([c], asc: c.name)
    |> repo().all()
  end

  defp roleable_uuids(type, role, opts) do
    PartyRole
    |> where([pr], pr.roleable_type == ^type and pr.role == ^role)
    |> maybe_active_scope(opts)
    |> select([pr], pr.roleable_uuid)
    |> repo().all()
  end

  defp maybe_active_scope(query, opts) do
    if Keyword.get(opts, :include_inactive, false),
      do: query,
      else: where(query, [pr], pr.is_active == true)
  end

  defp maybe_exclude_trashed(query, opts) do
    if Keyword.get(opts, :include_trashed, false),
      do: query,
      else: where(query, [c], c.status != "trashed")
  end

  @doc """
  Resolver entry point for the (future) Catalogue supplier facade: given a
  company **or** contact uuid, returns `%{uuid, name, email, phone, website,
  source: :crm}` if that party currently has an *active* `supplier` role, or
  `nil` otherwise (unknown uuid, inactive role, or no supplier role at all).

  This is the contract `PhoenixKitCatalogue.Catalogue.Suppliers.resolve/1`
  will call in Phase 2 (see the CRM v2 parties design doc, §4.3) — keep the
  return shape stable.
  """
  @spec get_supplier(UUIDv7.t() | String.t() | nil) ::
          %{
            uuid: UUIDv7.t(),
            name: String.t(),
            email: String.t() | nil,
            phone: String.t() | nil,
            website: String.t() | nil,
            source: :crm
          }
          | nil
  def get_supplier(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, _} ->
        case active_supplier_role(uuid) do
          %PartyRole{roleable_type: "company"} -> hydrate_company_supplier(uuid)
          %PartyRole{roleable_type: "contact"} -> hydrate_contact_supplier(uuid)
          nil -> nil
        end

      :error ->
        nil
    end
  end

  defp active_supplier_role(uuid) do
    PartyRole
    |> where([pr], pr.roleable_uuid == ^uuid and pr.role == "supplier" and pr.is_active == true)
    |> repo().one()
  end

  defp hydrate_company_supplier(uuid) do
    case repo().get(Company, uuid) do
      %Company{} = c ->
        %{
          uuid: c.uuid,
          name: Company.display_name(c),
          email: c.email,
          phone: c.phone,
          website: c.website,
          source: :crm
        }

      nil ->
        nil
    end
  end

  defp hydrate_contact_supplier(uuid) do
    case repo().get(Contact, uuid) do
      %Contact{} = c ->
        %{
          uuid: c.uuid,
          name: Contact.display_name(c),
          email: c.email,
          phone: c.phone,
          website: nil,
          source: :crm
        }

      nil ->
        nil
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp roleable_type(%Company{}), do: "company"
  defp roleable_type(%Contact{}), do: "contact"

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
