defmodule PhoenixKitCRM.Web.ListMembersLive do
  @moduledoc """
  Admin page for a single CRM contact list's memberships — paginated member
  table (status/source/email, remove action) plus a manual add-by-email form.

  The add form always creates a brand-new contact (`Lists.add_new_contact_to_list/3`),
  matching the import engine's policy — except when the typed email already
  holds a `"removed"` slot in this list (`idx_crm_list_members_list_email`),
  in which case a new-contact insert would just fail. That case gets its own
  "Resubscribe" affordance instead: reactivates the EXISTING contact's
  membership (`Lists.add_contact_to_list/3`) rather than trying (and
  failing) to create a second contact for the same email. Resubscribe never
  touches the found contact's name/locale — only the membership.
  """
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Activity, Lists, Paths}
  alias PhoenixKitCRM.PubSub, as: CRMPubSub
  alias PhoenixKitCRM.Schemas.{Contact, ListMember}

  @page_size 25

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    case Lists.get_list(uuid) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("List not found"))
         |> push_navigate(to: Paths.lists())}

      list ->
        if connected?(socket), do: CRMPubSub.subscribe(CRMPubSub.topic_lists())

        {:ok,
         socket
         |> assign(:list, list)
         |> assign(:page_title, gettext("CRM — %{name}", name: list.name))
         |> assign(:page_subtitle, list_subtitle(list))
         |> assign(:page_section, gettext("Lists"))
         |> assign(:page_section_path, Paths.lists())
         |> assign(:members, [])
         |> assign(:has_more?, false)
         |> assign(:add_form, blank_add_form())
         |> assign(:email_check, nil)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      case params["status"] do
        s when s in ~w(subscribed pending removed) -> s
        _ -> nil
      end

    page = parse_page(params["page"])
    search = params["search"] || ""

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:page, page)
     |> assign(:search, search)
     |> load_members()}
  end

  # ── Search / pagination ──────────────────────────────────────────────

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, push_patch(socket, to: members_path(socket.assigns, search: term, page: 1))}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply,
     push_patch(socket, to: members_path(socket.assigns, status: presence(status), page: 1))}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply,
     push_patch(socket, to: members_path(socket.assigns, page: socket.assigns.page + 1))}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: members_path(socket.assigns, page: max(socket.assigns.page - 1, 1))
     )}
  end

  # ── Manual add-by-email ───────────────────────────────────────────────

  def handle_event("check_email", %{"add_member" => params}, socket) do
    {:noreply,
     socket
     |> assign(:add_form, to_form(params, as: :add_member))
     |> assign(:email_check, check_email(socket.assigns.list, params["email"]))}
  end

  def handle_event("add_member", %{"add_member" => params}, socket) do
    case socket.assigns.email_check do
      {:removed, _} -> {:noreply, socket}
      {:active, _} -> {:noreply, socket}
      _ -> do_add_member(socket, params)
    end
  end

  def handle_event("resubscribe", _params, socket) do
    case socket.assigns.email_check do
      {:removed, %ListMember{} = member} ->
        contact = member.contact || %Contact{uuid: member.contact_uuid}
        resubscribe(socket, contact)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("resubscribe_row", %{"contact_uuid" => contact_uuid}, socket) do
    case Enum.find(socket.assigns.members, &(&1.contact_uuid == contact_uuid)) do
      %ListMember{contact: %Contact{} = contact} -> resubscribe(socket, contact)
      _ -> {:noreply, socket}
    end
  end

  # ── Removal ─────────────────────────────────────────────────────────

  def handle_event("remove_member", %{"uuid" => uuid}, socket) do
    case Enum.find(socket.assigns.members, &(&1.uuid == uuid)) do
      nil ->
        {:noreply, socket}

      member ->
        {:ok, _} = Lists.remove_from_list(member, Activity.actor_opts(socket))
        {:noreply, socket |> put_flash(:info, gettext("Member removed")) |> load_members()}
    end
  end

  @impl true
  def handle_info({:crm, _event, %{list_uuid: list_uuid}}, socket) do
    if list_uuid == socket.assigns.list.uuid do
      {:noreply, load_members(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── Private helpers ─────────────────────────────────────────────────

  defp load_members(socket) do
    %{list: list, filter: filter, page: page, search: search} = socket.assigns

    opts =
      [limit: @page_size + 1, offset: (page - 1) * @page_size]
      |> maybe_put(:status, filter)
      |> maybe_put(:search, if(search == "", do: nil, else: search))

    members = Lists.list_members(list, opts)
    has_more? = length(members) > @page_size
    refreshed_list = Lists.get_list!(list.uuid)

    socket
    |> assign(:members, Enum.take(members, @page_size))
    |> assign(:has_more?, has_more?)
    |> assign(:list, refreshed_list)
    |> assign(:page_subtitle, list_subtitle(refreshed_list))
  end

  defp list_subtitle(list) do
    ngettext("%{count} subscriber", "%{count} subscribers", list.subscriber_count,
      count: list.subscriber_count
    )
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  # `String.to_integer/1` raises on anything non-numeric — a fat-fingered
  # bookmark or a crawler hitting `?page=abc` (or a stray trailing
  # `?page=`) would crash the LiveView. `Integer.parse/1` doesn't raise;
  # anything it can't read at all (or the `nil` from no param) falls back
  # to page 1.
  defp parse_page(nil), do: 1

  defp parse_page(param) do
    case Integer.parse(param) do
      {n, _rest} -> max(n, 1)
      :error -> 1
    end
  end

  defp blank_add_form,
    do: to_form(%{"email" => "", "name" => "", "locale" => ""}, as: :add_member)

  defp presence(""), do: nil
  defp presence(v), do: v

  # Takes an assigns-shaped map — either a LiveView `socket.assigns` (from an
  # event handler) or the `assigns` passed into `render/1` (from the
  # template) — both expose `:filter`/`:search`/`:page`/`:list` the same way.
  defp members_path(assigns, overrides) do
    params =
      %{status: assigns.filter, search: assigns.search, page: assigns.page}
      |> Map.merge(Map.new(overrides))
      |> Enum.reject(fn {_k, v} -> v in [nil, "", 1] end)
      |> Enum.into(%{})

    case params do
      empty when map_size(empty) == 0 -> Paths.list_members(assigns.list.uuid)
      _ -> Paths.list_members(assigns.list.uuid) <> "?" <> URI.encode_query(params)
    end
  end

  defp check_email(_list, email) when email in [nil, ""], do: nil

  defp check_email(list, email) do
    normalized = email |> String.trim() |> String.downcase()

    case Lists.get_member_by_email(list, normalized) do
      nil -> :none
      %ListMember{status: "removed"} = member -> {:removed, member}
      %ListMember{} = member -> {:active, member}
    end
  end

  defp do_add_member(socket, params) do
    attrs = Map.take(params, ["email", "name", "locale"])

    case Lists.add_new_contact_to_list(attrs, socket.assigns.list, Activity.actor_opts(socket)) do
      {:ok, {_contact, _member}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Contact added to the list"))
         |> assign(:add_form, blank_add_form())
         |> assign(:email_check, nil)
         |> load_members()}

      {:error, :email_already_in_list} ->
        # Race: the slot got taken between the live check and submit — re-run
        # the check so the UI catches up (e.g. shows Resubscribe now).
        {:noreply,
         socket
         |> assign(:add_form, to_form(params, as: :add_member))
         |> assign(:email_check, check_email(socket.assigns.list, params["email"]))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :add_form, to_form(changeset, as: :add_member))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not add this contact"))}
    end
  end

  defp resubscribe(socket, %Contact{} = contact) do
    case Lists.add_contact_to_list(contact, socket.assigns.list, Activity.actor_opts(socket)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Contact resubscribed"))
         |> assign(:add_form, blank_add_form())
         |> assign(:email_check, nil)
         |> load_members()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not resubscribe this contact"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-6xl px-4 py-6 gap-6">
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body gap-4">
          <h2 class="font-semibold flex items-center gap-2">
            <.icon name="hero-user-plus" class="w-5 h-5" /> {gettext("Add a contact")}
          </h2>

          <.form
            for={@add_form}
            id="crm-list-add-member-form"
            phx-change="check_email"
            phx-submit="add_member"
            class="grid gap-3 sm:grid-cols-3"
          >
            <.input
              field={@add_form[:email]}
              type="email"
              label={gettext("Email")}
              phx-debounce="300"
              required
            />
            <.input field={@add_form[:name]} label={gettext("Name (optional)")} />
            <.input field={@add_form[:locale]} label={gettext("Locale (optional)")} placeholder="en" />

            <div class="sm:col-span-3 flex items-center gap-3">
              <%= case @email_check do %>
                <% {:active, _} -> %>
                  <span class="badge badge-warning gap-1">
                    <.icon name="hero-exclamation-triangle" class="w-3 h-3" />
                    {gettext("Already in this list")}
                  </span>
                <% {:removed, member} -> %>
                  <span class="badge badge-info gap-1">
                    <.icon name="hero-information-circle" class="w-3 h-3" />
                    {gettext("Previously unsubscribed: %{name}",
                      name: contact_label(member.contact)
                    )}
                  </span>
                  <.button
                    type="button"
                    phx-click="resubscribe"
                    class="btn-sm btn-outline btn-info"
                    phx-disable-with={gettext("Resubscribing…")}
                  >
                    {gettext("Resubscribe")}
                  </.button>
                <% _ -> %>
                  <.button
                    type="submit"
                    class="btn-sm btn-primary"
                    phx-disable-with={gettext("Adding…")}
                  >
                    {gettext("Add to list")}
                  </.button>
              <% end %>
            </div>
          </.form>
        </div>
      </div>

      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <div role="tablist" class="tabs tabs-bordered">
            <.link
              patch={members_path(assigns, status: nil, page: 1)}
              role="tab"
              class={["tab", is_nil(@filter) && "tab-active"]}
            >
              {gettext("All")}
            </.link>
            <.link
              patch={members_path(assigns, status: "subscribed", page: 1)}
              role="tab"
              class={["tab", @filter == "subscribed" && "tab-active"]}
            >
              {gettext("Subscribed")}
            </.link>
            <.link
              patch={members_path(assigns, status: "removed", page: 1)}
              role="tab"
              class={["tab", @filter == "removed" && "tab-active"]}
            >
              {gettext("Removed")}
            </.link>
          </div>

          <div class="flex items-center gap-2">
            <.link navigate={Paths.list_import(@list.uuid)} class="btn btn-outline btn-sm">
              <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> {gettext("Import")}
            </.link>
            <.link navigate={Paths.list_edit(@list.uuid)} class="btn btn-ghost btn-sm">
              <.icon name="hero-pencil" class="w-4 h-4" /> {gettext("Edit list")}
            </.link>
          </div>
        </div>

        <div class="w-full sm:w-64 self-end">
          <.search_toolbar
            name="search"
            value={@search}
            placeholder={gettext("Search email/name")}
            on_submit="search"
          />
        </div>
      </div>

      <.empty_state
        :if={@members == []}
        icon="hero-users"
        title={gettext("No members yet.")}
        variant="card"
      />

      <.table_default :if={@members != []} id="crm-list-members-table" size="sm">
        <.table_default_header>
          <.table_default_row>
            <.table_default_header_cell>{gettext("Contact")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Email")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Locale")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Status")}</.table_default_header_cell>
            <.table_default_header_cell>{gettext("Source")}</.table_default_header_cell>
            <.table_default_header_cell class="text-right whitespace-nowrap">
              {gettext("Actions")}
            </.table_default_header_cell>
          </.table_default_row>
        </.table_default_header>
        <.table_default_body>
          <.table_default_row :for={member <- @members}>
            <.table_default_cell class="font-medium">
              <.link
                :if={member.contact}
                navigate={Paths.contact(member.contact_uuid)}
                class="link link-hover"
              >
                {contact_label(member.contact)}
              </.link>
              <span :if={!member.contact} class="text-base-content/40">—</span>
            </.table_default_cell>
            <.table_default_cell class="text-base-content/70">{member.email || "—"}</.table_default_cell>
            <.table_default_cell class="text-base-content/70">{member_locale(member)}</.table_default_cell>
            <.table_default_cell>{member_status_badge(member.status)}</.table_default_cell>
            <.table_default_cell class="text-base-content/70">{member.source}</.table_default_cell>
            <.table_default_cell class="text-right whitespace-nowrap">
              <button
                :if={member.status != "removed"}
                type="button"
                phx-click="remove_member"
                phx-value-uuid={member.uuid}
                data-confirm={gettext("Remove this member from the list?")}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" /> {gettext("Remove")}
              </button>
              <button
                :if={member.status == "removed" && member.contact}
                type="button"
                phx-click="resubscribe_row"
                phx-value-contact_uuid={member.contact_uuid}
                class="btn btn-ghost btn-xs text-info"
              >
                <.icon name="hero-arrow-uturn-left" class="w-4 h-4" /> {gettext("Resubscribe")}
              </button>
            </.table_default_cell>
          </.table_default_row>
        </.table_default_body>
      </.table_default>

      <div :if={@page > 1 or @has_more?} class="flex items-center justify-center gap-2">
        <button
          type="button"
          class="btn btn-sm btn-ghost"
          disabled={@page <= 1}
          phx-click="prev_page"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" /> {gettext("Previous")}
        </button>
        <span class="text-sm text-base-content/60">{gettext("Page %{n}", n: @page)}</span>
        <button
          type="button"
          class="btn btn-sm btn-ghost"
          disabled={!@has_more?}
          phx-click="next_page"
        >
          {gettext("Next")} <.icon name="hero-chevron-right" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  defp contact_label(%Contact{} = contact), do: Contact.display_name(contact)
  defp contact_label(_), do: "—"

  defp member_locale(%ListMember{contact: %Contact{locale: locale}})
       when is_binary(locale) and locale != "",
       do: locale

  defp member_locale(_), do: "—"

  # `.status_badge` has no "subscribed" mapping (falls through to ghost/gray),
  # which reads as neutral rather than active — give it its own success color.
  # "pending"/"removed" already get a sensible default from `.status_badge`.
  defp member_status_badge("subscribed") do
    assigns = %{}

    ~H"""
    <span class="badge badge-success badge-sm">{gettext("Subscribed")}</span>
    """
  end

  defp member_status_badge(status) do
    assigns = %{status: status}

    ~H"""
    <.status_badge status={@status} size={:sm} />
    """
  end
end
