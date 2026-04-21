defmodule PhoenixKitCRM.Routes do
  @moduledoc """
  Route module scaffold for CRM.

  Not wired up by default — the single admin LiveView and the settings
  LiveView are registered via `admin_tabs/0` and `settings_tabs/0` in
  `PhoenixKitCRM`. Uncomment and extend below, then return this module
  from `PhoenixKitCRM.route_module/0` if you need multiple admin pages
  (list + form + detail), public routes, or custom controllers.
  """

  # def admin_locale_routes do
  #   quote do
  #     live "/admin/crm", PhoenixKitCRM.Web.CRMLive, :index, as: :crm_localized
  #   end
  # end

  # def admin_routes do
  #   quote do
  #     live "/admin/crm", PhoenixKitCRM.Web.CRMLive, :index, as: :crm
  #   end
  # end
end
