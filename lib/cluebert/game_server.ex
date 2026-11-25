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

  A game is created already playing (ADR 8): the teams are added, the play
  order is randomized and the game is started inside `start_game/2`, so no
  one ever sees a game in `:setup`.

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
  Starts a new game for the board with `board_id` and the given teams, under
  the game supervisor. The board is loaded once, here.

  The teams are added in order, then shuffled into a random play order, and
  the game is started. Returns an error from `Cluebert.Game` if the board
  has no clues (`:invalid_board`), there are no teams (`:no_teams`), or a
  name is rejected (see `Cluebert.Game.check_team_name/2`). Raises
  `Ecto.NoResultsError` if there is no such board.
  """
  @spec start_game(term(), [String.t()]) :: {:ok, id()} | {:error, Game.error()}
  def start_game(board_id, team_names) do
    board = Boards.get_board!(board_id)
    id = new_id()
    child = {__MODULE__, id: id, board: board, team_names: team_names}

    case DynamicSupervisor.start_child(@supervisor, child) do
      {:ok, _pid} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts a game process linked to the caller.

  Use `start_game/2` in application code; this is the child spec entry
  point. Options:

    * `:id` (required)
    * `:board` (required), with categories and clues preloaded
    * `:team_names` (required)
    * `:shuffle` (optional), passed to `Cluebert.Game.shuffle_order/2`;
      tests pass a deterministic function
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

  ## Actions during play, one per `Cluebert.Game` function

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
    team_names = Keyword.fetch!(opts, :team_names)
    shuffle = Keyword.get(opts, :shuffle, &Enum.shuffle/1)

    case new_game(board, team_names, shuffle) do
      {:ok, game} -> {:ok, %{id: id, board: board, game: game}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call({:select, team_id, clue_id}, _from, state),
    do: apply_rule(state, &Game.select(&1, team_id, clue_id))

  def handle_call({:judge, judgment}, _from, state),
    do: apply_rule(state, &Game.judge(&1, judgment))

  def handle_call(:end_game, _from, state), do: apply_rule(state, &Game.end_game/1)

  ## Helpers

  # Runs the game through :setup with Cluebert.Game's own functions.
  defp new_game(board, team_names, shuffle) do
    with {:ok, game} <- Game.new(clue_values(board)),
         {:ok, game} <- add_teams(game, team_names),
         {:ok, game} <- Game.shuffle_order(game, shuffle) do
      Game.start(game)
    end
  end

  defp add_teams(game, names) do
    Enum.reduce_while(names, {:ok, game}, fn name, {:ok, game} ->
      case Game.add_team(game, name) do
        {:ok, game, _team_id} -> {:cont, {:ok, game}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

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
