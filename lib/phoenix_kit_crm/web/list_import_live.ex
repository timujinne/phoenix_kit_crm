defmodule PhoenixKitCRM.Web.ListImportLive do
  @moduledoc """
  Import page for a single CRM contact list — paste-text or file (CSV/TXT)
  upload, a dry-run preview (no writes), then a chunked real run with
  progress so a large file doesn't block the LiveView process for minutes,
  finishing with the full `ImportReport` broken out by skip reason.

  Phases (`@phase`): `:input` → `:preview` → `:running` → `:done`. `:back`
  from `:preview` returns to `:input`; `:restart` from `:done` returns to
  `:input` for another file.
  """
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCRM.Gettext

  alias PhoenixKitCRM.{Activity, Lists, Paths}
  alias PhoenixKitCRM.Lists.Import

  @max_file_size 5_000_000
  @chunk_size 200
  @preview_limit 20

  @impl true
  def mount(%{"uuid" => uuid}, _session, socket) do
    case Lists.get_list(uuid) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("List not found"))
         |> push_navigate(to: Paths.lists())}

      list ->
        {:ok,
         socket
         |> assign(:list, list)
         |> assign(:page_title, gettext("CRM — Import — %{name}", name: list.name))
         |> assign(:preview_limit, @preview_limit)
         |> allow_upload(:file,
           accept: ~w(.csv .txt),
           max_entries: 1,
           max_file_size: @max_file_size,
           # auto_upload: the file starts transferring the moment it is picked,
           # so the progress bar the entry row shows actually moves. With manual
           # upload (false) nothing transfers until the form submit — live-tested
           # by the user as "the upload never moves": a 0% bar next to a chosen
           # file reads as a stall, not as "now press Preview".
           auto_upload: true
         )
         |> reset_to_input()}
    end
  end

  # ── Input phase: paste or upload → preview ──────────────────────────

  @impl true
  def handle_event("preview_paste", %{"paste" => %{"text" => text}}, socket) do
    start_preview(socket, Import.parse_text_rows(text), gettext("pasted text"))
  end

  def handle_event("preview_upload", _params, socket) do
    entries = socket.assigns.uploads.file.entries

    cond do
      entries == [] ->
        {:noreply, put_flash(socket, :error, gettext("Choose a file first"))}

      # The submit button's `disabled` is a client-side affordance only — a
      # direct "preview_upload" event (devtools, a replayed/forged socket
      # message) can still reach this handler mid-upload. entry.done? is
      # false until the entry has actually finished transferring;
      # consume_uploaded_entries/3 raises on an entry that isn't done, so
      # this guard has to be server-side, not just the disabled= in the
      # template.
      not Enum.all?(entries, & &1.done?) ->
        {:noreply, put_flash(socket, :error, gettext("Upload still in progress"))}

      true ->
        consume_and_preview_upload(socket)
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  # ── Preview phase ────────────────────────────────────────────────────

  def handle_event("back_to_input", _params, socket), do: {:noreply, reset_to_input(socket)}

  def handle_event("confirm_import", _params, socket) do
    send(self(), :process_chunk)

    {:noreply,
     socket
     |> assign(:phase, :running)
     |> assign(:pending_rows, socket.assigns.parsed_rows)
     |> assign(:progress, %{processed: 0, total: length(socket.assigns.parsed_rows)})
     |> assign(:accumulator, Import.new_accumulator())}
  end

  # ── Done phase ───────────────────────────────────────────────────────

  def handle_event("restart", _params, socket), do: {:noreply, reset_to_input(socket)}

  # ── Running phase: one chunk per message, yielding back to the
  #    LiveView's mailbox between chunks so progress actually renders and
  #    the process is never blocked on the whole file in one shot. ──────

  @impl true
  def handle_info(:process_chunk, socket) do
    {chunk, rest} = Enum.split(socket.assigns.pending_rows, @chunk_size)

    new_acc =
      Import.run_chunk(
        chunk,
        socket.assigns.list,
        Activity.actor_opts(socket),
        socket.assigns.accumulator
      )

    progress = socket.assigns.progress

    socket =
      socket
      |> assign(:pending_rows, rest)
      |> assign(:accumulator, new_acc)
      |> assign(:progress, %{progress | processed: progress.processed + length(chunk)})

    if rest == [] do
      {report, _seen} = new_acc
      {:noreply, socket |> assign(:phase, :done) |> assign(:final_report, report)}
    else
      send(self(), :process_chunk)
      {:noreply, socket}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp consume_and_preview_upload(socket) do
    case consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
           {:ok, {File.read!(path), entry.client_name}}
         end) do
      [{content, filename}] ->
        start_preview(socket, parse_by_extension(content, filename), filename)

      [] ->
        {:noreply, put_flash(socket, :error, gettext("Choose a file first"))}
    end
  end

  defp parse_by_extension(content, filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".csv" -> Import.parse_csv_rows(content)
      _ -> Import.parse_text_rows(content)
    end
  end

  defp start_preview(socket, [], _source_label) do
    {:noreply, put_flash(socket, :error, gettext("No rows found in that input"))}
  end

  defp start_preview(socket, rows, source_label) do
    preview_report = Import.preview_rows(rows, socket.assigns.list)

    {:noreply,
     socket
     |> assign(:phase, :preview)
     |> assign(:parsed_rows, rows)
     |> assign(:preview_report, preview_report)
     |> assign(:source_label, source_label)}
  end

  defp reset_to_input(socket) do
    socket
    |> assign(:phase, :input)
    |> assign(:paste_form, to_form(%{"text" => ""}, as: :paste))
    |> assign(:source_label, nil)
    |> assign(:parsed_rows, [])
    |> assign(:preview_report, nil)
    |> assign(:pending_rows, [])
    |> assign(:progress, %{processed: 0, total: 0})
    |> assign(:accumulator, nil)
    |> assign(:final_report, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col mx-auto max-w-4xl px-4 py-6 gap-6">
      <.admin_page_header
        back={Paths.list_members(@list.uuid)}
        back_label={gettext("Back to members")}
        title={gettext("Import contacts")}
        subtitle={@list.name}
      />

      <div :if={@phase == :input} class="grid gap-6 md:grid-cols-2">
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-4">
            <h2 class="font-semibold flex items-center gap-2">
              <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
              {gettext("Paste emails")}
            </h2>
            <p class="text-sm text-base-content/60">{gettext("One email address per line.")}</p>

            <.form for={@paste_form} id="crm-import-paste-form" phx-submit="preview_paste">
              <.textarea
                field={@paste_form[:text]}
                label={gettext("Emails")}
                rows="10"
                placeholder="alice@example.com&#10;bob@example.com"
              />
              <div class="flex justify-end mt-3">
                <.button type="submit" class="btn-primary" phx-disable-with={gettext("Parsing…")}>
                  {gettext("Preview")}
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-sm">
          <div class="card-body gap-4">
            <h2 class="font-semibold flex items-center gap-2">
              <.icon name="hero-document-arrow-up" class="w-5 h-5" /> {gettext("Upload a file")}
            </h2>
            <p class="text-sm text-base-content/60">
              {gettext(
                "CSV (with an email column) or a plain text file, one email per line. Max %{size}.",
                size: "5 MB"
              )}
            </p>

            <form
              id="crm-import-upload-form"
              phx-submit="preview_upload"
              phx-change="validate_upload"
              class="flex flex-col gap-3"
            >
              <.live_file_input upload={@uploads.file} class="file-input file-input-bordered w-full" />

              <div :for={entry <- @uploads.file.entries} class="flex items-center gap-2 text-sm">
                <span class="truncate">{entry.client_name}</span>
                <progress class="progress progress-primary w-32" value={entry.progress} max="100">
                </progress>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-x-mark" class="w-3 h-3" />
                </button>
              </div>

              <p :for={err <- all_upload_errors(@uploads.file)} class="text-error text-sm">
                {upload_error_message(err)}
              </p>

              <div class="flex justify-end">
                <.button
                  type="submit"
                  class="btn-primary"
                  disabled={
                    @uploads.file.entries == [] or
                      not Enum.all?(@uploads.file.entries, & &1.done?)
                  }
                  phx-disable-with={gettext("Parsing…")}
                >
                  {gettext("Preview")}
                </.button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <div :if={@phase == :preview} class="flex flex-col gap-4">
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <span>
            {gettext("Preview of %{source} — nothing has been imported yet.",
              source: @source_label
            )}
          </span>
        </div>

        {report_stats(@preview_report)}

        <.table_default id="crm-import-preview-table" size="sm">
          <.table_default_header>
            <.table_default_row>
              <.table_default_header_cell>{gettext("Line")}</.table_default_header_cell>
              <.table_default_header_cell>{gettext("Email")}</.table_default_header_cell>
              <.table_default_header_cell>{gettext("Result")}</.table_default_header_cell>
            </.table_default_row>
          </.table_default_header>
          <.table_default_body>
            <.table_default_row :for={row <- Enum.take(@preview_report.rows, @preview_limit)}>
              <.table_default_cell>{row.line}</.table_default_cell>
              <.table_default_cell>{row.email || "—"}</.table_default_cell>
              <.table_default_cell>{outcome_badge(row)}</.table_default_cell>
            </.table_default_row>
          </.table_default_body>
        </.table_default>

        <p :if={length(@parsed_rows) > @preview_limit} class="text-sm text-base-content/60">
          {gettext("Showing the first %{n} of %{total} rows.",
            n: @preview_limit,
            total: length(@parsed_rows)
          )}
        </p>

        <div class="flex justify-end gap-2">
          <.button type="button" phx-click="back_to_input" class="btn-ghost">
            {gettext("Back")}
          </.button>
          <.button
            type="button"
            phx-click="confirm_import"
            class="btn-primary"
            disabled={@preview_report.created == 0}
            phx-disable-with={gettext("Starting…")}
          >
            {gettext("Import %{n} contacts", n: @preview_report.created)}
          </.button>
        </div>
      </div>

      <div :if={@phase == :running} class="flex flex-col items-center gap-4 py-16">
        <span class="loading loading-spinner loading-lg text-primary"></span>
        <p>
          {gettext("Importing… %{done} / %{total}",
            done: @progress.processed,
            total: @progress.total
          )}
        </p>
        <progress
          class="progress progress-primary w-64"
          value={@progress.processed}
          max={max(@progress.total, 1)}
        >
        </progress>
      </div>

      <div :if={@phase == :done} class="flex flex-col gap-4">
        <div class="alert alert-success">
          <.icon name="hero-check-circle" class="w-5 h-5" />
          <span>
            {gettext("Imported %{created} contacts, added %{added} memberships.",
              created: @final_report.created,
              added: @final_report.added
            )}
          </span>
        </div>

        {report_stats(@final_report)}

        <div
          :for={{reason, count} <- nonzero_skip_buckets(@final_report)}
          class="collapse collapse-arrow bg-base-100 border border-base-200"
        >
          <input type="checkbox" />
          <div class="collapse-title font-medium">{skip_reason_label(reason)} ({count})</div>
          <div class="collapse-content">
            <ul class="text-sm flex flex-col gap-1">
              <li :for={row <- Enum.filter(@final_report.rows, &(&1.reason == reason))}>
                {gettext("Line %{line}: %{email}", line: row.line, email: row.email || "—")}
              </li>
            </ul>
          </div>
        </div>

        <div class="flex justify-end gap-2">
          <.link navigate={Paths.list_members(@list.uuid)} class="btn btn-primary">
            {gettext("View members")}
          </.link>
          <.button type="button" phx-click="restart" class="btn-ghost">
            {gettext("Import another file")}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr(:report, :map, required: true)

  defp report_stats(report) do
    assigns = %{report: report}

    ~H"""
    <div class="stats stats-vertical sm:stats-horizontal shadow overflow-x-auto">
      <div class="stat">
        <div class="stat-title">{gettext("Would import")}</div>
        <div class="stat-value text-success text-2xl">{@report.created}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Already in list")}</div>
        <div class="stat-value text-2xl">{@report.skipped.already_in_list}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Unsubscribed")}</div>
        <div class="stat-value text-2xl">{@report.skipped.unsubscribed}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Duplicate in file")}</div>
        <div class="stat-value text-2xl">{@report.skipped.duplicate_in_file}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("No email")}</div>
        <div class="stat-value text-2xl">{@report.skipped.no_email}</div>
      </div>
      <div class="stat">
        <div class="stat-title">{gettext("Invalid email")}</div>
        <div class="stat-value text-2xl">{@report.skipped.invalid_email}</div>
      </div>
    </div>
    """
  end

  defp outcome_badge(%{outcome: :imported}) do
    assigns = %{}

    ~H"""
    <span class="badge badge-success badge-sm">{gettext("Would import")}</span>
    """
  end

  defp outcome_badge(%{reason: reason}) do
    assigns = %{label: skip_reason_label(reason)}

    ~H"""
    <span class="badge badge-warning badge-sm">{@label}</span>
    """
  end

  # HEEx's :for special attribute only accepts a single generator, no
  # comprehension filter clause — pre-filter here instead.
  defp nonzero_skip_buckets(report),
    do: Enum.filter(report.skipped, fn {_reason, count} -> count > 0 end)

  defp skip_reason_label(:already_in_list), do: gettext("Already in list")
  defp skip_reason_label(:unsubscribed), do: gettext("Unsubscribed")
  defp skip_reason_label(:no_email), do: gettext("No email")
  defp skip_reason_label(:invalid_email), do: gettext("Invalid email")
  defp skip_reason_label(:duplicate_in_file), do: gettext("Duplicate in file")

  # upload_errors/1 only surfaces config-level errors (e.g. :too_many_files);
  # per-entry errors like :too_large or :not_accepted are keyed by the
  # entry's own ref and only come back from upload_errors/2. Combine both so
  # the template shows every rejection, not just the whole-config ones.
  defp all_upload_errors(upload_config) do
    entry_errors =
      Enum.flat_map(upload_config.entries, &upload_errors(upload_config, &1))

    upload_errors(upload_config) ++ entry_errors
  end

  defp upload_error_message(:too_large), do: gettext("File is too large (max 5 MB)")
  defp upload_error_message(:too_many_files), do: gettext("Only one file at a time")
  defp upload_error_message(:not_accepted), do: gettext("Only .csv or .txt files are accepted")
  defp upload_error_message(_), do: gettext("Could not accept this file")
end
