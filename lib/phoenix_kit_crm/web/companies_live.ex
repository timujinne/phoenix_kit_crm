defmodule PhoenixKitCRM.Web.CompaniesLive do
  @moduledoc "Admin list of CRM companies."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Activity, Companies, Paths}
  alias PhoenixKitCRM.Schemas.Company

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("CRM — Companies"), filter: "active", companies: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = if params["filter"] == "trashed", do: "trashed", else: "active"
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  defp load(socket) do
    opts = if socket.assigns.filter == "trashed", do: [status: "trashed"], else: []
    assign(socket, :companies, Companies.list_companies(opts))
  end

  @impl true
  def handle_event("trash", %{"uuid" => uuid}, socket) do
    with %Company{} = c <- Companies.get_company(uuid),
         {:ok, _} <- Companies.trash_company(c) do
      Activity.log(
        "crm.company_trashed",
        Activity.actor_opts(socket) ++ [resource_type: "crm_company", resource_uuid: uuid]
      )

      {:noreply, socket |> put_flash(:info, gettext("Company moved to trash")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not trash company"))}
    end
  end

  def handle_event("restore", %{"uuid" => uuid}, socket) do
    with %Company{} = c <- Companies.get_company(uuid),
         {:ok, _} <- Companies.restore_company(c) do
      {:noreply, socket |> put_flash(:info, gettext("Company restored")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not restore company"))}
    end
  end

  def handle_event("delete", %{"uuid" => uuid}, socket) do
    with %Company{} = c <- Companies.get_company(uuid),
         {:ok, _} <- Companies.delete_company(c) do
      Activity.log(
        "crm.company_deleted",
        Activity.actor_opts(socket) ++ [resource_type: "crm_company", resource_uuid: uuid]
      )

      {:noreply, socket |> put_flash(:info, gettext("Company permanently deleted")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not delete company"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-6xl px-4 py-6 gap-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h1 class="text-2xl font-bold flex items-center gap-2">
          <.icon name="hero-building-office-2" class="w-6 h-6" /> {gettext("Companies")}
        </h1>
        <.link navigate={Paths.company_new()} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4" /> {gettext("New company")}
        </.link>
      </div>

      <div role="tablist" class="tabs tabs-bordered">
        <.link patch={Paths.companies()} role="tab" class={["tab", @filter == "active" && "tab-active"]}>
          {gettext("Active")}
        </.link>
        <.link patch={Paths.companies() <> "?filter=trashed"} role="tab" class={["tab", @filter == "trashed" && "tab-active"]}>
          {gettext("Trashed")}
        </.link>
      </div>

      <div :if={@companies == []} class="text-center text-base-content/50 py-12">
        {gettext("No companies yet.")}
      </div>

      <div :if={@companies != []} class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>{gettext("Name")}</th>
              <th>{gettext("Industry")}</th>
              <th>{gettext("Status")}</th>
              <th class="w-px"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @companies} class="hover">
              <td>
                <.link navigate={Paths.company(c.uuid)} class="link link-hover font-medium">
                  {Company.display_name(c)}
                </.link>
              </td>
              <td class="text-base-content/70">{c.industry || "—"}</td>
              <td><.status_badge status={c.status} size={:sm} /></td>
              <td class="whitespace-nowrap text-right">
                <%= if @filter == "trashed" do %>
                  <button class="btn btn-ghost btn-xs" phx-click="restore" phx-value-uuid={c.uuid}>
                    {gettext("Restore")}
                  </button>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete"
                    phx-value-uuid={c.uuid}
                    data-confirm={gettext("Permanently delete this company? This cannot be undone.")}
                  >
                    {gettext("Delete")}
                  </button>
                <% else %>
                  <.link navigate={Paths.company_edit(c.uuid)} class="btn btn-ghost btn-xs">
                    {gettext("Edit")}
                  </.link>
                  <button
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="trash"
                    phx-value-uuid={c.uuid}
                    data-confirm={gettext("Move this company to trash?")}
                  >
                    {gettext("Trash")}
                  </button>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
