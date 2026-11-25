defmodule CluebertWeb.ImportBoardsLive do
  @moduledoc """
  The board import page at `/boards/import` (ADR 9), for loading boards
  where `mix cluebert.import` isn't available, such as the deployed app.

  JSON can be pasted, or one or more `.json` files chosen, or both. Each
  source (the pasted text, and each file) is imported on its own and
  all-or-nothing by `Cluebert.Boards.Import`, as the mix task does. The
  results list what each source imported or replaced, or the importer's
  error, which names the board, category and clue at fault. The format is
  documented in `docs/board-format.md`.
  """
  use CluebertWeb, :live_view

  alias Cluebert.Boards.Import

  @max_files 10
  @max_file_size 2_000_000

  @example """
  {
    "collection": "Primary Lessons",
    "name": "Lesson 12: Plants",
    "categories": [
      {
        "title": "Parts of a Plant",
        "clues": [
          { "prompt": "This part soaks up water", "response": "The roots" },
          { "prompt": "Leaves use this to make food", "response": "Sunlight", "value": 200 }
        ]
      }
    ]
  }
  """

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import boards")
     |> assign(:example, @example)
     |> assign(:results, [])
     |> assign_form(%{"json" => "", "replace" => "false"})
     |> allow_upload(:board_files,
       accept: ~w(.json),
       max_entries: @max_files,
       max_file_size: @max_file_size
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <nav id="breadcrumb" class="flex items-center gap-1.5 text-sm text-zinc-500">
        <.link navigate={~p"/boards"} class="hover:text-zinc-900">Boards</.link>
        <.icon name="hero-chevron-right-mini" class="size-4" />
        <span>Import</span>
      </nav>

      <.header>
        Import boards
        <:subtitle>
          Paste JSON or choose files. Each file, and the pasted text, is imported whole or not at all.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="import-form"
        phx-change="validate"
        phx-submit="import"
        class="space-y-4 rounded-xl border border-zinc-200 bg-white p-6 shadow-sm"
      >
        <.input
          field={@form[:json]}
          type="textarea"
          label="Paste JSON"
          rows="10"
          placeholder={@example}
          class="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 font-mono text-sm text-zinc-900 shadow-sm placeholder:text-zinc-400 focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
        />

        <div
          id="file-drop"
          phx-drop-target={@uploads.board_files.ref}
          class="rounded-lg border-2 border-dashed border-zinc-300 p-4 text-center transition-colors hover:border-blue-400"
        >
          <label class="cursor-pointer text-sm text-zinc-600">
            <span class="font-semibold text-blue-700 hover:underline">Choose .json files</span>
            or drop them here <.live_file_input upload={@uploads.board_files} class="sr-only" />
          </label>

          <ul
            :if={@uploads.board_files.entries != []}
            id="chosen-files"
            class="mt-3 space-y-1 text-left"
          >
            <li
              :for={entry <- @uploads.board_files.entries}
              id={"file-#{entry.ref}"}
              class="flex items-center justify-between rounded-md bg-zinc-50 px-3 py-1.5 text-sm"
            >
              <span class="truncate">{entry.client_name}</span>
              <span class="flex items-center gap-2">
                <span
                  :for={error <- upload_errors(@uploads.board_files, entry)}
                  class="text-red-700"
                >
                  {upload_error(error)}
                </span>
                <button
                  type="button"
                  phx-click="remove_file"
                  phx-value-ref={entry.ref}
                  aria-label={"Remove #{entry.client_name}"}
                  class="cursor-pointer rounded p-0.5 text-zinc-400 hover:bg-zinc-200 hover:text-zinc-700"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </span>
            </li>
          </ul>
          <p
            :for={error <- upload_errors(@uploads.board_files)}
            class="mt-2 text-sm text-red-700"
          >
            {upload_error(error)}
          </p>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4">
          <.input
            field={@form[:replace]}
            type="checkbox"
            label="Replace boards that already exist in their collection"
          />
          <.button id="import-button" variant="primary" phx-disable-with="Importing…">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Import
          </.button>
        </div>
      </.form>

      <section :if={@results != []} id="import-results" class="space-y-3">
        <h2 class="text-lg font-semibold">Results</h2>
        <div
          :for={{result, index} <- Enum.with_index(@results)}
          id={"result-#{index}"}
          data-status={result.status}
          class={[
            "rounded-lg border p-4",
            if(result.status == :ok,
              do: "border-emerald-200 bg-emerald-50",
              else: "border-red-200 bg-red-50"
            )
          ]}
        >
          <p class="flex items-center gap-2 font-medium">
            <.icon
              name={if(result.status == :ok, do: "hero-check-circle", else: "hero-x-circle")}
              class={[
                "size-5",
                if(result.status == :ok, do: "text-emerald-700", else: "text-red-700")
              ]}
            />
            {result.source}
          </p>
          <ul :if={result.status == :ok} class="mt-2 space-y-1 text-sm">
            <li :for={imported <- result.imported} id={"imported-board-#{imported.board.id}"}>
              {if imported.replaced?, do: "Replaced", else: "Imported"}
              <.link
                navigate={~p"/boards/#{imported.board.id}"}
                class="font-medium text-blue-700 hover:underline"
              >
                {imported.board.name}
              </.link>
              in {imported.collection}
            </li>
          </ul>
          <pre
            :if={result.status == :error}
            class="mt-2 whitespace-pre-wrap font-mono text-sm text-red-900"
          >{result.message}</pre>
        </div>
      </section>

      <details
        id="format-help"
        class="rounded-xl border border-zinc-200 bg-white p-5 text-sm shadow-sm"
      >
        <summary class="cursor-pointer font-semibold">Board format</summary>
        <div class="mt-3 space-y-2 text-zinc-700">
          <p>
            One board object, or a list of them. <code>collection</code> is optional
            (defaults to "General") and <code>value</code> is optional (100 × the clue's row).
            Categories and clues appear in the order listed. The full contract is in <code>docs/board-format.md</code>.
          </p>
          <pre class="overflow-x-auto rounded-lg bg-zinc-900 p-4 font-mono text-xs text-zinc-100">{@example}</pre>
        </div>
      </details>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"import" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("remove_file", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :board_files, ref)}
  end

  def handle_event("import", %{"import" => params}, socket) do
    replace? = params["replace"] == "true"
    json = params["json"] || ""

    files =
      consume_uploaded_entries(socket, :board_files, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    sources = if(String.trim(json) == "", do: [], else: [{"Pasted JSON", json}]) ++ files

    if sources == [] do
      {:noreply, put_flash(socket, :error, "Paste some JSON or choose a file to import.")}
    else
      results = Enum.map(sources, &import_source(&1, replace?))
      pasted_ok? = Enum.any?(results, &(&1.source == "Pasted JSON" and &1.status == :ok))

      {:noreply,
       socket
       |> assign(:results, results)
       |> assign_form(%{
         "json" => if(pasted_ok?, do: "", else: json),
         "replace" => to_string(replace?)
       })}
    end
  end

  defp import_source({source, json}, replace?) do
    case Import.import_json(json, replace: replace?) do
      {:ok, imported} -> %{source: source, status: :ok, imported: imported}
      {:error, error} -> %{source: source, status: :error, message: Import.format_error(error)}
    end
  end

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: :import))

  defp upload_error(:too_large), do: "File is too large (2 MB at most)."
  defp upload_error(:not_accepted), do: "Only .json files can be imported."
  defp upload_error(:too_many_files), do: "Choose at most #{@max_files} files at a time."
  defp upload_error(_other), do: "This file can't be uploaded."
end
