defmodule PhoenixKitCRM do
  @moduledoc """
  CRM module for PhoenixKit.

  Implements the `PhoenixKit.Module` behaviour — discovered automatically at
  startup via the `@phoenix_kit_module` attribute. No explicit config is needed
  in the host application beyond adding this package to `deps`.
  """

  use PhoenixKit.Module

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKit.Settings

  @enabled_setting "crm_enabled"

  @impl PhoenixKit.Module
  def module_key, do: "crm"

  @impl PhoenixKit.Module
  def module_name, do: "CRM"

  @impl PhoenixKit.Module
  def enabled? do
    Settings.get_boolean_setting(@enabled_setting, false)
  rescue
    _ -> false
  end

  @impl PhoenixKit.Module
  def enable_system do
    Settings.update_boolean_setting_with_module(@enabled_setting, true, module_key())
  end

  @impl PhoenixKit.Module
  def disable_system do
    Settings.update_boolean_setting_with_module(@enabled_setting, false, module_key())
  end

  @impl PhoenixKit.Module
  def version, do: "0.1.0"

  @impl PhoenixKit.Module
  def permission_metadata do
    %{
      key: module_key(),
      label: "CRM",
      icon: "hero-users",
      description: "Customer relationship management module"
    }
  end

  @impl PhoenixKit.Module
  def admin_tabs do
    [
      %Tab{
        id: :admin_crm,
        label: "CRM",
        icon: "hero-users",
        path: "crm",
        priority: 650,
        level: :admin,
        permission: module_key(),
        match: :prefix,
        group: :admin_modules,
        subtab_display: :when_active,
        highlight_with_subtabs: false,
        live_view: {PhoenixKitCRM.Web.CRMLive, :index}
      },
      %Tab{
        id: :admin_crm_overview,
        label: "Overview",
        icon: "hero-users",
        path: "crm",
        priority: 651,
        level: :admin,
        permission: module_key(),
        match: :exact,
        parent: :admin_crm,
        live_view: {PhoenixKitCRM.Web.CRMLive, :index}
      }
    ]
  end

  @impl PhoenixKit.Module
  def settings_tabs do
    [
      %Tab{
        id: :admin_settings_crm,
        label: "CRM",
        icon: "hero-users",
        path: "settings/crm",
        priority: 650,
        level: :admin,
        permission: module_key(),
        match: :exact,
        group: :admin_settings,
        live_view: {PhoenixKitCRM.Web.SettingsLive, :index}
      }
    ]
  end

  @impl PhoenixKit.Module
  def css_sources, do: [:phoenix_kit_crm]
end
