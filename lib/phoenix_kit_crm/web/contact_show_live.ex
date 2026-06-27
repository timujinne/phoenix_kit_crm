defmodule PhoenixKitCRM.Web.ContactShowLive do
  @moduledoc """
  Show page for a CRM contact. Tabs: Overview, Interactions, Events always;
  Files + Images when core Storage is enabled; Comments when the comments
  module is enabled. The header shows a circular avatar (initials fallback).
  """
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext
  # Forwards the comment composer's {:leaf_changed, …} into CommentsComponent via
  # a composing on_mount hook (the current pattern — see PhoenixKitComments.Embed).
  use PhoenixKitComments.Embed

  alias PhoenixKit.Modules.Storage
  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.{Attachments, Contacts, Paths}
  alias PhoenixKitCRM.PubSub, as: CRMPubSub
  alias PhoenixKitCRM.Schemas.Contact
  alias PhoenixKitCRM.Web.{ContactEventsComponent, ContactMediaComponent, InteractionsComponent}

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
        storage_enabled = storage_enabled?()
        comments_enabled = comments_available?()

        tab =
          if params["tab"] in valid_tabs(storage_enabled, comments_enabled),
            do: params["tab"],
            else: "overview"

        {:noreply,
         socket
         |> maybe_subscribe(contact.uuid)
         |> assign(:contact, contact)
         |> assign(:tab, tab)
         |> assign(:storage_enabled, storage_enabled)
         |> assign(:comments_enabled, comments_enabled)
         |> assign(:avatar_url, Attachments.avatar_url(contact))
         |> assign(:membership, Contacts.primary_membership(contact))
         |> assign(:tz_offset, tz_offset(socket.assigns[:phoenix_kit_current_user]))
         |> assign(:page_title, Contact.display_name(contact))}
    end
  end

  # Subscribe once (per contact) to this contact's interaction feed so any
  # add/edit/delete by anyone — including from another open tab — pushes a live
  # refresh. Tab switches re-run handle_params but keep the same contact, so the
  # guard avoids a duplicate subscription; navigating to a different contact is a
  # fresh LiveView, which cleans up the old subscription on its own.
  defp maybe_subscribe(socket, contact_uuid) do
    current = socket.assigns[:subscribed_uuid]

    if connected?(socket) and current != contact_uuid do
      # Drop a prior subscription if this process ever switches contact in place
      # (defensive — navigating today is a fresh LiveView, which cleans up its
      # own subscriptions). Only record the uuid once the subscribe succeeds, so
      # a transient failure is retried on the next handle_params.
      if current, do: CRMPubSub.unsubscribe(CRMPubSub.topic_contact_interactions(current))

      case CRMPubSub.subscribe(CRMPubSub.topic_contact_interactions(contact_uuid)) do
        :ok -> assign(socket, :subscribed_uuid, contact_uuid)
        _ -> socket
      end
    else
      socket
    end
  end

  @impl true
  # A CRM interaction touching this contact changed somewhere — refresh the
  # feed if the Interactions tab is open (the component reloads in update/2).
  # When it's not open, the component remounts fresh on the next switch, so
  # there's nothing to do.
  def handle_info({:crm, _event, _payload}, socket) do
    # Reload whichever feed-bearing tab is open. Interactions are the main
    # activity driver, so the Events tab live-refreshes off the same signal.
    if socket.assigns[:contact] do
      case socket.assigns[:tab] do
        "interactions" ->
          send_update(InteractionsComponent,
            id: "crm-interactions-#{socket.assigns.contact.uuid}"
          )

        "events" ->
          send_update(ContactEventsComponent, id: "crm-events-#{socket.assigns.contact.uuid}")

        _ ->
          :ok
      end
    end

    {:noreply, socket}
  end

  # Media component (a LiveComponent, so it routes user-facing flash + avatar
  # refreshes up to this host LiveView).
  def handle_info({:put_flash, kind, msg}, socket), do: {:noreply, put_flash(socket, kind, msg)}

  def handle_info({:avatar_changed}, socket) do
    contact = Contacts.get_contact(socket.assigns.contact.uuid) || socket.assigns.contact

    {:noreply,
     socket |> assign(:contact, contact) |> assign(:avatar_url, Attachments.avatar_url(contact))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Tab definitions drive both the nav and `valid_tabs/2` (deep-link clamp).
  # Files + Images appear only when core Storage is enabled; Comments only when
  # the comments module is enabled.
  defp tab_defs(storage_enabled?, comments_enabled?) do
    [
      {"overview", gettext("Overview"), "hero-identification"},
      {"interactions", gettext("Interactions"), "hero-chat-bubble-left-right"}
    ]
    |> maybe_concat(storage_enabled?, [
      {"files", gettext("Files"), "hero-document"},
      {"images", gettext("Images"), "hero-photo"}
    ])
    |> Kernel.++([{"events", gettext("Events"), "hero-clock"}])
    |> maybe_concat(comments_enabled?, [
      {"comments", gettext("Comments"), "hero-chat-bubble-bottom-center-text"}
    ])
  end

  defp maybe_concat(list, true, extra), do: list ++ extra
  defp maybe_concat(list, false, _extra), do: list

  defp valid_tabs(storage_enabled?, comments_enabled?),
    do:
      Enum.map(tab_defs(storage_enabled?, comments_enabled?), fn {value, _label, _icon} ->
        value
      end)

  defp tab_path(uuid, "overview"), do: Paths.contact(uuid)
  defp tab_path(uuid, tab), do: Paths.contact(uuid) <> "?tab=#{tab}"

  defp storage_enabled? do
    Storage.enabled?()
  rescue
    _ -> false
  end

  defp comments_available? do
    Code.ensure_loaded?(PhoenixKitComments) and PhoenixKitComments.enabled?()
  rescue
    _ -> false
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-4xl px-4 py-6 gap-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-3">
          <.contact_avatar url={@avatar_url} contact={@contact} />
          <div>
            <.link navigate={Paths.contacts()} class="text-sm text-base-content/60 hover:underline">
              ← {gettext("Contacts")}
            </.link>
            <h1 class="text-2xl font-bold flex items-center gap-2 mt-1">
              {Contact.display_name(@contact)}
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
        </div>
        <.link navigate={Paths.contact_edit(@contact.uuid)} class="btn btn-outline btn-sm">
          <.icon name="hero-pencil-square" class="w-4 h-4" /> {gettext("Edit")}
        </.link>
      </div>

      <div role="tablist" class="tabs tabs-bordered">
        <.link
          :for={{value, label, icon} <- tab_defs(@storage_enabled, @comments_enabled)}
          patch={tab_path(@contact.uuid, value)}
          role="tab"
          class={["tab gap-1.5", @tab == value && "tab-active"]}
        >
          <.icon name={icon} class="w-4 h-4" /> {label}
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

      <div :if={@tab == "events"}>
        <.live_component
          module={ContactEventsComponent}
          id={"crm-events-#{@contact.uuid}"}
          contact={@contact}
          tz_offset={@tz_offset}
        />
      </div>

      <div :if={@tab == "files"}>
        <.live_component
          module={ContactMediaComponent}
          id={"crm-files-#{@contact.uuid}"}
          kind={:files}
          contact={@contact}
          phoenix_kit_current_user={@phoenix_kit_current_user}
        />
      </div>

      <div :if={@tab == "images"}>
        <.live_component
          module={ContactMediaComponent}
          id={"crm-images-#{@contact.uuid}"}
          kind={:images}
          contact={@contact}
          phoenix_kit_current_user={@phoenix_kit_current_user}
        />
      </div>

      <div :if={@tab == "comments"}>
        <.live_component
          module={PhoenixKitComments.Web.CommentsComponent}
          id={"crm-contact-comments-#{@contact.uuid}"}
          resource_type="crm_contact"
          resource_uuid={@contact.uuid}
          current_user={@phoenix_kit_current_user}
        />
      </div>
    </div>
    """
  end

  # Circular contact avatar (header) — the image if set, else initials.
  attr(:url, :string, default: nil)
  attr(:contact, :map, required: true)

  defp contact_avatar(assigns) do
    ~H"""
    <img
      :if={@url}
      src={@url}
      alt=""
      class="w-12 h-12 rounded-full object-cover ring-1 ring-base-300 shrink-0"
    />
    <div
      :if={!@url}
      class="w-12 h-12 rounded-full bg-base-300 text-base-content/60 flex items-center justify-center text-lg font-semibold shrink-0"
    >
      {avatar_initials(@contact)}
    </div>
    """
  end

  defp avatar_initials(contact) do
    contact
    |> Contact.display_name()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
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
