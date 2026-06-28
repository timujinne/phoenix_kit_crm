defmodule PhoenixKitCRM.Web.ContactsLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Contacts

  setup %{conn: conn} do
    scope = fake_scope()
    {:ok, conn: put_test_scope(conn, scope), scope: scope}
  end

  test "lists active contacts", %{conn: conn} do
    {:ok, _contact} = Contacts.create_contact(%{"name" => "Ada Lovelace"})

    {:ok, _view, html} = live(conn, "/en/admin/crm/contacts")

    assert html =~ "Ada Lovelace"
  end

  test "trashing a contact moves it to trash and logs crm.contact_trashed",
       %{conn: conn, scope: scope} do
    {:ok, contact} = Contacts.create_contact(%{"name" => "To Be Trashed"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts")

    view
    |> element(~s{[phx-click="trash"][phx-value-uuid="#{contact.uuid}"]})
    |> render_click()

    assert Contacts.get_contact(contact.uuid).status == "trashed"

    assert_activity_logged("crm.contact_trashed",
      resource_uuid: contact.uuid,
      actor_uuid: scope.user.uuid
    )
  end
end
