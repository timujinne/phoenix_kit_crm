defmodule PhoenixKitCRM.Web.ContactsLive do
  @moduledoc "Admin list of CRM contacts."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Activity, Contacts, Paths}
  alias PhoenixKitCRM.Schemas.Contact

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("CRM — Contacts"), filter: "active", contacts: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = if params["filter"] == "trashed", do: "trashed", else: "active"
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  defp load(socket) do
    opts = if socket.assigns.filter == "trashed", do: [status: "trashed"], else: []
    assign(socket, :contacts, Contacts.list_contacts(opts))
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
      <div class="flex items-center justify-between flex-wrap gap-2">
        <h1 class="text-2xl font-bold flex items-center gap-2">
          <.icon name="hero-user" class="w-6 h-6" /> {gettext("Contacts")}
        </h1>
        <.link navigate={Paths.contact_new()} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="w-4 h-4" /> {gettext("New contact")}
        </.link>
      </div>

      <div role="tablist" class="tabs tabs-bordered">
        <.link patch={Paths.contacts()} role="tab" class={["tab", @filter == "active" && "tab-active"]}>
          {gettext("Active")}
        </.link>
        <.link patch={Paths.contacts() <> "?filter=trashed"} role="tab" class={["tab", @filter == "trashed" && "tab-active"]}>
          {gettext("Trashed")}
        </.link>
      </div>

      <div :if={@contacts == []} class="text-center text-base-content/50 py-12">
        {gettext("No contacts yet.")}
      </div>

      <div :if={@contacts != []} class="overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th>{gettext("Name")}</th>
              <th>{gettext("Company")}</th>
              <th>{gettext("Email")}</th>
              <th>{gettext("Login")}</th>
              <th>{gettext("Status")}</th>
              <th class="w-px"></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={c <- @contacts} class="hover">
              <td>
                <.link navigate={Paths.contact(c.uuid)} class="link link-hover font-medium">
                  {Contact.display_name(c)}
                </.link>
              </td>
              <td class="text-base-content/70"><.company_cell contact={c} /></td>
              <td class="text-base-content/70">{c.email || "—"}</td>
              <td>
                <span :if={c.user_uuid} class="badge badge-success badge-sm gap-1">
                  <.icon name="hero-key-mini" class="w-3 h-3" /> {gettext("Yes")}
                </span>
                <span :if={is_nil(c.user_uuid)} class="text-base-content/40 text-xs">—</span>
              </td>
              <td><.status_badge status={c.status} size={:sm} /></td>
              <td class="whitespace-nowrap text-right">
                <%= if @filter == "trashed" do %>
                  <button class="btn btn-ghost btn-xs" phx-click="restore" phx-value-uuid={c.uuid}>
                    {gettext("Restore")}
                  </button>
                  <button class="btn btn-ghost btn-xs text-error" phx-click="delete" phx-value-uuid={c.uuid}
                    data-confirm={gettext("Permanently delete this contact? This cannot be undone.")}>
                    {gettext("Delete")}
                  </button>
                <% else %>
                  <.link navigate={Paths.contact_edit(c.uuid)} class="btn btn-ghost btn-xs">
                    {gettext("Edit")}
                  </.link>
                  <button class="btn btn-ghost btn-xs text-error" phx-click="trash" phx-value-uuid={c.uuid}
                    data-confirm={gettext("Move this contact to trash?")}>
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
end
