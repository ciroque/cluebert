defmodule CluebertWeb.HostLive do
  @moduledoc """
  The host screen for a game, at `/games/:id/host` (ADR 8).

  Shows the board, the play order with scores, and the current team. The
  host clicks the clue the current team calls out (ADR 2), sees its prompt
  and response, and marks it Correct or Wrong on the tile (ADR 3). End Game
  is always available until the game is over.

  Every change goes through `Cluebert.GameServer`; this view renders what it
  returns and what it broadcasts, so it stays in sync with other screens.
  """
  use CluebertWeb, :live_view

  alias Cluebert.{Game, GameServer}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case GameServer.get(id) do
      {:ok, %{game: game, board: board}} ->
        if connected?(socket), do: GameServer.subscribe(id)

        {:ok,
         socket
         |> assign(:page_title, "Host · #{board.name}")
         |> assign(:game_id, id)
         |> assign(:board, board)
         |> assign(:rows, rows(board))
         |> assign(:clues, clues_by_id(board))
         |> assign(:game, game)}

      {:error, :not_found} ->
        {:ok, game_gone(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="text-sm font-medium uppercase tracking-wide text-zinc-500">Host</p>
          <h1 class="text-2xl font-bold tracking-tight">{@board.name}</h1>
        </div>
        <.button
          :if={@game.phase != :done}
          id="end-game"
          phx-click="end_game"
          data-confirm="End the game now? Scores will be final."
          class="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-zinc-300 bg-white px-4 py-2 text-sm font-semibold text-zinc-700 shadow-sm transition-colors hover:border-red-300 hover:bg-red-50 hover:text-red-700"
        >
          <.icon name="hero-flag" class="size-4" /> End game
        </.button>
      </div>

      <.scoreboard game={@game} />

      <section
        :if={@game.phase == :done}
        id="game-over"
        class="rounded-xl border border-zinc-200 bg-white p-6 text-center shadow-sm"
      >
        <h2 class="text-2xl font-bold">Game over</h2>
        <ol id="final-standings" class="mx-auto mt-4 max-w-sm space-y-2 text-left">
          <li
            :for={{team_id, place} <- standings(@game)}
            id={"standing-#{team_id}"}
            class="flex items-center justify-between rounded-lg bg-zinc-50 px-4 py-2"
          >
            <span class="font-medium">{place}. {@game.teams[team_id].name}</span>
            <span class="font-semibold tabular-nums">{@game.scores[team_id]}</span>
          </li>
        </ol>
        <.link
          navigate={~p"/"}
          id="new-game"
          class="mt-6 inline-flex items-center gap-2 rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-blue-700"
        >
          New game <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </section>

      <section
        :if={@game.open_clue}
        id="open-clue"
        class="rounded-xl border-2 border-blue-600 bg-white p-6 shadow-md"
      >
        <p class="text-sm font-medium uppercase tracking-wide text-blue-700">
          {@clues[@game.open_clue].category} · {@clues[@game.open_clue].value}
        </p>
        <p id="open-clue-prompt" class="mt-2 text-xl font-semibold">
          {@clues[@game.open_clue].prompt}
        </p>
        <p class="mt-4 text-sm font-medium uppercase tracking-wide text-zinc-500">Response</p>
        <p id="open-clue-response" class="mt-1 text-lg text-emerald-800">
          {@clues[@game.open_clue].response}
        </p>
        <p class="mt-4 text-sm text-zinc-500">Mark the response on the highlighted tile.</p>
      </section>

      <div
        id="board"
        class="grid gap-2"
        style={"grid-template-columns: repeat(#{length(@board.categories)}, minmax(0, 1fr))"}
      >
        <div
          :for={category <- @board.categories}
          id={"category-#{category.id}"}
          class="flex min-h-16 items-center justify-center rounded-lg bg-blue-900 p-2 text-center text-sm font-bold uppercase tracking-wide text-white"
        >
          {category.title}
        </div>

        <%= for row <- 0..(@rows - 1)//1, category <- @board.categories do %>
          <.tile
            clue={Enum.at(category.clues, row)}
            empty_id={"empty-#{category.id}-#{row}"}
            game={@game}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :game, Game, required: true

  defp scoreboard(assigns) do
    ~H"""
    <ol id="scoreboard" class="flex flex-wrap gap-2">
      <li
        :for={team_id <- @game.team_order}
        id={"team-#{team_id}"}
        aria-current={to_string(team_id == Game.current_team(@game))}
        class={[
          "flex items-center gap-3 rounded-lg px-4 py-2 shadow-sm ring-1 transition-colors",
          if(team_id == Game.current_team(@game),
            do: "bg-blue-600 text-white ring-blue-600",
            else: "bg-white text-zinc-900 ring-zinc-200"
          )
        ]}
      >
        <span class="font-medium">{@game.teams[team_id].name}</span>
        <span class="font-bold tabular-nums">{@game.scores[team_id]}</span>
      </li>
    </ol>
    """
  end

  attr :clue, :any, required: true
  attr :empty_id, :string, required: true
  attr :game, Game, required: true

  defp tile(%{clue: nil} = assigns) do
    ~H"""
    <div id={@empty_id} class="min-h-20 rounded-lg bg-zinc-100"></div>
    """
  end

  defp tile(assigns) do
    assigns = assign(assigns, :state, tile_state(assigns.game, assigns.clue.id))

    ~H"""
    <div
      :if={@state == :answered}
      id={"clue-#{@clue.id}"}
      data-state="answered"
      class="flex min-h-20 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700"
    >
      <.icon name="hero-check-circle-solid" class="size-8" />
      <span class="sr-only">Answered</span>
    </div>

    <div
      :if={@state == :open}
      id={"clue-#{@clue.id}"}
      data-state="open"
      class="flex min-h-20 flex-col items-center justify-center gap-2 rounded-lg bg-blue-600 p-2 text-white ring-4 ring-blue-300"
    >
      <span class="text-lg font-bold tabular-nums">{@clue.value}</span>
      <div class="flex gap-2">
        <button
          id="judge-correct"
          phx-click="judge"
          phx-value-result="correct"
          class="inline-flex cursor-pointer items-center gap-1 rounded-md bg-emerald-500 px-2.5 py-1 text-xs font-semibold text-white transition-colors hover:bg-emerald-400"
        >
          <.icon name="hero-check" class="size-4" /> Correct
        </button>
        <button
          id="judge-wrong"
          phx-click="judge"
          phx-value-result="wrong"
          class="inline-flex cursor-pointer items-center gap-1 rounded-md bg-red-500 px-2.5 py-1 text-xs font-semibold text-white transition-colors hover:bg-red-400"
        >
          <.icon name="hero-x-mark" class="size-4" /> Wrong
        </button>
      </div>
    </div>

    <button
      :if={@state in [:available, :locked]}
      id={"clue-#{@clue.id}"}
      data-state={@state}
      phx-click="select"
      phx-value-clue={@clue.id}
      disabled={@state == :locked}
      class="min-h-20 cursor-pointer rounded-lg bg-blue-800 text-2xl font-bold text-amber-300 tabular-nums shadow-sm transition hover:-translate-y-0.5 hover:bg-blue-700 hover:shadow-md disabled:cursor-default disabled:opacity-40 disabled:hover:translate-y-0 disabled:hover:bg-blue-800 disabled:hover:shadow-sm"
    >
      {@clue.value}
    </button>
    """
  end

  @impl true
  def handle_event("select", %{"clue" => clue_id}, socket) do
    %{game: game, game_id: id} = socket.assigns

    socket
    |> apply_result(GameServer.select(id, Game.current_team(game), String.to_integer(clue_id)))
    |> noreply()
  end

  def handle_event("judge", %{"result" => result}, socket) do
    judgment =
      case result do
        "correct" -> :correct
        "wrong" -> :wrong
        _ -> :invalid
      end

    socket
    |> apply_result(GameServer.judge(socket.assigns.game_id, judgment))
    |> noreply()
  end

  def handle_event("end_game", _params, socket) do
    socket
    |> apply_result(GameServer.end_game(socket.assigns.game_id))
    |> noreply()
  end

  @impl true
  def handle_info({:game_updated, id, game}, %{assigns: %{game_id: id}} = socket) do
    {:noreply, assign(socket, :game, game)}
  end

  defp apply_result(socket, {:ok, game}), do: assign(socket, :game, game)
  defp apply_result(socket, {:error, :not_found}), do: game_gone(socket)

  # Another screen may have moved the game on; show the error and catch up.
  defp apply_result(socket, {:error, _reason}) do
    case GameServer.get(socket.assigns.game_id) do
      {:ok, %{game: game}} ->
        socket
        |> put_flash(:error, "That move isn't allowed right now.")
        |> assign(:game, game)

      {:error, :not_found} ->
        game_gone(socket)
    end
  end

  defp noreply(socket), do: {:noreply, socket}

  defp game_gone(socket) do
    socket
    |> put_flash(:error, "That game no longer exists.")
    |> push_navigate(to: ~p"/")
  end

  defp tile_state(game, clue_id) do
    cond do
      MapSet.member?(game.answered, clue_id) -> :answered
      game.open_clue == clue_id -> :open
      game.phase == :selecting -> :available
      true -> :locked
    end
  end

  defp rows(board), do: board.categories |> Enum.map(&length(&1.clues)) |> Enum.max(fn -> 0 end)

  defp clues_by_id(board) do
    for category <- board.categories, clue <- category.clues, into: %{} do
      {clue.id, Map.put(Map.take(clue, [:prompt, :response, :value]), :category, category.title)}
    end
  end

  # Teams by score, highest first; ties keep play order and share a place.
  defp standings(game) do
    sorted = Enum.sort_by(game.team_order, &game.scores[&1], :desc)

    for team_id <- sorted do
      score = game.scores[team_id]
      {team_id, Enum.find_index(sorted, &(game.scores[&1] == score)) + 1}
    end
  end
end
