defmodule CluebertWeb.SetupLive do
  @moduledoc """
  The setup page at `/` (ADR 8).

  The host adds team names and chooses a board, in any order. Names are kept
  here until Start and are checked with `Cluebert.Game.check_team_name/2`,
  so the naming rule stays in the rules module. Start creates a game that is
  already playing and goes to its host screen.

  When the host comes here from a finished game (`/?from=<game id>`), its
  teams are filled in, in the order they were entered, ready to edit or
  clear. Start also announces the new game to that game's subscribers, so a
  player screen still open on it switches to the new game.
  """
  use CluebertWeb, :live_view

  alias Cluebert.{Boards, Game, GameServer}

  @impl true
  def mount(params, _session, socket) do
    boards = Boards.list_boards()

    {:ok,
     socket
     |> assign(:page_title, "New game")
     |> assign(:from, params["from"])
     |> assign(:boards, boards)
     |> assign(:board_id, boards |> List.first() |> then(&(&1 && &1.id)))
     |> assign_carried_over_teams(params["from"])
     |> assign(:min_teams, Game.min_teams())
     |> assign_team_form(%{"name" => ""})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        New game
        <:subtitle>
          Add the teams and pick a board. The play order is drawn at random when you start.
        </:subtitle>
      </.header>

      <div class="grid gap-8 md:grid-cols-2">
        <section id="teams-section" class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-500">Teams</h2>
            <button
              :if={@teams != []}
              id="clear-teams"
              type="button"
              phx-click="clear_teams"
              class="cursor-pointer text-sm font-medium text-zinc-500 transition-colors hover:text-red-700"
            >
              Clear all
            </button>
          </div>
          <p
            :if={@carried_over}
            id="teams-carried-over"
            class="mb-3 flex items-center gap-2 rounded-lg bg-blue-50 px-3 py-2 text-sm text-blue-900"
          >
            <.icon name="hero-arrow-path" class="size-4 shrink-0" />
            Teams from the last game. Edit them or clear them for a new group.
          </p>

          <.form
            for={@team_form}
            id="team-form"
            phx-change="validate_team"
            phx-submit="add_team"
            class="flex items-start gap-2"
          >
            <div class="flex-1">
              <.input field={@team_form[:name]} placeholder="Team name" autocomplete="off" />
            </div>
            <.button id="add-team" variant="primary">Add</.button>
          </.form>

          <ol id="teams" class="mt-2 space-y-2">
            <li
              :for={{name, index} <- Enum.with_index(@teams)}
              id={"team-#{index}"}
              class="group flex items-center justify-between rounded-lg bg-zinc-50 px-3 py-2 transition-colors hover:bg-zinc-100"
            >
              <span class="font-medium text-zinc-900">{name}</span>
              <button
                id={"remove-team-#{index}"}
                type="button"
                phx-click="remove_team"
                phx-value-index={index}
                aria-label={"Remove #{name}"}
                class="cursor-pointer rounded p-1 text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </li>
          </ol>
          <p :if={length(@teams) < @min_teams} id="teams-needed" class="mt-2 text-sm text-zinc-500">
            Add at least {@min_teams} teams to start. A single player is a team of one.
          </p>
        </section>

        <section id="boards-section" class="rounded-xl border border-zinc-200 bg-white p-6 shadow-sm">
          <h2 class="mb-4 text-sm font-semibold uppercase tracking-wide text-zinc-500">Board</h2>

          <div :if={@boards != []} id="boards" class="space-y-2">
            <button
              :for={board <- @boards}
              id={"board-#{board.id}"}
              type="button"
              phx-click="choose_board"
              phx-value-id={board.id}
              aria-pressed={to_string(board.id == @board_id)}
              class={[
                "flex w-full cursor-pointer items-center justify-between rounded-lg border px-4 py-3 text-left transition-colors",
                if(board.id == @board_id,
                  do: "border-blue-600 bg-blue-50 text-blue-900 ring-1 ring-blue-600",
                  else: "border-zinc-200 hover:border-zinc-300 hover:bg-zinc-50"
                )
              ]}
            >
              <span class="font-medium">{board.name}</span>
              <.icon :if={board.id == @board_id} name="hero-check-circle-solid" class="size-5" />
            </button>
          </div>
          <p :if={@boards == []} id="no-boards" class="text-sm text-zinc-500">
            No boards yet. Add one in <code>priv/repo/seeds.exs</code>
            and run <code>mix run priv/repo/seeds.exs</code>.
          </p>
        </section>
      </div>

      <div class="flex justify-end pt-4">
        <.button
          id="start-game"
          phx-click="start"
          disabled={length(@teams) < @min_teams or is_nil(@board_id)}
          class="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-blue-600 px-6 py-3 text-base font-semibold text-white shadow-sm transition-colors hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Start game <.icon name="hero-arrow-right" class="size-5" />
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_team", %{"team" => %{"name" => name} = params}, socket) do
    # Only flag duplicates while typing; a blank field is not an error yet.
    error =
      case Game.check_team_name(socket.assigns.teams, name) do
        {:error, :duplicate_name} -> :duplicate_name
        _ -> nil
      end

    {:noreply, assign_team_form(socket, params, error)}
  end

  def handle_event("add_team", %{"team" => %{"name" => name} = params}, socket) do
    case Game.check_team_name(socket.assigns.teams, name) do
      {:ok, name} ->
        {:noreply,
         socket
         |> update(:teams, &(&1 ++ [name]))
         |> assign_team_form(%{"name" => ""})}

      {:error, reason} ->
        {:noreply, assign_team_form(socket, params, reason)}
    end
  end

  def handle_event("clear_teams", _params, socket) do
    {:noreply, assign(socket, teams: [], carried_over: false)}
  end

  def handle_event("remove_team", %{"index" => index}, socket) do
    {:noreply, update(socket, :teams, &List.delete_at(&1, String.to_integer(index)))}
  end

  def handle_event("choose_board", %{"id" => id}, socket) do
    id = String.to_integer(id)

    if Enum.any?(socket.assigns.boards, &(&1.id == id)) do
      {:noreply, assign(socket, :board_id, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start", _params, %{assigns: %{board_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Choose a board first.")}
  end

  def handle_event("start", _params, socket) do
    %{board_id: board_id, teams: teams} = socket.assigns

    case GameServer.start_game(board_id, teams) do
      {:ok, id} ->
        if from = socket.assigns.from, do: GameServer.announce_next_game(from, id)
        {:noreply, push_navigate(socket, to: ~p"/games/#{id}/host")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, start_error(reason))}
    end
  end

  # Teams of the game the host came from, in the order they were entered
  # (team ids count up), not the shuffled play order.
  defp assign_carried_over_teams(socket, nil), do: assign(socket, teams: [], carried_over: false)

  defp assign_carried_over_teams(socket, from) do
    case GameServer.get(from) do
      {:ok, %{game: game}} ->
        teams =
          game.teams |> Enum.sort_by(fn {id, _} -> id end) |> Enum.map(fn {_, t} -> t.name end)

        assign(socket, teams: teams, carried_over: teams != [])

      {:error, :not_found} ->
        assign(socket, teams: [], carried_over: false)
    end
  end

  defp assign_team_form(socket, params, error \\ nil) do
    errors = if error, do: [name: {team_name_error(error), []}], else: []
    assign(socket, :team_form, to_form(params, as: :team, errors: errors))
  end

  defp team_name_error(:invalid_name), do: "Enter a team name"
  defp team_name_error(:duplicate_name), do: "That name is already taken"

  defp start_error(:invalid_board), do: "That board has no clues yet."
  defp start_error(:too_few_teams), do: "Add at least #{Game.min_teams()} teams."
  defp start_error(_reason), do: "The game could not be started."
end
