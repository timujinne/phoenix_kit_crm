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
end
