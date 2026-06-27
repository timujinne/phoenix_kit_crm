defmodule PhoenixKitCRM.SoftDeleteTest do
  use ExUnit.Case, async: true

  alias PhoenixKitCRM.Schemas.Contact
  alias PhoenixKitCRM.SoftDelete

  describe "trash_changeset/2" do
    test "stashes the current status under trashed_from_status and sets the sentinel" do
      cs =
        SoftDelete.trash_changeset(%Contact{status: "active", metadata: %{"x" => 1}}, "trashed")

      assert cs.changes.status == "trashed"
      assert cs.changes.metadata == %{"x" => 1, "trashed_from_status" => "active"}
    end

    test "tolerates nil metadata" do
      cs = SoftDelete.trash_changeset(%Contact{status: "inactive", metadata: nil}, "trashed")

      assert cs.changes.metadata == %{"trashed_from_status" => "inactive"}
    end
  end

  describe "restore_changeset/2" do
    test "restores the stashed status and clears the stash key" do
      record = %Contact{
        status: "trashed",
        metadata: %{"trashed_from_status" => "inactive", "y" => 2}
      }

      cs = SoftDelete.restore_changeset(record, ["active", "inactive"])

      assert cs.changes.status == "inactive"
      assert cs.changes.metadata == %{"y" => 2}
    end

    test "falls back to active when the stashed status is no longer valid" do
      record = %Contact{status: "trashed", metadata: %{"trashed_from_status" => "archived"}}

      cs = SoftDelete.restore_changeset(record, ["active", "inactive"])

      assert cs.changes.status == "active"
    end

    test "falls back to active when nothing was stashed" do
      cs = SoftDelete.restore_changeset(%Contact{status: "trashed", metadata: %{}}, ["active"])

      assert cs.changes.status == "active"
    end
  end
end
