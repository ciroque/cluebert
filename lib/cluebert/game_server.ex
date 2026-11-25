defmodule Cluebert.GameServer do
  @moduledoc """
  One process per live game (ADR 1). It holds a `%Cluebert.Game{}` and the
  board it was built from, calls `Cluebert.Game` for every change, and
  broadcasts the new game on `topic/1` after each successful one. It holds
  no rules of its own.

  Games are started under `Cluebert.GameSupervisor` and addressed by id via
  `Cluebert.GameRegistry`. State lives only in this process (ADR 4): games
  are `:temporary`, so a crashed game is gone rather than restarted empty.

  The board is copied in when the game starts (ADR 5); later edits to the
  board in the database never reach a running game.

  ## Broadcasts

  After every successful change, subscribers to `topic(id)` receive:

      {:game_updated, id, %Cluebert.Game{}}

  The board never changes, so it is not broadcast; read it once with
  `get/1`.
  """
  use GenServer, restart: :temporary

  alias Cluebert.Boards
  alias Cluebert.Boards.Board
  alias Cluebert.Game

  @registry Cluebert.GameRegistry
  @supervisor Cluebert.GameSupervisor
  @pubsub Cluebert.PubSub

  @type id :: String.t()
  @type state :: %{id: id(), board: Board.t(), game: Game.t()}

  ## Lifecycle

  @doc """
  Starts a new game for the board with `board_id`, under the game
  supervisor. The board is loaded once, here.

  Returns `{:error, :invalid_board}` if the board has no clues. Raises
  `Ecto.NoResultsError` if there is no such board.
  """
  @spec start_game(term()) :: {:ok, id()} | {:error, Game.error()}
  def start_game(board_id) do
    board = Boards.get_board!(board_id)
    id = new_id()

    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, id: id, board: board}) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts a game process linked to the caller.

  Use `start_game/1` in application code; this is the child spec entry
  point. Options: `:id` (required) and `:board`, a board with categories
  and clues preloaded (required).
  """
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc "The PubSub topic a game's updates are broadcast on."
  @spec topic(id()) :: String.t()
  def topic(id), do: "game:" <> id

  @doc "Subscribes the caller to a game's updates. See the moduledoc."
  @spec subscribe(id()) :: :ok | {:error, term()}
  def subscribe(id), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))

  @doc "Returns the game's id, board and current `%Cluebert.Game{}`."
  @spec get(id()) :: {:ok, state()} | {:error, :not_found}
  def get(id), do: call(id, :get)

  ## Actions, one per `Cluebert.Game` function

  @doc "See `Cluebert.Game.add_team/2`."
  @spec add_team(id(), String.t()) ::
          {:ok, Game.t(), Game.team_id()} | {:error, Game.error() | :not_found}
  def add_team(id, name), do: call(id, {:add_team, name})

  @doc "See `Cluebert.Game.remove_team/2`."
  @spec remove_team(id(), Game.team_id()) :: {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def remove_team(id, team_id), do: call(id, {:remove_team, team_id})

  @doc "See `Cluebert.Game.shuffle_order/2`."
  @spec shuffle_order(id(), ([Game.team_id()] -> [Game.team_id()])) ::
          {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def shuffle_order(id, shuffle \\ &Enum.shuffle/1), do: call(id, {:shuffle_order, shuffle})

  @doc "See `Cluebert.Game.start/1`."
  @spec start(id()) :: {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def start(id), do: call(id, :start)

  @doc "See `Cluebert.Game.select/3`."
  @spec select(id(), Game.team_id(), Game.clue_id()) ::
          {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def select(id, team_id, clue_id), do: call(id, {:select, team_id, clue_id})

  @doc "See `Cluebert.Game.judge/2`."
  @spec judge(id(), Game.judgment()) :: {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def judge(id, judgment), do: call(id, {:judge, judgment})

  @doc "See `Cluebert.Game.end_game/1`."
  @spec end_game(id()) :: {:ok, Game.t()} | {:error, Game.error() | :not_found}
  def end_game(id), do: call(id, :end_game)

  ## Callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    board = Keyword.fetch!(opts, :board)

    case Game.new(clue_values(board)) do
      {:ok, game} -> {:ok, %{id: id, board: board, game: game}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:add_team, name}, _from, state) do
    case Game.add_team(state.game, name) do
      {:ok, game, team_id} -> {:reply, {:ok, game, team_id}, update(state, game)}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_team, team_id}, _from, state),
    do: apply_rule(state, &Game.remove_team(&1, team_id))

  def handle_call({:shuffle_order, shuffle}, _from, state),
    do: apply_rule(state, &Game.shuffle_order(&1, shuffle))

  def handle_call(:start, _from, state), do: apply_rule(state, &Game.start/1)

  def handle_call({:select, team_id, clue_id}, _from, state),
    do: apply_rule(state, &Game.select(&1, team_id, clue_id))

  def handle_call({:judge, judgment}, _from, state),
    do: apply_rule(state, &Game.judge(&1, judgment))

  def handle_call(:end_game, _from, state), do: apply_rule(state, &Game.end_game/1)

  ## Helpers

  defp apply_rule(state, rule) do
    case rule.(state.game) do
      {:ok, game} -> {:reply, {:ok, game}, update(state, game)}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp update(state, game) do
    Phoenix.PubSub.broadcast(@pubsub, topic(state.id), {:game_updated, state.id, game})
    %{state | game: game}
  end

  defp call(id, request) do
    GenServer.call(via(id), request)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  defp via(id), do: {:via, Registry, {@registry, id}}

  defp clue_values(%Board{categories: categories}) do
    for category <- categories, clue <- category.clues, into: %{}, do: {clue.id, clue.value}
  end

  defp new_id, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
end
