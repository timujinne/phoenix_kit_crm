defmodule PhoenixKitCRM.AttachmentsTest do
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.{Attachments, Contacts}

  defp contact_fixture(name \\ "Avatar Contact") do
    {:ok, c} = Contacts.create_contact(%{"name" => name})
    c
  end

  describe "set_avatar/3 authorization" do
    test "refuses a file that isn't one of the record's own images" do
      c = contact_fixture()

      # No Images folder/file is linked to this contact, so a forged uuid is
      # rejected rather than blindly pointed at an arbitrary file in storage.
      assert {:error, :not_record_image} =
               Attachments.set_avatar(:contact, c, Ecto.UUID.generate())
    end

    test "refuses to set an avatar on a trashed record" do
      {:ok, trashed} = Contacts.trash_contact(contact_fixture())

      assert {:error, :record_trashed} =
               Attachments.set_avatar(:contact, trashed, Ecto.UUID.generate())
    end

    test "a blank file uuid is never a candidate" do
      c = contact_fixture()
      refute Attachments.avatar_candidate?(:contact, c.uuid, "")
    end
  end
end
