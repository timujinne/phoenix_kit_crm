defmodule PhoenixKitCRM.Web.ContactFormLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Contacts

  setup %{conn: conn} do
    scope = fake_scope()
    {:ok, conn: put_test_scope(conn, scope), scope: scope}
  end

  test "renders the new contact form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/en/admin/crm/contacts/new")
    assert html =~ "Name"
  end

  test "creating a contact persists it and logs crm.contact_created with the actor",
       %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts/new")

    view
    |> form("form", contact: %{name: "New Person", email: "new@example.com"})
    |> render_submit()

    assert [contact] = Enum.filter(Contacts.list_contacts(), &(&1.name == "New Person"))

    assert_activity_logged("crm.contact_created",
      resource_uuid: contact.uuid,
      actor_uuid: scope.user.uuid
    )
  end

  test "submitting a blank name re-renders with a validation error", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts/new")

    html = view |> form("form", contact: %{name: ""}) |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    assert Contacts.list_contacts() == []
  end

  test "editing a contact updates it", %{conn: conn} do
    {:ok, contact} = Contacts.create_contact(%{"name" => "Original Name"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts/#{contact.uuid}/edit")

    view |> form("form", contact: %{name: "Renamed"}) |> render_submit()

    assert Contacts.get_contact(contact.uuid).name == "Renamed"
  end
end
