defmodule PhoenixKitCRM.Web.CellFormat do
  @moduledoc """
  Shared formatters for CRM table/card cells.

  Currently covers user-defined custom field values (`format_custom_value/2`)
  and the `custom_*` cell renderer used by `RoleView` and `OrganizationsView`.
  """

  use Gettext, backend: PhoenixKitWeb.Gettext

  @doc """
  Renders a `"custom_<key>"` column for the given user, given a resolved
  `column_meta` map (`%{column_id => metadata}` — see
  `PhoenixKitCRM.ColumnConfig.column_metadata_map/1`). Returns `"—"` if the
  column is unknown or the value is missing.

  Callers should compute `column_meta` once per render cycle and pass it
  through, rather than calling `ColumnConfig.get_column_metadata/2` per cell.
  """
  @spec render_custom_cell(%{optional(String.t()) => map()}, String.t(), map()) :: String.t()
  def render_custom_cell(column_meta, "custom_" <> _ = column_id, user)
      when is_map(column_meta) do
    case Map.get(column_meta, column_id) do
      %{type: :custom_field, field_key: key, field_type: type} ->
        format_custom_value(Map.get(user.custom_fields || %{}, key), type)

      _ ->
        "—"
    end
  end

  @doc "Formats a custom field value according to its declared type."
  @spec format_custom_value(any(), String.t() | nil) :: String.t()
  def format_custom_value(nil, _), do: "—"
  def format_custom_value("", _), do: "—"
  def format_custom_value(true, "boolean"), do: gettext("Yes")
  def format_custom_value(false, "boolean"), do: gettext("No")
  def format_custom_value("true", "boolean"), do: gettext("Yes")
  def format_custom_value("false", "boolean"), do: gettext("No")
  def format_custom_value(true, "checkbox"), do: gettext("Yes")
  def format_custom_value(false, "checkbox"), do: gettext("No")
  def format_custom_value(list, "checkbox") when is_list(list), do: Enum.join(list, ", ")
  def format_custom_value(%Date{} = d, _), do: Date.to_string(d)
  def format_custom_value(%DateTime{} = dt, _), do: DateTime.to_string(dt)
  def format_custom_value(%NaiveDateTime{} = dt, _), do: NaiveDateTime.to_string(dt)
  def format_custom_value(value, _) when is_binary(value), do: value
  def format_custom_value(value, _), do: to_string(value)
end
