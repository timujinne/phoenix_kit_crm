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

  test "the page title lives in the chrome assign, not a duplicate in-body heading",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/en/admin/crm/companies")

    assert html =~ ~s(id="test-page-title")
    refute html =~ "<h1"
    refute has_element?(view, "h1")
  end

  test "New company is reachable in the table's toolbar, not a page-level header",
       %{conn: conn} do
    {:ok, _company} = Companies.create_company(%{"name" => "Globex Corporation"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/companies")

    assert has_element?(view, ~s{a[href="/en/admin/crm/companies/new"]}, "New company")
  end
end
