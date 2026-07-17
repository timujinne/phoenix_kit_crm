defmodule PhoenixKitCRM.Lists.ImportTest do
  use PhoenixKitCRM.DataCase, async: true

  alias PhoenixKitCRM.Lists
  alias PhoenixKitCRM.Lists.{Import, ImportReport}
  alias PhoenixKitCRM.Schemas.{Contact, ListMember}

  defp list_fixture(attrs \\ %{}) do
    {:ok, list} =
      Lists.create_list(
        Map.merge(%{"name" => "Newsletter", "slug" => "newsletter-#{unique_int()}"}, attrs)
      )

    list
  end

  defp unique_int, do: System.unique_integer([:positive])

  describe "import_csv/3" do
    test "creates a contact + membership per valid row, maps case-insensitive headers" do
      list = list_fixture()

      csv = """
      Email,Name,Company,Locale
      alice@example.com,Alice Wonder,Acme,en
      bob@example.com,Bob Builder,,de
      """

      report = Import.import_csv(csv, list)

      assert report.created == 2
      assert report.added == 2

      assert report.skipped == %{
               already_in_list: 0,
               unsubscribed: 0,
               no_email: 0,
               invalid_email: 0,
               duplicate_in_file: 0
             }

      assert length(report.rows) == 2
      assert Enum.all?(report.rows, &(&1.outcome == :imported))

      members = Lists.list_members(list)
      assert length(members) == 2

      alice = Enum.find(members, &(&1.email == "alice@example.com"))
      assert alice.contact.name == "Alice Wonder"
      assert alice.contact.locale == "en"
      assert alice.contact.metadata["import_company"] == "Acme"
      assert alice.contact.metadata["source"] == "import"
      assert alice.source == "import"

      bob = Enum.find(members, &(&1.email == "bob@example.com"))
      assert bob.contact.locale == "de"
      refute Map.has_key?(bob.contact.metadata, "import_company")
    end

    test "falls back to email as name when the name column is blank" do
      list = list_fixture()
      csv = "email,name\nnoname@example.com,\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1

      [member] = Lists.list_members(list)
      assert member.contact.name == "noname@example.com"
    end

    test "strips a UTF-8 BOM before parsing headers" do
      list = list_fixture()
      bom = <<0xEF, 0xBB, 0xBF>>
      csv = bom <> "email\nbom@example.com\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1
      assert [%{email: "bom@example.com", outcome: :imported}] = report.rows
    end

    test "handles CRLF line endings and quoted fields with embedded commas" do
      list = list_fixture()
      csv = "email,name\r\nquoted@example.com,\"Doe, Jane\"\r\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1

      [member] = Lists.list_members(list)
      assert member.contact.name == "Doe, Jane"
    end

    test "imports unicode email addresses" do
      list = list_fixture()
      csv = "email\nüser@münchen.example\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1
      assert [%{email: "üser@münchen.example", outcome: :imported}] = report.rows
    end

    test "skips a row with no email" do
      list = list_fixture()
      csv = "email,name\n,No Email\n"

      report = Import.import_csv(csv, list)
      assert report.created == 0
      assert report.skipped.no_email == 1
      assert [%{outcome: :skipped, reason: :no_email, email: nil}] = report.rows
    end

    test "skips a row with a malformed email" do
      list = list_fixture()
      csv = "email\nnot-an-email\n"

      report = Import.import_csv(csv, list)
      assert report.created == 0
      assert report.skipped.invalid_email == 1
    end

    test "skips the second row of a shared mailbox (same email, different names)" do
      list = list_fixture()

      csv = """
      email,name
      shared@example.com,Person One
      shared@example.com,Person Two
      """

      report = Import.import_csv(csv, list)
      assert report.created == 1
      assert report.skipped.duplicate_in_file == 1

      assert [
               %{outcome: :imported},
               %{outcome: :skipped, reason: :duplicate_in_file}
             ] = report.rows

      [member] = Lists.list_members(list)
      assert member.contact.name == "Person One"
    end

    test "drops an unrecognized locale format instead of skipping the row" do
      list = list_fixture()
      csv = "email,locale\ngoodrow@example.com,not-a-locale\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1

      [member] = Lists.list_members(list)
      refute member.contact.locale
    end

    test "unrecognized columns are ignored" do
      list = list_fixture()
      csv = "email,phone\nignored@example.com,555-1234\n"

      report = Import.import_csv(csv, list)
      assert report.created == 1
    end

    test "empty content returns an empty report" do
      list = list_fixture()
      assert Import.import_csv("", list) == %ImportReport{}
    end
  end

  describe "import_text/3" do
    test "imports one email per line, ignoring blank lines" do
      list = list_fixture()
      text = "one@example.com\n\ntwo@example.com\n   \nthree@example.com\n"

      report = Import.import_text(text, list)
      assert report.created == 3
      assert report.added == 3
    end

    test "handles CRLF and a leading BOM" do
      list = list_fixture()
      bom = <<0xEF, 0xBB, 0xBF>>
      text = bom <> "crlf1@example.com\r\ncrlf2@example.com\r\n"

      report = Import.import_text(text, list)
      assert report.created == 2
    end

    test "invalid lines are skipped as invalid_email" do
      list = list_fixture()
      text = "good@example.com\nnot an email\n"

      report = Import.import_text(text, list)
      assert report.created == 1
      assert report.skipped.invalid_email == 1
    end
  end

  describe "idempotency and unsubscribed classification" do
    test "re-importing the same file is a no-op: zero new contacts, everything skipped as already_in_list" do
      list = list_fixture()
      csv = "email,name\na@example.com,A\nb@example.com,B\n"

      first = Import.import_csv(csv, list)
      assert first.created == 2

      contact_count_before = Repo.aggregate(Contact, :count, :uuid)

      second = Import.import_csv(csv, list)
      assert second.created == 0
      assert second.added == 0
      assert second.skipped.already_in_list == 2

      assert Repo.aggregate(Contact, :count, :uuid) == contact_count_before
    end

    test "classifies a removed membership's held email slot as :unsubscribed, not :already_in_list" do
      list = list_fixture()
      csv = "email,name\nremoved@example.com,Removed Person\n"

      Import.import_csv(csv, list)
      [member] = Lists.list_members(list)
      {:ok, _} = Lists.remove_from_list(member)

      report = Import.import_csv(csv, list)
      assert report.created == 0
      assert report.skipped.unsubscribed == 1
      assert report.skipped.already_in_list == 0
    end

    # Cross-feature regression for the Lists.add_contact_to_list/3
    # reactivate-on-add fix: it must not leak into import. A removed
    # member's email slot should still block a NEW contact, the removed
    # member itself must stay untouched, and no orphan contact is created.
    test "removed member is not reactivated by an import row sharing its email" do
      list = list_fixture()
      csv = "email,name\nremoved@example.com,Removed Person\n"

      Import.import_csv(csv, list)
      [original_member] = Lists.list_members(list)
      {:ok, removed_member} = Lists.remove_from_list(original_member)
      assert removed_member.status == "removed"

      contact_count_before = Repo.aggregate(Contact, :count, :uuid)

      report = Import.import_csv(csv, list)
      assert report.created == 0
      assert report.added == 0
      assert report.skipped.unsubscribed == 1

      # Import always creates a brand-new contact per row, so
      # add_new_contact_to_list/3 always calls add_contact_to_list/3 with a
      # contact that has never had a row for this list — get_member/2 there
      # is always nil, so it can only ever take the plain-insert path, never
      # the reactivate path. The pre-existing removed member must therefore
      # be left exactly as it was:
      still_removed = Repo.get!(ListMember, removed_member.uuid)
      assert still_removed.status == "removed"
      assert still_removed.unsubscribed_at == removed_member.unsubscribed_at

      # ...and the transaction rollback on the email-uniqueness violation
      # must still mean no orphan contact for the skipped row:
      assert Repo.aggregate(Contact, :count, :uuid) == contact_count_before
    end

    test "does not create an orphan contact when the membership insert is rolled back" do
      list = list_fixture()
      csv = "email,name\ndup@example.com,First\n"
      Import.import_csv(csv, list)

      count_before = Repo.aggregate(Contact, :count, :uuid)

      # Re-import: the contact insert succeeds inside the transaction, but
      # the membership insert then violates idx_crm_list_members_list_email
      # and must roll the whole transaction — including the contact — back.
      Import.import_csv(csv, list)

      assert Repo.aggregate(Contact, :count, :uuid) == count_before
    end
  end

  describe "ImportReport" do
    test "default struct has zeroed counters and the full skip-reason map" do
      assert %ImportReport{created: 0, added: 0, rows: []} = %ImportReport{}
      assert map_size(%ImportReport{}.skipped) == 5
    end
  end
end
