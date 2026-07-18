defmodule PhoenixKitCRM.Web.ContactShowLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Contacts

  setup %{conn: conn} do
    {:ok, conn: put_test_scope(conn, fake_scope())}
  end

  test "renders the contact's name", %{conn: conn} do
    {:ok, contact} = Contacts.create_contact(%{"name" => "Grace Hopper"})

    {:ok, _view, html} = live(conn, "/en/admin/crm/contacts/#{contact.uuid}")

    assert html =~ "Grace Hopper"
  end

  test "redirects to the contacts list for an unknown uuid", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, "/en/admin/crm/contacts/#{Ecto.UUID.generate()}")

    assert to =~ "/admin/crm/contacts"
  end

  test "has a chrome breadcrumb back to Contacts (the rich in-body header stays, on purpose)",
       %{conn: conn} do
    {:ok, contact} = Contacts.create_contact(%{"name" => "Grace Hopper"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/contacts/#{contact.uuid}")

    assert has_element?(view, "#test-page-section[href='/en/admin/crm/contacts']", "Contacts")
  end
end
