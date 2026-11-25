defmodule Cluebert.GameTest do
  use ExUnit.Case, async: true

  alias Cluebert.Game

  # A ragged board: category A has 3 clues, category B has 1.
  @clues %{a1: 100, a2: 200, a3: 300, b1: 100}

  # Actions used by the random-play test.
  @actions [:select_any, :select_current, :correct, :wrong, :bogus, :end_game]

  defp new_game(clues \\ @clues) do
    {:ok, game} = Game.new(clues)
    game
  end

  defp add_teams(game, names) do
    Enum.reduce(names, game, fn name, acc ->
      {:ok, acc, _id} = Game.add_team(acc, name)
      acc
    end)
  end

  # Started game with teams in insertion order: ids 1, 2, 3.
  defp started(names \\ ["Red", "Green", "Blue"], clues \\ @clues) do
    {:ok, game} = clues |> new_game() |> add_teams(names) |> Game.start()
    game
  end

  defp play!(game, team, clue, judgment) do
    {:ok, game} = Game.select(game, team, clue)
    {:ok, game} = Game.judge(game, judgment)
    game
  end

  describe "new/1" do
    test "accepts any board shape with non-negative integer values" do
      assert {:ok, %Game{phase: :setup}} = Game.new(%{only: 0})
      assert {:ok, %Game{}} = Game.new(@clues)
    end

    test "rejects empty or malformed boards" do
      assert {:error, :invalid_board} = Game.new(%{})
      assert {:error, :invalid_board} = Game.new(%{a: -100})
      assert {:error, :invalid_board} = Game.new(%{a: 1.5})
      assert {:error, :invalid_board} = Game.new([{:a, 100}])
    end
  end

  describe "check_team_name/2" do
    test "returns the trimmed name when it is free" do
      assert {:ok, "Red"} = Game.check_team_name([], "  Red ")
      assert {:ok, "Blue"} = Game.check_team_name(["Red"], "Blue")
    end

    test "rejects blank and non-string names" do
      assert {:error, :invalid_name} = Game.check_team_name([], "   ")
      assert {:error, :invalid_name} = Game.check_team_name([], :red)
    end

    test "rejects names already taken, ignoring case and surrounding space" do
      assert {:error, :duplicate_name} = Game.check_team_name(["Red"], " red ")
    end
  end

  describe "setup" do
    test "add_team assigns ids, zero scores, and appends to play order" do
      {:ok, game, red} = Game.add_team(new_game(), "  Red ")
      {:ok, game, green} = Game.add_team(game, "Green")

      assert game.teams == %{red => %{name: "Red"}, green => %{name: "Green"}}
      assert game.team_order == [red, green]
      assert game.scores == %{red => 0, green => 0}
    end

    test "add_team rejects blank and duplicate names" do
      game = add_teams(new_game(), ["Red"])

      assert {:error, :invalid_name} = Game.add_team(game, "   ")
      assert {:error, :invalid_name} = Game.add_team(game, :red)
      assert {:error, :duplicate_name} = Game.add_team(game, "red")
    end

    test "remove_team drops the team from teams, order and scores" do
      game = add_teams(new_game(), ["Red", "Green"])

      assert {:ok, game} = Game.remove_team(game, 1)
      assert game.team_order == [2]
      refute Map.has_key?(game.teams, 1)
      refute Map.has_key?(game.scores, 1)
      assert {:error, :unknown_team} = Game.remove_team(game, 1)
    end

    test "removed team ids are not reused" do
      game = add_teams(new_game(), ["Red"])
      {:ok, game} = Game.remove_team(game, 1)
      {:ok, _game, id} = Game.add_team(game, "Red")

      assert id == 2
    end

    test "shuffle_order applies the shuffle and can be repeated" do
      game = add_teams(new_game(), ["Red", "Green", "Blue"])

      {:ok, game} = Game.shuffle_order(game, &Enum.reverse/1)
      assert game.team_order == [3, 2, 1]

      {:ok, game} = Game.shuffle_order(game, &Enum.reverse/1)
      assert game.team_order == [1, 2, 3]
    end

    test "default shuffle returns a permutation" do
      game = add_teams(new_game(), ["Red", "Green", "Blue", "Gold"])
      {:ok, shuffled} = Game.shuffle_order(game)

      assert Enum.sort(shuffled.team_order) == [1, 2, 3, 4]
    end

    test "shuffle_order raises if the shuffle is not a permutation" do
      game = add_teams(new_game(), ["Red", "Green"])

      assert_raise ArgumentError, fn -> Game.shuffle_order(game, fn _ -> [1] end) end
    end

    test "start requires at least two teams" do
      assert {:error, :too_few_teams} = Game.start(new_game())
      assert {:error, :too_few_teams} = Game.start(add_teams(new_game(), ["Solo"]))
      assert {:ok, %Game{phase: :selecting}} = Game.start(add_teams(new_game(), ["Red", "Blue"]))
      assert Game.min_teams() == 2
    end

    test "start gives the first team in play order the turn" do
      game = add_teams(new_game(), ["Red", "Green", "Blue"])
      {:ok, game} = Game.shuffle_order(game, &Enum.reverse/1)
      {:ok, game} = Game.start(game)

      assert game.phase == :selecting
      assert Game.current_team(game) == 3
    end

    test "current_team is nil during setup" do
      assert Game.current_team(add_teams(new_game(), ["Red"])) == nil
    end
  end

  describe "invariant 6: teams and order are locked after start" do
    test "setup actions fail once the game has started" do
      game = started()

      assert {:error, :wrong_phase} = Game.add_team(game, "Late")
      assert {:error, :wrong_phase} = Game.remove_team(game, 1)
      assert {:error, :wrong_phase} = Game.shuffle_order(game, &Enum.reverse/1)
      assert {:error, :wrong_phase} = Game.start(game)
    end
  end

  describe "invariant 1: only the current team selects, only while selecting" do
    test "other teams cannot select" do
      game = started()

      assert {:error, :not_your_turn} = Game.select(game, 2, :a1)
      assert {:error, :not_your_turn} = Game.select(game, 99, :a1)
    end

    test "unknown clues are rejected" do
      assert {:error, :unknown_clue} = Game.select(started(), 1, :zz)
    end

    test "selection is rejected outside :selecting" do
      setup_game = add_teams(new_game(), ["Red"])
      assert {:error, :wrong_phase} = Game.select(setup_game, 1, :a1)

      {:ok, open} = Game.select(started(), 1, :a1)
      assert {:error, :wrong_phase} = Game.select(open, 1, :a2)
    end
  end

  describe "invariant 2: at most one open clue, only while :clue_open" do
    test "select opens the clue; judging closes it" do
      {:ok, game} = Game.select(started(), 1, :a1)
      assert {game.phase, game.open_clue} == {:clue_open, :a1}

      {:ok, game} = Game.judge(game, :wrong)
      assert {game.phase, game.open_clue} == {:selecting, nil}
    end

    test "judge is rejected when no clue is open" do
      assert {:error, :wrong_phase} = Game.judge(started(), :correct)
    end

    test "judge rejects unknown judgments without changing state" do
      {:ok, game} = Game.select(started(), 1, :a1)
      assert {:error, :invalid_judgment} = Game.judge(game, :maybe)
    end
  end

  describe "invariant 3: answered clues cannot be selected again" do
    test "a correctly answered clue leaves the board" do
      game = play!(started(), 1, :a1, :correct)

      assert {:error, :already_answered} = Game.select(game, 1, :a1)
      refute :a1 in Game.remaining_clues(game)
    end

    test "a wrongly answered clue stays selectable, any number of times" do
      game =
        started()
        |> play!(1, :a1, :wrong)
        |> play!(2, :a1, :wrong)
        |> play!(3, :a1, :wrong)

      assert :a1 in Game.remaining_clues(game)
      assert {:ok, %Game{open_clue: :a1}} = Game.select(game, 1, :a1)
    end
  end

  describe "invariant 4: turn advances only on :wrong" do
    test ":correct keeps the turn with the same team" do
      game = play!(started(), 1, :a1, :correct)

      assert Game.current_team(game) == 1
    end

    test ":wrong passes the turn in play order and wraps around" do
      game = play!(started(), 1, :a1, :wrong)
      assert Game.current_team(game) == 2

      game = play!(game, 2, :a1, :wrong)
      assert Game.current_team(game) == 3

      game = play!(game, 3, :a1, :wrong)
      assert Game.current_team(game) == 1
    end

    test "turn follows the shuffled order" do
      game = add_teams(new_game(), ["Red", "Green", "Blue"])
      {:ok, game} = Game.shuffle_order(game, fn _ -> [2, 3, 1] end)
      {:ok, game} = Game.start(game)

      game = play!(game, 2, :a1, :wrong)
      assert Game.current_team(game) == 3
    end
  end

  describe "invariant 5: scores change only on :correct, by the clue value" do
    test ":correct adds the clue value to the current team only" do
      game = play!(started(), 1, :a3, :correct)

      assert game.scores == %{1 => 300, 2 => 0, 3 => 0}
    end

    test ":wrong changes no scores" do
      game = play!(started(), 1, :a3, :wrong)

      assert game.scores == %{1 => 0, 2 => 0, 3 => 0}
    end
  end

  describe "ending" do
    test "answering the last clue ends the game" do
      game =
        started(["Red", "Green"], %{a1: 100, b1: 200})
        |> play!(1, :a1, :correct)
        |> play!(1, :b1, :correct)

      assert game.phase == :done
      assert Game.current_team(game) == nil
      assert Game.remaining_clues(game) == []
    end

    test "end_game is allowed in setup, selecting, and with a clue open" do
      assert {:ok, %Game{phase: :done}} = Game.end_game(new_game())
      assert {:ok, %Game{phase: :done}} = Game.end_game(started())

      {:ok, open} = Game.select(started(), 1, :a1)
      assert {:ok, %Game{phase: :done, open_clue: nil}} = Game.end_game(open)
    end

    test "ending with a clue open awards nothing and leaves clues unanswered" do
      game = play!(started(), 1, :a1, :correct)
      {:ok, game} = Game.select(game, 1, :a2)
      {:ok, game} = Game.end_game(game)

      assert game.scores == %{1 => 100, 2 => 0, 3 => 0}
      assert Enum.sort(Game.remaining_clues(game)) == [:a2, :a3, :b1]
    end

    test "nothing is accepted once the game is done" do
      {:ok, game} = Game.end_game(started())

      assert {:error, :wrong_phase} = Game.end_game(game)
      assert {:error, :wrong_phase} = Game.select(game, 1, :a1)
      assert {:error, :wrong_phase} = Game.judge(game, :correct)
      assert {:error, :wrong_phase} = Game.add_team(game, "Late")
    end
  end

  describe "random play" do
    # Drives many random action sequences (valid and invalid) through the
    # public API and checks every invariant after each step. Seeded by
    # ExUnit's seed, so failures reproduce with `mix test --seed N`.
    test "invariants hold for arbitrary action sequences" do
      for _run <- 1..300 do
        clues = for i <- 1..Enum.random(1..12), into: %{}, do: {i, 100 * Enum.random(0..10)}
        names = for i <- 1..Enum.random(2..5), do: "Team #{i}"

        {:ok, game} = clues |> new_game() |> add_teams(names) |> Game.shuffle_order()
        {:ok, game} = Game.start(game)

        Enum.reduce_while(1..80, game, fn _step, before ->
          after_ = step(before, Enum.random(@actions))
          check_invariants!(before, after_)
          if after_.phase == :done, do: {:halt, after_}, else: {:cont, after_}
        end)
      end
    end
  end

  defp step(game, :select_any) do
    team = Enum.random(game.team_order)
    clue = Enum.random(Map.keys(game.clues) ++ [:missing])
    result(game, Game.select(game, team, clue))
  end

  defp step(game, :select_current) do
    case Game.remaining_clues(game) do
      [] -> game
      clues -> result(game, Game.select(game, Game.current_team(game), Enum.random(clues)))
    end
  end

  defp step(game, :correct), do: result(game, Game.judge(game, :correct))
  defp step(game, :wrong), do: result(game, Game.judge(game, :wrong))
  defp step(game, :bogus), do: result(game, Game.judge(game, :bogus))

  # Rare, so most runs play long enough to exercise turns and scoring.
  defp step(game, :end_game) do
    if :rand.uniform(20) == 1, do: result(game, Game.end_game(game)), else: game
  end

  # Rejected actions are expected; the game simply carries on unchanged.
  defp result(_game, {:ok, game}), do: game
  defp result(game, {:error, _reason}), do: game

  defp check_invariants!(before, after_) do
    sum_answered = after_.answered |> Enum.map(&after_.clues[&1]) |> Enum.sum()

    # 5: total score equals the value of answered clues.
    assert Enum.sum(Map.values(after_.scores)) == sum_answered

    # 3: answered only grows; and a selected clue was never answered.
    assert MapSet.subset?(before.answered, after_.answered)

    if after_.open_clue != nil and before.open_clue == nil do
      refute MapSet.member?(before.answered, after_.open_clue)
      # 1: only the current team can have opened it; turn unchanged.
      assert after_.turn == before.turn
    end

    # 2: an open clue exists exactly when the phase is :clue_open.
    open? = not is_nil(after_.open_clue)
    assert open? == (after_.phase == :clue_open)

    # 4: turn changes only on a wrong judgment (clue closed, nothing answered).
    if after_.turn != before.turn do
      assert before.phase == :clue_open
      assert after_.phase == :selecting
      assert after_.answered == before.answered
    end

    # 5: scores change only when a clue was answered, for the current team.
    if after_.scores != before.scores do
      [clue] = MapSet.difference(after_.answered, before.answered) |> MapSet.to_list()
      team = Enum.at(before.team_order, before.turn)

      assert after_.scores ==
               Map.update!(before.scores, team, &(&1 + before.clues[clue]))
    end

    # 6: teams and order never change after start.
    assert after_.teams == before.teams
    assert after_.team_order == before.team_order

    # Done means no open clue and no going back.
    if before.phase == :done, do: assert(after_ == before)
  end
end
