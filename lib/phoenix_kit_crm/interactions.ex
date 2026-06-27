defmodule PhoenixKitCRM.Interactions do
  @moduledoc """
  Context for CRM interactions — the History/Interactions tab.

  Handles the logged interaction itself, its resolvable "involved parties"
  (flat list, no per-party role), the as-of-then `party_snapshot` captured on
  save, and the reverse "all interactions involving this contact" query
  (subject OR party).
  """

  import Ecto.Query, warn: false

  alias PhoenixKit.RepoHelper
  alias PhoenixKitCRM.Activity
  alias PhoenixKitCRM.Contacts
  alias PhoenixKitCRM.PubSub
  alias PhoenixKitCRM.Schemas.{Contact, Interaction, InteractionParty}
  alias PhoenixKitCRM.StaffLink

  defp repo, do: RepoHelper.repo()

  @doc """
  Lists every interaction that involves the given contact — whether they are
  the **subject** (`interactions.contact_uuid`) or an **involved party**
  (`interaction_parties.contact_uuid`). Newest first; parties preloaded.
  """
  @spec list_involving(UUIDv7.t() | String.t() | nil) :: [Interaction.t()]
  def list_involving(contact_uuid) do
    case Ecto.UUID.cast(contact_uuid) do
      {:ok, _} ->
        party_subq =
          from(p in InteractionParty,
            where: p.contact_uuid == ^contact_uuid,
            select: p.interaction_uuid
          )

        Interaction
        |> where([i], i.contact_uuid == ^contact_uuid or i.uuid in subquery(party_subq))
        |> order_by([i], desc: i.occurred_at, desc: i.inserted_at)
        |> repo().all()
        |> repo().preload(parties: from(p in InteractionParty, order_by: p.position))

      :error ->
        []
    end
  end

  @spec get_interaction(UUIDv7.t() | String.t() | nil) :: Interaction.t() | nil
  def get_interaction(uuid) do
    with {:ok, _} <- Ecto.UUID.cast(uuid),
         %Interaction{} = interaction <- repo().get(Interaction, uuid) do
      repo().preload(interaction, [:parties])
    else
      _ -> nil
    end
  end

  @spec change_interaction(Interaction.t(), map()) :: Ecto.Changeset.t()
  def change_interaction(%Interaction{} = interaction, attrs \\ %{}),
    do: Interaction.changeset(interaction, attrs)

  @doc """
  Creates an interaction and (re)builds its party list. `party_inputs` is a
  list of maps with `:raw_name` (required) and an optional resolved reference
  (`:contact_uuid` OR `:staff_person_uuid`). The snapshot is captured here.
  """
  @spec create_interaction(map(), [map()]) ::
          {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def create_interaction(attrs, party_inputs \\ []) do
    result =
      repo().transaction(fn ->
        case %Interaction{} |> Interaction.changeset(attrs) |> repo().insert() do
          {:ok, interaction} ->
            replace_parties(interaction, party_inputs)
            repo().preload(interaction, [:parties], force: true)

          {:error, changeset} ->
            repo().rollback(changeset)
        end
      end)

    case result do
      {:ok, interaction} = ok ->
        # Log the audit entry BEFORE broadcasting, so a subscriber that reloads
        # its Events feed off the broadcast already sees this row (the activity
        # log is what the Events tab reads).
        log_interaction_logged(interaction)
        PubSub.broadcast_interaction(:interaction_created, interaction)
        ok

      other ->
        other
    end
  end

  @spec update_interaction(Interaction.t(), map(), [map()]) ::
          {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def update_interaction(%Interaction{} = interaction, attrs, party_inputs \\ []) do
    # Capture the OLD involved contacts before we replace parties / change the
    # subject, so anyone dropped by this edit still gets a refresh to remove it.
    old_uuids = PubSub.involved_contact_uuids(repo().preload(interaction, :parties))

    result =
      repo().transaction(fn ->
        case interaction |> Interaction.changeset(attrs) |> repo().update() do
          {:ok, updated} ->
            replace_parties(updated, party_inputs)
            repo().preload(updated, [:parties], force: true)

          {:error, changeset} ->
            repo().rollback(changeset)
        end
      end)

    case result do
      {:ok, updated} = ok ->
        PubSub.broadcast_to_contacts(
          :interaction_updated,
          updated.uuid,
          old_uuids ++ PubSub.involved_contact_uuids(updated)
        )

        ok

      other ->
        other
    end
  end

  @spec delete_interaction(Interaction.t()) ::
          {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def delete_interaction(%Interaction{} = interaction) do
    # Force parties loaded (works for any caller, not just the component path) so
    # every involved contact's feed is reached even though the row is now gone.
    interaction = repo().preload(interaction, :parties)

    case repo().delete(interaction) do
      {:ok, _deleted} = ok ->
        PubSub.broadcast_interaction(:interaction_deleted, interaction)
        ok

      error ->
        error
    end
  end

  # The contact's Events feed audit entry for a logged interaction. Logged in the
  # context (not the LiveView) so it's written before the realtime broadcast and
  # so every create path records it. Best-effort via the Activity wrapper.
  defp log_interaction_logged(%Interaction{} = interaction) do
    Activity.log("crm.interaction_logged",
      actor_uuid: interaction.owner_user_uuid,
      resource_type: "crm_contact",
      resource_uuid: interaction.contact_uuid,
      target_uuid: interaction.uuid,
      metadata: %{
        "interaction_type" => interaction.interaction_type,
        "subject" => interaction.subject
      }
    )
  end

  # ── Party reconciliation + snapshot ─────────────────────────────────

  defp replace_parties(%Interaction{uuid: interaction_uuid}, party_inputs) do
    from(p in InteractionParty, where: p.interaction_uuid == ^interaction_uuid)
    |> repo().delete_all()

    party_inputs
    |> Enum.reject(&blank_party?/1)
    |> Enum.with_index()
    |> Enum.each(fn {input, idx} ->
      changeset =
        InteractionParty.changeset(%InteractionParty{}, %{
          "interaction_uuid" => interaction_uuid,
          "raw_name" => party_raw_name(input),
          "contact_uuid" => input[:contact_uuid],
          "staff_person_uuid" => input[:staff_person_uuid],
          "party_snapshot" => build_snapshot(input),
          "position" => idx
        })

      # Inside a transaction — roll the whole interaction back on a bad party
      # (e.g. over-length free text) instead of raising out of the LiveView.
      case repo().insert(changeset) do
        {:ok, _party} -> :ok
        {:error, cs} -> repo().rollback(cs)
      end
    end)
  end

  defp blank_party?(input), do: party_raw_name(input) in [nil, ""]

  defp party_raw_name(input), do: input[:raw_name] && String.trim(input[:raw_name])

  # Capture the party's profile "as it was then".
  defp build_snapshot(%{contact_uuid: contact_uuid}) when is_binary(contact_uuid) do
    case Contacts.get_contact(contact_uuid) do
      %Contact{} = contact -> contact_snapshot(contact)
      _ -> %{"source" => "crm_contact"}
    end
    |> stamp()
  end

  defp build_snapshot(%{staff_person_uuid: staff_uuid}) when is_binary(staff_uuid) do
    StaffLink.snapshot(staff_uuid) |> Map.put_new("source", "staff") |> stamp()
  end

  defp build_snapshot(_input), do: %{"source" => "free_text"} |> stamp()

  defp contact_snapshot(%Contact{} = contact) do
    membership = Contacts.primary_membership(contact)

    %{
      "source" => "crm_contact",
      "name" => Contact.display_name(contact),
      "company" => membership && membership.company && membership.company.name,
      "role_in_company" => membership && membership.role_in_company,
      "department" => membership && membership.department
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp stamp(map) do
    Map.put(
      map,
      "captured_at",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end
end
