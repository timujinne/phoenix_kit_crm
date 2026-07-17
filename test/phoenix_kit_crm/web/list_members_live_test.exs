defmodule PhoenixKitCRM.Web.ListMembersLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.{Contacts, Lists}

  setup %{conn: conn} do
    scope = fake_scope()
    {:ok, conn: put_test_scope(conn, scope), scope: scope}
  end

  defp list_fixture(attrs \\ %{}) do
    {:ok, list} =
      Lists.create_list(
        Map.merge(
          %{"name" => "Newsletter", "slug" => "list-#{System.unique_integer([:positive])}"},
          attrs
        )
      )

    list
  end

  defp contact_fixture(attrs \\ %{}) do
    {:ok, contact} =
      Contacts.create_contact(
        Map.merge(%{"name" => "Jane Trader", "email" => unique_email()}, attrs)
      )

    contact
  end

  defp unique_email, do: "member-#{System.unique_integer([:positive])}@example.com"

  test "renders the list name and existing members", %{conn: conn} do
    list = list_fixture(%{"name" => "Beta Testers"})
    contact = contact_fixture(%{"name" => "Alice Wonder"})
    {:ok, _} = Lists.add_contact_to_list(contact, list)

    {:ok, _view, html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/members")

    assert html =~ "Beta Testers"
    assert html =~ "Alice Wonder"
  end

  test "adding a new contact by email creates a contact + membership and logs the actor",
       %{conn: conn, scope: scope} do
    list = list_fixture()

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/members")

    view
    |> form("#crm-list-add-member-form",
      add_member: %{email: "new@example.com", name: "New Person", locale: "en"}
    )
    |> render_submit()

    [member] = Lists.list_members(list)
    assert member.email == "new@example.com"
    assert member.contact.name == "New Person"
    assert member.source == "manual"

    assert_activity_logged("crm.list_member_added",
      resource_uuid: member.uuid,
      actor_uuid: scope.user.uuid
    )
  end

  test "live email check shows an 'already in this list' hint and blocks submit", %{conn: conn} do
    list = list_fixture()
    contact = contact_fixture(%{"email" => "taken@example.com"})
    {:ok, _} = Lists.add_contact_to_list(contact, list)

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/members")

    html =
      view
      |> form("#crm-list-add-member-form", add_member: %{email: "taken@example.com"})
      |> render_change()

    assert html =~ "Already in this list"

    view
    |> form("#crm-list-add-member-form", add_member: %{email: "taken@example.com"})
    |> render_submit()

    # blocked: still just the one original member, no second contact created
    assert length(Lists.list_members(list)) == 1
  end

  test "the Resubscribe affordance reactivates a removed member instead of creating a new contact",
       %{conn: conn} do
    list = list_fixture()
    contact = contact_fixture(%{"email" => "removed@example.com"})
    {:ok, member} = Lists.add_contact_to_list(contact, list)
    {:ok, _} = Lists.remove_from_list(member)

    contact_count_before = length(Contacts.list_contacts())

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/members")

    html =
      view
      |> form("#crm-list-add-member-form", add_member: %{email: "removed@example.com"})
      |> render_change()

    assert html =~ "Previously unsubscribed"

    view |> element("button[phx-click='resubscribe']") |> render_click()

    [reactivated] = Lists.list_members(list)
    assert reactivated.uuid == member.uuid
    assert reactivated.status == "subscribed"
    assert length(Contacts.list_contacts()) == contact_count_before
  end

  test "removing a member flips its status without deleting the row", %{conn: conn} do
    list = list_fixture()
    contact = contact_fixture()
    {:ok, member} = Lists.add_contact_to_list(contact, list)

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/members")

    view
    |> element("button[phx-click='remove_member'][phx-value-uuid='#{member.uuid}']")
    |> render_click()

    assert Lists.list_members(list, status: "removed") |> length() == 1
    refute Lists.subscribed?(contact, list)
  end
end
