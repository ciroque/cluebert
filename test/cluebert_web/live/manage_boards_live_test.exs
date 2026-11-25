defmodule CluebertWeb.ManageBoardsLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.Boards
  alias Cluebert.DataCase

  defp board(collection, name, clues \\ []) do
    {:ok, board} =
      Boards.create_board(collection, %{name: name, categories: [%{title: "T", clues: clues}]})

    board
  end

  defp clue, do: %{prompt: "p", response: "r", value: 100}

  defp submit(view, form_id, field, name) do
    view |> form("##{form_id}", %{field => %{name: name}}) |> render_submit()
  end

  describe "navigation" do
    test "the header links to new game and boards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: "/boards"}}} =
               view |> element("#nav-boards") |> render_click()

      {:ok, view, _html} = live(conn, ~p"/boards")
      assert has_element?(view, ~s(#nav-new-game[href="/"]))
    end
  end

  describe "collections" do
    test "lists collections with their boards and clue counts", %{conn: conn} do
      collection = DataCase.unique_collection()
      full = board(collection, "Full", [clue(), clue()])
      empty = board(collection, "Empty")

      {:ok, view, _html} = live(conn, ~p"/boards")

      assert has_element?(view, "#collection-#{collection.id} h2", collection.name)
      assert has_element?(view, "#collection-#{collection.id} #board-#{full.id}", "Full")
      assert has_element?(view, "#clue-count-#{full.id}", "2 clues")
      assert has_element?(view, "#no-clues-#{empty.id}")
    end

    test "creates a collection", %{conn: conn} do
      name = DataCase.unique_board_name("Primary Lessons")
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#new-collection") |> render_click()
      submit(view, "collection-form", :collection, name)

      assert has_element?(view, "#flash-info", "Created the collection")
      assert has_element?(view, "section h2", name)
      refute has_element?(view, "#collection-form")
    end

    test "shows errors for a blank or taken name", %{conn: conn} do
      taken = DataCase.unique_collection()
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#new-collection") |> render_click()
      submit(view, "collection-form", :collection, " ")
      assert has_element?(view, "#collection-form", "can't be blank")

      submit(view, "collection-form", :collection, taken.name)
      assert has_element?(view, "#collection-form", "is already a collection")
    end

    test "renames a collection, and cancel closes the form", %{conn: conn} do
      collection = DataCase.unique_collection()
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#rename-collection-#{collection.id}") |> render_click()
      view |> element("#collection-form button", "Cancel") |> render_click()
      refute has_element?(view, "#collection-form")

      view |> element("#rename-collection-#{collection.id}") |> render_click()
      submit(view, "collection-form", :collection, collection.name <> " Renamed")

      assert has_element?(view, "#collection-#{collection.id} h2", collection.name <> " Renamed")
    end

    test "deletes only an empty collection", %{conn: conn} do
      empty = DataCase.unique_collection()
      used = DataCase.unique_collection()
      board(used, "Keep")
      {:ok, view, _html} = live(conn, ~p"/boards")

      assert has_element?(view, "#delete-collection-#{used.id}[disabled]")

      # Even if the click gets through, the collection is kept.
      render_click(view, "delete_collection", %{"id" => to_string(used.id)})
      assert has_element?(view, "#flash-error", "still has boards")
      assert has_element?(view, "#collection-#{used.id}")

      view |> element("#delete-collection-#{empty.id}") |> render_click()
      refute has_element?(view, "#collection-#{empty.id}")
    end
  end

  describe "boards" do
    setup do
      %{collection: DataCase.unique_collection()}
    end

    test "adds a board to a collection", %{conn: conn, collection: collection} do
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#new-board-#{collection.id}") |> render_click()
      submit(view, "board-form", :board, "Lesson 1")

      assert has_element?(view, "#collection-#{collection.id} li", "Lesson 1")
      assert has_element?(view, "#flash-info", "Created the board")
    end

    test "rejects a board name already taken in the collection", %{
      conn: conn,
      collection: collection
    } do
      board(collection, "Lesson 1")
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#new-board-#{collection.id}") |> render_click()
      submit(view, "board-form", :board, "Lesson 1")

      assert has_element?(view, "#board-form", "has already been taken in this collection")
    end

    test "renames a board", %{conn: conn, collection: collection} do
      lesson = board(collection, "Lesson 1", [clue()])
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#rename-board-#{lesson.id}") |> render_click()
      submit(view, "board-form", :board, "Lesson One")

      assert has_element?(view, "#board-#{lesson.id}", "Lesson One")
      assert has_element?(view, "#clue-count-#{lesson.id}", "1 clue")
    end

    test "moves a board to another collection", %{conn: conn, collection: collection} do
      other = DataCase.unique_collection()
      lesson = board(collection, "Lesson 1")
      {:ok, view, _html} = live(conn, ~p"/boards")

      view
      |> form("#move-board-#{lesson.id}", %{collection_id: other.id})
      |> render_change()

      assert has_element?(view, "#collection-#{other.id} #board-#{lesson.id}")
      refute has_element?(view, "#collection-#{collection.id} #board-#{lesson.id}")
    end

    test "explains when a move would clash with a board of the same name", %{
      conn: conn,
      collection: collection
    } do
      other = DataCase.unique_collection()
      board(other, "Same")
      mine = board(collection, "Same")
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> form("#move-board-#{mine.id}", %{collection_id: other.id}) |> render_change()

      assert has_element?(view, "#flash-error", "Couldn't move")
      assert has_element?(view, "#collection-#{collection.id} #board-#{mine.id}")
    end

    test "deletes a board", %{conn: conn, collection: collection} do
      lesson = board(collection, "Lesson 1", [clue()])
      {:ok, view, _html} = live(conn, ~p"/boards")

      view |> element("#delete-board-#{lesson.id}") |> render_click()

      refute has_element?(view, "#board-#{lesson.id}")
      assert has_element?(view, "#collection-empty-#{collection.id}")
    end
  end
end
