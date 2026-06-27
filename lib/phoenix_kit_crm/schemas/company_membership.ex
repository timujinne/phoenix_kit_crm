defmodule PhoenixKitCRM.Schemas.CompanyMembership do
  @moduledoc """
  The contact ↔ company link (many-to-many), carrying free-form
  `role_in_company` and `department` on the edge, plus an `is_primary` flag.

  The v1 UI presents a single primary membership per contact (a company +
  role + department block), but the schema is M:N so a contact can relate to
  several companies without a later reshape.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias PhoenixKitCRM.Schemas.{Company, Contact}

  @primary_key {:uuid, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @type t :: %__MODULE__{
          uuid: UUIDv7.t() | nil,
          contact_uuid: UUIDv7.t() | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          company_uuid: UUIDv7.t() | nil,
          company: Company.t() | Ecto.Association.NotLoaded.t() | nil,
          role_in_company: String.t() | nil,
          department: String.t() | nil,
          is_primary: boolean(),
          position: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "phoenix_kit_crm_company_memberships" do
    field(:role_in_company, :string)
    field(:department, :string)
    field(:is_primary, :boolean, default: false)
    field(:position, :integer, default: 0)

    belongs_to(:contact, Contact, foreign_key: :contact_uuid, references: :uuid)
    belongs_to(:company, Company, foreign_key: :company_uuid, references: :uuid)

    timestamps(type: :utc_datetime)
  end

  @castable ~w(contact_uuid company_uuid role_in_company department is_primary position)a

  @spec changeset(t() | Ecto.Changeset.t(t()), map()) :: Ecto.Changeset.t(t())
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, @castable)
    |> validate_required([:contact_uuid, :company_uuid])
    |> validate_length(:role_in_company, max: 255)
    |> validate_length(:department, max: 255)
    |> assoc_constraint(:contact)
    |> assoc_constraint(:company)
    |> unique_constraint([:contact_uuid, :company_uuid],
      name: :phoenix_kit_crm_company_memberships_uniq,
      message: "already linked to this company"
    )
  end
end
