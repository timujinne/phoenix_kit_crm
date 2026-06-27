defmodule PhoenixKitCRM.Web.CompanyShowLive do
  @moduledoc "Show page for a CRM company (details + contacts at this company)."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Companies, Paths}
  alias PhoenixKitCRM.Schemas.{Company, Contact}

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
        {:noreply,
         socket
         |> assign(:company, company)
         |> assign(:page_title, Company.display_name(company))
         |> assign(:memberships, Companies.list_memberships(company.uuid))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-4xl px-4 py-6 gap-6">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div>
          <.link navigate={Paths.companies()} class="text-sm text-base-content/60 hover:underline">
            ← {gettext("Companies")}
          </.link>
          <h1 class="text-2xl font-bold flex items-center gap-2 mt-1">
            <.icon name="hero-building-office-2" class="w-6 h-6" /> {Company.display_name(@company)}
            <.status_badge status={@company.status} size={:sm} />
          </h1>
        </div>
        <.link navigate={Paths.company_edit(@company.uuid)} class="btn btn-outline btn-sm">
          <.icon name="hero-pencil-square" class="w-4 h-4" /> {gettext("Edit")}
        </.link>
      </div>

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
end
