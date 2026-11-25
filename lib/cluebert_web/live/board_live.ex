defmodule CluebertWeb.BoardLive do
  @moduledoc """
  The player screen for a game, at `/games/:id` (ADR 8): what the room sees,
  full-screen on a TV.

  Display only. It shows the board with answered clues checked off, the play
  order with scores and the current team, and the open clue's prompt
  covering the screen. Responses are never sent to this screen. It follows
  the game through `Cluebert.GameServer` broadcasts.

  When the host starts a new game from this one, the screen switches to the
  new game by itself, so the window on the TV can stay open between games.
  """
  use CluebertWeb, :live_view

  import CluebertWeb.GameComponents

  alias Cluebert.GameServer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case GameServer.get(id) do
      {:ok, %{game: game, board: board}} ->
        if connected?(socket), do: GameServer.subscribe(id)

        {:ok,
         socket
         |> assign(:page_title, board.name)
         |> assign(:game_id, id)
         |> assign(:board, board)
         |> assign(:clues, clues_by_id(board))
         |> assign(:game, game)}

      {:error, :not_found} ->
        {:ok, socket |> assign(:page_title, "Game not found") |> assign(:game, nil)}
    end
  end

  @impl true
  def render(%{game: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <div
        id="game-missing"
        class="flex min-h-screen flex-col items-center justify-center gap-4 bg-blue-950 p-8 text-center text-white"
      >
        <h1 class="text-4xl font-bold">Game not found</h1>
        <p class="text-lg text-blue-200">This game has ended or never existed.</p>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <div id="board-screen" class="min-h-screen space-y-6 bg-blue-950 p-6 text-white lg:p-10">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <h1 class="text-2xl font-bold tracking-tight lg:text-3xl">{@board.name}</h1>
          <.scoreboard game={@game} />
        </div>

        <.board board={@board} game={@game} />

        <section
          :if={@game.open_clue}
          id="open-clue"
          class="fixed inset-0 z-40 flex flex-col items-center justify-center gap-8 bg-blue-900 p-10 text-center"
        >
          <p class="text-xl font-semibold uppercase tracking-widest text-amber-300 lg:text-2xl">
            {@clues[@game.open_clue].category} · {@clues[@game.open_clue].value}
          </p>
          <p
            id="open-clue-prompt"
            class="max-w-5xl text-4xl font-bold leading-tight text-white lg:text-6xl"
          >
            {@clues[@game.open_clue].prompt}
          </p>
        </section>

        <section
          :if={@game.phase == :done}
          id="game-over"
          class="fixed inset-0 z-40 flex flex-col items-center justify-center gap-8 bg-blue-950/95 p-10 text-center"
        >
          <h2 class="text-5xl font-bold lg:text-6xl">Game over</h2>
          <div class="w-full max-w-md text-xl"><.standings game={@game} /></div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:game_updated, id, game}, %{assigns: %{game_id: id}} = socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:next_game, id, next_id}, %{assigns: %{game_id: id}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/#{next_id}")}
  end
end
