defmodule PhoenixKitCRM.Test.Hooks do
  @moduledoc """
  `on_mount` hooks used by the LiveView test endpoint.

  Production runs the CRM LiveViews inside a `live_session` configured by core
  phoenix_kit, which populates `socket.assigns[:phoenix_kit_current_scope]` and
  `socket.assigns[:phoenix_kit_current_user]` from the host's authentication. Our
  test endpoint doesn't load core's hooks, so this module replicates the same
  effect by pulling scope data from the test session.

  Tests set scope via `LiveCase.put_test_scope/2`; the `:assign_scope` hook below
  reads it back and mirrors it onto socket assigns (also as `current_user_uuid`,
  which the embedded/comments paths read directly).
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:assign_scope, _params, session, socket) do
    case Map.get(session, "phoenix_kit_test_scope") do
      nil ->
        {:cont, socket}

      %{user: user} = scope ->
        socket =
          socket
          |> assign(:phoenix_kit_current_scope, scope)
          |> assign(:phoenix_kit_current_user, user)
          |> assign(:current_user_uuid, user[:uuid])

        {:cont, socket}
    end
  end
end
