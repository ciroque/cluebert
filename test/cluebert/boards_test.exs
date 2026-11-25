defmodule Cluebert.BoardsTest do
  use Cluebert.DataCase, async: true

  alias Cluebert.Boards
  alias Cluebert.Boards.{Board, Category, Clue, Collection}

  setup do
    %{collection: unique_collection()}
  end

  defp clue(n), do: %{prompt: "Prompt #{n}", response: "Response #{n}", value: n * 100}

  defp board_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: unique_board_name("Sample"),
        categories: [
          %{title: "First", clues: [clue(1), clue(2), clue(3)]},
          %{title: "Second", clues: [clue(1)]}
        ]
      },
      overrides
    )
  end

  describe "collections" do
    test "get_or_create_collection/1 creates a collection once, trimming the name" do
      name = unique_board_name("Primary Lessons")

      assert {:ok, %Collection{id: id, name: ^name}} =
               Boards.get_or_create_collection("  #{name} ")

      assert {:ok, %Collection{id: ^id}} = Boards.get_or_create_collection(name)
    end

    test "get_or_create_collection/1 rejects a blank name" do
      assert {:error, changeset} = Boards.get_or_create_collection("  ")
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_board/1 puts the board in the default collection" do
      assert {:ok, board} = Boards.create_board(%{name: unique_board_name("Default")})

      assert Repo.preload(board, :collection).collection.name ==
               Boards.default_collection_name()
    end
  end

  describe "managing collections" do
    test "create, rename and list them by name with their boards and clue counts" do
      {:ok, zoo} = Boards.create_collection(%{name: unique_board_name("Zoo")})
      {:ok, art} = Boards.create_collection(%{name: "  " <> unique_board_name("Art") <> " "})
      {:ok, _} = Boards.create_board(zoo, %{name: "Empty"})

      {:ok, _} =
        Boards.create_board(zoo, %{
          name: "Full",
          categories: [
            %{title: "A", clues: [clue(1), clue(2)]},
            %{title: "B", clues: [clue(1)]}
          ]
        })

      {:ok, art} = Boards.update_collection(art, %{name: art.name <> " renamed"})

      listed =
        Boards.list_collections_with_boards() |> Enum.filter(&(&1.id in [zoo.id, art.id]))

      assert Enum.map(listed, & &1.id) == [art.id, zoo.id]
      assert String.ends_with?(hd(listed).name, " renamed")

      assert [%{name: "Empty", clue_count: 0}, %{name: "Full", clue_count: 3}] =
               List.last(listed).boards
    end

    test "names must be unique and not blank" do
      name = unique_board_name("Taken")
      {:ok, _} = Boards.create_collection(%{name: name})

      assert {:error, changeset} = Boards.create_collection(%{name: name})
      assert "is already a collection" in errors_on(changeset).name
      assert {:error, changeset} = Boards.create_collection(%{name: " "})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "only an empty collection can be deleted", %{collection: collection} do
      {:ok, board} = Boards.create_board(collection, %{name: "Keep"})

      assert {:error, changeset} = Boards.delete_collection(collection)
      assert "still has boards; move or delete them first" in errors_on(changeset).boards

      {:ok, _} = Boards.delete_board(board)
      assert {:ok, _} = Boards.delete_collection(collection)
      assert_raise Ecto.NoResultsError, fn -> Boards.get_collection!(collection.id) end
    end
  end

  describe "managing boards" do
    test "rename keeps categories and clues", %{collection: collection} do
      {:ok, board} = Boards.create_board(collection, board_attrs())

      assert {:ok, %Board{name: "Renamed"}} = Boards.rename_board(board, %{name: " Renamed "})
      assert length(Boards.get_board!(board.id).categories) == 2
    end

    test "rename rejects a name taken in the same collection", %{collection: collection} do
      {:ok, _} = Boards.create_board(collection, %{name: "Taken"})
      {:ok, board} = Boards.create_board(collection, %{name: "Mine"})

      assert {:error, changeset} = Boards.rename_board(board, %{name: "Taken"})
      assert "has already been taken in this collection" in errors_on(changeset).name
    end

    test "move puts the board in another collection", %{collection: collection} do
      other = unique_collection()
      {:ok, board} = Boards.create_board(collection, board_attrs())

      assert {:ok, moved} = Boards.move_board(board, other)
      assert Boards.get_board_summary!(moved.id).collection.id == other.id
      assert length(Boards.get_board!(board.id).categories) == 2
    end

    test "move fails if the target has a board with the same name", %{collection: collection} do
      other = unique_collection()
      {:ok, _} = Boards.create_board(other, %{name: "Same"})
      {:ok, board} = Boards.create_board(collection, %{name: "Same"})

      assert {:error, changeset} = Boards.move_board(board, other)
      assert "has already been taken in this collection" in errors_on(changeset).name
    end

    test "delete removes the board with its categories and clues", %{collection: collection} do
      {:ok, board} = Boards.create_board(collection, board_attrs())

      assert {:ok, _} = Boards.delete_board(board)
      assert_raise Ecto.NoResultsError, fn -> Boards.get_board!(board.id) end
      assert Repo.aggregate(Category, :count) == 0
    end
  end

  describe "list_boards/0" do
    test "lists boards by collection name, then board name, with the collection loaded" do
      zoo = unique_collection("Zoo")
      art = unique_collection("Art")
      {:ok, zoo_b} = Boards.create_board(zoo, %{name: "B"})
      {:ok, zoo_a} = Boards.create_board(zoo, %{name: "A"})
      {:ok, art_z} = Boards.create_board(art, %{name: "Z"})

      boards = Boards.list_boards()
      assert Enum.map(boards, & &1.id) == [art_z.id, zoo_a.id, zoo_b.id]
      assert hd(boards).collection.id == art.id
    end
  end

  describe "create_board/2" do
    test "creates a board with categories and clues positioned in list order", %{
      collection: collection
    } do
      attrs = board_attrs()
      assert {:ok, %Board{id: id}} = Boards.create_board(collection, attrs)

      board = Boards.get_board!(id)
      assert board.name == attrs.name
      assert [%{title: "First", position: 0}, %{title: "Second", position: 1}] = board.categories

      [first, second] = board.categories
      assert Enum.map(first.clues, &{&1.position, &1.value}) == [{0, 100}, {1, 200}, {2, 300}]
      assert Enum.map(second.clues, &{&1.position, &1.value}) == [{0, 100}]
    end

    test "allows categories with different numbers of clues, and empty boards", %{
      collection: collection
    } do
      assert {:ok, _} = Boards.create_board(collection, board_attrs())
      assert {:ok, board} = Boards.create_board(collection, %{name: unique_board_name("Empty")})
      assert Boards.get_board!(board.id).categories == []
    end

    test "requires a name", %{collection: collection} do
      assert {:error, changeset} = Boards.create_board(collection, board_attrs(%{name: ""}))
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects a duplicate name", %{collection: collection} do
      attrs = board_attrs()
      assert {:ok, _} = Boards.create_board(collection, attrs)
      assert {:error, changeset} = Boards.create_board(collection, attrs)
      assert "has already been taken in this collection" in errors_on(changeset).name
    end

    test "allows the same name in different collections", %{collection: collection} do
      attrs = board_attrs()
      assert {:ok, _} = Boards.create_board(collection, attrs)
      assert {:ok, _} = Boards.create_board(unique_collection(), attrs)
    end

    test "trims the name", %{collection: collection} do
      assert {:ok, %Board{name: "Trimmed"}} =
               Boards.create_board(collection, board_attrs(%{name: "  Trimmed "}))
    end

    test "requires category titles and clue prompts, responses and values", %{
      collection: collection
    } do
      attrs =
        board_attrs(%{
          categories: [%{title: "", clues: [%{prompt: "", response: "", value: nil}]}]
        })

      assert {:error, changeset} = Boards.create_board(collection, attrs)

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

    test "rejects a negative clue value", %{collection: collection} do
      attrs =
        board_attrs(%{categories: [%{title: "T", clues: [%{clue(1) | value: -100}]}]})

      assert {:error, changeset} = Boards.create_board(collection, attrs)
      assert %{categories: [%{clues: [%{value: [_]}]}]} = errors_on(changeset)
    end

    test "ignores a position given in attrs", %{collection: collection} do
      attrs = board_attrs(%{categories: [%{title: "T", position: 7, clues: []}]})

      assert {:ok, board} = Boards.create_board(collection, attrs)
      assert [%{position: 0}] = Boards.get_board!(board.id).categories
    end
  end

  describe "get_board!/1" do
    test "returns categories and clues in position order, not insertion order", %{
      collection: collection
    } do
      board =
        Repo.insert!(%Board{
          name: unique_board_name("Out of order"),
          collection_id: collection.id
        })

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
    test "import priv/boards, replacing on re-runs, with uneven categories" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Code.eval_file("priv/repo/seeds.exs")
          Code.eval_file("priv/repo/seeds.exs")
        end)

      assert output =~ ~s(Seeded "Sampler" in "General")
      assert [board] = Board |> Repo.all() |> Repo.preload(:collection)
      assert board.collection.name == Boards.default_collection_name()
      board = Boards.get_board!(board.id)

      clue_counts = Enum.map(board.categories, &length(&1.clues))
      assert length(clue_counts) > 1
      assert length(Enum.uniq(clue_counts)) > 1
    end
  end
end
