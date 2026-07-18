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

  test "the page title lives in the chrome assign, not a duplicate in-body heading",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/en/admin/crm/contacts")

    # page_title flows to the host app's chrome breadcrumb (out of the
    # LiveView body) — this repo's test layout stands in for that with
    # #test-page-title, so this only proves it's ASSIGNED, not duplicated
    # by an in-body <h1>/<.admin_page_header title=...> as well.
    assert html =~ ~s(id="test-page-title")
    refute html =~ "<h1"
    refute has_element?(view, "h1")
  end

  test "New contact is reachable in the table's toolbar, not a page-level header",
       %{conn: conn} do
    {:ok, _contact} = Contacts.create_contact(%{"name" => "Ada Lovelace"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts")

    assert has_element?(view, ~s{a[href="/en/admin/crm/contacts/new"]}, "New contact")
  end

  test "trashing a contact moves it to trash and logs crm.contact_trashed",
       %{conn: conn, scope: scope} do
    {:ok, contact} = Contacts.create_contact(%{"name" => "To Be Trashed"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts")

    # toggleable table_default keeps both the table-view and card-view rows
    # in the DOM at once (CSS-hidden, not removed) — scope to the
    # table-view copy (id_suffix "table") so the selector matches exactly
    # one element.
    view
    |> element(~s{#crm-contact-menu-table-#{contact.uuid} [phx-click="trash"]})
    |> render_click()

    assert Contacts.get_contact(contact.uuid).status == "trashed"

    assert_activity_logged("crm.contact_trashed",
      resource_uuid: contact.uuid,
      actor_uuid: scope.user.uuid
    )
  end
end
