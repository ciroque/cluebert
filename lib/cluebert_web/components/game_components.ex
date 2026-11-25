defmodule CluebertWeb.GameComponents do
  @moduledoc """
  Pieces of a running game shared by the host and player screens (ADR 8):
  the board grid, the scoreboard and the final standings.

  They only render a `%Cluebert.Game{}` and its board; they hold no rules.
  """
  use Phoenix.Component

  import CluebertWeb.CoreComponents, only: [icon: 1]

  alias Cluebert.Boards.Board
  alias Cluebert.Game

  @doc """
  Renders the board: one column per category and as many rows as the
  longest category, with empty cells below shorter ones (ADR 6).

  Each clue tile carries `data-state`: `available`, `locked` (another clue
  is open, or the game is over), `open` or `answered` (a 2% black
  with a faint checkmark, so the clues still in play stand out). With `selectable`, available tiles are buttons that send a
  `"select"` event with the clue id as `phx-value-clue`.
  """
  attr :board, Board, required: true
  attr :game, Game, required: true
  attr :selectable, :boolean, default: false

  def board(assigns) do
    assigns = assign(assigns, :rows, rows(assigns.board))

    ~H"""
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
          selectable={@selectable}
        />
      <% end %>
    </div>
    """
  end

  attr :clue, :any, required: true
  attr :empty_id, :string, required: true
  attr :game, Game, required: true
  attr :selectable, :boolean, required: true

  defp tile(%{clue: nil} = assigns) do
    ~H"""
    <div id={@empty_id} class="min-h-20 rounded-lg bg-zinc-500/10"></div>
    """
  end

  defp tile(assigns) do
    assigns = assign(assigns, :state, tile_state(assigns.game, assigns.clue.id))

    ~H"""
    <div
      :if={@state == :answered}
      id={"clue-#{@clue.id}"}
      data-state="answered"
      class="flex min-h-20 items-center justify-center rounded-lg bg-black/2 text-zinc-400/15"
    >
      <.icon name="hero-check-circle-solid" class="size-8" />
      <span class="sr-only">Answered</span>
    </div>

    <div
      :if={@state == :open}
      id={"clue-#{@clue.id}"}
      data-state="open"
      class="flex min-h-20 items-center justify-center rounded-lg bg-blue-600 text-2xl font-bold text-white tabular-nums ring-4 ring-blue-300"
    >
      {@clue.value}
    </div>

    <button
      :if={@selectable and @state in [:available, :locked]}
      id={"clue-#{@clue.id}"}
      data-state={@state}
      phx-click="select"
      phx-value-clue={@clue.id}
      disabled={@state == :locked}
      class="min-h-20 cursor-pointer rounded-lg bg-blue-800 text-2xl font-bold text-amber-300 tabular-nums shadow-sm transition hover:-translate-y-0.5 hover:bg-blue-700 hover:shadow-md disabled:cursor-default disabled:opacity-40 disabled:hover:translate-y-0 disabled:hover:bg-blue-800 disabled:hover:shadow-sm"
    >
      {@clue.value}
    </button>

    <div
      :if={not @selectable and @state in [:available, :locked]}
      id={"clue-#{@clue.id}"}
      data-state={@state}
      class={[
        "flex min-h-20 items-center justify-center rounded-lg bg-blue-800 text-2xl font-bold text-amber-300 tabular-nums shadow-sm transition-opacity",
        @state == :locked && "opacity-40"
      ]}
    >
      {@clue.value}
    </div>
    """
  end

  @doc """
  Renders the teams in play order with their scores. The current team is
  highlighted and marked with `aria-current="true"`.
  """
  attr :game, Game, required: true

  def scoreboard(assigns) do
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

  @doc """
  Renders the final standings: teams by score, highest first. Tied teams
  share a place and keep their play order.
  """
  attr :game, Game, required: true

  def standings(assigns) do
    ~H"""
    <ol id="final-standings" class="mx-auto max-w-sm space-y-2 text-left">
      <li
        :for={{team_id, place} <- places(@game)}
        id={"standing-#{team_id}"}
        class="flex items-center justify-between rounded-lg bg-zinc-50 px-4 py-2 text-zinc-900"
      >
        <span class="font-medium">{place}. {@game.teams[team_id].name}</span>
        <span class="font-semibold tabular-nums">{@game.scores[team_id]}</span>
      </li>
    </ol>
    """
  end

  @doc """
  Returns each clue on the board by id, with its prompt, response, value and
  category title, for showing the open clue.
  """
  @spec clues_by_id(Board.t()) :: %{term() => map()}
  def clues_by_id(board) do
    for category <- board.categories, clue <- category.clues, into: %{} do
      {clue.id, Map.put(Map.take(clue, [:prompt, :response, :value]), :category, category.title)}
    end
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

  defp places(game) do
    sorted = Enum.sort_by(game.team_order, &game.scores[&1], :desc)

    for team_id <- sorted do
      score = game.scores[team_id]
      {team_id, Enum.find_index(sorted, &(game.scores[&1] == score)) + 1}
    end
  end
end
