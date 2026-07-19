defmodule PhoenixKitCRM.ContactDeleteCountersTest do
  @moduledoc """
  Hard-deleting a contact cascades its `ListMember` rows at the DB
  level (FK `ON DELETE CASCADE`), bypassing
  `Lists.remove_from_list/2`'s atomic `subscriber_count` decrement —
  that path only fires on a live status flip, not a row disappearing
  out from under it. A contact deleted while still `"subscribed"` on a
  list left that list's `subscriber_count` permanently overcounted,
  since nothing else ever revisits it (a real user hit this: a list
  reading "2" with only one actual member, from a reviewer's fixture
  contact deleted directly).
  """

  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.{Contacts, Lists}
  alias PhoenixKitCRM.Schemas.ListMember

  defp contact_fixture(attrs \\ %{}) do
    {:ok, contact} =
      Contacts.create_contact(
        Map.merge(%{"name" => "Jane Trader", "email" => unique_email()}, attrs)
      )

    contact
  end

  defp list_fixture(attrs \\ %{}) do
    {:ok, list} =
      Lists.create_list(
        Map.merge(%{"name" => "Newsletter", "slug" => "newsletter-#{unique_int()}"}, attrs)
      )

    list
  end

  defp unique_email, do: "contact-#{unique_int()}@example.com"
  defp unique_int, do: System.unique_integer([:positive])

  describe "delete_contact/1" do
    test "decrements subscriber_count only on lists where the contact was actually subscribed" do
      contact = contact_fixture()
      subscribed_list = list_fixture(%{"slug" => "subscribed-#{unique_int()}"})
      removed_list = list_fixture(%{"slug" => "removed-#{unique_int()}"})

      {:ok, _} = Lists.add_contact_to_list(contact, subscribed_list)

      {:ok, _} = Lists.add_contact_to_list(contact, removed_list)
      {:ok, _} = Lists.remove_from_list(contact, removed_list, [])

      assert Lists.get_list!(subscribed_list.uuid).subscriber_count == 1
      assert Lists.get_list!(removed_list.uuid).subscriber_count == 0

      assert {:ok, _} = Contacts.delete_contact(contact)

      assert Lists.get_list!(subscribed_list.uuid).subscriber_count == 0
      assert Lists.get_list!(removed_list.uuid).subscriber_count == 0
    end

    test "the contact and its memberships are actually gone (the FK cascade itself still runs)" do
      contact = contact_fixture()
      list = list_fixture()
      {:ok, member} = Lists.add_contact_to_list(contact, list)

      assert {:ok, _} = Contacts.delete_contact(contact)

      assert Repo.get(PhoenixKitCRM.Schemas.Contact, contact.uuid) == nil
      assert Repo.get(ListMember, member.uuid) == nil
    end

    test "a contact with no subscribed memberships at all deletes cleanly, no list touched" do
      contact = contact_fixture()
      list = list_fixture()
      {:ok, _} = Lists.add_contact_to_list(contact, list)
      {:ok, _} = Lists.remove_from_list(contact, list, [])

      assert Lists.get_list!(list.uuid).subscriber_count == 0
      assert {:ok, _} = Contacts.delete_contact(contact)
      assert Lists.get_list!(list.uuid).subscriber_count == 0
    end

    test "a contact on multiple subscribed lists decrements every one of them" do
      contact = contact_fixture()
      list_a = list_fixture(%{"slug" => "a-#{unique_int()}"})
      list_b = list_fixture(%{"slug" => "b-#{unique_int()}"})

      {:ok, _} = Lists.add_contact_to_list(contact, list_a)
      {:ok, _} = Lists.add_contact_to_list(contact, list_b)

      assert {:ok, _} = Contacts.delete_contact(contact)

      assert Lists.get_list!(list_a.uuid).subscriber_count == 0
      assert Lists.get_list!(list_b.uuid).subscriber_count == 0
    end
  end

  describe "trash_contact/1 (soft delete)" do
    test "does not cascade memberships and does not touch subscriber_count" do
      contact = contact_fixture()
      list = list_fixture()
      {:ok, member} = Lists.add_contact_to_list(contact, list)

      assert Lists.get_list!(list.uuid).subscriber_count == 1

      assert {:ok, trashed} = Contacts.trash_contact(contact)
      assert trashed.status == "trashed"

      # The membership row is untouched — trashing only flips the contact's
      # own status, it never deletes anything.
      assert Repo.get(ListMember, member.uuid).status == "subscribed"
      assert Lists.get_list!(list.uuid).subscriber_count == 1
    end
  end
end
