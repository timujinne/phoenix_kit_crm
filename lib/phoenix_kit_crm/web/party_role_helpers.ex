defmodule PhoenixKitCRM.Web.PartyRoleHelpers do
  @moduledoc """
  Shared helpers for the commercial party-role UI (badges on the list pages,
  the Roles checkbox section on the company/contact forms).
  """

  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.PartyRoles
  alias PhoenixKitCRM.Schemas.PartyRole

  @doc "Human label for a role value."
  def role_label("supplier"), do: gettext("Supplier")
  def role_label("client"), do: gettext("Client")
  def role_label("partner"), do: gettext("Partner")
  def role_label(role), do: role

  @doc "daisyUI badge modifier for a role value."
  def role_badge_class("supplier"), do: "badge-info"
  def role_badge_class("client"), do: "badge-success"
  def role_badge_class(_), do: "badge-ghost"

  @doc """
  Reads the checked `roles[]` checkboxes from a raw form event payload,
  keeping only known roles (a forged payload can't invent one).
  """
  def selected_roles(payload) when is_map(payload) do
    payload
    |> Map.get("roles", [])
    |> List.wrap()
    |> Enum.filter(&(&1 in PartyRole.roles()))
  end

  def selected_roles(_), do: []

  @doc """
  Active role values currently held by a company/contact — the initial
  checkbox state for the edit forms.
  """
  def active_role_values(roleable) do
    roleable
    |> PartyRoles.list_roles()
    |> Enum.filter(& &1.is_active)
    |> Enum.map(& &1.role)
  end

  @doc """
  Reconciles checkbox state with stored roles: grants what's newly checked,
  revokes active roles that were unchecked. Both operations are idempotent,
  so re-saving an unchanged form is a no-op.
  """
  def sync_roles(roleable, selected) when is_list(selected) do
    Enum.each(PartyRole.roles(), fn role ->
      cond do
        role in selected -> PartyRoles.grant_role(roleable, role)
        PartyRoles.has_role?(roleable, role) -> PartyRoles.revoke_role(roleable, role)
        true -> :ok
      end
    end)
  end
end
