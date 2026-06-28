defmodule PhoenixKitCRM.RoleSettingsIntegrationTest do
  use PhoenixKitCRM.DataCase

  alias PhoenixKit.Users.Role
  alias PhoenixKitCRM.{RoleSettings, Test.Repo}

  defp create_role(name, opts \\ []) do
    Repo.insert!(%Role{name: name, is_system_role: Keyword.get(opts, :is_system_role, false)})
  end

  describe "enabled?/1" do
    test "returns false when no setting row exists for the role" do
      role = create_role("Manager")
      refute RoleSettings.enabled?(role.uuid)
    end

    test "returns true after set_enabled/2 with true" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      assert RoleSettings.enabled?(role.uuid)
    end

    test "returns false after disabling a previously enabled role" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      {:ok, _} = RoleSettings.set_enabled(role.uuid, false)
      refute RoleSettings.enabled?(role.uuid)
    end
  end

  describe "set_enabled/2" do
    test "enables a role and returns {:ok, setting}" do
      role = create_role("Manager")
      assert {:ok, setting} = RoleSettings.set_enabled(role.uuid, true)
      assert setting.enabled == true
      assert setting.role_uuid == role.uuid
    end

    test "disables a role and returns {:ok, setting}" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      assert {:ok, setting} = RoleSettings.set_enabled(role.uuid, false)
      assert setting.enabled == false
    end

    test "upserts — repeated enable calls are idempotent" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      assert {:ok, setting} = RoleSettings.set_enabled(role.uuid, true)
      assert setting.enabled == true
    end
  end

  describe "list_enabled/0" do
    test "returns empty list when no roles have CRM enabled" do
      create_role("Manager")
      assert RoleSettings.list_enabled() == []
    end

    test "includes a role that was enabled" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      uuids = RoleSettings.list_enabled() |> Enum.map(& &1.uuid)
      assert role.uuid in uuids
    end

    test "excludes a role that was disabled after being enabled" do
      role = create_role("Manager")
      {:ok, _} = RoleSettings.set_enabled(role.uuid, true)
      {:ok, _} = RoleSettings.set_enabled(role.uuid, false)
      assert RoleSettings.list_enabled() == []
    end

    test "returns only enabled roles when several roles exist" do
      enabled_role = create_role("Manager")
      disabled_role = create_role("Agent")
      {:ok, _} = RoleSettings.set_enabled(enabled_role.uuid, true)
      {:ok, _} = RoleSettings.set_enabled(disabled_role.uuid, false)

      uuids = RoleSettings.list_enabled() |> Enum.map(& &1.uuid)
      assert enabled_role.uuid in uuids
      refute disabled_role.uuid in uuids
    end
  end

  describe "list_eligible_roles/0" do
    test "excludes roles named Owner and Admin" do
      # Owner/Admin/User are seeded as system roles by core's V01 migration, so
      # they already exercise the exclusion — re-inserting them would violate the
      # unique name constraint.
      _manager = create_role("Manager")

      names = RoleSettings.list_eligible_roles() |> Enum.map(& &1.name)
      refute "Owner" in names
      refute "Admin" in names
      assert "Manager" in names
    end

    test "returns all non-excluded roles" do
      _manager = create_role("Manager")
      _agent = create_role("Agent")

      names = RoleSettings.list_eligible_roles() |> Enum.map(& &1.name)
      assert "Manager" in names
      assert "Agent" in names
    end

    test "returns empty list when only the seeded system roles exist" do
      # No non-system roles created → only Owner/Admin/User (all system) remain,
      # and list_eligible_roles rejects system roles.
      assert RoleSettings.list_eligible_roles() == []
    end
  end
end
