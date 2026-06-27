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
    repo().transaction(fn ->
      case %Interaction{} |> Interaction.changeset(attrs) |> repo().insert() do
        {:ok, interaction} ->
          replace_parties(interaction, party_inputs)
          repo().preload(interaction, [:parties], force: true)

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
    |> broadcast_after(:interaction_created)
  end

  @spec update_interaction(Interaction.t(), map(), [map()]) ::
          {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def update_interaction(%Interaction{} = interaction, attrs, party_inputs \\ []) do
    repo().transaction(fn ->
      case interaction |> Interaction.changeset(attrs) |> repo().update() do
        {:ok, updated} ->
          replace_parties(updated, party_inputs)
          repo().preload(updated, [:parties], force: true)

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
    |> broadcast_after(:interaction_updated)
  end

  @spec delete_interaction(Interaction.t()) ::
          {:ok, Interaction.t()} | {:error, Ecto.Changeset.t()}
  def delete_interaction(%Interaction{} = interaction) do
    # Broadcast with the passed-in struct (parties preloaded by the caller) so
    # every involved contact's feed is reached even though the row is now gone.
    case repo().delete(interaction) do
      {:ok, _deleted} = ok ->
        PubSub.broadcast_interaction(:interaction_deleted, interaction)
        ok

      error ->
        error
    end
  end

  # Fan a successful create/update out to involved contacts' feeds (after commit).
  defp broadcast_after({:ok, %Interaction{} = interaction} = ok, event) do
    PubSub.broadcast_interaction(event, interaction)
    ok
  end

  defp broadcast_after(other, _event), do: other

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
