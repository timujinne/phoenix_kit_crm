defmodule PhoenixKitCRM.Web.ContactsLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Contacts

  setup %{conn: conn} do
    {:ok, conn: put_test_scope(conn, fake_scope())}
  end

  test "lists active contacts", %{conn: conn} do
    {:ok, _contact} = Contacts.create_contact(%{"name" => "Ada Lovelace"})

    {:ok, _view, html} = live(conn, "/en/admin/crm/contacts")

    assert html =~ "Ada Lovelace"
  end
end
