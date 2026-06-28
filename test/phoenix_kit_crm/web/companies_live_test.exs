defmodule PhoenixKitCRM.Web.CompaniesLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Companies

  setup %{conn: conn} do
    {:ok, conn: put_test_scope(conn, fake_scope())}
  end

  test "lists active companies", %{conn: conn} do
    {:ok, _company} = Companies.create_company(%{"name" => "Globex Corporation"})

    {:ok, _view, html} = live(conn, "/en/admin/crm/companies")

    assert html =~ "Globex Corporation"
  end
end
