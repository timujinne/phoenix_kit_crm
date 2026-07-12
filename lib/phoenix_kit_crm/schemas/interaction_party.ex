defmodule PhoenixKitCRM.Schemas.InteractionParty do
  @moduledoc """
  An "involved party" on an interaction — a flat, resolvable mention.

  `raw_name` is always kept (the typed text / display fallback). A party
  resolves to a CRM `Contact` (`contact_uuid`) **or** a staff person
  (`staff_person_uuid`, a soft ref — no FK — so the staff module stays
  optional), at most one (exclusive-arc). `party_snapshot` freezes the
  party's profile as it was at log time, so the record is true to that
  moment even after the person changes role or is deleted.

  There is **no per-party role** by design (see the v1 design note): a
  business relationship-role belongs on a durable contact↔company edge, not
  on an interaction.
  """

  use Ecto.Schema
  use PhoenixKit.SchemaPrefix
  import Ecto.Changeset

  alias PhoenixKitCRM.Schemas.{Contact, Interaction}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          interaction_uuid: UUIDv7.t() | nil,
          interaction: Interaction.t() | Ecto.Association.NotLoaded.t() | nil,
          raw_name: String.t() | nil,
          contact_uuid: UUIDv7.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          staff_person_uuid: UUIDv7.t() | nil,
          party_snapshot: map(),
          position: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "phoenix_kit_crm_interaction_parties" do
    field(:raw_name, :string)
    field(:staff_person_uuid, UUIDv7)
    field(:party_snapshot, :map, default: %{})
    field(:position, :integer, default: 0)

    belongs_to(:interaction, Interaction, foreign_key: :interaction_uuid, references: :uuid)
    belongs_to(:contact, Contact, foreign_key: :contact_uuid, references: :uuid)

    timestamps(type: :utc_datetime)
  end

  @castable ~w(interaction_uuid raw_name contact_uuid staff_person_uuid party_snapshot position)a

  @spec changeset(t() | Ecto.Changeset.t(t()), map()) :: Ecto.Changeset.t(t())
  def changeset(party, attrs) do
    party
    |> cast(attrs, @castable)
    |> validate_required([:raw_name])
    |> validate_length(:raw_name, max: 255)
    |> validate_exclusive_arc()
    |> check_constraint(:contact_uuid,
      name: :phoenix_kit_crm_party_exclusive_arc,
      message: "a party can resolve to a contact or a staff person, not both"
    )
    # Turn FK violations (stale/forged uuid) into changeset errors, not raises.
    |> foreign_key_constraint(:interaction_uuid)
    |> foreign_key_constraint(:contact_uuid)
  end

  # At most one resolved reference (contact OR staff person).
  defp validate_exclusive_arc(changeset) do
    contact = get_field(changeset, :contact_uuid)
    staff = get_field(changeset, :staff_person_uuid)

    if not is_nil(contact) and not is_nil(staff) do
      add_error(changeset, :contact_uuid, "cannot resolve to both a contact and a staff person")
    else
      changeset
    end
  end
end
