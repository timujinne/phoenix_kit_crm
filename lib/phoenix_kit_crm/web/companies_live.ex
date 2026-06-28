defmodule PhoenixKitCRM.Web.CompaniesLive do
  @moduledoc "Admin list of CRM companies."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Activity, Companies, Paths}
  alias PhoenixKitCRM.Schemas.Company

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("CRM — Companies"),
       filter: "active",
       companies: [],
       trashed_count: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = if params["filter"] == "trashed", do: "trashed", else: "active"
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  defp load(socket) do
    opts = if socket.assigns.filter == "trashed", do: [status: "trashed"], else: []

    socket
    |> assign(:companies, Companies.list_companies(opts))
    |> assign(:trashed_count, Companies.count_companies(status: "trashed"))
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
      # Permanent delete cascades the company's media folder subtree (best-effort).
      PhoenixKitCRM.Attachments.purge_media(:company, uuid)

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

      <div
        :if={@trashed_count > 0 or @filter == "trashed"}
        role="tablist"
        class="tabs tabs-bordered"
      >
        <.link patch={Paths.companies()} role="tab" class={["tab", @filter == "active" && "tab-active"]}>
          {gettext("Active")}
        </.link>
        <.link patch={Paths.companies() <> "?filter=trashed"} role="tab" class={["tab", @filter == "trashed" && "tab-active"]}>
          {trashed_tab_label(@trashed_count)}
        </.link>
      </div>

      <.empty_state
        :if={@companies == []}
        icon="hero-building-office-2"
        title={gettext("No companies yet.")}
        variant="card"
      />

      <.table_default :if={@companies != []} id="crm-companies-list" size="sm">
        <.table_default_header>
          <.table_default_row>
            <.table_default_header_cell>{gettext("Name")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Industry")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Status")}</.table_default_header_cell>
            <.table_default_header_cell class="text-right whitespace-nowrap">
              {gettext("Actions")}
            </.table_default_header_cell>
          </.table_default_row>
        </.table_default_header>
        <tbody>
          <.table_default_row :for={c <- @companies}>
            <.table_default_cell class="font-medium">
              <.link navigate={Paths.company(c.uuid)} class="link link-hover">
                {Company.display_name(c)}
              </.link>
            </.table_default_cell>
            <.table_default_cell class="text-base-content/70">{c.industry || "—"}</.table_default_cell>
            <.table_default_cell><.status_badge status={c.status} size={:sm} /></.table_default_cell>
            <.table_default_cell class="text-right whitespace-nowrap">
              <.table_row_menu id={"crm-company-menu-#{c.uuid}"}>
                <%= if @filter == "trashed" do %>
                  <.table_row_menu_button
                    phx-click="restore"
                    phx-value-uuid={c.uuid}
                    phx-disable-with={gettext("Restoring…")}
                    icon="hero-arrow-uturn-left"
                    label={gettext("Restore")}
                    variant="success"
                  />
                  <.table_row_menu_divider />
                  <.table_row_menu_button
                    phx-click="delete"
                    phx-value-uuid={c.uuid}
                    phx-disable-with={gettext("Deleting…")}
                    data-confirm={gettext("Permanently delete this company? This cannot be undone.")}
                    icon="hero-x-circle"
                    label={gettext("Delete permanently")}
                    variant="error"
                  />
                <% else %>
                  <.table_row_menu_link
                    navigate={Paths.company_edit(c.uuid)}
                    icon="hero-pencil"
                    label={gettext("Edit")}
                  />
                  <.table_row_menu_divider />
                  <.table_row_menu_button
                    phx-click="trash"
                    phx-value-uuid={c.uuid}
                    phx-disable-with={gettext("Moving…")}
                    data-confirm={gettext("Move this company to trash?")}
                    icon="hero-trash"
                    label={gettext("Trash")}
                    variant="error"
                  />
                <% end %>
              </.table_row_menu>
            </.table_default_cell>
          </.table_default_row>
        </tbody>
      </.table_default>
    </div>
    """
  end

  defp trashed_tab_label(0), do: gettext("Trashed")
  defp trashed_tab_label(n), do: gettext("Trashed (%{count})", count: n)
end
