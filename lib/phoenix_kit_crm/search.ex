defmodule PhoenixKitCRM.Search do
  @moduledoc """
  Shared LIKE/ILIKE search-term escaping for contexts that filter by a
  free-text search box (`Contacts`, `Companies`, `PartyRoles`, `Lists`).
  """

  @doc """
  Wraps a trimmed search term in `%…%`, escaping the LIKE/ILIKE
  metacharacters (`\\`, `%`, `_`) so a literal `%` or `_` in the term
  matches itself rather than acting as a wildcard. Postgres ILIKE uses
  backslash as the default escape character.
  """
  def like_pattern(term) do
    escaped =
      term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end
end
