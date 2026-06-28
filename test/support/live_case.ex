defmodule PhoenixKitCRM.LiveCase do
  @moduledoc """
  Test case for LiveView tests. Wires up the test Endpoint, imports
  `Phoenix.LiveViewTest` helpers, and sets up an Ecto SQL sandbox connection.
  Tests using this case are tagged `:integration` automatically (excluded when
  the test DB isn't available).

  ## Example

      defmodule PhoenixKitCRM.Web.ContactsLiveTest do
        use PhoenixKitCRM.LiveCase

        test "renders", %{conn: conn} do
          {:ok, _view, html} = live(conn, "/en/admin/crm/contacts")
          assert html =~ "Contacts"
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
      @endpoint PhoenixKitCRM.Test.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import PhoenixKitCRM.ActivityLogAssertions
      import PhoenixKitCRM.LiveCase
    end
  end

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitCRM.Test.Repo, as: TestRepo

  setup tags do
    pid = Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{})

    {:ok, conn: conn}
  end

  @doc """
  A real `PhoenixKit.Users.Auth.Scope` for testing. The CRM LiveViews read
  `socket.assigns[:phoenix_kit_current_user]` (via `Activity.actor_opts/1`) to
  thread the actor uuid into activity logging; production
  `live_session :phoenix_kit_admin` gates admin access, which the test endpoint
  bypasses. Per workspace AGENTS.md `cached_roles` must be a list if
  `Scope.admin?/1` ever fires.

  ## Options

    * `:user_uuid` — defaults to a fresh UUID
    * `:email` — defaults to a unique-suffix string
    * `:roles` — role-name strings; defaults to `["Owner"]`
    * `:permissions` — module-key strings; defaults to `["crm"]`
    * `:authenticated?` — defaults to `true`
  """
  def fake_scope(opts \\ []) do
    user_uuid = Keyword.get(opts, :user_uuid, Ecto.UUID.generate())
    email = Keyword.get(opts, :email, "test-#{System.unique_integer([:positive])}@example.com")
    roles = Keyword.get(opts, :roles, ["Owner"])
    permissions = Keyword.get(opts, :permissions, ["crm"])
    authenticated? = Keyword.get(opts, :authenticated?, true)

    user = %{uuid: user_uuid, email: email}

    %PhoenixKit.Users.Auth.Scope{
      user: user,
      authenticated?: authenticated?,
      cached_roles: roles,
      cached_permissions: MapSet.new(permissions)
    }
  end

  @doc """
  Plugs a fake scope into the test conn's session so the `:assign_scope`
  `on_mount` hook can mirror it onto socket assigns at mount. Pair with
  `fake_scope/1`.
  """
  def put_test_scope(conn, scope) do
    Plug.Test.init_test_session(conn, %{"phoenix_kit_test_scope" => scope})
  end
end
