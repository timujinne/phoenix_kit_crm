defmodule PhoenixKitCRM.InteractionsTest do
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.{Contacts, Interactions}
  alias PhoenixKitCRM.Schemas.Interaction

  defp contact_fixture(name \\ "Subject") do
    {:ok, c} = Contacts.create_contact(%{"name" => name})
    c
  end

  defp interaction_attrs(contact, attrs \\ %{}) do
    Map.merge(
      %{
        "contact_uuid" => contact.uuid,
        "interaction_type" => "note",
        "occurred_at" => DateTime.utc_now() |> DateTime.truncate(:second)
      },
      attrs
    )
  end

  describe "create_interaction/3" do
    test "creates an interaction anchored to its subject contact" do
      c = contact_fixture()

      assert {:ok, %Interaction{} = i} =
               Interactions.create_interaction(interaction_attrs(c, %{"subject" => "Called"}))

      assert i.subject == "Called"
      assert i.contact_uuid == c.uuid
    end

    test "requires a subject contact_uuid (type + occurred_at default in the schema)" do
      assert {:error, cs} = Interactions.create_interaction(%{})
      assert cs.errors[:contact_uuid]
    end

    test "rejects an invalid interaction_type" do
      c = contact_fixture()

      assert {:error, cs} =
               Interactions.create_interaction(
                 interaction_attrs(c, %{"interaction_type" => "bogus"})
               )

      assert cs.errors[:interaction_type]
    end

    test "stores a resolvable party with a frozen profile snapshot" do
      c = contact_fixture()
      party = contact_fixture("Party Person")

      {:ok, i} =
        Interactions.create_interaction(interaction_attrs(c), [
          %{raw_name: "Party Person", contact_uuid: party.uuid}
        ])

      assert [p] = Interactions.get_interaction(i.uuid).parties
      assert p.raw_name == "Party Person"
      assert p.contact_uuid == party.uuid
      assert p.party_snapshot["source"] == "crm_contact"
      assert p.party_snapshot["name"] == "Party Person"
    end

    test "blank parties are dropped" do
      c = contact_fixture()
      {:ok, i} = Interactions.create_interaction(interaction_attrs(c), [%{raw_name: "  "}])
      assert Interactions.get_interaction(i.uuid).parties == []
    end
  end

  describe "list_involving/1" do
    test "returns interactions where the contact is the subject OR a party" do
      subject = contact_fixture("Subj")
      other = contact_fixture("Other")
      {:ok, own} = Interactions.create_interaction(interaction_attrs(subject))

      {:ok, as_party} =
        Interactions.create_interaction(interaction_attrs(other), [
          %{raw_name: "Subj", contact_uuid: subject.uuid}
        ])

      uuids = subject.uuid |> Interactions.list_involving() |> Enum.map(& &1.uuid)
      assert own.uuid in uuids
      assert as_party.uuid in uuids
    end

    test "returns [] for a malformed uuid" do
      assert Interactions.list_involving("not-a-uuid") == []
    end
  end

  describe "list_for_contacts/1 + interaction_uuids_for_contact/1" do
    test "list_for_contacts returns interactions for the given subjects; [] for empty" do
      a = contact_fixture("A")
      {:ok, i} = Interactions.create_interaction(interaction_attrs(a))

      uuids = [a.uuid] |> Interactions.list_for_contacts() |> Enum.map(& &1.uuid)
      assert i.uuid in uuids
      assert Interactions.list_for_contacts([]) == []
    end

    test "interaction_uuids_for_contact returns the subject's interaction uuids" do
      c = contact_fixture()
      {:ok, i} = Interactions.create_interaction(interaction_attrs(c))
      assert i.uuid in Interactions.interaction_uuids_for_contact(c.uuid)
    end
  end

  describe "delete_interaction/2" do
    test "removes the interaction" do
      c = contact_fixture()
      {:ok, i} = Interactions.create_interaction(interaction_attrs(c))
      assert {:ok, _} = Interactions.delete_interaction(i)
      assert Interactions.get_interaction(i.uuid) == nil
    end
  end
end
