defmodule PhoenixKitCRM.Lists.Import do
  @moduledoc """
  Pure-ish CSV/plaintext import engine for CRM contact lists (Stage 3 of the
  restructuring plan — the user's stated priority: account list import).
  Parses rows, applies the restructuring spec's Locked decisions, and writes
  only through `PhoenixKitCRM.Lists` — it never duplicates that context's
  insert/counter/broadcast logic.

  ## Locked decisions this engine enforces

    * Import always creates a NEW contact — never a merge, never "add to
      existing contact by matching email". Matching duplicates across
      contacts is a separate, later, human-reviewed comparison screen
      (Stage C4c), not something this engine decides on its own.
    * Per-row atomicity: contact INSERT + membership INSERT happen in ONE
      transaction (`Lists.add_new_contact_to_list/3`) — a uniqueness
      violation rolls both back, so a failed/duplicate row never leaves an
      orphan contact behind.
    * Idempotent re-import: importing the identical file twice creates zero
      new contacts on the second pass — every row lands in `skipped`
      instead of `created`/`added` (`:already_in_list` if the existing
      membership is still active, `:unsubscribed` if a prior membership was
      removed but still holds the email slot per the DB's partial unique
      index — see `ListMember`'s moduledoc).

  ## Row pipeline

  Each row goes through, in order: normalize (trim + downcase, matching the
  `email` column's citext case-insensitivity) → in-file dedup prefilter
  (`:duplicate_in_file` — a second row with the same email, e.g. a shared
  mailbox listed under two names, never reaches the DB) → email format
  check (`:invalid_email`) → the one write transaction, classifying any
  `idx_crm_list_members_list_email` violation by looking up the existing
  holder's status.

  `name` is CSV-optional per the spec; a blank name falls back to the email
  itself (mirrors `Contact.display_name/1`'s own fallback) so the contact
  changeset's `validate_required([:name])` never rejects an otherwise-valid
  row. `locale`, if present but not in a recognized format, is silently
  dropped rather than rejecting the row over a cosmetic field. `company`
  has no dedicated contact field yet (linking to `PhoenixKitCRM.Companies`
  is out of scope here) — it's stashed in `contact.metadata["import_company"]`
  so the comparison screen (C4c) can still surface it later instead of the
  data being silently discarded.

  ## XLSX

  Deliberately not supported yet. `xlsxir` (the library the plan asked to
  evaluate) is unmaintained since 2019 — not something to add as a new
  dependency. `xlsx_reader` is an actively-maintained alternative but wasn't
  evaluated in depth (its own dependency footprint, streaming behavior, etc.
  is a separate task). CSV/TXT cover the stated priority (account import);
  XLSX is deferred to a follow-up rather than shipped on an abandoned lib.
  """

  require Logger

  alias PhoenixKitCRM.Lists
  alias PhoenixKitCRM.Lists.ImportReport
  alias PhoenixKitCRM.Schemas.{Contact, ContactList}

  @csv_columns ~w(email name company locale)
  @locale_format ~r/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/

  # ── Public API ──────────────────────────────────────────────────────

  @doc """
  Imports from CSV content (already read from an upload or textarea paste).
  Header row is required; column matching is case-insensitive and only
  looks for `email` (required), `name`, `company`, `locale` (all optional)
  — unrecognized columns are ignored. `opts` accepts `:actor_uuid` (passed
  through to the activity log on every successful row).
  """
  @spec import_csv(String.t(), ContactList.t(), keyword()) :: ImportReport.t()
  def import_csv(content, %ContactList{} = list, opts \\ []) do
    content
    |> parse_csv()
    |> run(list, opts)
  end

  @doc """
  Imports from plaintext/clipboard content — one email address per line.
  Blank lines are ignored. `opts` accepts `:actor_uuid`.
  """
  @spec import_text(String.t(), ContactList.t(), keyword()) :: ImportReport.t()
  def import_text(content, %ContactList{} = list, opts \\ []) do
    content
    |> parse_text()
    |> run(list, opts)
  end

  # ── Parsing ─────────────────────────────────────────────────────────

  defp parse_csv(content) do
    case content |> strip_bom() |> NimbleCSV.RFC4180.parse_string(skip_headers: false) do
      [] ->
        []

      [header | data_rows] ->
        index = header_index(header)

        data_rows
        |> Enum.with_index(2)
        |> Enum.map(fn {row, line} -> {line, row_to_attrs(row, index)} end)
    end
  end

  defp header_index(header) do
    header
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {col, idx}, acc ->
      key = col |> to_string() |> String.trim() |> String.downcase()
      if key in @csv_columns, do: Map.put(acc, key, idx), else: acc
    end)
  end

  defp row_to_attrs(row, index) do
    %{
      "email" => fetch_cell(row, index, "email"),
      "name" => fetch_cell(row, index, "name"),
      "company" => fetch_cell(row, index, "company"),
      "locale" => fetch_cell(row, index, "locale")
    }
  end

  defp fetch_cell(row, index, key) do
    case Map.get(index, key) do
      nil -> nil
      idx -> row |> Enum.at(idx) |> blank_to_nil()
    end
  end

  defp parse_text(content) do
    content
    |> strip_bom()
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {raw_line, line}, acc ->
      case blank_to_nil(raw_line) do
        nil ->
          acc

        email ->
          [{line, %{"email" => email, "name" => nil, "company" => nil, "locale" => nil}} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(content), do: content

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # ── Row pipeline ────────────────────────────────────────────────────

  defp run(parsed_rows, %ContactList{} = list, opts) do
    {report, _seen} =
      Enum.reduce(parsed_rows, {%ImportReport{}, MapSet.new()}, fn {line, attrs},
                                                                   {report, seen} ->
        process_row(line, attrs, list, opts, report, seen)
      end)

    report
  end

  defp process_row(line, attrs, list, opts, report, seen) do
    case attrs["email"] do
      nil ->
        {skip(report, line, nil, :no_email), seen}

      raw_email ->
        email = normalize_email(raw_email)

        cond do
          not Contact.valid_email?(email) ->
            {skip(report, line, email, :invalid_email), seen}

          MapSet.member?(seen, email) ->
            {skip(report, line, email, :duplicate_in_file), seen}

          true ->
            result = import_row(attrs, email, list, opts)
            {apply_result(report, line, email, result, list), MapSet.put(seen, email)}
        end
    end
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp import_row(attrs, email, list, opts) do
    contact_attrs = %{
      "name" => attrs["name"] || email,
      "email" => email,
      "locale" => valid_locale_or_nil(attrs["locale"]),
      "metadata" => import_metadata(attrs)
    }

    Lists.add_new_contact_to_list(contact_attrs, list, Keyword.put(opts, :source, "import"))
  end

  defp import_metadata(attrs) do
    %{"source" => "import"} |> maybe_put("import_company", attrs["company"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp valid_locale_or_nil(nil), do: nil

  defp valid_locale_or_nil(locale) do
    if Regex.match?(@locale_format, locale), do: locale, else: nil
  end

  defp apply_result(report, line, email, {:ok, {_contact, _member}}, _list) do
    report
    |> Map.update!(:created, &(&1 + 1))
    |> Map.update!(:added, &(&1 + 1))
    |> add_row(line, email, :imported, nil)
  end

  defp apply_result(report, line, email, {:error, :email_already_in_list}, list) do
    reason =
      case Lists.get_member_by_email(list, email) do
        %{status: "removed"} -> :unsubscribed
        _ -> :already_in_list
      end

    skip(report, line, email, reason)
  end

  defp apply_result(report, line, email, {:error, :already_member}, _list) do
    # Structurally unreachable — the imported contact is always brand-new,
    # so it can never already be a member of this list. Kept only so this
    # stays exhaustive against add_new_contact_to_list/3's real return type.
    skip(report, line, email, :already_in_list)
  end

  defp apply_result(report, line, email, {:error, %Ecto.Changeset{} = changeset}, _list) do
    Logger.warning(
      "[CRM] Import row #{line} (#{inspect(email)}) rejected: #{inspect(changeset.errors)}"
    )

    skip(report, line, email, :invalid_email)
  end

  defp skip(report, line, email, reason) do
    report
    |> Map.update!(:skipped, &Map.update!(&1, reason, fn n -> n + 1 end))
    |> add_row(line, email, :skipped, reason)
  end

  defp add_row(report, line, email, outcome, reason) do
    Map.update!(
      report,
      :rows,
      &(&1 ++ [%{line: line, email: email, outcome: outcome, reason: reason}])
    )
  end
end
