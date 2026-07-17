defmodule PhoenixKitCRM.Lists do
  @moduledoc """
  Context for CRM contact lists (`PhoenixKitCRM.Schemas.ContactList`) and
  their memberships (`PhoenixKitCRM.Schemas.ListMember`).

  Modeled on `PhoenixKitCRM.PartyRoles` (soft-toggle mutations, `actor_uuid`
  audit via `PhoenixKitCRM.Activity`) with one deliberate divergence: unlike
  PartyRoles, this context broadcasts over PubSub (`PhoenixKitCRM.PubSub`,
  topic `crm:lists`) after every list/membership mutation — the admin UI
  shows live subscriber counters, so a live-updating feed is worth the extra
  moving part here even though PartyRoles didn't need one.

  Membership is never hard-deleted: `remove_from_list/2,3` flips `status` to
  `"removed"` and stamps `unsubscribed_at`, same as a list's `archive_list/1,2`
  only flips `status` rather than deleting the row. This keeps list history
  (and the `idx_crm_list_members_list_email` email slot — see the schema
  moduledoc) intact.

  Opt-out/consent live on the **contact**, not the membership — an opt-out
  applies across every list the contact belongs to. The Stage-4 send path is
  expected to check membership `status == "subscribed"` AND
  `contact.opted_out_at == nil`.

  `subscriber_count` is a maintained cache, kept in sync here via atomic
  `UPDATE ... SET subscriber_count = subscriber_count + $1` on every
  membership add/remove; `recount_list/1` is the repair function if it ever
  drifts.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset

  alias PhoenixKit.RepoHelper
  alias PhoenixKitCRM.Activity
  alias PhoenixKitCRM.PubSub
  alias PhoenixKitCRM.Schemas.{Contact, ContactList, ListMember}

  defp repo, do: RepoHelper.repo()

  # ── Lists CRUD ──────────────────────────────────────────────────────

  @spec change_list(ContactList.t(), map()) :: Ecto.Changeset.t()
  def change_list(%ContactList{} = list, attrs \\ %{}), do: ContactList.changeset(list, attrs)

  @doc "Creates a list. Pass `:actor_uuid` in `opts` for the activity log entry."
  @spec create_list(map(), keyword()) :: {:ok, ContactList.t()} | {:error, Ecto.Changeset.t()}
  def create_list(attrs, opts \\ []) do
    %ContactList{}
    |> ContactList.changeset(attrs)
    |> repo().insert()
    |> log_on_ok("crm.list_created", opts)
    |> broadcast_on_ok(:list_created, &list_payload/1)
  end

  @doc "Updates a list. Pass `:actor_uuid` in `opts` for the activity log entry."
  @spec update_list(ContactList.t(), map(), keyword()) ::
          {:ok, ContactList.t()} | {:error, Ecto.Changeset.t()}
  def update_list(%ContactList{} = list, attrs, opts \\ []) do
    list
    |> ContactList.changeset(attrs)
    |> repo().update()
    |> log_on_ok("crm.list_updated", opts)
    |> broadcast_on_ok(:list_updated, &list_payload/1)
  end

  @doc "Archives a list (status flip, not delete). Idempotent if already archived."
  @spec archive_list(ContactList.t(), keyword()) ::
          {:ok, ContactList.t()} | {:error, Ecto.Changeset.t()}
  def archive_list(list, opts \\ [])
  def archive_list(%ContactList{status: "archived"} = list, _opts), do: {:ok, list}

  def archive_list(%ContactList{} = list, opts) do
    list
    |> change(status: "archived")
    |> repo().update()
    |> log_on_ok("crm.list_archived", opts)
    |> broadcast_on_ok(:list_archived, &list_payload/1)
  end

  @doc "Unarchives a list back to active. Idempotent if already active."
  @spec unarchive_list(ContactList.t(), keyword()) ::
          {:ok, ContactList.t()} | {:error, Ecto.Changeset.t()}
  def unarchive_list(list, opts \\ [])
  def unarchive_list(%ContactList{status: "active"} = list, _opts), do: {:ok, list}

  def unarchive_list(%ContactList{} = list, opts) do
    list
    |> change(status: "active")
    |> repo().update()
    |> log_on_ok("crm.list_unarchived", opts)
    |> broadcast_on_ok(:list_unarchived, &list_payload/1)
  end

  @doc """
  Lists contact lists, name ascending.

  ## Options
    * `:status` — filter to one status (default: all)
    * `:subscribable` — filter to `subscribable == true/false` (default: all)
  """
  @spec list_lists(keyword()) :: [ContactList.t()]
  def list_lists(opts \\ []) do
    ContactList
    |> maybe_filter_status(opts)
    |> maybe_filter_subscribable(opts)
    |> order_by([l], asc: l.name)
    |> repo().all()
  end

  @spec get_list(UUIDv7.t() | String.t() | nil) :: ContactList.t() | nil
  def get_list(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, _} -> repo().get(ContactList, uuid)
      :error -> nil
    end
  end

  @spec get_list!(UUIDv7.t() | String.t()) :: ContactList.t()
  def get_list!(uuid), do: repo().get!(ContactList, uuid)

  @spec get_list_by_slug(String.t() | nil) :: ContactList.t() | nil
  def get_list_by_slug(nil), do: nil
  def get_list_by_slug(slug), do: repo().get_by(ContactList, slug: slug)

  # ── Membership ──────────────────────────────────────────────────────

  @doc """
  Adds a contact to a list — writes a membership snapshotting the contact's
  current email (may be `nil`; the contact is just unsendable). Sets
  `subscribed_at` and bumps the list's `subscriber_count`.

  ## Options
    * `:source` — one of `PhoenixKitCRM.Schemas.ListMember.sources/0` (default `"manual"`)
    * `:actor_uuid` — for the activity log entry

  Returns `{:error, :already_member}` if this contact is already in the
  list, or `{:error, :email_already_in_list}` if a *different* contact
  already holds this email in the list (the `idx_crm_list_members_list_email`
  race-shaped case — a `removed` member still holds its email slot).
  """
  @spec add_contact_to_list(Contact.t(), ContactList.t(), keyword()) ::
          {:ok, ListMember.t()}
          | {:error, :already_member | :email_already_in_list | Ecto.Changeset.t()}
  def add_contact_to_list(%Contact{} = contact, %ContactList{} = list, opts \\ []) do
    source = Keyword.get(opts, :source, "manual")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      "list_uuid" => list.uuid,
      "contact_uuid" => contact.uuid,
      "source" => source,
      "status" => "subscribed",
      "subscribed_at" => now
    }

    changeset =
      %ListMember{}
      |> ListMember.changeset(attrs)
      |> change(email: contact.email)

    case repo().insert(changeset) do
      {:ok, member} ->
        updated_list = bump_counter(list, 1)

        Activity.log("crm.list_member_added",
          actor_uuid: Keyword.get(opts, :actor_uuid),
          resource_type: "crm_list_member",
          resource_uuid: member.uuid,
          metadata: %{"list_uuid" => list.uuid, "contact_uuid" => contact.uuid}
        )

        PubSub.broadcast_list_event(:member_added, member_payload(member, updated_list))
        {:ok, member}

      {:error, cs} ->
        classify_membership_error(cs)
    end
  end

  @doc """
  Removes a contact's membership from a list (soft: `status` → `"removed"`,
  stamps `unsubscribed_at`). Never deletes the row. Idempotent if already
  removed. `opts` accepts `:actor_uuid`.

  Accepts either an existing `ListMember` directly, or a `contact` + `list`
  pair to look one up.
  """
  @spec remove_from_list(ListMember.t(), keyword()) ::
          {:ok, ListMember.t()} | {:error, Ecto.Changeset.t()}
  def remove_from_list(member, opts \\ [])
  def remove_from_list(%ListMember{status: "removed"} = member, _opts), do: {:ok, member}

  def remove_from_list(%ListMember{} = member, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case member |> change(status: "removed", unsubscribed_at: now) |> repo().update() do
      {:ok, updated} = ok ->
        list = repo().get!(ContactList, updated.list_uuid)
        updated_list = bump_counter(list, -1)

        Activity.log("crm.list_member_removed",
          actor_uuid: Keyword.get(opts, :actor_uuid),
          resource_type: "crm_list_member",
          resource_uuid: updated.uuid,
          metadata: %{"list_uuid" => updated.list_uuid, "contact_uuid" => updated.contact_uuid}
        )

        PubSub.broadcast_list_event(:member_removed, member_payload(updated, updated_list))
        ok

      error ->
        error
    end
  end

  @doc """
  Same as `remove_from_list/2`, but looks the membership up by contact + list
  instead of taking an existing `ListMember` directly. `opts` is required here
  (not defaulted) to avoid an arity clash with the single-struct form above —
  pass `[]` for no options.
  """
  @spec remove_from_list(Contact.t(), ContactList.t(), keyword()) ::
          {:ok, ListMember.t()} | {:error, :not_member | Ecto.Changeset.t()}
  def remove_from_list(%Contact{} = contact, %ContactList{} = list, opts) do
    case get_member(list, contact) do
      nil -> {:error, :not_member}
      %ListMember{} = member -> remove_from_list(member, opts)
    end
  end

  @doc "Whether the contact currently has an active (`subscribed`) membership on the list."
  @spec subscribed?(Contact.t(), ContactList.t()) :: boolean()
  def subscribed?(%Contact{} = contact, %ContactList{} = list) do
    ListMember
    |> where(
      [m],
      m.list_uuid == ^list.uuid and m.contact_uuid == ^contact.uuid and m.status == "subscribed"
    )
    |> repo().exists?()
  end

  @doc """
  Lists a list's memberships, newest first, contact preloaded.

  ## Options
    * `:status` — filter to one status (default: all)
    * `:search` — case-insensitive match on the member's email or its contact's name
    * `:limit` / `:offset` — pagination
  """
  @spec list_members(ContactList.t(), keyword()) :: [ListMember.t()]
  def list_members(%ContactList{} = list, opts \\ []) do
    ListMember
    |> where([m], m.list_uuid == ^list.uuid)
    |> maybe_filter_member_status(opts)
    |> maybe_search_members(opts)
    |> order_by([m], desc: m.inserted_at)
    |> maybe_paginate(opts)
    |> repo().all()
    |> repo().preload(:contact)
  end

  @doc "Recomputes and stores `subscriber_count` from the actual subscribed-member count. Repair function."
  @spec recount_list(ContactList.t()) :: ContactList.t()
  def recount_list(%ContactList{} = list) do
    count =
      ListMember
      |> where([m], m.list_uuid == ^list.uuid and m.status == "subscribed")
      |> repo().aggregate(:count, :uuid)

    updated_list = set_counter(list, count)
    PubSub.broadcast_list_event(:list_recounted, list_payload(updated_list))
    updated_list
  end

  defp get_member(%ContactList{} = list, %Contact{} = contact) do
    repo().get_by(ListMember, list_uuid: list.uuid, contact_uuid: contact.uuid)
  end

  defp classify_membership_error(%Ecto.Changeset{errors: errors} = cs) do
    cond do
      Keyword.has_key?(errors, :email) ->
        {:error, :email_already_in_list}

      Keyword.has_key?(errors, :list_uuid) or Keyword.has_key?(errors, :contact_uuid) ->
        {:error, :already_member}

      true ->
        {:error, cs}
    end
  end

  defp bump_counter(%ContactList{uuid: uuid}, delta) do
    {1, _} =
      ContactList
      |> where([l], l.uuid == ^uuid)
      |> repo().update_all(inc: [subscriber_count: delta])

    repo().get!(ContactList, uuid)
  end

  defp set_counter(%ContactList{uuid: uuid}, count) do
    {1, _} =
      ContactList
      |> where([l], l.uuid == ^uuid)
      |> repo().update_all(set: [subscriber_count: count])

    repo().get!(ContactList, uuid)
  end

  # ── Contact-level opt-out / consent ──────────────────────────────────

  @doc """
  Opts a contact out — sets `opted_out_at` and appends an entry to `consent`
  (`ts`/`action`/`actor_uuid`/`source`). Applies across every list the
  contact belongs to (the send path checks this, not per-membership status).
  Idempotent: a no-op if already opted out.

  ## Options
    * `:source` — free-form origin tag (e.g. `"admin"`, `"unsubscribe_link"`); default `"manual"`
    * `:actor_uuid` — for the activity log entry
  """
  @spec opt_out(Contact.t(), keyword()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def opt_out(contact, opts \\ [])

  def opt_out(%Contact{opted_out_at: opted_out_at} = contact, _opts)
      when not is_nil(opted_out_at),
      do: {:ok, contact}

  def opt_out(%Contact{} = contact, opts), do: set_consent(contact, "opt_out", opts)

  @doc """
  Opts a contact back in — clears `opted_out_at` and appends a `consent`
  entry. Idempotent: a no-op if not currently opted out.
  """
  @spec opt_in(Contact.t(), keyword()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def opt_in(contact, opts \\ [])
  def opt_in(%Contact{opted_out_at: nil} = contact, _opts), do: {:ok, contact}
  def opt_in(%Contact{} = contact, opts), do: set_consent(contact, "opt_in", opts)

  defp set_consent(contact, action, opts) do
    source = Keyword.get(opts, :source, "manual")
    actor_uuid = Keyword.get(opts, :actor_uuid)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entry = %{
      "ts" => DateTime.to_iso8601(now),
      "action" => action,
      "actor_uuid" => actor_uuid,
      "source" => source
    }

    opted_out_at = if action == "opt_out", do: now, else: nil

    contact
    |> change(opted_out_at: opted_out_at, consent: append_consent(contact.consent, entry))
    |> repo().update()
    |> log_on_ok("crm.contact_#{action}", opts, "crm_contact", contact.uuid)
  end

  defp append_consent(consent, entry) when is_map(consent) do
    log = Map.get(consent, "log", [])
    Map.put(consent, "log", log ++ [entry])
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp maybe_filter_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [l], l.status == ^status)
    end
  end

  defp maybe_filter_subscribable(query, opts) do
    case Keyword.get(opts, :subscribable) do
      nil -> query
      subscribable -> where(query, [l], l.subscribable == ^subscribable)
    end
  end

  defp maybe_filter_member_status(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      status -> where(query, [m], m.status == ^status)
    end
  end

  defp maybe_search_members(query, opts) do
    case Keyword.get(opts, :search) do
      term when is_binary(term) and term != "" ->
        like = "%#{term}%"

        query
        |> join(:left, [m], c in Contact, on: c.uuid == m.contact_uuid)
        |> where([m, c], ilike(m.email, ^like) or ilike(c.name, ^like))

      _ ->
        query
    end
  end

  defp maybe_paginate(query, opts) do
    query
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  defp log_on_ok({:ok, %ContactList{} = list} = ok, action, opts) do
    Activity.log(action,
      actor_uuid: Keyword.get(opts, :actor_uuid),
      resource_type: "crm_list",
      resource_uuid: list.uuid,
      metadata: %{"name" => list.name, "slug" => list.slug}
    )

    ok
  end

  defp log_on_ok(error, _action, _opts), do: error

  defp log_on_ok({:ok, %Contact{}} = ok, action, opts, resource_type, resource_uuid) do
    Activity.log(action,
      actor_uuid: Keyword.get(opts, :actor_uuid),
      resource_type: resource_type,
      resource_uuid: resource_uuid,
      metadata: %{}
    )

    ok
  end

  defp log_on_ok(error, _action, _opts, _resource_type, _resource_uuid), do: error

  defp broadcast_on_ok({:ok, entity} = ok, event, payload_fun) do
    PubSub.broadcast_list_event(event, payload_fun.(entity))
    ok
  end

  defp broadcast_on_ok(error, _event, _payload_fun), do: error

  defp list_payload(%ContactList{} = list) do
    %{list_uuid: list.uuid, subscriber_count: list.subscriber_count, status: list.status}
  end

  defp member_payload(%ListMember{} = member, %ContactList{} = list) do
    %{
      list_uuid: list.uuid,
      member_uuid: member.uuid,
      subscriber_count: list.subscriber_count,
      status: member.status
    }
  end
end
