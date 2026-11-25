defmodule CluebertWeb.HostLive do
  @moduledoc """
  The host screen for a game, at `/games/:id/host` (ADR 8).

  Shows the board, the play order with scores, and the current team. The
  host clicks the clue the current team calls out (ADR 2), sees its prompt
  and response, and marks it Correct or Incorrect (ADR 3). End Game
  is always available until the game is over.

  Every change goes through `Cluebert.GameServer`; this view renders what it
  returns and what it broadcasts, so it stays in sync with other screens.
  """
  use CluebertWeb, :live_view

  import CluebertWeb.GameComponents

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
        <div class="mt-4"><.standings game={@game} /></div>
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
        <div class="mt-6 flex justify-end gap-3">
          <button
            id="judge-correct"
            phx-click="judge"
            phx-value-result="correct"
            class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-emerald-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-500"
          >
            <.icon name="hero-check" class="size-5" /> Correct
          </button>
          <button
            id="judge-incorrect"
            phx-click="judge"
            phx-value-result="incorrect"
            class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-red-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-red-500"
          >
            <.icon name="hero-x-mark" class="size-5" /> Incorrect
          </button>
        </div>
      </section>

      <.board board={@board} game={@game} selectable />
    </Layouts.app>
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
        "incorrect" -> :wrong
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
end
