defmodule PhoenixKitCRM.Web.CompaniesLive do
  @moduledoc "Admin list of CRM companies."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  import PhoenixKitCRM.Web.PartyRoleHelpers, only: [role_label: 1, role_badge_class: 1]

  alias PhoenixKitCRM.{Activity, Companies, PartyRoles, Paths}
  alias PhoenixKitCRM.Schemas.Company

  @role_filters ~w(supplier client)
  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("CRM — Companies"),
       filter: "active",
       page: 1,
       search: "",
       companies: [],
       roles_map: %{},
       total_count: 0,
       total_pages: 1,
       trashed_count: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      case params["filter"] do
        f when f == "trashed" or f in @role_filters -> f
        _ -> "active"
      end

    page = max(String.to_integer(params["page"] || "1"), 1)
    search = params["search"] || ""

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:page, page)
     |> assign(:search, search)
     |> load()}
  end

  # ── Search / pagination ──────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, push_patch(socket, to: companies_path(socket.assigns, search: term, page: 1))}
  end

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
        <div role="tablist" class="tabs tabs-bordered">
          <.link
            patch={companies_path(assigns, filter: "active", page: 1)}
            role="tab"
            class={["tab", @filter == "active" && "tab-active"]}
          >
            {gettext("Active")}
          </.link>
          <.link
            patch={companies_path(assigns, filter: "supplier", page: 1)}
            role="tab"
            class={["tab", @filter == "supplier" && "tab-active"]}
          >
            {gettext("Suppliers")}
          </.link>
          <.link
            patch={companies_path(assigns, filter: "client", page: 1)}
            role="tab"
            class={["tab", @filter == "client" && "tab-active"]}
          >
            {gettext("Clients")}
          </.link>
          <.link
            :if={@trashed_count > 0 or @filter == "trashed"}
            patch={companies_path(assigns, filter: "trashed", page: 1)}
            role="tab"
            class={["tab", @filter == "trashed" && "tab-active"]}
          >
            {trashed_tab_label(@trashed_count)}
          </.link>
        </div>

        <div class="w-full sm:w-64">
          <.search_toolbar
            name="search"
            value={@search}
            placeholder={gettext("Search name/email")}
            on_submit="search"
          />
        </div>
      </div>

      <.empty_state
        :if={@companies == []}
        icon="hero-building-office-2"
        title={
          if @search != "",
            do: gettext("No companies match your search."),
            else: gettext("No companies yet.")
        }
        variant="card"
      >
        <.link
          :if={@search == "" and @filter == "active"}
          navigate={Paths.company_new()}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="w-4 h-4" /> {gettext("Create first company")}
        </.link>
      </.empty_state>

      <.table_default
        :if={@companies != []}
        id="crm-companies-list"
        size="sm"
        toggleable
        items={@companies}
        card_title={fn c -> card_title_link(c, @roles_map) end}
        card_fields={fn c -> card_fields(c) end}
      >
        <:toolbar_title>
          <span class="text-sm text-base-content/60">
            {ngettext("%{count} company", "%{count} companies", @total_count, count: @total_count)}
          </span>
        </:toolbar_title>
        <:toolbar_actions>
          <.link navigate={Paths.company_new()} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="w-4 h-4" /> {gettext("New company")}
          </.link>
        </:toolbar_actions>

        <:card_actions :let={c}>
          {row_menu(%{company: c, filter: @filter, id_suffix: "card"})}
        </:card_actions>

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
        <.table_default_body>
          <.table_default_row :for={c <- @companies}>
            <.table_default_cell class="font-medium">
              <.link navigate={Paths.company(c.uuid)} class="link link-hover">
                {Company.display_name(c)}
              </.link>
              <span :for={role <- Map.get(@roles_map, c.uuid, [])} class={["badge badge-sm ml-1", role_badge_class(role)]}>
                {role_label(role)}
              </span>
            </.table_default_cell>
            <.table_default_cell class="text-base-content/70">{c.industry || "—"}</.table_default_cell>
            <.table_default_cell><.status_badge status={c.status} size={:sm} /></.table_default_cell>
            <.table_default_cell class="text-right whitespace-nowrap">
              {row_menu(%{company: c, filter: @filter, id_suffix: "table"})}
            </.table_default_cell>
          </.table_default_row>
        </.table_default_body>
      </.table_default>

      <.pagination
        current_page={@page}
        total_pages={@total_pages}
        base_path={Paths.companies()}
        params={%{
          "filter" => (@filter != "active" && @filter) || nil,
          "search" => (@search != "" && @search) || nil
        }}
      />
    </div>
    """
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp load(socket) do
    %{filter: filter, page: page, search: search} = socket.assigns
    search_opt = if search == "", do: nil, else: search

    page_opts =
      [limit: @page_size, offset: (page - 1) * @page_size] |> maybe_put(:search, search_opt)

    {companies, total_count} =
      case filter do
        "trashed" ->
          {Companies.list_companies([status: "trashed"] ++ page_opts),
           Companies.count_companies([status: "trashed"] |> maybe_put(:search, search_opt))}

        role when role in @role_filters ->
          {PartyRoles.list_companies_with_role(role, page_opts),
           PartyRoles.count_companies_with_role(role, [] |> maybe_put(:search, search_opt))}

        _ ->
          {Companies.list_companies(page_opts),
           Companies.count_companies([] |> maybe_put(:search, search_opt))}
      end

    socket
    |> assign(:companies, companies)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, max(ceil(total_count / @page_size), 1))
    |> assign(
      :roles_map,
      PartyRoles.active_roles_map("company", Enum.map(companies, & &1.uuid))
    )
    |> assign(:trashed_count, Companies.count_companies(status: "trashed"))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  # Takes an assigns-shaped map — either a LiveView `socket.assigns` (from an
  # event handler) or the `assigns` passed into `render/1` (from the
  # template) — both expose `:filter`/`:search`/`:page` the same way.
  # "active" is the default filter (never shown in the query string, matching
  # the plain `Paths.companies()` href the Active tab has always used).
  defp companies_path(assigns, overrides) do
    params =
      %{filter: assigns.filter, search: assigns.search, page: assigns.page}
      |> Map.merge(Map.new(overrides))
      |> Enum.reject(fn {k, v} -> v in [nil, "", 1] or (k == :filter and v == "active") end)
      |> Enum.into(%{})

    case params do
      empty when map_size(empty) == 0 -> Paths.companies()
      _ -> Paths.companies() <> "?" <> URI.encode_query(params)
    end
  end

  defp trashed_tab_label(0), do: gettext("Trashed")
  defp trashed_tab_label(n), do: gettext("Trashed (%{count})", count: n)

  defp card_title_link(company, roles_map) do
    assigns = %{company: company, roles: Map.get(roles_map, company.uuid, [])}

    ~H"""
    <.link navigate={Paths.company(@company.uuid)} class="link link-hover font-medium">
      {Company.display_name(@company)}
    </.link>
    <span :for={role <- @roles} class={["badge badge-sm ml-1", role_badge_class(role)]}>
      {role_label(role)}
    </span>
    """
  end

  defp card_fields(company) do
    [
      %{label: gettext("Industry"), value: company.industry || "—"},
      %{label: gettext("Status"), value: company.status}
    ]
  end

  # `id_suffix` distinguishes the table-cell and card_actions renders — the
  # toggleable table_default keeps BOTH views in the DOM at once (CSS-hidden,
  # not removed), so reusing one id across the two would be a real duplicate.
  defp row_menu(assigns) do
    ~H"""
    <.table_row_menu id={"crm-company-menu-#{@id_suffix}-#{@company.uuid}"}>
      <%= if @filter == "trashed" do %>
        <.table_row_menu_button
          phx-click="restore"
          phx-value-uuid={@company.uuid}
          phx-disable-with={gettext("Restoring…")}
          icon="hero-arrow-uturn-left"
          label={gettext("Restore")}
          variant="success"
        />
        <.table_row_menu_divider />
        <.table_row_menu_button
          phx-click="delete"
          phx-value-uuid={@company.uuid}
          phx-disable-with={gettext("Deleting…")}
          data-confirm={gettext("Permanently delete this company? This cannot be undone.")}
          icon="hero-x-circle"
          label={gettext("Delete permanently")}
          variant="error"
        />
      <% else %>
        <.table_row_menu_link
          navigate={Paths.company_edit(@company.uuid)}
          icon="hero-pencil"
          label={gettext("Edit")}
        />
        <.table_row_menu_divider />
        <.table_row_menu_button
          phx-click="trash"
          phx-value-uuid={@company.uuid}
          phx-disable-with={gettext("Moving…")}
          data-confirm={gettext("Move this company to trash?")}
          icon="hero-trash"
          label={gettext("Trash")}
          variant="error"
        />
      <% end %>
    </.table_row_menu>
    """
  end
end
