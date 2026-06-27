defmodule PhoenixKitCRM.Web.ContactShowLive do
  @moduledoc "Show page for a CRM contact — Overview + Interactions/History tabs."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.{Contacts, Paths}
  alias PhoenixKitCRM.Schemas.Contact
  alias PhoenixKitCRM.Web.InteractionsComponent

  @tabs ~w(overview interactions)

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    case Contacts.get_contact(params["uuid"]) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Contact not found"))
         |> push_navigate(to: Paths.contacts())}

      contact ->
        tab = if params["tab"] in @tabs, do: params["tab"], else: "overview"

        {:noreply,
         socket
         |> assign(:contact, contact)
         |> assign(:tab, tab)
         |> assign(:membership, Contacts.primary_membership(contact))
         |> assign(:tz_offset, tz_offset(socket.assigns[:phoenix_kit_current_user]))
         |> assign(:page_title, Contact.display_name(contact))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-4xl px-4 py-6 gap-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div>
          <.link navigate={Paths.contacts()} class="text-sm text-base-content/60 hover:underline">
            ← {gettext("Contacts")}
          </.link>
          <h1 class="text-2xl font-bold flex items-center gap-2 mt-1">
            <.icon name="hero-user" class="w-6 h-6" /> {Contact.display_name(@contact)}
            <.status_badge status={@contact.status} size={:sm} />
            <span :if={@contact.user_uuid} class="badge badge-success badge-sm gap-1">
              <.icon name="hero-key-mini" class="w-3 h-3" /> {gettext("Login")}
            </span>
          </h1>
          <div :if={@membership} class="text-sm text-base-content/60 mt-1">
            {[membership_company(@membership), @membership.role_in_company, @membership.department]
            |> Enum.reject(&(&1 in [nil, ""]))
            |> Enum.join(" · ")}
          </div>
        </div>
        <.link navigate={Paths.contact_edit(@contact.uuid)} class="btn btn-outline btn-sm">
          <.icon name="hero-pencil-square" class="w-4 h-4" /> {gettext("Edit")}
        </.link>
      </div>

      <div role="tablist" class="tabs tabs-bordered">
        <.link patch={Paths.contact(@contact.uuid)} role="tab" class={["tab", @tab == "overview" && "tab-active"]}>
          {gettext("Overview")}
        </.link>
        <.link patch={Paths.contact(@contact.uuid) <> "?tab=interactions"} role="tab" class={["tab", @tab == "interactions" && "tab-active"]}>
          {gettext("Interactions")}
        </.link>
      </div>

      <div :if={@tab == "overview"} class="card bg-base-100 shadow-sm">
        <div class="card-body grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-3">
          <.field label={gettext("Email")} value={@contact.email} />
          <.field label={gettext("Phone")} value={@contact.phone} />
          <.field label={gettext("Company")} value={@membership && membership_company(@membership)} />
          <.field label={gettext("Role in company")} value={@membership && @membership.role_in_company} />
          <.field label={gettext("Department / team")} value={@membership && @membership.department} />
          <.field label={gettext("Login account")} value={if(@contact.user_uuid, do: gettext("Connected"), else: gettext("None"))} />
          <div class="sm:col-span-2"><.field label={gettext("Notes")} value={@contact.notes} /></div>
        </div>
      </div>

      <div :if={@tab == "interactions"}>
        <.live_component
          module={InteractionsComponent}
          id={"crm-interactions-#{@contact.uuid}"}
          contact={@contact}
          current_user_uuid={current_user_uuid(assigns)}
          current_user_name={current_user_name(assigns)}
          tz_offset={@tz_offset}
        />
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, default: nil)

  defp field(assigns) do
    ~H"""
    <div>
      <div class="text-xs uppercase tracking-wide text-base-content/50">{@label}</div>
      <div class="text-sm">{@value || "—"}</div>
    </div>
    """
  end

  defp membership_company(%{company: %{name: name}}) when is_binary(name), do: name
  defp membership_company(_), do: nil

  defp current_user_uuid(assigns) do
    case assigns[:phoenix_kit_current_user] do
      %{uuid: uuid} -> uuid
      _ -> nil
    end
  end

  # Display name for the "Add me" party shortcut — full name, else email.
  defp current_user_name(assigns) do
    case assigns[:phoenix_kit_current_user] do
      %{} = user ->
        case User.full_name(user) do
          name when is_binary(name) and name != "" -> name
          _ -> user.email
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # The viewer's timezone offset (hours) — user profile → system setting → UTC,
  # via core's `PhoenixKit.Utils.Date.get_user_timezone/1`. Drives interaction
  # times so they show/save in the user's configured timezone (storage is UTC).
  defp tz_offset(%{} = user) do
    case PhoenixKit.Utils.Date.get_user_timezone(user) do
      off when is_binary(off) ->
        case Integer.parse(off) do
          {hours, _} -> hours
          _ -> 0
        end

      _ ->
        0
    end
  rescue
    _ -> 0
  end

  defp tz_offset(_), do: 0
end
