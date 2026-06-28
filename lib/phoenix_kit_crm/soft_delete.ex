defmodule PhoenixKitCRM.SoftDelete do
  @moduledoc """
  Status-column soft-delete shared by `Contacts` and `Companies`.

  Trashing stashes the record's current status in
  `metadata["trashed_from_status"]` and sets `status` to the schema's
  soft-delete sentinel; restoring reverses it (falling back to `"active"` if the
  stashed status is no longer valid). Works on any schema with a `status` string
  column and a `metadata` map column. The contexts keep the
  already-trashed/not-trashed guards and the `repo().update/1` call; only the
  changeset-building lives here.
  """

  @stash_key "trashed_from_status"

  @doc "Changeset that trashes `record`: stash the current status, set `sentinel`."
  @spec trash_changeset(struct(), String.t()) :: Ecto.Changeset.t()
  def trash_changeset(record, sentinel) do
    meta = Map.put(record.metadata || %{}, @stash_key, record.status)
    Ecto.Changeset.change(record, status: sentinel, metadata: meta)
  end

  @doc """
  Changeset that restores `record`: pop the stashed status (or `"active"` if it
  isn't one of `valid_statuses`), clearing the stash key.
  """
  @spec restore_changeset(struct(), [String.t()]) :: Ecto.Changeset.t()
  def restore_changeset(record, valid_statuses) do
    prior = Map.get(record.metadata || %{}, @stash_key)
    status = if prior in valid_statuses, do: prior, else: "active"
    meta = Map.delete(record.metadata || %{}, @stash_key)
    Ecto.Changeset.change(record, status: status, metadata: meta)
  end
end
