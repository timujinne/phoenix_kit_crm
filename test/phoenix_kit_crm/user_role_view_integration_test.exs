defmodule PhoenixKitCRM.UserRoleViewIntegrationTest do
  use PhoenixKitCRM.DataCase

  alias PhoenixKit.Users.Auth.User
  alias PhoenixKitCRM.{ColumnConfig, Test.Repo, UserRoleView}

  defp create_user do
    Repo.insert!(%User{
      email: "crm_test_#{System.unique_integer([:positive])}@example.com",
      hashed_password: "fake_hash_not_used_in_tests",
      is_active: true
    })
  end

  describe "get_view_config/2" do
    test "returns default empty map when no row exists for companies scope" do
      user = create_user()
      assert UserRoleView.get_view_config(user.uuid, :companies) == %{}
    end

    test "returns default empty map when no row exists for role scope" do
      user = create_user()
      assert UserRoleView.get_view_config(user.uuid, {:role, "any-uuid"}) == %{}
    end

    test "returns stored config after a successful put_view_config" do
      user = create_user()
      config = %{"columns" => ["name", "tax_id"]}
      {:ok, _} = UserRoleView.put_view_config(user.uuid, :companies, config)
      assert UserRoleView.get_view_config(user.uuid, :companies) == config
    end

    test "companies and role scopes are stored independently" do
      user = create_user()
      {:ok, _} = UserRoleView.put_view_config(user.uuid, :companies, %{"columns" => ["name"]})
      role_config = UserRoleView.get_view_config(user.uuid, {:role, "some-uuid"})
      assert role_config == %{}
    end
  end

  describe "put_view_config/3 round-trip" do
    test "upserts — second write for same scope overwrites first" do
      user = create_user()
      {:ok, _} = UserRoleView.put_view_config(user.uuid, :companies, %{"columns" => ["name"]})

      {:ok, _} =
        UserRoleView.put_view_config(user.uuid, :companies, %{"columns" => ["tax_id", "name"]})

      assert UserRoleView.get_view_config(user.uuid, :companies) == %{
               "columns" => ["tax_id", "name"]
             }
    end

    test "different users have independent configs for the same scope" do
      user_a = create_user()
      user_b = create_user()
      {:ok, _} = UserRoleView.put_view_config(user_a.uuid, :companies, %{"columns" => ["name"]})
      {:ok, _} = UserRoleView.put_view_config(user_b.uuid, :companies, %{"columns" => ["tax_id"]})
      assert UserRoleView.get_view_config(user_a.uuid, :companies) == %{"columns" => ["name"]}
      assert UserRoleView.get_view_config(user_b.uuid, :companies) == %{"columns" => ["tax_id"]}
    end
  end

  describe "ColumnConfig.update_columns/3 — empty list resets to defaults" do
    test "empty list stores empty columns; get_columns then falls back to defaults" do
      user = create_user()
      {:ok, _} = ColumnConfig.update_columns(user.uuid, :companies, [])

      assert ColumnConfig.get_columns(user.uuid, :companies) ==
               ColumnConfig.default_columns(:companies)
    end
  end

  describe "ColumnConfig.update_columns/3 — valid list persists" do
    test "persists a valid subset in the given order for companies scope" do
      user = create_user()
      {:ok, _} = ColumnConfig.update_columns(user.uuid, :companies, ["name", "country"])
      assert ColumnConfig.get_columns(user.uuid, :companies) == ["name", "country"]
    end

    test "persists a valid subset for role scope" do
      user = create_user()
      scope = {:role, "bbbbbbbb-cccc-dddd-eeee-ffffffffffff"}
      {:ok, _} = ColumnConfig.update_columns(user.uuid, scope, ["email", "status"])
      assert ColumnConfig.get_columns(user.uuid, scope) == ["email", "status"]
    end

    test "role scope and companies scope are stored independently" do
      user = create_user()
      role_scope = {:role, "cccccccc-dddd-eeee-ffff-000000000000"}
      {:ok, _} = ColumnConfig.update_columns(user.uuid, :companies, ["name", "tax_id"])
      {:ok, _} = ColumnConfig.update_columns(user.uuid, role_scope, ["email", "full_name"])
      assert ColumnConfig.get_columns(user.uuid, :companies) == ["name", "tax_id"]
      assert ColumnConfig.get_columns(user.uuid, role_scope) == ["email", "full_name"]
    end
  end

  describe "ColumnConfig.update_columns/3 — cross-scope columns rejected" do
    test "role column ids are stripped when scope is companies" do
      user = create_user()
      {:ok, _} = ColumnConfig.update_columns(user.uuid, :companies, ["email", "username"])
      # validate_columns strips invalid ids → empty → falls back to defaults
      assert ColumnConfig.get_columns(user.uuid, :companies) ==
               ColumnConfig.default_columns(:companies)
    end

    test "companies column ids are stripped when scope is role" do
      user = create_user()
      scope = {:role, "dddddddd-eeee-ffff-0000-111111111111"}
      {:ok, _} = ColumnConfig.update_columns(user.uuid, scope, ["name", "tax_id"])
      assert ColumnConfig.get_columns(user.uuid, scope) == ColumnConfig.default_columns(scope)
    end
  end
end
