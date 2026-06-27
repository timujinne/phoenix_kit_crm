defmodule PhoenixKitCRM.ActivityLabels do
  @moduledoc """
  Maps CRM activity action strings (e.g. `"crm.interaction_logged"`) to a
  `{heroicon, human_label}` pair plus an optional secondary `detail/2` line, for
  the contact/company **Events** tab. Domain labels go through
  `PhoenixKitCRM.Gettext`. Unknown actions fall back to a humanized form of the
  action string, so a newly-added action still renders without a change here.

  Icon names are literals (Tailwind scans them); render dynamically via `<.icon>`.
  """

  use Gettext, backend: PhoenixKitCRM.Gettext

  @doc "Returns `{icon_name, label}` for an action string + its metadata."
  @spec describe(String.t(), map()) :: {String.t(), String.t()}
  def describe(action, metadata \\ %{})

  def describe("crm.contact_created", _), do: {"hero-user-plus", gettext("Contact created")}

  def describe("crm.contact_updated", _), do: {"hero-pencil-square", gettext("Contact updated")}

  def describe("crm.contact_trashed", _), do: {"hero-trash", gettext("Moved to trash")}

  def describe("crm.contact_deleted", _), do: {"hero-x-circle", gettext("Permanently deleted")}

  def describe("crm.company_created", _),
    do: {"hero-building-office-2", gettext("Company created")}

  def describe("crm.company_updated", _), do: {"hero-pencil-square", gettext("Company updated")}

  def describe("crm.company_trashed", _), do: {"hero-trash", gettext("Moved to trash")}

  def describe("crm.company_deleted", _), do: {"hero-x-circle", gettext("Permanently deleted")}

  def describe("crm.interaction_logged", _),
    do: {"hero-chat-bubble-left-ellipsis", gettext("Interaction logged")}

  def describe("crm.contact_file_added", _), do: {"hero-document-plus", gettext("File added")}

  def describe("crm.contact_file_removed", _),
    do: {"hero-document-minus", gettext("File removed")}

  def describe("crm.contact_image_added", _), do: {"hero-photo", gettext("Image added")}

  def describe("crm.contact_image_removed", _), do: {"hero-photo", gettext("Image removed")}

  def describe("crm.contact_avatar_set", _),
    do: {"hero-user-circle", gettext("Profile photo updated")}

  def describe("crm.contact_avatar_removed", _),
    do: {"hero-user-circle", gettext("Profile photo removed")}

  def describe("crm.company_file_added", _), do: {"hero-document-plus", gettext("File added")}

  def describe("crm.company_file_removed", _),
    do: {"hero-document-minus", gettext("File removed")}

  def describe("crm.company_image_added", _), do: {"hero-photo", gettext("Image added")}

  def describe("crm.company_image_removed", _), do: {"hero-photo", gettext("Image removed")}

  def describe("crm.company_avatar_set", _), do: {"hero-photo", gettext("Logo updated")}

  def describe("crm.company_avatar_removed", _), do: {"hero-photo", gettext("Logo removed")}

  def describe(action, _), do: {"hero-bolt", humanize(action)}

  @doc "Optional secondary line for an entry (e.g. an interaction's subject)."
  @spec detail(String.t(), map()) :: String.t() | nil
  def detail("crm.interaction_logged", %{"subject" => s}) when is_binary(s) and s != "", do: s

  def detail("crm.interaction_logged", %{"interaction_type" => t})
      when is_binary(t) and t != "",
      do: type_label(t)

  def detail("crm.contact_file_added", %{"count" => n}) when is_integer(n) and n > 0,
    do: ngettext("%{count} file", "%{count} files", n)

  def detail("crm.contact_image_added", %{"count" => n}) when is_integer(n) and n > 0,
    do: ngettext("%{count} image", "%{count} images", n)

  def detail(action, %{"count" => n})
      when action in ["crm.company_file_added", "crm.company_image_added"] and is_integer(n) and
             n > 0 do
    case action do
      "crm.company_file_added" -> ngettext("%{count} file", "%{count} files", n)
      _ -> ngettext("%{count} image", "%{count} images", n)
    end
  end

  def detail(_action, _metadata), do: nil

  # "note" -> "Note"; humble fallback for the interaction type.
  defp type_label(t), do: t |> String.replace("_", " ") |> String.capitalize()

  # "crm.interaction_logged" -> "Interaction logged"
  defp humanize(action) do
    action
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
