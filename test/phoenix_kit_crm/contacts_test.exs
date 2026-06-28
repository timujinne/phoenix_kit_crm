defmodule PhoenixKitCRM.ContactsTest do
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.Contacts
  alias PhoenixKitCRM.Schemas.Contact

  defp contact_fixture(attrs \\ %{}) do
    {:ok, contact} = Contacts.create_contact(Map.merge(%{"name" => "Test Contact"}, attrs))
    contact
  end

  describe "create_contact/1" do
    test "creates an active contact from a name" do
      assert {:ok, %Contact{} = c} = Contacts.create_contact(%{"name" => "Ada Lovelace"})
      assert c.name == "Ada Lovelace"
      assert c.status == "active"
    end

    test "requires a name" do
      assert {:error, cs} = Contacts.create_contact(%{"name" => ""})
      assert cs.errors[:name]
    end

    test "rejects an invalid status" do
      assert {:error, cs} = Contacts.create_contact(%{"name" => "X", "status" => "bogus"})
      assert cs.errors[:status]
    end
  end

  describe "get_contact/1" do
    test "returns the contact by uuid" do
      c = contact_fixture()
      assert Contacts.get_contact(c.uuid).uuid == c.uuid
    end

    test "returns nil for an unknown or malformed uuid" do
      assert Contacts.get_contact(Ecto.UUID.generate()) == nil
      assert Contacts.get_contact("not-a-uuid") == nil
    end
  end

  describe "update_contact/2" do
    test "updates editable fields" do
      c = contact_fixture()
      assert {:ok, updated} = Contacts.update_contact(c, %{"name" => "Renamed"})
      assert updated.name == "Renamed"
    end
  end

  describe "trash_contact/1 + restore_contact/1" do
    test "trash sets the sentinel status and stashes the prior one" do
      assert {:ok, trashed} = Contacts.trash_contact(contact_fixture())
      assert trashed.status == "trashed"
      assert trashed.metadata["trashed_from_status"] == "active"
    end

    test "trashing an already-trashed contact errors" do
      {:ok, trashed} = Contacts.trash_contact(contact_fixture())
      assert {:error, :already_trashed} = Contacts.trash_contact(trashed)
    end

    test "restore reverses the trash and clears the stash" do
      {:ok, trashed} = Contacts.trash_contact(contact_fixture())
      assert {:ok, restored} = Contacts.restore_contact(trashed)
      assert restored.status == "active"
      refute Map.has_key?(restored.metadata, "trashed_from_status")
    end

    test "restoring a non-trashed contact errors" do
      assert {:error, :not_trashed} = Contacts.restore_contact(contact_fixture())
    end
  end

  describe "list_contacts/1 + count_contacts/1" do
    test "active list excludes trashed; trashed filter is the inverse" do
      active = contact_fixture(%{"name" => "Active One"})
      {:ok, trashed} = Contacts.trash_contact(contact_fixture(%{"name" => "Trashed One"}))

      active_uuids = Contacts.list_contacts() |> Enum.map(& &1.uuid)
      assert active.uuid in active_uuids
      refute trashed.uuid in active_uuids

      trashed_uuids = Contacts.list_contacts(status: "trashed") |> Enum.map(& &1.uuid)
      assert trashed.uuid in trashed_uuids
      refute active.uuid in trashed_uuids
    end

    test "count_contacts honors the status filter" do
      contact_fixture()
      {:ok, _} = Contacts.trash_contact(contact_fixture())
      assert Contacts.count_contacts(status: "trashed") == 1
    end
  end

  describe "list_by_uuids/1" do
    test "returns the contacts for the given uuids; [] for empty input" do
      a = contact_fixture(%{"name" => "A"})
      b = contact_fixture(%{"name" => "B"})
      uuids = [a.uuid, b.uuid] |> Contacts.list_by_uuids() |> Enum.map(& &1.uuid)
      assert a.uuid in uuids and b.uuid in uuids
      assert Contacts.list_by_uuids([]) == []
    end

    test "drops malformed uuids instead of raising" do
      a = contact_fixture(%{"name" => "Valid"})
      assert ["not-a-uuid", a.uuid] |> Contacts.list_by_uuids() |> Enum.map(& &1.uuid) == [a.uuid]
      assert Contacts.list_by_uuids(["also-bad"]) == []
    end
  end

  describe "get_by_user_uuid/1" do
    test "returns nil for nil and for a malformed uuid (no cast error)" do
      assert Contacts.get_by_user_uuid(nil) == nil
      assert Contacts.get_by_user_uuid("not-a-uuid") == nil
    end
  end

  describe "search_contacts/3" do
    test "matches by name, excluding trashed and the excluded uuids" do
      hit = contact_fixture(%{"name" => "Searchable Sam"})
      excluded = contact_fixture(%{"name" => "Searchable Sue"})
      {:ok, trashed} = Contacts.trash_contact(contact_fixture(%{"name" => "Searchable Trash"}))

      uuids = "Searchable" |> Contacts.search_contacts(8, [excluded.uuid]) |> Enum.map(& &1.uuid)
      assert hit.uuid in uuids
      refute excluded.uuid in uuids
      refute trashed.uuid in uuids
    end

    test "blank query returns no results" do
      contact_fixture(%{"name" => "Whoever"})
      assert Contacts.search_contacts("   ") == []
    end

    test "escapes LIKE wildcards so % matches literally, not everything" do
      pct = contact_fixture(%{"name" => "50% Off Sam"})
      plain = contact_fixture(%{"name" => "Plain Sam"})

      # Unescaped, "%" would be a wildcard matching every contact.
      uuids = "%" |> Contacts.search_contacts() |> Enum.map(& &1.uuid)
      assert pct.uuid in uuids
      refute plain.uuid in uuids
    end

    test "tolerates a null byte in the query (no Postgres crash)" do
      hit = contact_fixture(%{"name" => "Nullsafe Sam"})
      uuids = "Null\x00safe" |> Contacts.search_contacts() |> Enum.map(& &1.uuid)
      assert hit.uuid in uuids
    end
  end
end
