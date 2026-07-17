defmodule PhoenixKitCRM.Web.ListFormLiveTest do
  use PhoenixKitCRM.LiveCase

  alias PhoenixKitCRM.Lists

  setup %{conn: conn} do
    scope = fake_scope()
    {:ok, conn: put_test_scope(conn, scope), scope: scope}
  end

  test "renders the new list form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/en/admin/crm/lists/new")
    assert html =~ "New list"
  end

  test "creating a list persists it, auto-generates the slug, and logs the actor",
       %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/new")

    view |> form("#crm-list-form", list: %{name: "Product Updates"}) |> render_submit()

    assert [list] = Enum.filter(Lists.list_lists(), &(&1.name == "Product Updates"))
    assert list.slug == "product-updates"

    assert_activity_logged("crm.list_created",
      resource_uuid: list.uuid,
      actor_uuid: scope.user.uuid
    )
  end

  test "editing a list updates it", %{conn: conn} do
    {:ok, list} = Lists.create_list(%{"name" => "Original", "slug" => "original"})

    {:ok, view, _html} = live(conn, "/en/admin/crm/lists/#{list.uuid}/edit")
    view |> form("#crm-list-form", list: %{name: "Renamed"}) |> render_submit()

    assert Lists.get_list!(list.uuid).name == "Renamed"
  end
end
