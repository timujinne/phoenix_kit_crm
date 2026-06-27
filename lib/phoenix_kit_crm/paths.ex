defmodule PhoenixKitCRM.Paths do
  @moduledoc """
  Centralized path helpers for the CRM module. All paths go through
  `PhoenixKit.Utils.Routes.path/1` for prefix/locale handling.
  """

  alias PhoenixKit.Utils.Routes

  @base "/admin/crm"
  @settings_base "/admin/settings/crm"

  def index, do: Routes.path(@base)
  def organizations, do: Routes.path("#{@base}/organizations")
  def role(""), do: raise(ArgumentError, "role_uuid must not be empty")
  def role(role_uuid) when is_binary(role_uuid), do: Routes.path("#{@base}/role/#{role_uuid}")
  def settings, do: Routes.path(@settings_base)

  # ── Contacts ────────────────────────────────────────────────────────
  def contacts, do: Routes.path("#{@base}/contacts")
  def contact_new, do: Routes.path("#{@base}/contacts/new")
  def contact(uuid) when is_binary(uuid), do: Routes.path("#{@base}/contacts/#{uuid}")
  def contact_edit(uuid) when is_binary(uuid), do: Routes.path("#{@base}/contacts/#{uuid}/edit")

  # ── Companies ───────────────────────────────────────────────────────
  def companies, do: Routes.path("#{@base}/companies")
  def company_new, do: Routes.path("#{@base}/companies/new")
  def company(uuid) when is_binary(uuid), do: Routes.path("#{@base}/companies/#{uuid}")
  def company_edit(uuid) when is_binary(uuid), do: Routes.path("#{@base}/companies/#{uuid}/edit")

  def user_view(""), do: raise(ArgumentError, "user_uuid must not be empty")

  def user_view(user_uuid) when is_binary(user_uuid),
    do: Routes.path("/admin/users/view/#{user_uuid}")
end
