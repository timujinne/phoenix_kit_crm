defmodule PhoenixKitCRM.Schemas.Interaction do
  @moduledoc """
  A logged interaction ("client called, we discussed X") — the core of the
  CRM v1 interaction tracker. A structured log entry (type + when + body),
  anchored to a subject `Contact`, with N resolvable involved parties.
  """

  use Ecto.Schema
  use Gettext, backend: PhoenixKitCRM.Gettext
  import Ecto.Changeset

  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.Schemas.{Contact, InteractionParty}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @types ~w(call email meeting note other)

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          contact_uuid: UUIDv7.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          interaction_type: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          subject: String.t() | nil,
          body: String.t() | nil,
          owner_user_uuid: UUIDv7.t() | nil,
          owner_user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          parties: [InteractionParty.t()] | Ecto.Association.NotLoaded.t(),
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "phoenix_kit_crm_interactions" do
    field(:interaction_type, :string, default: "note")
    field(:occurred_at, :utc_datetime)
    field(:subject, :string)
    field(:body, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:contact, Contact, foreign_key: :contact_uuid, references: :uuid)
    belongs_to(:owner_user, User, foreign_key: :owner_user_uuid, references: :uuid)

    has_many(:parties, InteractionParty,
      foreign_key: :interaction_uuid,
      on_delete: :delete_all,
      preload_order: [asc: :position]
    )

    timestamps(type: :utc_datetime)
  end

  @castable ~w(contact_uuid interaction_type occurred_at subject body owner_user_uuid metadata)a

  @spec changeset(t() | Ecto.Changeset.t(t()), map()) :: Ecto.Changeset.t(t())
  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, @castable)
    |> maybe_default_occurred_at()
    |> validate_required([:contact_uuid, :interaction_type, :occurred_at])
    |> validate_inclusion(:interaction_type, @types,
      message: "must be one of: #{Enum.join(@types, ", ")}"
    )
    |> validate_length(:subject, max: 255)
    |> assoc_constraint(:contact)
  end

  defp maybe_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.truncate(DateTime.utc_now(), :second))
      _ -> changeset
    end
  end

  @spec types() :: [String.t()]
  def types, do: @types

  @spec type_label(String.t()) :: String.t()
  def type_label("call"), do: gettext("Call")
  def type_label("email"), do: gettext("Email")
  def type_label("meeting"), do: gettext("Meeting")
  def type_label("note"), do: gettext("Note")
  def type_label("other"), do: gettext("Other")
  def type_label(other), do: other
end
