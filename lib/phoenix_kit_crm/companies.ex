defmodule PhoenixKitCRM.Companies do
  @moduledoc """
  Context for CRM companies — CRUD, soft-delete, and search (for the contact
  form's company picker).
  """

  import Ecto.Query, warn: false

  alias PhoenixKit.RepoHelper
  alias PhoenixKitCRM.Schemas.{Company, CompanyMembership}

  defp repo, do: RepoHelper.repo()

  @doc "Memberships at a company (primary first), each with its contact preloaded."
  @spec list_memberships(UUIDv7.t() | String.t() | nil) :: [CompanyMembership.t()]
  def list_memberships(company_uuid) do
    case Ecto.UUID.cast(company_uuid) do
      {:ok, _} ->
        from(m in CompanyMembership,
          where: m.company_uuid == ^company_uuid,
          order_by: [desc: m.is_primary, asc: m.position]
        )
        |> repo().all()
        |> repo().preload(:contact)

      :error ->
        []
    end
  end

  @doc """
  Lists companies. Excludes trashed by default.

  ## Options
    * `:status` — `"trashed"` for the Trash view, or any specific status
    * `:include_trashed` — `true` to include trashed alongside the rest
  """
  @spec list_companies(keyword()) :: [Company.t()]
  def list_companies(opts \\ []) do
    Company
    |> apply_status_scope(opts)
    |> order_by([c], asc: c.name)
    |> repo().all()
  end

  @spec count_companies(keyword()) :: non_neg_integer()
  def count_companies(opts \\ []) do
    Company
    |> apply_status_scope(opts)
    |> repo().aggregate(:count, :uuid)
  end

  @spec get_company(UUIDv7.t() | String.t() | nil) :: Company.t() | nil
  def get_company(uuid) do
    # Format-check first so a malformed id returns nil instead of raising.
    case Ecto.UUID.cast(uuid) do
      {:ok, _} -> repo().get(Company, uuid)
      :error -> nil
    end
  end

  @spec change_company(Company.t(), map()) :: Ecto.Changeset.t()
  def change_company(%Company{} = company, attrs \\ %{}),
    do: Company.changeset(company, attrs)

  @spec create_company(map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def create_company(attrs) do
    %Company{}
    |> Company.changeset(attrs)
    |> repo().insert()
  end

  @spec update_company(Company.t(), map()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def update_company(%Company{} = company, attrs) do
    company
    |> Company.changeset(attrs)
    |> repo().update()
  end

  @doc "Soft-deletes a company (status → trashed, stashing the prior status)."
  @spec trash_company(Company.t()) :: {:ok, Company.t()} | {:error, atom() | Ecto.Changeset.t()}
  def trash_company(%Company{status: "trashed"}), do: {:error, :already_trashed}

  def trash_company(%Company{} = company) do
    meta = Map.put(company.metadata || %{}, "trashed_from_status", company.status)

    company
    |> Ecto.Changeset.change(status: Company.soft_delete_status(), metadata: meta)
    |> repo().update()
  end

  @spec restore_company(Company.t()) :: {:ok, Company.t()} | {:error, atom() | Ecto.Changeset.t()}
  def restore_company(%Company{status: "trashed"} = company) do
    prior = Map.get(company.metadata || %{}, "trashed_from_status")
    status = if prior in Company.statuses(), do: prior, else: "active"
    meta = Map.delete(company.metadata || %{}, "trashed_from_status")

    company
    |> Ecto.Changeset.change(status: status, metadata: meta)
    |> repo().update()
  end

  def restore_company(%Company{}), do: {:error, :not_trashed}

  @doc "Permanently deletes a company (cascades its memberships)."
  @spec delete_company(Company.t()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
  def delete_company(%Company{} = company), do: repo().delete(company)

  @doc "Searches companies by name (case-insensitive) for the picker. Excludes trashed."
  @spec search_companies(String.t(), pos_integer()) :: [Company.t()]
  def search_companies(query, limit \\ 8) when is_binary(query) do
    q = String.trim(query)

    if q == "" do
      []
    else
      like = "%#{q}%"

      Company
      |> where([c], c.status != "trashed")
      |> where([c], ilike(c.name, ^like))
      |> order_by([c], asc: c.name)
      |> limit(^limit)
      |> repo().all()
    end
  end

  defp apply_status_scope(query, opts) do
    cond do
      opts[:status] -> where(query, [c], c.status == ^opts[:status])
      opts[:include_trashed] -> query
      true -> where(query, [c], c.status != "trashed")
    end
  end
end
