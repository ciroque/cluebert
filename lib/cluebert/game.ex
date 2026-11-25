defmodule Cluebert.Game do
  @moduledoc """
  Pure rules for a single Cluebert game. No processes, no persistence.

  A process (the future `GameServer`) holds a `%Cluebert.Game{}` and calls
  these functions; every rule lives here so it can be tested without OTP.

  ## Rules

    * Teams are added during `:setup`. An individual player is a team of one.
      Team names are trimmed, must not be blank, and must be unique ignoring
      case (`check_team_name/2`).
    * The play order can be shuffled during `:setup` and is locked by `start/1`.
    * At least two teams are needed to start.
    * On their turn, the current team selects any clue that has not been
      answered. A clue can be selected any number of times until it is
      answered correctly.
    * The host judges the response:
      * `:correct` - the team scores the clue's value, the clue leaves the
        board, and the same team selects again.
      * `:wrong` - no points, the clue stays on the board, and the turn
        passes to the next team in order.
    * The game ends when every clue is answered, or when the host calls
      `end_game/1` (allowed in any phase). Unanswered clues stay unanswered.

  ## Phases

      :setup -> :selecting <-> :clue_open
                     |              |
                     +----> :done <-+   (also reachable from :setup)

  ## Invariants

    1. Only the current team may select, and only during `:selecting`.
    2. At most one clue is open, and only during `:clue_open`.
    3. A clue in `answered` can never be selected again.
    4. The turn advances only on a `:wrong` judgment.
    5. Scores change only on a `:correct` judgment, by exactly the clue's
       value; so the sum of all scores equals the sum of answered values.
    6. Teams and play order change only during `:setup`.
  """

  @min_teams 2

  @enforce_keys [:clues]
  defstruct clues: %{},
            phase: :setup,
            teams: %{},
            team_order: [],
            next_team_id: 1,
            turn: 0,
            scores: %{},
            answered: MapSet.new(),
            open_clue: nil

  @typedoc "Any term that identifies a clue (e.g. a database id)."
  @type clue_id :: term()
  @type team_id :: pos_integer()
  @type phase :: :setup | :selecting | :clue_open | :done
  @type judgment :: :correct | :wrong

  @type t :: %__MODULE__{
          clues: %{clue_id() => non_neg_integer()},
          phase: phase(),
          teams: %{team_id() => %{name: String.t()}},
          team_order: [team_id()],
          next_team_id: team_id(),
          turn: non_neg_integer(),
          scores: %{team_id() => integer()},
          answered: MapSet.t(clue_id()),
          open_clue: clue_id() | nil
        }

  @type error ::
          :invalid_board
          | :wrong_phase
          | :invalid_name
          | :duplicate_name
          | :unknown_team
          | :too_few_teams
          | :not_your_turn
          | :unknown_clue
          | :already_answered
          | :invalid_judgment

  @doc """
  Creates a game in `:setup` from a snapshot of the board.

  `clues` maps each clue id to its point value. The board may have any number
  of categories and any number of clues per category; only ids and values
  matter to the rules. Returns `{:error, :invalid_board}` if the map is empty
  or any value is not a non-negative integer.
  """
  @spec new(%{clue_id() => non_neg_integer()}) :: {:ok, t()} | {:error, :invalid_board}
  def new(clues) when is_map(clues) and map_size(clues) > 0 do
    if Enum.all?(clues, fn {_id, value} -> is_integer(value) and value >= 0 end) do
      {:ok, %__MODULE__{clues: clues}}
    else
      {:error, :invalid_board}
    end
  end

  def new(_clues), do: {:error, :invalid_board}

  @doc """
  Adds a team during `:setup`. Returns the new team's id.

  Names are trimmed; blank names and names already in use (case-insensitive)
  are rejected. New teams are appended to the end of the play order.
  """
  @spec add_team(t(), String.t()) :: {:ok, t(), team_id()} | {:error, error()}
  def add_team(%__MODULE__{phase: :setup} = game, name) do
    existing = Enum.map(game.teams, fn {_id, team} -> team.name end)

    case check_team_name(existing, name) do
      {:error, _} = error ->
        error

      {:ok, name} ->
        id = game.next_team_id

        game = %{
          game
          | teams: Map.put(game.teams, id, %{name: name}),
            team_order: game.team_order ++ [id],
            scores: Map.put(game.scores, id, 0),
            next_team_id: id + 1
        }

        {:ok, game, id}
    end
  end

  def add_team(%__MODULE__{}, _name), do: {:error, :wrong_phase}

  @doc """
  Checks a team name against the names already taken, before or without a
  game. Returns the trimmed name.

  Used by `add_team/2`, and by setup screens that collect names before a
  game exists (ADR 8), so the rule lives only here.
  """
  @spec check_team_name([String.t()], term()) ::
          {:ok, String.t()} | {:error, :invalid_name | :duplicate_name}
  def check_team_name(existing, name) when is_list(existing) and is_binary(name) do
    name = String.trim(name)
    down = String.downcase(name)

    cond do
      name == "" -> {:error, :invalid_name}
      Enum.any?(existing, &(String.downcase(&1) == down)) -> {:error, :duplicate_name}
      true -> {:ok, name}
    end
  end

  def check_team_name(existing, _name) when is_list(existing), do: {:error, :invalid_name}

  @doc "Removes a team during `:setup`."
  @spec remove_team(t(), team_id()) :: {:ok, t()} | {:error, error()}
  def remove_team(%__MODULE__{phase: :setup} = game, team_id) do
    if Map.has_key?(game.teams, team_id) do
      {:ok,
       %{
         game
         | teams: Map.delete(game.teams, team_id),
           team_order: List.delete(game.team_order, team_id),
           scores: Map.delete(game.scores, team_id)
       }}
    else
      {:error, :unknown_team}
    end
  end

  def remove_team(%__MODULE__{}, _team_id), do: {:error, :wrong_phase}

  @doc """
  Randomizes the play order during `:setup`. May be called repeatedly.

  `shuffle` defaults to `Enum.shuffle/1`; pass a deterministic function in
  tests. It must return a permutation of the list it is given.
  """
  @spec shuffle_order(t(), ([team_id()] -> [team_id()])) :: {:ok, t()} | {:error, error()}
  def shuffle_order(game, shuffle \\ &Enum.shuffle/1)

  def shuffle_order(%__MODULE__{phase: :setup} = game, shuffle) do
    order = shuffle.(game.team_order)

    if Enum.sort(order) == Enum.sort(game.team_order) do
      {:ok, %{game | team_order: order}}
    else
      raise ArgumentError, "shuffle function must return a permutation of the team order"
    end
  end

  def shuffle_order(%__MODULE__{}, _shuffle), do: {:error, :wrong_phase}

  @doc "The fewest teams a game can start with."
  @spec min_teams() :: pos_integer()
  def min_teams, do: @min_teams

  @doc """
  Locks teams and play order and gives the first team the turn.

  Needs at least two teams; returns `{:error, :too_few_teams}` otherwise.
  """
  @spec start(t()) :: {:ok, t()} | {:error, error()}
  def start(%__MODULE__{phase: :setup, team_order: order}) when length(order) < @min_teams,
    do: {:error, :too_few_teams}

  def start(%__MODULE__{phase: :setup} = game),
    do: {:ok, %{game | phase: :selecting, turn: 0}}

  def start(%__MODULE__{}), do: {:error, :wrong_phase}

  @doc "The current team selects a clue that has not been answered."
  @spec select(t(), team_id(), clue_id()) :: {:ok, t()} | {:error, error()}
  def select(%__MODULE__{phase: :selecting} = game, team_id, clue_id) do
    cond do
      team_id != current_team(game) -> {:error, :not_your_turn}
      not Map.has_key?(game.clues, clue_id) -> {:error, :unknown_clue}
      MapSet.member?(game.answered, clue_id) -> {:error, :already_answered}
      true -> {:ok, %{game | phase: :clue_open, open_clue: clue_id}}
    end
  end

  def select(%__MODULE__{}, _team_id, _clue_id), do: {:error, :wrong_phase}

  @doc """
  The host judges the open clue.

  `:correct` scores the clue for the current team and keeps their turn;
  the game ends if that was the last clue. `:wrong` leaves the clue on the
  board and passes the turn.
  """
  @spec judge(t(), judgment()) :: {:ok, t()} | {:error, error()}
  def judge(%__MODULE__{phase: :clue_open, open_clue: clue_id} = game, :correct) do
    team_id = current_team(game)
    answered = MapSet.put(game.answered, clue_id)

    phase = if MapSet.size(answered) == map_size(game.clues), do: :done, else: :selecting

    {:ok,
     %{
       game
       | scores: Map.update!(game.scores, team_id, &(&1 + game.clues[clue_id])),
         answered: answered,
         open_clue: nil,
         phase: phase
     }}
  end

  def judge(%__MODULE__{phase: :clue_open} = game, :wrong) do
    {:ok,
     %{
       game
       | open_clue: nil,
         phase: :selecting,
         turn: rem(game.turn + 1, length(game.team_order))
     }}
  end

  def judge(%__MODULE__{phase: :clue_open}, _judgment), do: {:error, :invalid_judgment}
  def judge(%__MODULE__{}, _judgment), do: {:error, :wrong_phase}

  @doc """
  Ends the game in any phase. An open clue is closed without points;
  scores are frozen as they are.
  """
  @spec end_game(t()) :: {:ok, t()} | {:error, error()}
  def end_game(%__MODULE__{phase: :done}), do: {:error, :wrong_phase}
  def end_game(%__MODULE__{} = game), do: {:ok, %{game | phase: :done, open_clue: nil}}

  @doc "The team whose turn it is, or `nil` outside `:selecting` / `:clue_open`."
  @spec current_team(t()) :: team_id() | nil
  def current_team(%__MODULE__{phase: phase} = game) when phase in [:selecting, :clue_open],
    do: Enum.at(game.team_order, game.turn)

  def current_team(%__MODULE__{}), do: nil

  @doc "Clue ids still on the board."
  @spec remaining_clues(t()) :: [clue_id()]
  def remaining_clues(%__MODULE__{} = game),
    do: game.clues |> Map.keys() |> Enum.reject(&MapSet.member?(game.answered, &1))
end
