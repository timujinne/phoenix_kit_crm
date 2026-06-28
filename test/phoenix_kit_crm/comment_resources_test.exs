defmodule PhoenixKitCRM.CommentResourcesTest do
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.{Companies, Contacts}

  describe "resolve_comment_resources/1" do
    test "maps a contact uuid to its display name + raw back-link path" do
      {:ok, c} = Contacts.create_contact(%{"name" => "Ada Lovelace"})

      assert %{title: "Ada Lovelace", path: path} =
               PhoenixKitCRM.resolve_comment_resources([c.uuid])[c.uuid]

      assert path =~ c.uuid
    end

    test "maps a company uuid to its display name + raw back-link path" do
      {:ok, co} = Companies.create_company(%{"name" => "Acme Corp"})

      assert %{title: "Acme Corp", path: path} =
               PhoenixKitCRM.resolve_comment_resources([co.uuid])[co.uuid]

      assert path =~ co.uuid
    end

    test "returns an empty map for unknown uuids" do
      assert PhoenixKitCRM.resolve_comment_resources([Ecto.UUID.generate()]) == %{}
    end
  end
end
