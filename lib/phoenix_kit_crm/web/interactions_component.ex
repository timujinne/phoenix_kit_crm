defmodule PhoenixKitCRM.Web.InteractionsComponent do
  @moduledoc """
  The Interactions / History tab for a contact: a reverse-chronological feed
  of interactions involving the contact, plus a composer to log a new one with
  a free-form-but-resolvable "involved parties" picker (CRM contacts + staff).
  """
  use PhoenixKitWeb, :live_component
  use Gettext, backend: PhoenixKitCRM.Gettext

  require Logger

  alias PhoenixKit.Modules.Storage
  alias PhoenixKitCRM.{Attachments, Contacts, Interactions, StaffLink}
  alias PhoenixKitCRM.Schemas.{Contact, Interaction}
  alias PhoenixKitWeb.Live.Components.MediaSelectorModal

  @impl true
  # The composer's file picker (core MediaSelectorModal) notifies results here.
  def update(%{media_selected: uuids}, socket) when is_list(uuids) do
    {:ok, socket |> stage_files(uuids) |> assign(:show_file_picker, false)}
  end

  def update(%{media_selector_closed: true}, socket),
    do: {:ok, assign(socket, :show_file_picker, false)}

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    offset = socket.assigns[:tz_offset] || 0

    {:ok,
     socket
     |> assign_new(:staged_parties, fn -> [] end)
     |> assign_new(:staged_files, fn -> [] end)
     |> assign_new(:show_file_picker, fn -> false end)
     # Composer fields are controlled (kept in assigns) so re-renders triggered
     # by staging a party don't wipe what the user has typed. `c_occurred_at`
     # is the user's LOCAL wall-clock time (in their profile timezone); it's
     # converted to/from UTC at the storage boundary. (The party search box +
     # dropdown are owned entirely by the PartyPicker JS hook — no server state.)
     |> assign_new(:c_type, fn -> "note" end)
     |> assign_new(:c_subject, fn -> "" end)
     |> assign_new(:c_body, fn -> "" end)
     |> assign_new(:c_occurred_at, fn -> local_now_str(offset) end)
     |> assign_new(:save_error, fn -> nil end)
     |> assign(:staff_enabled, StaffLink.enabled?())
     |> assign(:storage_enabled, storage_enabled?())
     |> load_interactions()}
  end

  defp load_interactions(socket) do
    interactions = Interactions.list_involving(socket.assigns.contact.uuid)

    interaction_files =
      if socket.assigns[:storage_enabled],
        do: Attachments.list_files_by_interaction(Enum.map(interactions, & &1.uuid)),
        else: %{}

    socket
    |> assign(:interactions, interactions)
    |> assign(:interaction_files, interaction_files)
  end

  defp storage_enabled? do
    Storage.enabled?()
  rescue
    _ -> false
  end

  @impl true
  # The PartyPicker JS hook owns the search box + dropdown entirely (instant,
  # client-side). It pushes the (client-debounced) query here; we run the DB
  # search and hand rows back to the hook via push_event. No server-side search
  # state is kept.
  def handle_event("search_party", %{"q" => q} = params, socket) when is_binary(q) do
    q = String.trim(q)

    {results, has_more} =
      search_parties(q, socket.assigns.staff_enabled, parse_limit(params["limit"]))

    {:noreply,
     push_event(socket, "crm_party_results", %{q: q, results: results, has_more: has_more})}
  end

  def handle_event("stage_party", %{"kind" => kind, "uuid" => uuid, "label" => label}, socket)
      when is_binary(kind) and is_binary(uuid) and is_binary(label) do
    party = %{raw_name: label, kind: kind, contact_uuid: nil, staff_person_uuid: nil}

    party =
      case kind do
        "contact" -> %{party | contact_uuid: uuid}
        "staff" -> %{party | staff_person_uuid: uuid}
        _ -> party
      end

    {:noreply, socket |> maybe_append(party) |> push_event("crm_party_staged", %{})}
  end

  def handle_event("stage_text", %{"name" => name}, socket) when is_binary(name) do
    name = String.trim(name)
    party = %{raw_name: name, kind: "text", contact_uuid: nil, staff_person_uuid: nil}
    socket = if name == "", do: socket, else: maybe_append(socket, party)

    {:noreply, push_event(socket, "crm_party_staged", %{})}
  end

  def handle_event("add_me", _params, socket) do
    case me_party(socket.assigns[:current_user_uuid], socket.assigns[:current_user_name]) do
      nil -> {:noreply, socket}
      party -> {:noreply, maybe_append(socket, party)}
    end
  end

  def handle_event("remove_party", %{"idx" => idx}, socket) do
    case Integer.parse(to_string(idx)) do
      {i, _} ->
        {:noreply,
         assign(socket, :staged_parties, List.delete_at(socket.assigns.staged_parties, i))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("composer_change", %{"interaction" => p}, socket) when is_map(p) do
    {:noreply,
     socket
     |> assign(:c_type, p["interaction_type"] || socket.assigns.c_type)
     |> assign(:c_subject, p["subject"] || "")
     |> assign(:c_body, p["body"] || "")
     |> assign(:c_occurred_at, p["occurred_at"] || socket.assigns.c_occurred_at)
     |> assign(:save_error, nil)}
  end

  def handle_event("composer_change", _params, socket), do: {:noreply, socket}

  def handle_event("set_now", _params, socket) do
    {:noreply, assign(socket, :c_occurred_at, local_now_str(socket.assigns[:tz_offset] || 0))}
  end

  def handle_event("save_interaction", _params, socket) do
    # `c_occurred_at` is the user's LOCAL time (profile tz); store true UTC.
    occurred_at = local_to_utc(socket.assigns.c_occurred_at, socket.assigns[:tz_offset] || 0)

    attrs =
      %{
        "contact_uuid" => socket.assigns.contact.uuid,
        "interaction_type" => socket.assigns.c_type,
        "subject" => socket.assigns.c_subject,
        "body" => socket.assigns.c_body,
        "owner_user_uuid" => socket.assigns[:current_user_uuid]
      }
      |> maybe_put_occurred_at(occurred_at)

    party_inputs =
      Enum.map(socket.assigns.staged_parties, fn p ->
        %{
          raw_name: p.raw_name,
          contact_uuid: p[:contact_uuid],
          staff_person_uuid: p[:staff_person_uuid]
        }
      end)

    file_uuids = Enum.map(socket.assigns.staged_files, & &1.uuid)

    case Interactions.create_interaction(attrs, party_inputs, file_uuids) do
      {:ok, _interaction} ->
        # (The audit-log entry, file attach, + realtime broadcast are emitted by
        # the context.) Reset the composer ONLY on success — every failure path
        # below leaves the typed fields + staged parties + files untouched.
        {:noreply,
         socket
         |> assign(:staged_parties, [])
         |> assign(:staged_files, [])
         |> assign(:c_type, "note")
         |> assign(:c_subject, "")
         |> assign(:c_body, "")
         |> assign(:c_occurred_at, local_now_str(socket.assigns[:tz_offset] || 0))
         |> assign(:save_error, nil)
         |> load_interactions()}

      {:error, changeset} ->
        {:noreply, assign(socket, :save_error, changeset_message(changeset))}
    end
  rescue
    e ->
      Logger.error(
        "[CRM] save_interaction crashed: " <> Exception.format(:error, e, __STACKTRACE__)
      )

      {:noreply, assign(socket, :save_error, default_save_error())}
  end

  def handle_event("delete_interaction", %{"uuid" => uuid}, socket) do
    # Only delete interactions actually shown in this contact's feed — a forged
    # event must not be able to delete an unrelated interaction by uuid.
    in_feed? = Enum.any?(socket.assigns.interactions, &(&1.uuid == uuid))

    with true <- in_feed?,
         %Interaction{} = i <- Interactions.get_interaction(uuid) do
      Interactions.delete_interaction(i)
      {:noreply, load_interactions(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_file_picker", _params, socket),
    do: {:noreply, assign(socket, :show_file_picker, true)}

  def handle_event("close_file_picker", _params, socket),
    do: {:noreply, assign(socket, :show_file_picker, false)}

  def handle_event("remove_staged_file", %{"uuid" => uuid}, socket) do
    {:noreply,
     assign(socket, :staged_files, Enum.reject(socket.assigns.staged_files, &(&1.uuid == uuid)))}
  end

  # Ignore any unexpected/forged event rather than crashing the LiveView.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # Add newly-picked/uploaded files to the composer's staged list (deduped). The
  # files are attached to the interaction's folder when it's saved.
  defp stage_files(socket, uuids) do
    current = socket.assigns[:staged_files] || []
    seen = MapSet.new(current, & &1.uuid)

    added =
      uuids
      |> Enum.reject(&MapSet.member?(seen, &1))
      |> Enum.map(&Attachments.get_file/1)
      |> Enum.reject(&is_nil/1)

    assign(socket, :staged_files, current ++ added)
  end

  # Best-effort, user-facing message from a failed changeset (interaction or a
  # rolled-back party); details are logged, the input is preserved either way.
  defp changeset_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, to_string(msg), fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", safe_str(v))
      end)
    end)
    |> Enum.flat_map(fn {_field, msgs} -> msgs end)
    |> List.first()
    |> case do
      detail when is_binary(detail) -> gettext("Couldn't save: %{detail}", detail: detail)
      _ -> default_save_error()
    end
  rescue
    # Never let the error-message builder itself crash the save handler.
    _ -> default_save_error()
  end

  defp changeset_message(_), do: default_save_error()

  defp default_save_error do
    gettext("Couldn't save this interaction. Your input was kept — please try again.")
  end

  defp safe_str(v) when is_binary(v), do: v
  defp safe_str(v) when is_atom(v) or is_number(v), do: to_string(v)
  defp safe_str(v), do: inspect(v)

  defp append_party(socket, party) do
    assign(socket, :staged_parties, socket.assigns.staged_parties ++ [party])
  end

  defp maybe_append(socket, party) do
    if already_staged?(socket.assigns.staged_parties, party),
      do: socket,
      else: append_party(socket, party)
  end

  # "Add me" → the current user's linked CRM contact if any, else free text.
  # Tagged `is_me` for the "(you)" badge suffix (display-only; dropped on save).
  defp me_party(uuid, name) when is_binary(uuid) do
    base =
      case Contacts.get_by_user_uuid(uuid) do
        %Contact{} = c ->
          %{
            raw_name: Contact.display_name(c),
            kind: "contact",
            contact_uuid: c.uuid,
            staff_person_uuid: nil
          }

        _ ->
          text_party(name)
      end

    mark_me(base)
  end

  defp me_party(_uuid, name), do: mark_me(text_party(name))

  defp text_party(name) when is_binary(name) and name != "" do
    %{raw_name: name, kind: "text", contact_uuid: nil, staff_person_uuid: nil}
  end

  defp text_party(_), do: nil

  defp mark_me(nil), do: nil
  defp mark_me(party), do: Map.put(party, :is_me, true)

  defp me_staged?(parties), do: Enum.any?(parties, & &1[:is_me])

  defp already_staged?(staged, %{contact_uuid: cu}) when is_binary(cu) do
    Enum.any?(staged, &(&1[:contact_uuid] == cu))
  end

  defp already_staged?(staged, %{staff_person_uuid: su}) when is_binary(su) do
    Enum.any?(staged, &(&1[:staff_person_uuid] == su))
  end

  defp already_staged?(staged, %{raw_name: name}) do
    Enum.any?(staged, &(&1[:raw_name] == name))
  end

  # Fetch one extra per source so the hook knows whether to offer "Load more".
  defp search_parties(query, staff_enabled?, limit) do
    contacts =
      query
      |> Contacts.search_contacts(limit + 1)
      |> Enum.map(fn c ->
        %{kind: "contact", uuid: c.uuid, label: Contact.display_name(c), sublabel: c.email || ""}
      end)

    staff = if staff_enabled?, do: staff_results(query, limit + 1), else: []
    has_more = length(contacts) > limit or length(staff) > limit

    {Enum.take(contacts, limit) ++ Enum.take(staff, limit), has_more}
  end

  defp staff_results(query, limit) do
    query
    |> StaffLink.search(limit)
    |> Enum.map(fn p ->
      %{kind: "staff", uuid: p.uuid, label: p.name, sublabel: p[:job_title] || gettext("Staff")}
    end)
  end

  @default_limit 8
  @max_limit 60

  defp parse_limit(n) when is_integer(n), do: n |> max(@default_limit) |> min(@max_limit)

  defp parse_limit(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> parse_limit(i)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit

  defp maybe_put_occurred_at(attrs, nil), do: attrs
  defp maybe_put_occurred_at(attrs, %DateTime{} = dt), do: Map.put(attrs, "occurred_at", dt)

  # ── Timezone helpers (storage is always UTC; UI is in the user's profile tz) ──

  # "Now" in the user's timezone, formatted for a datetime-local input.
  defp local_now_str(offset) do
    DateTime.utc_now()
    |> DateTime.add(offset * 3600, :second)
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  # A local datetime-local string (in the user's tz) → the true UTC instant.
  defp local_to_utc(value, offset) when is_binary(value) and value != "" do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, naive} ->
        naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.add(-offset * 3600, :second)

      _ ->
        nil
    end
  end

  defp local_to_utc(_, _), do: nil

  # A stored UTC datetime → display string in the user's tz.
  defp format_local(nil, _offset), do: "—"

  defp format_local(%DateTime{} = utc, offset) do
    utc |> DateTime.add(offset * 3600, :second) |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-6">
      <%!-- Composer --%>
      <div class="card bg-base-100 shadow-sm border border-base-200">
        <div class="card-body gap-3">
          <h3 class="font-semibold">{gettext("Log an interaction")}</h3>

          <.form
            for={%{}}
            as={:interaction}
            phx-change="composer_change"
            phx-target={@myself}
            class="flex flex-col gap-3"
          >
            <.select
              id="crm-type"
              name="interaction[interaction_type]"
              value={@c_type}
              label={gettext("Type")}
              options={Enum.map(Interaction.types(), &{Interaction.type_label(&1), &1})}
            />

            <div>
              <.input
                type="datetime-local"
                id="crm-when"
                name="interaction[occurred_at]"
                value={@c_occurred_at}
                label={gettext("When")}
                phx-hook="CrmWhenWarnings"
                data-profile-offset={@tz_offset}
                data-warning-target="crm-when-warning"
                data-setnow-target="crm-set-now"
              />
              <div class="flex flex-wrap items-center gap-2 mt-1">
                <div
                  id="crm-when-warning"
                  data-when-warning
                  phx-update="ignore"
                  class="text-xs text-warning empty:hidden flex flex-col gap-0.5"
                >
                </div>
                <button
                  type="button"
                  id="crm-set-now"
                  phx-update="ignore"
                  phx-click="set_now"
                  phx-target={@myself}
                  class="btn btn-xs btn-outline gap-1 hidden"
                >
                  <.icon name="hero-clock" class="w-3.5 h-3.5" /> {gettext("Set to now")}
                </button>
              </div>
            </div>

            <.input
              id="crm-subject"
              name="interaction[subject]"
              value={@c_subject}
              label={gettext("Subject")}
              placeholder={gettext("Optional")}
            />
            <.textarea
              id="crm-body"
              name="interaction[body]"
              value={@c_body}
              label={gettext("What was discussed?")}
            />
          </.form>

          <%!-- Involved parties — outside the <.form> so Enter in the search box
                never submits the composer (it only stages parties). --%>
          <div class="flex flex-col gap-2">
              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-1">
                  <label for="crm-party-search" class="label-text font-semibold leading-none">
                    {gettext("Involved parties")}
                  </label>
                  <div class="relative inline-flex items-center group">
                    <.icon
                      name="hero-information-circle"
                      class="w-3.5 h-3.5 text-base-content/40 group-hover:text-base-content cursor-help"
                    />
                    <div class="hidden group-hover:block absolute left-0 top-6 z-30 w-56 p-3 rounded-box border border-base-200 bg-base-100 shadow-lg text-xs space-y-1.5">
                      <div class="font-semibold text-base-content">{gettext("In search results:")}</div>
                      <div class="flex items-center gap-2 text-base-content/70">
                        <.icon name="hero-user" class="w-4 h-4 text-base-content/50" />
                        <span>{gettext("CRM contact")}</span>
                      </div>
                      <div :if={@staff_enabled} class="flex items-center gap-2 text-base-content/70">
                        <.icon name="hero-identification" class="w-4 h-4 text-base-content/50" />
                        <span>{gettext("Staff member")}</span>
                      </div>
                      <div class="flex items-center gap-2 text-base-content/70">
                        <.icon name="hero-plus-mini" class="w-4 h-4 text-base-content/50" />
                        <span>{gettext("Added as free text")}</span>
                      </div>
                    </div>
                  </div>
                </div>
                <button
                  :if={@current_user_uuid && not me_staged?(@staged_parties)}
                  type="button"
                  phx-click="add_me"
                  phx-target={@myself}
                  class="btn btn-xs btn-outline gap-1"
                >
                  <.icon name="hero-user-plus" class="w-3.5 h-3.5" /> {gettext("Add me")}
                </button>
              </div>

              <div :if={@staged_parties != []} class="flex flex-wrap gap-2">
                <span :for={{p, idx} <- Enum.with_index(@staged_parties)} class="badge badge-lg gap-1">
                  {p.raw_name}<span :if={p[:is_me]} class="opacity-60">&nbsp;{gettext("(you)")}</span>
                  <button
                    type="button"
                    phx-click="remove_party"
                    phx-value-idx={idx}
                    phx-target={@myself}
                    aria-label={gettext("Remove")}
                    class="ml-1 cursor-pointer"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </span>
              </div>

              <%!-- Hook-driven typeahead: the dropdown is rendered + toggled
                    entirely client-side (instant); the server (search_party)
                    only returns rows via push_event. --%>
              <div class="relative">
                <input
                  type="text"
                  id="crm-party-search"
                  phx-hook="PartyPicker"
                  data-target={"##{@id}"}
                  data-dropdown="crm-party-dropdown"
                  data-t-searching={gettext("Searching…")}
                  data-t-add-prefix={gettext("Add")}
                  data-t-add-suffix={gettext("as free text")}
                  data-t-adding={gettext("Adding…")}
                  data-t-more={gettext("Load more")}
                  data-t-loading-more={gettext("Loading…")}
                  placeholder={gettext("Type a name — searches contacts%{staff}…", staff: if(@staff_enabled, do: gettext(" and staff"), else: ""))}
                  class="input input-bordered w-full"
                  autocomplete="off"
                />
                <div
                  id="crm-party-dropdown"
                  phx-update="ignore"
                  class="hidden absolute left-0 right-0 z-20 mt-1 border border-base-200 rounded-box bg-base-100 shadow overflow-hidden"
                >
                </div>
              </div>
              <%!-- Keep the JS-rendered dropdown's classes in the CSS bundle. --%>
              <span class="hidden loading loading-spinner loading-xs hero-user hero-identification hero-pencil hero-plus-mini"></span>
            </div>

          <%!-- Attachments — staged in the composer, attached to the interaction
                when it's saved (the picker uploads; we hold the uuids). --%>
          <div :if={@storage_enabled} class="flex flex-col gap-2">
            <div class="flex items-center justify-between gap-2">
              <span class="label-text font-semibold leading-none">{gettext("Attachments")}</span>
              <button
                type="button"
                phx-click="open_file_picker"
                phx-target={@myself}
                class="btn btn-xs btn-outline gap-1"
              >
                <.icon name="hero-paper-clip" class="w-3.5 h-3.5" /> {gettext("Attach files")}
              </button>
            </div>
            <div :if={@staged_files != []} class="flex flex-wrap gap-2">
              <span :for={f <- @staged_files} class="badge badge-lg gap-1">
                <.icon name={Attachments.file_icon(f)} class="w-3.5 h-3.5 shrink-0" />
                <span class="max-w-[12rem] truncate">{f.original_file_name || f.file_name}</span>
                <button
                  type="button"
                  phx-click="remove_staged_file"
                  phx-value-uuid={f.uuid}
                  phx-target={@myself}
                  aria-label={gettext("Remove")}
                  class="ml-1 cursor-pointer"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </span>
            </div>
          </div>

          <div :if={@save_error} class="alert alert-error text-sm py-2" role="alert">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 shrink-0" />
            <span>{@save_error}</span>
          </div>

          <div class="flex justify-end">
            <.button
              type="button"
              phx-click="save_interaction"
              phx-target={@myself}
              class="btn-primary btn-sm"
              phx-disable-with={gettext("Saving…")}
            >
              {gettext("Save interaction")}
            </.button>
          </div>
        </div>
      </div>

      <%!-- Composer file picker: upload-only, unscoped (files land orphan and
            are adopted into the interaction's folder on save). Notifies here. --%>
      <.live_component
        :if={@storage_enabled}
        module={MediaSelectorModal}
        id={"#{@id}-file-selector"}
        show={@show_file_picker}
        mode={:multiple}
        file_type_filter={:all}
        browse={false}
        selected_uuids={[]}
        scope_folder_id={nil}
        phoenix_kit_current_user={@phoenix_kit_current_user}
        notify={{__MODULE__, @id}}
      />

      <%!-- Timeline --%>
      <div :if={@interactions == []} class="text-center text-base-content/50 py-8">
        {gettext("No interactions logged yet.")}
      </div>

      <ol :if={@interactions != []} class="flex flex-col gap-3">
        <li :for={i <- @interactions} class="card bg-base-100 shadow-sm border border-base-200">
          <div class="card-body py-3 gap-1">
            <div class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <span class="badge badge-ghost badge-sm">{Interaction.type_label(i.interaction_type)}</span>
                <span class="text-xs text-base-content/60">{format_local(i.occurred_at, @tz_offset)}</span>
              </div>
              <button
                type="button"
                phx-click="delete_interaction"
                phx-value-uuid={i.uuid}
                phx-target={@myself}
                data-confirm={gettext("Delete this interaction?")}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash-mini" class="w-3 h-3" />
              </button>
            </div>
            <div :if={i.subject} class="font-medium">{i.subject}</div>
            <div :if={i.body} class="text-sm whitespace-pre-wrap">{i.body}</div>
            <div :if={i.parties != []} class="flex flex-wrap gap-1 mt-1">
              <span class="text-xs text-base-content/50">{gettext("Involved:")}</span>
              <span :for={p <- i.parties} class="badge badge-outline badge-sm gap-1" title={snapshot_title(p.party_snapshot)}>
                {p.raw_name}<span :if={snapshot_detail(p.party_snapshot)} class="opacity-60">— {snapshot_detail(p.party_snapshot)}</span>
              </span>
            </div>

            <% files = Map.get(@interaction_files, i.uuid, []) %>
            <div :if={files != []} class="flex flex-wrap gap-2 mt-1">
              <a
                :for={f <- files}
                href={Attachments.download_url(f)}
                target="_blank"
                rel="noopener"
                class="inline-flex items-center gap-1 badge badge-ghost badge-sm hover:badge-outline"
                title={f.original_file_name || f.file_name}
              >
                <.icon name={Attachments.file_icon(f)} class="w-3.5 h-3.5 shrink-0" />
                <span class="max-w-[10rem] truncate">{f.original_file_name || f.file_name}</span>
              </a>
            </div>
          </div>
        </li>
      </ol>
    </div>
    """
  end

  # "Intern at Acme" style detail from the frozen snapshot.
  defp snapshot_detail(snapshot) when is_map(snapshot) do
    role = snapshot["role_in_company"] || snapshot["job_title"]
    company = snapshot["company"]

    cond do
      role && company -> "#{role}, #{company}"
      role -> role
      company -> company
      true -> nil
    end
  end

  defp snapshot_detail(_), do: nil

  defp snapshot_title(snapshot) when is_map(snapshot) do
    case snapshot["captured_at"] do
      ts when is_binary(ts) -> gettext("Captured %{ts}", ts: ts)
      _ -> nil
    end
  end

  defp snapshot_title(_), do: nil
end
