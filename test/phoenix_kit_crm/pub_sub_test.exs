defmodule PhoenixKitCRM.PubSubTest do
  use ExUnit.Case, async: true

  alias PhoenixKitCRM.PubSub
  alias PhoenixKitCRM.Schemas.{Interaction, InteractionParty}

  describe "involved_contact_uuids/1" do
    test "returns the subject plus party contact uuids, deduped, nils dropped" do
      interaction = %Interaction{
        contact_uuid: "subject-uuid",
        parties: [
          %InteractionParty{contact_uuid: "party-1"},
          # free-text party (no resolved contact)
          %InteractionParty{contact_uuid: nil},
          # a party that is also the subject
          %InteractionParty{contact_uuid: "subject-uuid"}
        ]
      }

      assert PubSub.involved_contact_uuids(interaction) == ["subject-uuid", "party-1"]
    end

    test "treats a not-loaded parties association as no parties" do
      interaction = %Interaction{contact_uuid: "s", parties: %Ecto.Association.NotLoaded{}}
      assert PubSub.involved_contact_uuids(interaction) == ["s"]
    end
  end
end
