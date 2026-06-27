defmodule PhoenixKitCRM.Web.CompanyShowLive do
  @moduledoc """
  Show page for a CRM company. Tabs: Overview (details + contacts) and Events
  always; Files + Images when core Storage is enabled; Comments when the
  comments module is enabled. The header shows a circular logo (icon fallback).
  Companies have no interaction feed, so no Interactions tab.
  """
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext
  # Forwards the comment composer's {:leaf_changed, …} into CommentsComponent.
  use PhoenixKitComments.Embed

  alias PhoenixKit.Modules.Storage
  alias PhoenixKitCRM.{Attachments, Companies, Paths}
  alias PhoenixKitCRM.Schemas.{Company, Contact}
  alias PhoenixKitCRM.Web.{EventsComponent, MediaComponent}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    case Companies.get_company(params["uuid"]) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Company not found"))
         |> push_navigate(to: Paths.companies())}

      company ->
        storage_enabled = storage_enabled?()
        comments_enabled = comments_available?()

        tab =
          if params["tab"] in valid_tabs(storage_enabled, comments_enabled),
            do: params["tab"],
            else: "overview"

        {:noreply,
         socket
         |> assign(:company, company)
         |> assign(:tab, tab)
         |> assign(:storage_enabled, storage_enabled)
         |> assign(:comments_enabled, comments_enabled)
         |> assign(:avatar_url, Attachments.avatar_url(company))
         |> assign(:tz_offset, tz_offset(socket.assigns[:phoenix_kit_current_user]))
         |> assign(:page_title, Company.display_name(company))
         |> assign(:memberships, Companies.list_memberships(company.uuid))}
    end
  end

  @impl true
  # The media component (a LiveComponent) routes flash + logo refreshes up here.
  def handle_info({:put_flash, kind, msg}, socket), do: {:noreply, put_flash(socket, kind, msg)}

  def handle_info({:avatar_changed}, socket) do
    company = Companies.get_company(socket.assigns.company.uuid) || socket.assigns.company

    {:noreply,
     socket |> assign(:company, company) |> assign(:avatar_url, Attachments.avatar_url(company))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp tab_defs(storage_enabled?, comments_enabled?) do
    [
      {"overview", gettext("Overview"), "hero-identification"},
      {"events", gettext("Events"), "hero-clock"}
    ]
    |> maybe_concat(storage_enabled?, [
      {"files", gettext("Files"), "hero-document"},
      {"images", gettext("Images"), "hero-photo"}
    ])
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

  defp tab_path(uuid, "overview"), do: Paths.company(uuid)
  defp tab_path(uuid, tab), do: Paths.company(uuid) <> "?tab=#{tab}"

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
          <.company_logo url={@avatar_url} />
          <div>
            <.link navigate={Paths.companies()} class="text-sm text-base-content/60 hover:underline">
              ← {gettext("Companies")}
            </.link>
            <h1 class="text-2xl font-bold flex items-center gap-2 mt-1">
              {Company.display_name(@company)}
              <.status_badge status={@company.status} size={:sm} />
            </h1>
          </div>
        </div>
        <.link navigate={Paths.company_edit(@company.uuid)} class="btn btn-outline btn-sm">
          <.icon name="hero-pencil-square" class="w-4 h-4" /> {gettext("Edit")}
        </.link>
      </div>

      <div role="tablist" class="tabs tabs-bordered">
        <.link
          :for={{value, label, icon} <- tab_defs(@storage_enabled, @comments_enabled)}
          patch={tab_path(@company.uuid, value)}
          role="tab"
          class={["tab gap-1.5", @tab == value && "tab-active"]}
        >
          <.icon name={icon} class="w-4 h-4" /> {label}
        </.link>
      </div>

      <div :if={@tab == "overview"} class="flex flex-col gap-6">
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-3">
            <.field label={gettext("Website")} value={@company.website} />
            <.field label={gettext("Email")} value={@company.email} />
            <.field label={gettext("Phone")} value={@company.phone} />
            <.field label={gettext("Industry")} value={@company.industry} />
            <div class="sm:col-span-2"><.field label={gettext("Address")} value={@company.address} /></div>
            <div class="sm:col-span-2"><.field label={gettext("Notes")} value={@company.notes} /></div>
          </div>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-2">{gettext("Contacts at this company")}</h2>
          <div :if={@memberships == []} class="text-base-content/50 text-sm">
            {gettext("No contacts linked yet.")}
          </div>
          <ul :if={@memberships != []} class="menu bg-base-100 rounded-box shadow-sm w-full">
            <li :for={m <- @memberships}>
              <.link navigate={Paths.contact(m.contact_uuid)} class="flex items-center justify-between">
                <span class="font-medium">{contact_name(m.contact)}</span>
                <span class="text-xs text-base-content/60">
                  {[m.role_in_company, m.department] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")}
                </span>
              </.link>
            </li>
          </ul>
        </div>
      </div>

      <div :if={@tab == "events"}>
        <.live_component
          module={EventsComponent}
          id={"crm-company-events-#{@company.uuid}"}
          resource_type="crm_company"
          resource_uuid={@company.uuid}
          tz_offset={@tz_offset}
        />
      </div>

      <div :if={@tab == "files"}>
        <.live_component
          module={MediaComponent}
          id={"crm-company-files-#{@company.uuid}"}
          kind={:files}
          resource_type={:company}
          resource={@company}
          phoenix_kit_current_user={@phoenix_kit_current_user}
        />
      </div>

      <div :if={@tab == "images"}>
        <.live_component
          module={MediaComponent}
          id={"crm-company-images-#{@company.uuid}"}
          kind={:images}
          resource_type={:company}
          resource={@company}
          phoenix_kit_current_user={@phoenix_kit_current_user}
        />
      </div>

      <div :if={@tab == "comments"}>
        <.live_component
          module={PhoenixKitComments.Web.CommentsComponent}
          id={"crm-company-comments-#{@company.uuid}"}
          resource_type="crm_company"
          resource_uuid={@company.uuid}
          current_user={@phoenix_kit_current_user}
        />
      </div>
    </div>
    """
  end

  # Circular company logo (header) — the image if set, else a building icon.
  attr(:url, :string, default: nil)

  defp company_logo(assigns) do
    ~H"""
    <img
      :if={@url}
      src={@url}
      alt=""
      class="w-12 h-12 rounded-full object-cover ring-1 ring-base-300 shrink-0"
    />
    <div
      :if={!@url}
      class="w-12 h-12 rounded-full bg-base-300 text-base-content/60 flex items-center justify-center shrink-0"
    >
      <.icon name="hero-building-office-2" class="w-6 h-6" />
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

  defp contact_name(%Contact{} = c), do: Contact.display_name(c)
  defp contact_name(_), do: gettext("Unknown")

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
