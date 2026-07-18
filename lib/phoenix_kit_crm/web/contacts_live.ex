defmodule PhoenixKitCRM.Web.ContactsLive do
  @moduledoc "Admin list of CRM contacts."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  import PhoenixKitCRM.Web.PartyRoleHelpers, only: [role_label: 1, role_badge_class: 1]

  alias PhoenixKitCRM.{Activity, Contacts, PartyRoles, Paths}
  alias PhoenixKitCRM.Schemas.Contact

  @role_filters ~w(supplier client)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("CRM — Contacts"),
       filter: "active",
       contacts: [],
       roles_map: %{},
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

    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  defp load(socket) do
    contacts =
      case socket.assigns.filter do
        "trashed" -> Contacts.list_contacts(status: "trashed")
        role when role in @role_filters -> PartyRoles.list_contacts_with_role(role)
        _ -> Contacts.list_contacts([])
      end

    socket
    |> assign(:contacts, contacts)
    |> assign(:roles_map, PartyRoles.active_roles_map("contact", Enum.map(contacts, & &1.uuid)))
    |> assign(:trashed_count, Contacts.count_contacts(status: "trashed"))
  end

  @impl true
  def handle_event("trash", %{"uuid" => uuid}, socket) do
    with %Contact{} = c <- Contacts.get_contact(uuid), {:ok, _} <- Contacts.trash_contact(c) do
      Activity.log(
        "crm.contact_trashed",
        Activity.actor_opts(socket) ++ [resource_type: "crm_contact", resource_uuid: uuid]
      )

      {:noreply, socket |> put_flash(:info, gettext("Contact moved to trash")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not trash contact"))}
    end
  end

  def handle_event("restore", %{"uuid" => uuid}, socket) do
    with %Contact{} = c <- Contacts.get_contact(uuid), {:ok, _} <- Contacts.restore_contact(c) do
      {:noreply, socket |> put_flash(:info, gettext("Contact restored")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not restore contact"))}
    end
  end

  def handle_event("delete", %{"uuid" => uuid}, socket) do
    with %Contact{} = c <- Contacts.get_contact(uuid), {:ok, _} <- Contacts.delete_contact(c) do
      # Permanent delete cascades the contact's media folder subtree (best-effort).
      PhoenixKitCRM.Attachments.purge_media(:contact, uuid)

      Activity.log(
        "crm.contact_deleted",
        Activity.actor_opts(socket) ++ [resource_type: "crm_contact", resource_uuid: uuid]
      )

      {:noreply, socket |> put_flash(:info, gettext("Contact permanently deleted")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not delete contact"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-6xl px-4 py-6 gap-6">
      <div role="tablist" class="tabs tabs-bordered">
        <.link patch={Paths.contacts()} role="tab" class={["tab", @filter == "active" && "tab-active"]}>
          {gettext("Active")}
        </.link>
        <.link patch={Paths.contacts() <> "?filter=supplier"} role="tab" class={["tab", @filter == "supplier" && "tab-active"]}>
          {gettext("Suppliers")}
        </.link>
        <.link patch={Paths.contacts() <> "?filter=client"} role="tab" class={["tab", @filter == "client" && "tab-active"]}>
          {gettext("Clients")}
        </.link>
        <.link
          :if={@trashed_count > 0 or @filter == "trashed"}
          patch={Paths.contacts() <> "?filter=trashed"}
          role="tab"
          class={["tab", @filter == "trashed" && "tab-active"]}
        >
          {trashed_tab_label(@trashed_count)}
        </.link>
      </div>

      <.empty_state
        :if={@contacts == []}
        icon="hero-user"
        title={gettext("No contacts yet.")}
        variant="card"
      >
        <.link navigate={Paths.contact_new()} class="btn btn-primary">
          <.icon name="hero-plus" class="w-4 h-4" /> {gettext("Create first contact")}
        </.link>
      </.empty_state>

      <.table_default
        :if={@contacts != []}
        id="crm-contacts-list"
        size="sm"
        toggleable
        items={@contacts}
        card_title={fn c -> card_title_link(c, @roles_map) end}
        card_fields={fn c -> card_fields(c) end}
      >
        <:toolbar_title>
          <span class="text-sm text-base-content/60">
            {ngettext("%{count} contact", "%{count} contacts", length(@contacts),
              count: length(@contacts)
            )}
          </span>
        </:toolbar_title>
        <:toolbar_actions>
          <.link navigate={Paths.contact_new()} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="w-4 h-4" /> {gettext("New contact")}
          </.link>
        </:toolbar_actions>

        <:card_actions :let={c}>
          {row_menu(%{contact: c, filter: @filter, id_suffix: "card"})}
        </:card_actions>

        <.table_default_header>
          <.table_default_row>
            <.table_default_header_cell>{gettext("Name")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Company")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Email")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Login")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Status")}</.table_default_header_cell>
            <.table_default_header_cell class="text-right whitespace-nowrap">
              {gettext("Actions")}
            </.table_default_header_cell>
          </.table_default_row>
        </.table_default_header>
        <.table_default_body>
          <.table_default_row :for={c <- @contacts}>
            <.table_default_cell class="font-medium">
              <.link navigate={Paths.contact(c.uuid)} class="link link-hover">
                {Contact.display_name(c)}
              </.link>
              <span :for={role <- Map.get(@roles_map, c.uuid, [])} class={["badge badge-sm ml-1", role_badge_class(role)]}>
                {role_label(role)}
              </span>
            </.table_default_cell>
            <.table_default_cell class="text-base-content/70">
              <.company_cell contact={c} />
            </.table_default_cell>
            <.table_default_cell class="text-base-content/70">{c.email || "—"}</.table_default_cell>
            <.table_default_cell>
              <span :if={c.user_uuid} class="badge badge-success badge-sm gap-1">
                <.icon name="hero-key-mini" class="w-3 h-3" /> {gettext("Yes")}
              </span>
              <span :if={is_nil(c.user_uuid)} class="text-base-content/40 text-xs">—</span>
            </.table_default_cell>
            <.table_default_cell><.status_badge status={c.status} size={:sm} /></.table_default_cell>
            <.table_default_cell class="text-right whitespace-nowrap">
              {row_menu(%{contact: c, filter: @filter, id_suffix: "table"})}
            </.table_default_cell>
          </.table_default_row>
        </.table_default_body>
      </.table_default>
    </div>
    """
  end

  # The contact's primary company (linked) + role, or "—".
  attr(:contact, :map, required: true)

  defp company_cell(assigns) do
    assigns = assign(assigns, :m, Contacts.primary_membership(assigns.contact))

    ~H"""
    <span :if={!company_name(@m)}>—</span>
    <span :if={company_name(@m)}>
      <.link navigate={Paths.company(@m.company_uuid)} class="link link-hover">{company_name(@m)}</.link><span :if={@m.role_in_company not in [nil, ""]}>{" · " <> @m.role_in_company}</span>
    </span>
    """
  end

  defp company_name(%{company: %{name: name}}) when is_binary(name), do: name
  defp company_name(_), do: nil

  defp trashed_tab_label(0), do: gettext("Trashed")
  defp trashed_tab_label(n), do: gettext("Trashed (%{count})", count: n)

  defp card_title_link(contact, roles_map) do
    assigns = %{contact: contact, roles: Map.get(roles_map, contact.uuid, [])}

    ~H"""
    <.link navigate={Paths.contact(@contact.uuid)} class="link link-hover font-medium">
      {Contact.display_name(@contact)}
    </.link>
    <span :for={role <- @roles} class={["badge badge-sm ml-1", role_badge_class(role)]}>
      {role_label(role)}
    </span>
    """
  end

  defp card_fields(contact) do
    [
      %{label: gettext("Company"), value: company_value(contact)},
      %{label: gettext("Email"), value: contact.email || "—"},
      %{label: gettext("Status"), value: contact.status}
    ]
  end

  # company_cell/1 is a proper Phoenix.Component — calling it as a bare
  # function (company_cell(%{contact: contact})) skips the ~H sigil's
  # change-tracking setup and raises. Routing through this ~H wrapper (same
  # trick card_title_link/2 already uses) gives it real assigns.
  defp company_value(contact) do
    assigns = %{contact: contact}

    ~H"""
    <.company_cell contact={@contact} />
    """
  end

  # `id_suffix` distinguishes the table-cell and card_actions renders — the
  # toggleable table_default keeps BOTH views in the DOM at once (CSS-hidden,
  # not removed), so reusing one id across the two would be a real duplicate.
  defp row_menu(assigns) do
    ~H"""
    <.table_row_menu id={"crm-contact-menu-#{@id_suffix}-#{@contact.uuid}"}>
      <%= if @filter == "trashed" do %>
        <.table_row_menu_button
          phx-click="restore"
          phx-value-uuid={@contact.uuid}
          phx-disable-with={gettext("Restoring…")}
          icon="hero-arrow-uturn-left"
          label={gettext("Restore")}
          variant="success"
        />
        <.table_row_menu_divider />
        <.table_row_menu_button
          phx-click="delete"
          phx-value-uuid={@contact.uuid}
          phx-disable-with={gettext("Deleting…")}
          data-confirm={gettext("Permanently delete this contact? This cannot be undone.")}
          icon="hero-x-circle"
          label={gettext("Delete permanently")}
          variant="error"
        />
      <% else %>
        <.table_row_menu_link
          navigate={Paths.contact_edit(@contact.uuid)}
          icon="hero-pencil"
          label={gettext("Edit")}
        />
        <.table_row_menu_divider />
        <.table_row_menu_button
          phx-click="trash"
          phx-value-uuid={@contact.uuid}
          phx-disable-with={gettext("Moving…")}
          data-confirm={gettext("Move this contact to trash?")}
          icon="hero-trash"
          label={gettext("Trash")}
          variant="error"
        />
      <% end %>
    </.table_row_menu>
    """
  end
end
