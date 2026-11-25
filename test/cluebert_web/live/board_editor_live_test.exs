defmodule CluebertWeb.BoardEditorLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.Boards
  alias Cluebert.DataCase

  defp create_board(categories) do
    {:ok, board} =
      Boards.create_board(DataCase.unique_collection(), %{name: "Lesson", categories: categories})

    Boards.get_board!(board.id)
  end

  defp clue(prompt, value), do: %{prompt: prompt, response: "#{prompt}!", value: value}

  defp open(conn, board) do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    view
  end

  defp titles(board), do: Enum.map(Boards.get_board!(board.id).categories, & &1.title)

  defp prompts(board, index) do
    board.id
    |> Boards.get_board!()
    |> Map.fetch!(:categories)
    |> Enum.at(index)
    |> Map.fetch!(:clues)
    |> Enum.map(& &1.prompt)
  end

  setup do
    board =
      create_board([
        %{title: "Plants", clues: [clue("Roots", 100), clue("Leaves", 200)]},
        %{title: "Animals", clues: []}
      ])

    [plants, animals] = board.categories
    [roots, leaves] = plants.clues
    %{board: board, plants: plants, animals: animals, roots: roots, leaves: leaves}
  end

  describe "viewing" do
    test "shows categories and clues in board order", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      assert has_element?(view, "#breadcrumb", "Boards")
      assert has_element?(view, "#board-summary", "2 categories · 2 clues")
      assert has_element?(view, "#category-#{ctx.plants.id} h2", "Plants")
      assert has_element?(view, "#clue-#{ctx.roots.id}", "Roots")
      assert has_element?(view, "#clue-#{ctx.roots.id}", "Roots!")
      assert has_element?(view, "#clue-#{ctx.roots.id}", "100")
      assert has_element?(view, "#category-empty-#{ctx.animals.id}")
      refute has_element?(view, "#not-playable")
    end

    test "disables moves at the ends", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      assert has_element?(view, "#move-category-up-#{ctx.plants.id}[disabled]")
      refute has_element?(view, "#move-category-down-#{ctx.plants.id}[disabled]")
      assert has_element?(view, "#move-category-down-#{ctx.animals.id}[disabled]")
      assert has_element?(view, "#move-clue-up-#{ctx.roots.id}[disabled]")
      assert has_element?(view, "#move-clue-down-#{ctx.leaves.id}[disabled]")
    end

    test "warns when the board has no clues", %{conn: conn} do
      view = open(conn, create_board([%{title: "Empty", clues: []}]))

      assert has_element?(view, "#not-playable")
    end

    test "is linked from the boards page", %{conn: conn, board: board} do
      {:ok, view, _html} = live(conn, ~p"/boards")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#edit-board-#{board.id}") |> render_click()

      assert to == "/boards/#{board.id}"
    end

    test "goes back to the boards page for an unknown board", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/boards"}}} = live(conn, ~p"/boards/0")
      assert {:error, {:live_redirect, %{to: "/boards"}}} = live(conn, ~p"/boards/nope")
    end
  end

  describe "categories" do
    test "adds one at the end", %{conn: conn, board: board} do
      view = open(conn, board)

      view |> element("#new-category") |> render_click()
      view |> form("#category-form", category: %{title: "Weather"}) |> render_submit()

      assert titles(board) == ["Plants", "Animals", "Weather"]
      refute has_element?(view, "#category-form")
      assert has_element?(view, "section h2", "Weather")
    end

    test "requires a title", %{conn: conn, board: board} do
      view = open(conn, board)

      view |> element("#new-category") |> render_click()
      view |> form("#category-form", category: %{title: " "}) |> render_submit()

      assert has_element?(view, "#category-form", "can't be blank")
    end

    test "renames one", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#rename-category-#{ctx.animals.id}") |> render_click()
      view |> form("#category-form", category: %{title: "Creatures"}) |> render_submit()

      assert has_element?(view, "#category-#{ctx.animals.id} h2", "Creatures")
    end

    test "moves one", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#move-category-down-#{ctx.plants.id}") |> render_click()

      assert titles(ctx.board) == ["Animals", "Plants"]
      assert has_element?(view, "#move-category-up-#{ctx.animals.id}[disabled]")
    end

    test "deletes one with its clues", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#delete-category-#{ctx.plants.id}") |> render_click()

      assert titles(ctx.board) == ["Animals"]
      refute has_element?(view, "#clue-#{ctx.roots.id}")
      assert has_element?(view, "#not-playable")
    end
  end

  describe "clues" do
    test "adds one at the bottom with the next row's value suggested", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#new-clue-#{ctx.plants.id}") |> render_click()
      assert has_element?(view, ~s(#clue-form input[name="clue[value]"][value="300"]))

      view
      |> form("#clue-form", clue: %{prompt: "Stem", response: "Holds it up", value: "300"})
      |> render_submit()

      assert prompts(ctx.board, 0) == ["Roots", "Leaves", "Stem"]
      assert has_element?(view, "#board-summary", "3 clues")
    end

    test "shows errors for missing text and negative values", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#new-clue-#{ctx.animals.id}") |> render_click()

      view
      |> form("#clue-form", clue: %{prompt: "", response: "", value: "-5"})
      |> render_submit()

      assert has_element?(view, "#clue-form", "can't be blank")
      assert has_element?(view, "#clue-form", "must be greater than or equal to 0")
      assert prompts(ctx.board, 1) == []
    end

    test "edits one", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#edit-clue-#{ctx.roots.id}") |> render_click()

      view
      |> form("#clue-form", clue: %{prompt: "Roots drink", response: "Water", value: "150"})
      |> render_submit()

      assert has_element?(view, "#clue-#{ctx.roots.id}", "Roots drink")
      assert Boards.get_clue!(ctx.roots.id).value == 150
    end

    test "moves one", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#move-clue-down-#{ctx.roots.id}") |> render_click()

      assert prompts(ctx.board, 0) == ["Leaves", "Roots"]
    end

    test "deletes one", %{conn: conn} = ctx do
      view = open(conn, ctx.board)

      view |> element("#delete-clue-#{ctx.leaves.id}") |> render_click()

      assert prompts(ctx.board, 0) == ["Roots"]
      refute has_element?(view, "#clue-#{ctx.leaves.id}")
    end
  end

  describe "stale and foreign ids" do
    test "a clue deleted elsewhere is reported, not edited", %{conn: conn} = ctx do
      view = open(conn, ctx.board)
      {:ok, _} = Boards.delete_clue(Boards.get_clue!(ctx.roots.id))

      view |> element("#move-clue-down-#{ctx.roots.id}") |> render_click()

      assert has_element?(view, "#flash-error", "no longer exists")
      refute has_element?(view, "#clue-#{ctx.roots.id}")
    end

    test "a clue from another board is refused", %{conn: conn} = ctx do
      other = create_board([%{title: "Other", clues: [clue("Theirs", 100)]}])
      [%{clues: [theirs]}] = other.categories
      view = open(conn, ctx.board)

      render_click(view, "delete_clue", %{"id" => to_string(theirs.id)})

      assert has_element?(view, "#flash-error", "no longer exists")
      assert Boards.get_clue!(theirs.id).prompt == "Theirs"
    end
  end
end
