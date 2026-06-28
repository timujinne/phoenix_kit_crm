defmodule PhoenixKitCRM.ActivityLabelsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitCRM.ActivityLabels

  describe "describe/2" do
    test "maps a known action to its icon + label" do
      assert {"hero-user-plus", "Contact created"} =
               ActivityLabels.describe("crm.contact_created")

      assert {"hero-trash", "Interaction deleted"} =
               ActivityLabels.describe("crm.interaction_deleted")
    end

    test "falls back to a humanized label for an unknown action" do
      assert {"hero-bolt", "Frobnicated widget"} =
               ActivityLabels.describe("crm.frobnicated_widget")
    end
  end

  describe "detail/2" do
    test "returns the interaction subject when present" do
      assert ActivityLabels.detail("crm.interaction_logged", %{"subject" => "Re: invoice"}) ==
               "Re: invoice"
    end

    test "falls back to the gettext'd interaction type when there's no subject" do
      assert ActivityLabels.detail("crm.interaction_updated", %{"interaction_type" => "call"}) ==
               "Call"
    end

    test "ignores an empty subject" do
      assert ActivityLabels.detail("crm.interaction_logged", %{"subject" => ""}) == nil
    end

    test "pluralizes file + image counts" do
      assert ActivityLabels.detail("crm.contact_file_added", %{"count" => 1}) == "1 file"
      assert ActivityLabels.detail("crm.contact_file_added", %{"count" => 3}) == "3 files"
      assert ActivityLabels.detail("crm.company_image_added", %{"count" => 2}) == "2 images"
    end

    test "returns nil when there is nothing to show" do
      assert ActivityLabels.detail("crm.contact_created", %{}) == nil
    end
  end
end
