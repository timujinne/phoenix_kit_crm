defmodule PhoenixKitCRM.Web.CompanyFormLive do
  @moduledoc "New / edit form for a CRM company."
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  require Logger

  alias PhoenixKitCRM.{Activity, Companies, Paths}
  alias PhoenixKitCRM.Schemas.Company

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :new ->
        company = %Company{}
        {:noreply, assign_form(socket, company, gettext("New company"))}

      :edit ->
        case Companies.get_company(params["uuid"]) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Company not found"))
             |> push_navigate(to: Paths.companies())}

          company ->
            {:noreply, assign_form(socket, company, gettext("Edit company"))}
        end
    end
  end

  defp assign_form(socket, company, title) do
    socket
    |> assign(:company, company)
    |> assign(:page_title, title)
    |> assign(:form, to_form(Companies.change_company(company)))
  end

  @impl true
  def handle_event("validate", %{"company" => params}, socket) do
    changeset =
      socket.assigns.company
      |> Companies.change_company(safe_map(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"company" => params}, socket) do
    # Normalize once so a forged non-map payload can't raise here OR in the rescue.
    params = safe_map(params)
    save(socket, socket.assigns.live_action, params)
  rescue
    e ->
      Logger.error(
        "[CRM] company save crashed (company_uuid=#{inspect(socket.assigns.company.uuid)}): " <>
          Exception.format(:error, e, __STACKTRACE__)
      )

      # Rebuild @form from the submitted params so the rerender shows what the
      # user typed (not stale values from the last phx-change).
      changeset =
        socket.assigns.company |> Companies.change_company(params) |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> put_flash(
         :error,
         gettext(
           "Something went wrong saving this company. Your input was kept — please try again."
         )
       )
       |> assign(:form, to_form(changeset))}
  end

  # Ignore unexpected/forged events (and malformed validate/save payloads).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save(socket, :new, params) do
    case Companies.create_company(params) do
      {:ok, company} ->
        Activity.log(
          "crm.company_created",
          Activity.actor_opts(socket) ++
            [resource_type: "crm_company", resource_uuid: company.uuid]
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Company created"))
         |> push_navigate(to: Paths.company(company.uuid))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case Companies.update_company(socket.assigns.company, params) do
      {:ok, company} ->
        Activity.log(
          "crm.company_updated",
          Activity.actor_opts(socket) ++
            [resource_type: "crm_company", resource_uuid: company.uuid]
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Company updated"))
         |> push_navigate(to: Paths.company(company.uuid))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container flex-col mx-auto px-4 py-6 max-w-2xl">
      <header class="mb-6">
        <.link navigate={Paths.companies()} class="btn btn-ghost btn-sm mb-3">
          <.icon name="hero-arrow-left" class="w-4 h-4" /> {gettext("Companies")}
        </.link>
        <h1 class="text-2xl sm:text-3xl font-bold">{@page_title}</h1>
      </header>

      <.form for={@form} phx-change="validate" phx-submit="save">
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body flex flex-col gap-5">
            <.input field={@form[:name]} label={gettext("Name")} required />
            <.select field={@form[:status]} label={gettext("Status")} options={status_options()} />
            <.input field={@form[:website]} label={gettext("Website")} />
            <.input field={@form[:email]} type="email" label={gettext("Email")} />
            <.input field={@form[:phone]} label={gettext("Phone")} />
            <.input field={@form[:industry]} label={gettext("Industry")} />
            <.textarea field={@form[:address]} label={gettext("Address")} />
            <.textarea field={@form[:notes]} label={gettext("Notes")} />

            <div class="divider my-0"></div>
            <div class="flex justify-end gap-2">
              <.link navigate={Paths.companies()} class="btn btn-ghost">{gettext("Cancel")}</.link>
              <.button type="submit" class="btn-primary" phx-disable-with={gettext("Saving…")}>
                {gettext("Save")}
              </.button>
            </div>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  defp status_options, do: Enum.map(Company.statuses(), &{status_label(&1), &1})

  defp status_label("active"), do: gettext("Active")
  defp status_label("inactive"), do: gettext("Inactive")
  defp status_label(s), do: s

  defp safe_map(p) when is_map(p), do: p
  defp safe_map(_), do: %{}
end
