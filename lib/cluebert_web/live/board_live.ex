defmodule CluebertWeb.BoardLive do
  @moduledoc """
  The player screen for a game, at `/games/:id` (ADR 8): what the room sees,
  full-screen on a TV.

  Display only. A button in the corner puts the window into full screen,
  and is hidden while it is (Esc leaves). It shows the board with answered clues checked off, the play
  order with scores and the current team, and the open clue's prompt
  covering the screen. Responses are never sent to this screen. It follows
  the game through `Cluebert.GameServer` broadcasts.

  When the host starts a new game from this one, the screen switches to the
  new game by itself, so the window on the TV can stay open between games.
  If the game stops instead (a finished game stops after an hour, see
  `Cluebert.GameServer`), the screen says so rather than showing a board
  that no longer changes.
  """
  use CluebertWeb, :live_view

  import CluebertWeb.GameComponents

  alias Cluebert.GameServer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case GameServer.get(id) do
      {:ok, %{game: game, board: board}} ->
        {:ok,
         socket
         |> assign(:page_title, board.name)
         |> assign(:game_id, id)
         |> assign(:board, board)
         |> assign(:clues, clues_by_id(board))
         |> assign(:game, game)
         |> watch(id)}

      {:error, :not_found} ->
        {:ok, game_gone(socket)}
    end
  end

  # Subscribe before monitoring, so no update falls between the two; a game
  # that stopped after get/1 shows as gone.
  defp watch(socket, id) do
    if connected?(socket) do
      :ok = GameServer.subscribe(id)

      case GameServer.monitor(id) do
        {:ok, _ref} -> socket
        {:error, :not_found} -> game_gone(socket)
      end
    else
      socket
    end
  end

  defp game_gone(socket), do: socket |> assign(:page_title, "Game over") |> assign(:game, nil)

  @impl true
  def render(%{game: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_screen>
      <div
        id="game-missing"
        class="flex min-h-screen flex-col items-center justify-center gap-4 bg-blue-950 p-8 text-center text-white"
      >
        <h1 class="text-4xl font-bold">No game here</h1>
        <p class="text-lg text-blue-200">
          This game has ended or never existed. Start a new one from the host screen.
        </p>
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

        <button
          id="fullscreen-button"
          type="button"
          phx-hook=".Fullscreen"
          class="fixed right-4 bottom-4 z-30 inline-flex cursor-pointer items-center gap-2 rounded-lg bg-white/10 px-3 py-2 text-sm font-medium text-blue-100 opacity-60 transition hover:bg-white/20 hover:opacity-100"
        >
          <.icon name="hero-arrows-pointing-out" class="size-5" /> Full screen
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Fullscreen">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                document.documentElement.requestFullscreen?.().catch(() => {})
              })
            }
          }
        </script>

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

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, game_gone(socket)}
  end
end
