defmodule CluebertWeb.ManageBoardsLive do
  @moduledoc """
  Board management at `/boards` (ADR 9): collections and the boards in them.

  Collections can be created, renamed and deleted (only when empty). Boards
  can be created, renamed, moved to another collection and deleted. Boards
  with no clues are pointed out, since a game can't be started with them.
  Editing boards never affects a game in progress (ADR 5).

  One inline form is open at a time; `@editing` says which:
  `:new_collection`, `{:collection, id}`, `{:new_board, collection_id}` or
  `{:board, id}`.
  """
  use CluebertWeb, :live_view

  alias Cluebert.Boards
  alias Cluebert.Boards.{Board, Collection}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Boards")
     |> assign(editing: nil, form: nil)
     |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Boards
        <:subtitle>
          Collections group boards, like "Primary Lessons" or "General Knowledge".
        </:subtitle>
        <:actions>
          <.button id="new-collection" variant="primary" phx-click="new_collection">
            <.icon name="hero-plus" class="size-4" /> New collection
          </.button>
        </:actions>
      </.header>

      <div :if={@editing == :new_collection} class="rounded-xl border border-blue-200 bg-blue-50 p-4">
        <.name_form form={@form} id="collection-form" placeholder="Collection name" />
      </div>

      <p :if={@collections == []} id="no-collections" class="text-zinc-500">
        No collections yet. Create one, or import boards with <code>mix cluebert.import</code>.
      </p>

      <section
        :for={collection <- @collections}
        id={"collection-#{collection.id}"}
        class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <%= if @editing == {:collection, collection.id} do %>
            <.name_form form={@form} id="collection-form" placeholder="Collection name" />
          <% else %>
            <h2 class="text-lg font-semibold">{collection.name}</h2>
            <div class="flex items-center gap-1">
              <.icon_button
                id={"new-board-#{collection.id}"}
                icon="hero-plus"
                label="Add board"
                phx-click="new_board"
                phx-value-collection={collection.id}
              />
              <.icon_button
                id={"rename-collection-#{collection.id}"}
                icon="hero-pencil-square"
                label="Rename"
                phx-click="edit_collection"
                phx-value-id={collection.id}
              />
              <.icon_button
                id={"delete-collection-#{collection.id}"}
                icon="hero-trash"
                label="Delete"
                danger
                phx-click="delete_collection"
                phx-value-id={collection.id}
                disabled={collection.boards != []}
                title={if(collection.boards != [], do: "Move or delete its boards first")}
                data-confirm={"Delete the collection \"#{collection.name}\"?"}
              />
            </div>
          <% end %>
        </div>

        <ul class="mt-3 divide-y divide-zinc-100">
          <li
            :for={board <- collection.boards}
            id={"board-#{board.id}"}
            class="flex flex-wrap items-center justify-between gap-3 py-2.5"
          >
            <%= if @editing == {:board, board.id} do %>
              <.name_form form={@form} id="board-form" placeholder="Board name" />
            <% else %>
              <div class="flex min-w-0 items-center gap-3">
                <.link
                  navigate={~p"/boards/#{board.id}"}
                  id={"edit-board-#{board.id}"}
                  class="truncate font-medium text-zinc-900 underline-offset-4 transition-colors hover:text-blue-700 hover:underline"
                >
                  {board.name}
                </.link>
                <span
                  :if={board.clue_count > 0}
                  id={"clue-count-#{board.id}"}
                  class="shrink-0 rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600"
                >
                  {board.clue_count} {if board.clue_count == 1, do: "clue", else: "clues"}
                </span>
                <span
                  :if={board.clue_count == 0}
                  id={"no-clues-#{board.id}"}
                  class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-800"
                >
                  No clues yet
                </span>
              </div>
              <div class="flex items-center gap-1">
                <form
                  :if={length(@collections) > 1}
                  id={"move-board-#{board.id}"}
                  phx-change="move_board"
                  class="mr-1"
                >
                  <input type="hidden" name="board_id" value={board.id} />
                  <label class="sr-only" for={"move-board-#{board.id}-select"}>Collection</label>
                  <select
                    id={"move-board-#{board.id}-select"}
                    name="collection_id"
                    class="rounded-md border border-zinc-300 bg-white py-1 pr-7 pl-2 text-sm text-zinc-700"
                  >
                    <option
                      :for={c <- @collections}
                      value={c.id}
                      selected={c.id == collection.id}
                    >
                      {c.name}
                    </option>
                  </select>
                </form>
                <.icon_button
                  id={"rename-board-#{board.id}"}
                  icon="hero-pencil-square"
                  label="Rename"
                  phx-click="edit_board"
                  phx-value-id={board.id}
                />
                <.icon_button
                  id={"delete-board-#{board.id}"}
                  icon="hero-trash"
                  label="Delete"
                  danger
                  phx-click="delete_board"
                  phx-value-id={board.id}
                  data-confirm={"Delete the board \"#{board.name}\" and all its clues?"}
                />
              </div>
            <% end %>
          </li>

          <li :if={@editing == {:new_board, collection.id}} class="py-2.5">
            <.name_form form={@form} id="board-form" placeholder="Board name" />
          </li>
        </ul>

        <p
          :if={collection.boards == [] and @editing != {:new_board, collection.id}}
          id={"collection-empty-#{collection.id}"}
          class="mt-2 text-sm text-zinc-500"
        >
          No boards in this collection yet.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true
  attr :placeholder, :string, required: true

  defp name_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-change="validate"
      phx-submit="save"
      class="flex flex-1 items-start gap-2"
    >
      <div class="flex-1">
        <.input
          field={@form[:name]}
          placeholder={@placeholder}
          autocomplete="off"
          phx-mounted={JS.focus()}
        />
      </div>
      <.button variant="primary">Save</.button>
      <.button type="button" phx-click="cancel">Cancel</.button>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :title, :string, default: nil, doc: "tooltip; defaults to the label"
  attr :rest, :global, include: ~w(disabled)

  defp icon_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      aria-label={@label}
      title={@title || @label}
      class={[
        "cursor-pointer rounded-md p-1.5 text-zinc-500 transition-colors disabled:cursor-not-allowed disabled:opacity-30",
        if(@danger,
          do:
            "hover:bg-red-50 hover:text-red-700 disabled:hover:bg-transparent disabled:hover:text-zinc-500",
          else: "hover:bg-zinc-100 hover:text-zinc-900"
        )
      ]}
      {@rest}
    >
      <.icon name={@icon} class="size-5" />
    </button>
    """
  end

  ## Opening and closing forms

  @impl true
  def handle_event("new_collection", _params, socket) do
    {:noreply, edit(socket, :new_collection, Boards.change_collection(%Collection{}))}
  end

  def handle_event("edit_collection", %{"id" => id}, socket) do
    collection = Boards.get_collection!(id)
    {:noreply, edit(socket, {:collection, collection.id}, Boards.change_collection(collection))}
  end

  def handle_event("new_board", %{"collection" => id}, socket) do
    collection = Boards.get_collection!(id)
    board = %Board{collection_id: collection.id}
    {:noreply, edit(socket, {:new_board, collection.id}, Boards.change_board_name(board))}
  end

  def handle_event("edit_board", %{"id" => id}, socket) do
    board = Boards.get_board_summary!(id)
    {:noreply, edit(socket, {:board, board.id}, Boards.change_board_name(board))}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, form: nil)}
  end

  ## Saving

  # A form submitted after it was closed (e.g. a double click) has nothing
  # to save.
  def handle_event(event, _params, %{assigns: %{editing: nil}} = socket)
      when event in ["validate", "save"],
      do: {:noreply, socket}

  def handle_event("validate", params, socket) do
    changeset =
      socket.assigns.editing
      |> subject()
      |> changeset(form_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", params, socket) do
    case save(socket.assigns.editing, form_params(params)) do
      {:ok, message} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(editing: nil, form: nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  ## Moving and deleting

  def handle_event(
        "move_board",
        %{"board_id" => board_id, "collection_id" => collection_id},
        socket
      ) do
    board = Boards.get_board_summary!(board_id)
    collection = Boards.get_collection!(collection_id)

    socket =
      case Boards.move_board(board, collection) do
        {:ok, _} ->
          put_flash(socket, :info, "Moved \"#{board.name}\" to \"#{collection.name}\".")

        {:error, changeset} ->
          put_flash(socket, :error, "Couldn't move \"#{board.name}\": #{first_error(changeset)}.")
      end

    {:noreply, load(socket)}
  end

  def handle_event("delete_collection", %{"id" => id}, socket) do
    collection = Boards.get_collection!(id)

    socket =
      case Boards.delete_collection(collection) do
        {:ok, _} ->
          put_flash(socket, :info, "Deleted the collection \"#{collection.name}\".")

        {:error, changeset} ->
          put_flash(socket, :error, "\"#{collection.name}\" #{first_error(changeset)}.")
      end

    {:noreply, load(socket)}
  end

  def handle_event("delete_board", %{"id" => id}, socket) do
    board = Boards.get_board_summary!(id)
    {:ok, _} = Boards.delete_board(board)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted the board \"#{board.name}\".")
     |> load()}
  end

  ## Helpers

  defp load(socket), do: assign(socket, :collections, Boards.list_collections_with_boards())

  defp edit(socket, editing, changeset),
    do: assign(socket, editing: editing, form: to_form(changeset))

  defp form_params(%{"collection" => params}), do: params
  defp form_params(%{"board" => params}), do: params
  defp form_params(_params), do: %{}

  defp subject(:new_collection), do: %Collection{}
  defp subject({:collection, id}), do: Boards.get_collection!(id)
  defp subject({:new_board, collection_id}), do: %Board{collection_id: collection_id}
  defp subject({:board, id}), do: Boards.get_board_summary!(id)

  defp changeset(%Collection{} = collection, params),
    do: Boards.change_collection(collection, params)

  defp changeset(%Board{} = board, params), do: Boards.change_board_name(board, params)

  defp save(:new_collection, params) do
    with {:ok, collection} <- Boards.create_collection(params),
         do: {:ok, "Created the collection \"#{collection.name}\"."}
  end

  defp save({:collection, id}, params) do
    with {:ok, collection} <- Boards.update_collection(Boards.get_collection!(id), params),
         do: {:ok, "Renamed the collection to \"#{collection.name}\"."}
  end

  defp save({:new_board, collection_id}, params) do
    collection = Boards.get_collection!(collection_id)

    with {:ok, board} <- Boards.create_board(collection, Map.take(params, ["name"])),
         do: {:ok, "Created the board \"#{board.name}\" in \"#{collection.name}\"."}
  end

  defp save({:board, id}, params) do
    with {:ok, board} <- Boards.rename_board(Boards.get_board_summary!(id), params),
         do: {:ok, "Renamed the board to \"#{board.name}\"."}
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> List.first()
  end
end
