defmodule Cluebert.BoardsTest do
  use Cluebert.DataCase, async: true

  alias Cluebert.Boards
  alias Cluebert.Boards.{Board, Category, Clue}

  defp clue(n), do: %{prompt: "Prompt #{n}", response: "Response #{n}", value: n * 100}

  defp board_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Sample",
        categories: [
          %{title: "First", clues: [clue(1), clue(2), clue(3)]},
          %{title: "Second", clues: [clue(1)]}
        ]
      },
      overrides
    )
  end

  describe "list_boards/0" do
    test "lists boards by name" do
      {:ok, _} = Boards.create_board(%{name: "Zebra"})
      {:ok, _} = Boards.create_board(%{name: "Apple"})

      assert Enum.map(Boards.list_boards(), & &1.name) == ["Apple", "Zebra"]
    end
  end

  describe "create_board/1" do
    test "creates a board with categories and clues positioned in list order" do
      assert {:ok, %Board{id: id}} = Boards.create_board(board_attrs())

      board = Boards.get_board!(id)
      assert board.name == "Sample"
      assert [%{title: "First", position: 0}, %{title: "Second", position: 1}] = board.categories

      [first, second] = board.categories
      assert Enum.map(first.clues, &{&1.position, &1.value}) == [{0, 100}, {1, 200}, {2, 300}]
      assert Enum.map(second.clues, &{&1.position, &1.value}) == [{0, 100}]
    end

    test "allows categories with different numbers of clues, and empty boards" do
      assert {:ok, _} = Boards.create_board(board_attrs())
      assert {:ok, board} = Boards.create_board(%{name: "Empty"})
      assert Boards.get_board!(board.id).categories == []
    end

    test "requires a name" do
      assert {:error, changeset} = Boards.create_board(board_attrs(%{name: ""}))
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects a duplicate name" do
      assert {:ok, _} = Boards.create_board(board_attrs())
      assert {:error, changeset} = Boards.create_board(board_attrs())
      assert "has already been taken" in errors_on(changeset).name
    end

    test "requires category titles and clue prompts, responses and values" do
      attrs =
        board_attrs(%{
          categories: [%{title: "", clues: [%{prompt: "", response: "", value: nil}]}]
        })

      assert {:error, changeset} = Boards.create_board(attrs)

      assert %{
               categories: [
                 %{
                   title: ["can't be blank"],
                   clues: [
                     %{
                       prompt: ["can't be blank"],
                       response: ["can't be blank"],
                       value: ["can't be blank"]
                     }
                   ]
                 }
               ]
             } = errors_on(changeset)
    end

    test "rejects a negative clue value" do
      attrs =
        board_attrs(%{categories: [%{title: "T", clues: [%{clue(1) | value: -100}]}]})

      assert {:error, changeset} = Boards.create_board(attrs)
      assert %{categories: [%{clues: [%{value: [_]}]}]} = errors_on(changeset)
    end

    test "ignores a position given in attrs" do
      attrs = board_attrs(%{categories: [%{title: "T", position: 7, clues: []}]})

      assert {:ok, board} = Boards.create_board(attrs)
      assert [%{position: 0}] = Boards.get_board!(board.id).categories
    end
  end

  describe "get_board!/1" do
    test "returns categories and clues in position order, not insertion order" do
      board = Repo.insert!(%Board{name: "Out of order"})
      later = Repo.insert!(%Category{board_id: board.id, title: "Later", position: 1})
      earlier = Repo.insert!(%Category{board_id: board.id, title: "Earlier", position: 0})

      for {position, value} <- [{2, 300}, {0, 100}, {1, 200}] do
        Repo.insert!(%Clue{
          category_id: earlier.id,
          prompt: "p",
          response: "r",
          value: value,
          position: position
        })
      end

      loaded = Boards.get_board!(board.id)

      assert Enum.map(loaded.categories, & &1.id) == [earlier.id, later.id]
      assert Enum.map(hd(loaded.categories).clues, & &1.value) == [100, 200, 300]
      assert List.last(loaded.categories).clues == []
    end

    test "raises for an unknown board" do
      assert_raise Ecto.NoResultsError, fn -> Boards.get_board!(-1) end
    end
  end

  describe "seeds" do
    test "create a sample board whose categories have different numbers of clues" do
      Code.eval_file("priv/repo/seeds.exs")
      Code.eval_file("priv/repo/seeds.exs")

      assert [board] = Repo.all(Board)
      board = Boards.get_board!(board.id)

      clue_counts = Enum.map(board.categories, &length(&1.clues))
      assert length(clue_counts) > 1
      assert length(Enum.uniq(clue_counts)) > 1
    end
  end
end
