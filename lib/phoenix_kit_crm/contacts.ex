defmodule PhoenixKitCRM.Contacts do
  @moduledoc """
  Context for CRM contacts — CRUD, soft-delete, the (v1 single) company
  membership, and the **optional** login-user connection.

  The user connection mirrors `phoenix_kit_staff`'s flow but is opt-in: a
  contact has no `user_uuid` until `connect_user/2` is called (driven by the
  form's "allow login" checkbox). It uses find-or-create — an existing user
  by email is linked; if none exists a placeholder is registered (tagged
  `custom_fields.source = "crm_contact"`), which the person can later claim by
  registering / signing in with that email.
  """

  import Ecto.Query, warn: false
  require Logger

  alias PhoenixKit.RepoHelper
  alias PhoenixKit.Users.Auth
  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.Schemas.{CompanyMembership, Contact}
  alias PhoenixKitCRM.SoftDelete

  defp repo, do: RepoHelper.repo()

  @placeholder_source "crm_contact"

  # ── Queries ─────────────────────────────────────────────────────────

  @doc """
  Lists contacts. Excludes trashed by default; preloads the primary company
  membership (with company) and the linked user.
  """
  @spec list_contacts(keyword()) :: [Contact.t()]
  def list_contacts(opts \\ []) do
    Contact
    |> apply_status_scope(opts)
    |> order_by([c], asc: c.name)
    |> repo().all()
    |> repo().preload(company_memberships: :company, user: [])
  end

  @doc "Contacts for the given uuids (any status) — for comment back-link resolution."
  @spec list_by_uuids([binary()]) :: [Contact.t()]
  def list_by_uuids([]), do: []

  def list_by_uuids(uuids) when is_list(uuids) do
    # Drop malformed ids so one bad element can't raise an Ecto cast error.
    case Enum.filter(uuids, &valid_uuid?/1) do
      [] -> []
      valid -> from(c in Contact, where: c.uuid in ^valid) |> repo().all()
    end
  end

  @spec count_contacts(keyword()) :: non_neg_integer()
  def count_contacts(opts \\ []) do
    Contact
    |> apply_status_scope(opts)
    |> repo().aggregate(:count, :uuid)
  end

  @doc """
  Groups non-trashed contacts sharing the same email (case-insensitive, via
  the column's citext type), for the CRM comparison screen's directory-wide
  duplicate-email report. Only emails held by 2+ contacts; blank/nil emails
  are never a "duplicate" (many contacts legitimately have none). Ordered by
  group size, largest first.
  """
  @spec list_duplicate_email_groups() :: [%{email: String.t(), count: pos_integer()}]
  def list_duplicate_email_groups do
    Contact
    |> where([c], not is_nil(c.email) and c.email != "" and c.status != "trashed")
    |> group_by([c], c.email)
    |> having([c], count(c.uuid) > 1)
    |> select([c], %{email: c.email, count: count(c.uuid)})
    |> order_by([c], desc: count(c.uuid))
    |> repo().all()
  end

  @doc "Non-trashed contacts holding exactly this email — the drill-down for a `list_duplicate_email_groups/0` row."
  @spec list_by_email(String.t()) :: [Contact.t()]
  def list_by_email(email) when is_binary(email) do
    Contact
    |> where([c], c.email == ^email and c.status != "trashed")
    |> order_by([c], asc: c.inserted_at)
    |> repo().all()
    |> repo().preload(company_memberships: :company)
  end

  @spec get_contact(UUIDv7.t() | String.t() | nil) :: Contact.t() | nil
  def get_contact(uuid) do
    # Validate the UUID format first so a malformed id (bad URL / forged event)
    # returns nil instead of raising an Ecto cast error.
    with {:ok, _} <- Ecto.UUID.cast(uuid),
         %Contact{} = contact <- repo().get(Contact, uuid) do
      repo().preload(contact, company_memberships: :company, user: [])
    else
      _ -> nil
    end
  end

  @doc "The (at most one) contact linked to a given login user, or nil."
  @spec get_by_user_uuid(UUIDv7.t() | String.t() | nil) :: Contact.t() | nil
  def get_by_user_uuid(nil), do: nil

  def get_by_user_uuid(user_uuid) do
    # Format-check first so a malformed id returns nil instead of raising.
    case Ecto.UUID.cast(user_uuid) do
      {:ok, _} -> repo().get_by(Contact, user_uuid: user_uuid)
      :error -> nil
    end
  end

  @doc "The contact's primary company membership (or the first), or nil."
  @spec primary_membership(Contact.t()) :: CompanyMembership.t() | nil
  def primary_membership(%Contact{company_memberships: memberships})
      when is_list(memberships) do
    Enum.find(memberships, & &1.is_primary) || List.first(memberships)
  end

  def primary_membership(%Contact{}), do: nil

  # ── Mutations ───────────────────────────────────────────────────────

  @spec change_contact(Contact.t(), map()) :: Ecto.Changeset.t()
  def change_contact(%Contact{} = contact, attrs \\ %{}),
    do: Contact.changeset(contact, attrs)

  @spec create_contact(map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact(attrs) do
    %Contact{}
    |> Contact.changeset(attrs)
    |> repo().insert()
  end

  @spec update_contact(Contact.t(), map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> repo().update()
  end

  @doc "Soft-deletes a contact (status → trashed, stashing the prior status)."
  @spec trash_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, atom() | Ecto.Changeset.t()}
  def trash_contact(%Contact{status: "trashed"}), do: {:error, :already_trashed}

  def trash_contact(%Contact{} = contact) do
    contact
    |> SoftDelete.trash_changeset(Contact.soft_delete_status())
    |> repo().update()
  end

  @spec restore_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, atom() | Ecto.Changeset.t()}
  def restore_contact(%Contact{status: "trashed"} = contact) do
    contact
    |> SoftDelete.restore_changeset(Contact.statuses())
    |> repo().update()
  end

  def restore_contact(%Contact{}), do: {:error, :not_trashed}

  @doc "Permanently deletes a contact (cascades memberships + interactions)."
  @spec delete_contact(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact(%Contact{} = contact), do: repo().delete(contact)

  @doc """
  Searches contacts by name/email (case-insensitive) for the parties picker.
  Excludes trashed and any uuids in `exclude_uuids` (e.g. the contact whose page
  the interaction is being logged on — they're already the subject).
  """
  @spec search_contacts(String.t(), pos_integer(), [binary()]) :: [Contact.t()]
  def search_contacts(query, limit \\ 8, exclude_uuids \\ []) when is_binary(query) do
    q = query |> String.replace("\x00", "") |> String.trim()

    if q == "" do
      []
    else
      like = like_pattern(q)

      Contact
      |> where([c], c.status != "trashed")
      |> where([c], ilike(c.name, ^like) or ilike(c.email, ^like))
      |> maybe_exclude_uuids(exclude_uuids)
      |> order_by([c], asc: c.name)
      |> limit(^limit)
      |> repo().all()
    end
  end

  defp maybe_exclude_uuids(query, []), do: query
  defp maybe_exclude_uuids(query, uuids), do: where(query, [c], c.uuid not in ^uuids)

  # Wrap a trimmed search term in `%…%`, escaping the LIKE/ILIKE metacharacters
  # (`\`, `%`, `_`) so a literal `%` matches a percent sign rather than acting as
  # a wildcard. Postgres ILIKE uses backslash as the default escape character.
  defp like_pattern(q) do
    escaped =
      q
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end

  # ── Company membership (v1: a single primary company per contact) ───

  @doc """
  Sets the contact's primary company membership to the given company, with
  free-form role + department. v1 manages exactly one company per contact via
  the form, so this replaces the contact's membership set. A blank/nil company
  clears it.
  """
  @spec set_primary_company(
          Contact.t(),
          UUIDv7.t() | String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) ::
          {:ok, CompanyMembership.t() | nil} | {:error, Ecto.Changeset.t()}
  def set_primary_company(%Contact{} = contact, company_uuid, _role, _department)
      when company_uuid in [nil, ""] do
    clear_memberships(contact)
    {:ok, nil}
  end

  def set_primary_company(%Contact{} = contact, company_uuid, role, department) do
    repo().transaction(fn ->
      clear_memberships(contact)

      result =
        %CompanyMembership{}
        |> CompanyMembership.changeset(%{
          "contact_uuid" => contact.uuid,
          "company_uuid" => company_uuid,
          "role_in_company" => role,
          "department" => department,
          "is_primary" => true,
          "position" => 0
        })
        |> repo().insert()

      case result do
        {:ok, membership} -> membership
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  defp clear_memberships(%Contact{uuid: uuid}) do
    from(m in CompanyMembership, where: m.contact_uuid == ^uuid) |> repo().delete_all()
  end

  # ── Optional login-user connection (staff-style find-or-create) ─────

  @doc """
  Connects a contact to a login user by email (staff-style find-or-create).
  Existing user by email → linked; otherwise a placeholder user is registered.
  Rolls back a just-created placeholder if the link fails. No-op-safe to call
  on an already-linked contact (re-links).
  """
  @spec connect_user(Contact.t(), String.t()) ::
          {:ok, Contact.t(), :existing | :created} | {:error, atom() | Ecto.Changeset.t()}
  def connect_user(%Contact{} = contact, email) when is_binary(email) do
    with {:ok, user, user_status} <- find_or_create_user_by_email(email),
         {:ok, linked} <- link_or_rollback(contact, user, user_status) do
      {:ok, linked, user_status}
    end
  end

  defp link_or_rollback(contact, user, user_status) do
    case contact |> Contact.link_user_changeset(user.uuid) |> repo().update() do
      {:ok, linked} ->
        {:ok, linked}

      {:error, _} = err ->
        if user_status == :created, do: _ = repo().delete(user)
        err
    end
  end

  @doc "Disconnects a contact from its login user (unlinks only; never deletes the user)."
  @spec disconnect_user(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def disconnect_user(%Contact{} = contact) do
    contact
    |> Contact.link_user_changeset(nil)
    |> repo().update()
  end

  @doc """
  Finds an existing user by email, or registers a placeholder with no usable
  password (tagged `custom_fields.source = "crm_contact"`).
  """
  @spec find_or_create_user_by_email(String.t()) ::
          {:ok, User.t(), :existing | :created} | {:error, atom() | Ecto.Changeset.t()}
  def find_or_create_user_by_email(email) when is_binary(email) do
    case String.trim(email) do
      "" -> {:error, :blank_email}
      trimmed -> find_or_register_placeholder(trimmed)
    end
  end

  defp find_or_register_placeholder(email) do
    case Auth.get_user_by_email(email) do
      %User{} = user -> {:ok, user, :existing}
      nil -> register_placeholder(email)
    end
  end

  defp register_placeholder(email) do
    random_password =
      :crypto.strong_rand_bytes(24) |> Base.url_encode64() |> binary_part(0, 24)

    attrs = %{
      "email" => email,
      "password" => random_password <> "Aa1!",
      "custom_fields" => %{"source" => @placeholder_source}
    }

    with {:ok, user} <- Auth.register_user(attrs), do: {:ok, user, :created}
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp apply_status_scope(query, opts) do
    cond do
      opts[:status] -> where(query, [c], c.status == ^opts[:status])
      opts[:include_trashed] -> query
      true -> where(query, [c], c.status != "trashed")
    end
  end

  defp valid_uuid?(uuid), do: match?({:ok, _}, Ecto.UUID.cast(uuid))
end
