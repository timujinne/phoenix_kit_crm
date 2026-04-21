defmodule PhoenixKitCRM.Web.SettingsLive do
  @moduledoc """
  CRM settings page — currently just exposes the enable/disable toggle.

  The admin Modules page also toggles the same setting; this tab is here
  to host future module-specific configuration.
  """
  use PhoenixKitWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: Gettext.gettext(PhoenixKitWeb.Gettext, "CRM settings"),
       enabled: PhoenixKitCRM.enabled?()
     )}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    result =
      if socket.assigns.enabled,
        do: PhoenixKitCRM.disable_system(),
        else: PhoenixKitCRM.enable_system()

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:enabled, PhoenixKitCRM.enabled?())
         |> put_flash(:info, Gettext.gettext(PhoenixKitWeb.Gettext, "CRM settings updated"))}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(PhoenixKitWeb.Gettext, "Failed to update CRM settings")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-3xl px-4 py-6 gap-6">
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl">
            <.icon name="hero-cog-6-tooth" class="w-6 h-6" />
            {Gettext.gettext(PhoenixKitWeb.Gettext, "CRM settings")}
          </h2>
          <p class="text-base-content/70 text-sm">
            {Gettext.gettext(
              PhoenixKitWeb.Gettext,
              "Module-specific configuration will appear here as the CRM grows."
            )}
          </p>

          <div class="divider"></div>

          <div class="flex items-center justify-between">
            <div>
              <div class="font-medium">
                {Gettext.gettext(PhoenixKitWeb.Gettext, "Enable CRM")}
              </div>
              <div class="text-xs text-base-content/60">
                {Gettext.gettext(
                  PhoenixKitWeb.Gettext,
                  "Toggles this module on or off. Same setting as the admin Modules page."
                )}
              </div>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-primary"
              phx-click="toggle"
              checked={@enabled}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
