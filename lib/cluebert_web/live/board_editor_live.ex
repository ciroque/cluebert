defmodule CluebertWeb.BoardEditorLive do
  @moduledoc """
  The board editor at `/boards/:id` (ADR 9): a board's categories and clues.

  Categories are listed in board order (top to bottom here is left to right
  on the board), each with its clues in row order. Categories and clues can
  be added, edited, deleted and moved up or down. New clues suggest a value
  of 100 times their row. Editing never affects a game in progress (ADR 5).

  One inline form is open at a time; `@editing` says which:
  `:new_category`, `{:category, id}`, `{:new_clue, category_id}` or
  `{:clue, id}`. Every action looks its record up within this board first,
  so a stale or foreign id is refused rather than edited.
  """
  use CluebertWeb, :live_view

  alias Cluebert.Boards
  alias Cluebert.Boards.{Category, Clue}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load_board(id) do
      {:ok, board} ->
        {:ok,
         socket
         |> assign(:board, board)
         |> assign(:page_title, "Edit · #{board.name}")
         |> assign(editing: nil, form: nil)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That board doesn't exist.")
         |> push_navigate(to: ~p"/boards")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <nav id="breadcrumb" class="flex items-center gap-1.5 text-sm text-zinc-500">
        <.link navigate={~p"/boards"} class="hover:text-zinc-900">Boards</.link>
        <.icon name="hero-chevron-right-mini" class="size-4" />
        <span>{@board.collection.name}</span>
      </nav>

      <.header>
        {@board.name}
        <:subtitle>
          <span id="board-summary">
            {plural(length(@board.categories), "category", "categories")} · {plural(
              clue_count(@board),
              "clue",
              "clues"
            )}
          </span>
        </:subtitle>
        <:actions>
          <.button id="new-category" variant="primary" phx-click="new_category">
            <.icon name="hero-plus" class="size-4" /> Add category
          </.button>
        </:actions>
      </.header>

      <p
        :if={clue_count(@board) == 0}
        id="not-playable"
        class="flex items-center gap-2 rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        Add at least one clue before this board can be played.
      </p>

      <p :if={@board.categories != []} class="text-sm text-zinc-500">
        Categories appear on the board left to right in this order; clues top to bottom.
      </p>

      <section
        :for={{category, index} <- Enum.with_index(@board.categories)}
        id={"category-#{category.id}"}
        class="rounded-xl border border-zinc-200 bg-white p-5 shadow-sm"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <%= if @editing == {:category, category.id} do %>
            <.category_form form={@form} />
          <% else %>
            <h2 class="text-lg font-semibold">{category.title}</h2>
            <div class="flex items-center gap-1">
              <.icon_button
                id={"move-category-up-#{category.id}"}
                icon="hero-chevron-up"
                label="Move earlier"
                phx-click="move_category"
                phx-value-id={category.id}
                phx-value-direction="up"
                disabled={index == 0}
              />
              <.icon_button
                id={"move-category-down-#{category.id}"}
                icon="hero-chevron-down"
                label="Move later"
                phx-click="move_category"
                phx-value-id={category.id}
                phx-value-direction="down"
                disabled={index == length(@board.categories) - 1}
              />
              <.icon_button
                id={"new-clue-#{category.id}"}
                icon="hero-plus"
                label="Add clue"
                phx-click="new_clue"
                phx-value-category={category.id}
              />
              <.icon_button
                id={"rename-category-#{category.id}"}
                icon="hero-pencil-square"
                label="Rename"
                phx-click="edit_category"
                phx-value-id={category.id}
              />
              <.icon_button
                id={"delete-category-#{category.id}"}
                icon="hero-trash"
                label="Delete"
                danger
                phx-click="delete_category"
                phx-value-id={category.id}
                data-confirm={"Delete \"#{category.title}\" and its #{plural(length(category.clues), "clue", "clues")}?"}
              />
            </div>
          <% end %>
        </div>

        <ol class="mt-3 divide-y divide-zinc-100">
          <li
            :for={{clue, row} <- Enum.with_index(category.clues)}
            id={"clue-#{clue.id}"}
            class="py-3"
          >
            <%= if @editing == {:clue, clue.id} do %>
              <.clue_form form={@form} />
            <% else %>
              <div class="flex items-start gap-3">
                <span class="mt-0.5 w-14 shrink-0 rounded-md bg-blue-900 py-1 text-center text-sm font-bold text-amber-300 tabular-nums">
                  {clue.value}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="font-medium text-zinc-900">{clue.prompt}</p>
                  <p class="mt-0.5 text-sm text-emerald-800">{clue.response}</p>
                </div>
                <div class="flex shrink-0 items-center gap-1">
                  <.icon_button
                    id={"move-clue-up-#{clue.id}"}
                    icon="hero-chevron-up"
                    label="Move up"
                    phx-click="move_clue"
                    phx-value-id={clue.id}
                    phx-value-direction="up"
                    disabled={row == 0}
                  />
                  <.icon_button
                    id={"move-clue-down-#{clue.id}"}
                    icon="hero-chevron-down"
                    label="Move down"
                    phx-click="move_clue"
                    phx-value-id={clue.id}
                    phx-value-direction="down"
                    disabled={row == length(category.clues) - 1}
                  />
                  <.icon_button
                    id={"edit-clue-#{clue.id}"}
                    icon="hero-pencil-square"
                    label="Edit"
                    phx-click="edit_clue"
                    phx-value-id={clue.id}
                  />
                  <.icon_button
                    id={"delete-clue-#{clue.id}"}
                    icon="hero-trash"
                    label="Delete"
                    danger
                    phx-click="delete_clue"
                    phx-value-id={clue.id}
                    data-confirm="Delete this clue?"
                  />
                </div>
              </div>
            <% end %>
          </li>

          <li :if={@editing == {:new_clue, category.id}} class="py-3">
            <.clue_form form={@form} />
          </li>
        </ol>

        <p
          :if={category.clues == [] and @editing != {:new_clue, category.id}}
          id={"category-empty-#{category.id}"}
          class="mt-2 text-sm text-zinc-500"
        >
          No clues yet.
        </p>
      </section>

      <div :if={@editing == :new_category} class="rounded-xl border border-blue-200 bg-blue-50 p-4">
        <.category_form form={@form} />
      </div>

      <p
        :if={@board.categories == [] and @editing != :new_category}
        id="no-categories"
        class="text-zinc-500"
      >
        No categories yet. Each category is a column on the board.
      </p>
    </Layouts.app>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp category_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="category-form"
      phx-change="validate"
      phx-submit="save"
      class="flex flex-1 items-start gap-2"
    >
      <div class="flex-1">
        <.input
          field={@form[:title]}
          placeholder="Category title"
          autocomplete="off"
          phx-mounted={JS.focus()}
        />
      </div>
      <.button variant="primary">Save</.button>
      <.button type="button" phx-click="cancel">Cancel</.button>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp clue_form(assigns) do
    ~H"""
    <.form for={@form} id="clue-form" phx-change="validate" phx-submit="save" class="space-y-1">
      <.input field={@form[:prompt]} type="textarea" label="Prompt" rows="2" phx-mounted={JS.focus()} />
      <div class="grid gap-3 sm:grid-cols-[1fr_8rem]">
        <.input field={@form[:response]} label="Response" autocomplete="off" />
        <.input field={@form[:value]} type="number" label="Value" min="0" step="1" />
      </div>
      <div class="flex justify-end gap-2">
        <.button type="button" phx-click="cancel">Cancel</.button>
        <.button variant="primary">Save</.button>
      </div>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :rest, :global, include: ~w(disabled)

  defp icon_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      aria-label={@label}
      title={@label}
      class={[
        "cursor-pointer rounded-md p-1.5 text-zinc-500 transition-colors disabled:cursor-not-allowed disabled:opacity-30",
        if(@danger,
          do: "hover:bg-red-50 hover:text-red-700 disabled:hover:bg-transparent",
          else: "hover:bg-zinc-100 hover:text-zinc-900 disabled:hover:bg-transparent"
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
  def handle_event("new_category", _params, socket) do
    category = %Category{board_id: socket.assigns.board.id}
    {:noreply, edit(socket, :new_category, Boards.change_category(category))}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    with_category(socket, id, fn category ->
      edit(socket, {:category, category.id}, Boards.change_category(category))
    end)
  end

  def handle_event("new_clue", %{"category" => id}, socket) do
    with_category(socket, id, fn category ->
      edit(socket, {:new_clue, category.id}, Boards.change_clue(Boards.new_clue(category)))
    end)
  end

  def handle_event("edit_clue", %{"id" => id}, socket) do
    with_clue(socket, id, fn clue ->
      edit(socket, {:clue, clue.id}, Boards.change_clue(clue))
    end)
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
    case subject(socket) do
      nil ->
        {:noreply, gone(socket)}

      subject ->
        changeset = subject |> changeset(form_params(params)) |> Map.put(:action, :validate)
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("save", params, socket) do
    case save(socket, form_params(params)) do
      {:ok, _} ->
        {:noreply, socket |> assign(editing: nil, form: nil) |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      :gone ->
        {:noreply, gone(socket)}
    end
  end

  ## Moving and deleting

  def handle_event("move_category", %{"id" => id, "direction" => direction}, socket) do
    with_category(socket, id, fn category ->
      {:ok, _} = Boards.move_category(category, direction(direction))
      reload(socket)
    end)
  end

  def handle_event("move_clue", %{"id" => id, "direction" => direction}, socket) do
    with_clue(socket, id, fn clue ->
      {:ok, _} = Boards.move_clue(clue, direction(direction))
      reload(socket)
    end)
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    with_category(socket, id, fn category ->
      {:ok, _} = Boards.delete_category(category)

      socket
      |> put_flash(:info, "Deleted the category \"#{category.title}\".")
      |> close_form_for({:category, category.id})
      |> reload()
    end)
  end

  def handle_event("delete_clue", %{"id" => id}, socket) do
    with_clue(socket, id, fn clue ->
      {:ok, _} = Boards.delete_clue(clue)

      socket
      |> put_flash(:info, "Deleted the clue.")
      |> close_form_for({:clue, clue.id})
      |> reload()
    end)
  end

  ## Helpers

  defp load_board(id) do
    with {id, ""} <- Integer.parse(id) do
      {:ok, Boards.get_board_for_editing!(id)}
    else
      _ -> :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  defp reload(socket) do
    case load_board(to_string(socket.assigns.board.id)) do
      {:ok, board} ->
        assign(socket, :board, board)

      :error ->
        socket
        |> put_flash(:error, "That board no longer exists.")
        |> push_navigate(to: ~p"/boards")
    end
  end

  defp edit(socket, editing, changeset),
    do: assign(socket, editing: editing, form: to_form(changeset))

  defp close_form_for(%{assigns: %{editing: editing}} = socket, editing),
    do: assign(socket, editing: nil, form: nil)

  defp close_form_for(socket, _deleted), do: socket

  # Runs `fun` with the category if it belongs to this board, otherwise
  # explains and reloads. Membership is checked against the loaded board;
  # the record itself is read fresh, so moves use current positions even if
  # another tab changed them.
  defp with_category(socket, id, fun) do
    with %Category{id: id} <- find_category(socket, id),
         %Category{} = category <- fresh(fn -> Boards.get_category!(id) end) do
      {:noreply, fun.(category)}
    else
      nil -> {:noreply, gone(socket)}
    end
  end

  defp with_clue(socket, id, fun) do
    with %Clue{id: id} <- find_clue(socket, id),
         %Clue{} = clue <- fresh(fn -> Boards.get_clue!(id) end) do
      {:noreply, fun.(clue)}
    else
      nil -> {:noreply, gone(socket)}
    end
  end

  defp fresh(get) do
    get.()
  rescue
    Ecto.NoResultsError -> nil
  end

  defp find_category(socket, id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Category{} = category <- Enum.find(socket.assigns.board.categories, &(&1.id == id)) do
      category
    else
      _ -> nil
    end
  end

  defp find_clue(socket, id) do
    with {id, ""} <- Integer.parse(to_string(id)) do
      socket.assigns.board.categories
      |> Enum.flat_map(& &1.clues)
      |> Enum.find(&(&1.id == id))
    else
      _ -> nil
    end
  end

  defp gone(socket) do
    socket
    |> put_flash(:error, "That item no longer exists.")
    |> assign(editing: nil, form: nil)
    |> reload()
  end

  defp direction("up"), do: :up
  defp direction(_down), do: :down

  defp form_params(%{"category" => params}), do: params
  defp form_params(%{"clue" => params}), do: params
  defp form_params(_params), do: %{}

  defp subject(%{assigns: %{editing: :new_category, board: board}}),
    do: %Category{board_id: board.id}

  defp subject(%{assigns: %{editing: {:category, id}}} = socket), do: find_category(socket, id)

  defp subject(%{assigns: %{editing: {:new_clue, category_id}}} = socket) do
    if category = find_category(socket, category_id), do: Boards.new_clue(category)
  end

  defp subject(%{assigns: %{editing: {:clue, id}}} = socket), do: find_clue(socket, id)

  defp changeset(%Category{} = category, params), do: Boards.change_category(category, params)
  defp changeset(%Clue{} = clue, params), do: Boards.change_clue(clue, params)

  defp save(%{assigns: %{editing: :new_category, board: board}}, params),
    do: Boards.create_category(board, params)

  defp save(%{assigns: %{editing: {:category, id}}} = socket, params) do
    if category = find_category(socket, id),
      do: Boards.update_category(category, params),
      else: :gone
  end

  defp save(%{assigns: %{editing: {:new_clue, category_id}}} = socket, params) do
    if category = find_category(socket, category_id),
      do: Boards.create_clue(category, params),
      else: :gone
  end

  defp save(%{assigns: %{editing: {:clue, id}}} = socket, params) do
    if clue = find_clue(socket, id),
      do: Boards.update_clue(clue, params),
      else: :gone
  end

  defp clue_count(board), do: Enum.sum_by(board.categories, &length(&1.clues))

  defp plural(1, singular, _plural), do: "1 #{singular}"
  defp plural(n, _singular, plural), do: "#{n} #{plural}"
end
