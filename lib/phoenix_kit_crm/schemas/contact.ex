defmodule PhoenixKitCRM.Schemas.Contact do
  @moduledoc """
  A CRM contact (client / customer / prospect).

  Cloned in spirit from `PhoenixKitStaff.Schemas.Person`, with one critical
  difference: the link to a PhoenixKit `User` (`user_uuid`) is **optional** —
  most contacts never log in. The link is set only when the "allow login"
  checkbox is ticked (see `PhoenixKitCRM.Contacts`), never cast from form
  params, so a crafted payload can't link an arbitrary user.
  """

  use Ecto.Schema
  use PhoenixKit.SchemaPrefix
  import Ecto.Changeset

  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.Schemas.{CompanyMembership, Interaction}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  # User-selectable lifecycle statuses (the form's status dropdown).
  @statuses ~w(active inactive)
  # Soft-delete sentinel — set via `Contacts.trash_contact/2`, never offered
  # in the form. Allowed by the changeset's status validation list below.
  @soft_delete_status "trashed"

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          notes: String.t() | nil,
          user_uuid: UUIDv7.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          company_memberships: [CompanyMembership.t()] | Ecto.Association.NotLoaded.t(),
          interactions: [Interaction.t()] | Ecto.Association.NotLoaded.t(),
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "phoenix_kit_crm_contacts" do
    field(:name, :string)
    field(:status, :string, default: "active")
    field(:email, :string)
    field(:phone, :string)
    field(:notes, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:user, User, foreign_key: :user_uuid, references: :uuid)

    has_many(:company_memberships, CompanyMembership,
      foreign_key: :contact_uuid,
      on_delete: :delete_all
    )

    has_many(:interactions, Interaction,
      foreign_key: :contact_uuid,
      on_delete: :delete_all
    )

    timestamps(type: :utc_datetime)
  end

  @castable ~w(name status email phone notes metadata)a

  @doc "Public changeset for create/edit. `user_uuid` is NOT castable here."
  @spec changeset(t() | Ecto.Changeset.t(t()), map()) :: Ecto.Changeset.t(t())
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @castable)
    |> validate_required([:name])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:name, max: 255)
    |> validate_length(:email, max: 255)
    |> validate_length(:phone, max: 50)
    |> maybe_validate_email()
    |> unique_constraint(:user_uuid,
      name: :idx_crm_contacts_user_uuid,
      message: "already linked to a contact"
    )
  end

  @doc "Sets or clears the optional `user_uuid` login link (controlled, not from form params)."
  @spec link_user_changeset(t() | Ecto.Changeset.t(t()), UUIDv7.t() | nil) ::
          Ecto.Changeset.t(t())
  def link_user_changeset(contact, user_uuid) do
    contact
    |> change(user_uuid: user_uuid)
    |> unique_constraint(:user_uuid,
      name: :idx_crm_contacts_user_uuid,
      message: "already linked to a contact"
    )
  end

  defp maybe_validate_email(changeset) do
    case get_field(changeset, :email) do
      e when is_binary(e) and e != "" ->
        validate_format(changeset, :email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/,
          message: "must be a valid email"
        )

      _ ->
        changeset
    end
  end

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @spec soft_delete_status() :: String.t()
  def soft_delete_status, do: @soft_delete_status

  @spec trashed?(t()) :: boolean()
  def trashed?(%__MODULE__{status: @soft_delete_status}), do: true
  def trashed?(%__MODULE__{}), do: false

  @doc "Best human label for a contact."
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%__MODULE__{email: email}) when is_binary(email) and email != "", do: email
  def display_name(%__MODULE__{}), do: "Unnamed"
end
