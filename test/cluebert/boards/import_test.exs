defmodule Cluebert.Boards.ImportTest do
  use Cluebert.DataCase, async: true

  alias Cluebert.Boards
  alias Cluebert.Boards.{Board, Import}

  # Each test uses its own collection name; see DataCase.unique_collection/1.
  setup do
    %{collection: unique_board_name("Lessons")}
  end

  defp board(collection, name, categories \\ nil) do
    %{
      "collection" => collection,
      "name" => name,
      "categories" =>
        categories ||
          [
            %{
              "title" => "Plants",
              "clues" => [
                %{"prompt" => "Plants make food from this", "response" => "Sunlight"},
                %{"prompt" => "The part that drinks water", "response" => "Roots"}
              ]
            },
            %{
              "title" => "Animals",
              "clues" => [%{"prompt" => "A baby frog", "response" => "Tadpole", "value" => 500}]
            }
          ]
    }
  end

  defp import!(data, opts \\ []) do
    {:ok, imported} = data |> Jason.encode!() |> Import.import_json(opts)
    imported
  end

  defp import_error(data, opts \\ []) do
    {:error, error} = data |> Jason.encode!() |> Import.import_json(opts)
    Import.format_error(error)
  end

  defp boards_in(collection) do
    Board
    |> join(:inner, [b], c in assoc(b, :collection))
    |> where([_b, c], c.name == ^collection)
    |> Repo.all()
  end

  describe "importing" do
    test "imports a single board into its collection, in order", %{collection: collection} do
      assert [%{board: %Board{id: id}, collection: ^collection, replaced?: false}] =
               import!(board(collection, "Lesson 1"))

      loaded = Boards.get_board!(id)
      assert loaded.name == "Lesson 1"
      assert Enum.map(loaded.categories, & &1.title) == ["Plants", "Animals"]

      [plants, animals] = loaded.categories

      assert Enum.map(plants.clues, &{&1.prompt, &1.response}) == [
               {"Plants make food from this", "Sunlight"},
               {"The part that drinks water", "Roots"}
             ]

      assert Enum.map(animals.clues, & &1.value) == [500]
    end

    test "defaults missing or null values to 100 times the row", %{collection: collection} do
      categories = [
        %{
          "title" => "T",
          "clues" => [
            %{"prompt" => "a", "response" => "a"},
            %{"prompt" => "b", "response" => "b", "value" => nil},
            %{"prompt" => "c", "response" => "c", "value" => 50}
          ]
        }
      ]

      [%{board: board}] = import!(board(collection, "Values", categories))

      [category] = Boards.get_board!(board.id).categories
      assert Enum.map(category.clues, & &1.value) == [100, 200, 50]
    end

    test "imports a list of boards", %{collection: collection} do
      imported = import!([board(collection, "One"), board(collection, "Two")])

      assert Enum.map(imported, & &1.board.name) == ["One", "Two"]
      assert collection |> boards_in() |> length() == 2
    end

    test "puts a board without a collection in the default one" do
      name = unique_board_name("No collection")

      [%{collection: collection}] = import!(Map.delete(board("unused", name), "collection"))

      assert collection == Boards.default_collection_name()
    end
  end

  describe "existing boards" do
    test "are rejected without replace, and nothing is imported", %{collection: collection} do
      import!(board(collection, "Lesson 1"))

      message = import_error([board(collection, "New"), board(collection, "Lesson 1")])

      assert message =~ ~s(board 2: "Lesson 1" already exists in collection "#{collection}")
      assert collection |> boards_in() |> Enum.map(& &1.name) == ["Lesson 1"]
    end

    test "are replaced with replace", %{collection: collection} do
      [%{board: old}] = import!(board(collection, "Lesson 1"))

      [%{board: new, replaced?: true}] =
        import!(board(collection, "Lesson 1", [%{"title" => "New", "clues" => []}]),
          replace: true
        )

      assert new.id != old.id
      assert [%{title: "New"}] = Boards.get_board!(new.id).categories
      assert_raise Ecto.NoResultsError, fn -> Boards.get_board!(old.id) end
    end

    test "with the same name in another collection are left alone", %{collection: collection} do
      other = unique_board_name("Other")
      [%{board: theirs}] = import!(board(other, "Lesson 1"))

      import!(board(collection, "Lesson 1"))

      assert Boards.get_board!(theirs.id).name == "Lesson 1"
    end
  end

  describe "errors" do
    test "report invalid JSON" do
      assert {:error, error} = Import.import_json("{not json")
      assert Import.format_error(error) =~ "not valid JSON"
    end

    test "report a top level that is not a board or a list" do
      assert {:error, :not_a_board_list} = Import.import_json(~s("just a string"))
    end

    test "report entries that are not objects" do
      assert import_error([42]) == "board 1: expected an object"
    end

    test "report a blank or non-string collection", %{collection: collection} do
      assert import_error(%{board(collection, "X") | "collection" => " "}) =~
               ~s(board 1: "collection" must be a non-blank string)

      assert import_error(%{board(collection, "X") | "collection" => 7}) =~ "collection"
    end

    test "report the same board twice in one file", %{collection: collection} do
      assert import_error([board(collection, "Twice"), board(collection, " Twice ")]) =~
               ~s(board 2: "Twice" appears more than once)
    end

    test "name the board, category and clue at fault, and import nothing", %{
      collection: collection
    } do
      bad = [
        %{"title" => "Fine", "clues" => [%{"prompt" => "p", "response" => "r"}]},
        %{
          "title" => "",
          "clues" => [
            %{"prompt" => "p", "response" => "r"},
            %{"prompt" => "", "response" => "r", "value" => -5}
          ]
        }
      ]

      message = import_error([board(collection, "Good"), board(collection, "Bad", bad)])

      assert message =~ ~s{board 2 ("Bad"), category 2: title can't be blank}
      assert message =~ ~s{board 2 ("Bad"), category 2, clue 2: prompt can't be blank}

      assert message =~
               ~s{board 2 ("Bad"), category 2, clue 2: value must be greater than or equal to 0}

      refute message =~ "category 1"
      assert boards_in(collection) == []
    end

    test "report a missing board name", %{collection: collection} do
      assert import_error(Map.delete(board(collection, "X"), "name")) ==
               "board 1: name can't be blank"
    end
  end
end
