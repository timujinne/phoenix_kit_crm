defmodule PhoenixKitCRM.Web.ListsLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Lists

  setup %{conn: conn} do
    {:ok, conn: put_test_scope(conn, fake_scope())}
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

  test "lists active lists", %{conn: conn} do
    list_fixture(%{"name" => "VIP Customers"})

    {:ok, _view, html} = live(conn, "/en/admin/crm/lists")

    assert html =~ "VIP Customers"
  end

  test "archived lists only show on the Archived tab", %{conn: conn} do
    list = list_fixture(%{"name" => "Old Campaign"})
    {:ok, _} = Lists.archive_list(list)

    {:ok, _view, html} = live(conn, "/en/admin/crm/lists")
    refute html =~ "Old Campaign"

    {:ok, _view, html} = live(conn, "/en/admin/crm/lists?filter=archived")
    assert html =~ "Old Campaign"
  end

  test "toggling subscribable flips the flag", %{conn: conn} do
    list = list_fixture(%{"subscribable" => false})

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists")
    view |> element("input[phx-value-uuid='#{list.uuid}']") |> render_click()

    assert Lists.get_list!(list.uuid).subscribable
  end

  test "archiving a list via the row menu action", %{conn: conn} do
    list = list_fixture()

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists")

    view
    |> element("#crm-list-menu-table-#{list.uuid} button[phx-click='archive']")
    |> render_click()

    assert Lists.get_list!(list.uuid).status == "archived"
  end
end
