defmodule PhoenixKitCRM.Web.CellFormatTest do
  use ExUnit.Case, async: true

  alias PhoenixKitCRM.Web.CellFormat

  describe "render_custom_cell/3" do
    test "looks up metadata in the column_meta map and formats by field_type" do
      meta = %{
        "custom_phone" => %{
          type: :custom_field,
          field_key: "phone",
          field_type: "string"
        }
      }

      user = %{custom_fields: %{"phone" => "+1-555-0100"}}

      assert CellFormat.render_custom_cell(meta, "custom_phone", user) == "+1-555-0100"
    end

    test "returns em-dash when the column id is unknown in the meta map" do
      user = %{custom_fields: %{"phone" => "x"}}
      assert CellFormat.render_custom_cell(%{}, "custom_phone", user) == "—"
    end

    test "returns em-dash when the user has no value for the field" do
      meta = %{
        "custom_phone" => %{type: :custom_field, field_key: "phone", field_type: "string"}
      }

      assert CellFormat.render_custom_cell(meta, "custom_phone", %{custom_fields: %{}}) == "—"
    end

    test "tolerates nil custom_fields on the user" do
      meta = %{
        "custom_phone" => %{type: :custom_field, field_key: "phone", field_type: "string"}
      }

      assert CellFormat.render_custom_cell(meta, "custom_phone", %{custom_fields: nil}) == "—"
    end

    test "uses field_type to format booleans" do
      meta = %{
        "custom_active" => %{type: :custom_field, field_key: "active", field_type: "boolean"}
      }

      user = %{custom_fields: %{"active" => true}}
      assert CellFormat.render_custom_cell(meta, "custom_active", user) == "Yes"
    end
  end

  describe "format_custom_value/2 — empty values" do
    test "nil renders em-dash" do
      assert CellFormat.format_custom_value(nil, "string") == "—"
      assert CellFormat.format_custom_value(nil, "boolean") == "—"
      assert CellFormat.format_custom_value(nil, nil) == "—"
    end

    test "empty string renders em-dash" do
      assert CellFormat.format_custom_value("", "string") == "—"
    end
  end

  describe "format_custom_value/2 — boolean" do
    test "true → Yes, false → No, in both atom and string form" do
      assert CellFormat.format_custom_value(true, "boolean") == "Yes"
      assert CellFormat.format_custom_value(false, "boolean") == "No"
      assert CellFormat.format_custom_value("true", "boolean") == "Yes"
      assert CellFormat.format_custom_value("false", "boolean") == "No"
    end
  end

  describe "format_custom_value/2 — checkbox" do
    test "boolean-like values render as Yes/No" do
      assert CellFormat.format_custom_value(true, "checkbox") == "Yes"
      assert CellFormat.format_custom_value(false, "checkbox") == "No"
    end

    test "list values are joined with comma" do
      assert CellFormat.format_custom_value(["a", "b", "c"], "checkbox") == "a, b, c"
    end

    test "empty list joins to empty string (caller's choice)" do
      assert CellFormat.format_custom_value([], "checkbox") == ""
    end
  end

  describe "format_custom_value/2 — dates" do
    test "Date struct formats as ISO string regardless of declared type" do
      d = ~D[2026-05-05]
      assert CellFormat.format_custom_value(d, "date") == "2026-05-05"
      assert CellFormat.format_custom_value(d, "string") == "2026-05-05"
    end

    test "DateTime struct formats via DateTime.to_string/1" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-05-05T10:30:00Z")
      assert CellFormat.format_custom_value(dt, "datetime") =~ "2026-05-05"
    end

    test "NaiveDateTime struct formats via NaiveDateTime.to_string/1" do
      ndt = ~N[2026-05-05 10:30:00]
      assert CellFormat.format_custom_value(ndt, "datetime") == "2026-05-05 10:30:00"
    end
  end

  describe "format_custom_value/2 — fallthrough" do
    test "binary value passes through as-is" do
      assert CellFormat.format_custom_value("hello", "string") == "hello"
      assert CellFormat.format_custom_value("42", "select") == "42"
    end

    test "non-binary scalar values are stringified" do
      assert CellFormat.format_custom_value(42, "number") == "42"
      assert CellFormat.format_custom_value(3.14, "number") == "3.14"
      assert CellFormat.format_custom_value(:something, nil) == "something"
    end
  end
end
