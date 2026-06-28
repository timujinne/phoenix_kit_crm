defmodule PhoenixKitCRM.PathsTest do
  # DataCase (sandbox connection + :integration tag): Paths.* go through
  # Routes.path, which reads the languages_enabled setting from the DB, so these
  # need a connection.
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.Paths

  test "builds contact paths off the CRM base" do
    assert Paths.contacts() =~ "/admin/crm/contacts"
    assert Paths.contact("abc") =~ "/admin/crm/contacts/abc"
    assert Paths.contact_edit("abc") =~ "/admin/crm/contacts/abc/edit"
  end

  test "builds company paths off the CRM base" do
    assert Paths.companies() =~ "/admin/crm/companies"
    assert Paths.company("xyz") =~ "/admin/crm/companies/xyz"
  end

  test "raw paths (for the comments back-link) include the uuid" do
    assert Paths.contact_raw("abc") =~ "/admin/crm/contacts/abc"
    assert Paths.company_raw("xyz") =~ "/admin/crm/companies/xyz"
  end

  test "role/1 rejects an empty uuid" do
    assert_raise ArgumentError, fn -> Paths.role("") end
  end
end
