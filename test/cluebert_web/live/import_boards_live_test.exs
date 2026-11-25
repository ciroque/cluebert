defmodule CluebertWeb.ImportBoardsLiveTest do
  use CluebertWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Cluebert.Boards
  alias Cluebert.Boards.Board
  alias Cluebert.DataCase
  alias Cluebert.Repo

  import Ecto.Query

  # Each test imports into its own collection; see DataCase.unique_collection/1.
  setup do
    %{collection: DataCase.unique_board_name("Lessons")}
  end

  defp board_json(collection, name, prompt \\ "Roots drink this") do
    Jason.encode!(%{
      collection: collection,
      name: name,
      categories: [%{title: "Plants", clues: [%{prompt: prompt, response: "Water"}]}]
    })
  end

  defp boards_in(collection) do
    Repo.all(
      from b in Board,
        join: c in assoc(b, :collection),
        where: c.name == ^collection,
        order_by: b.name,
        select: b.name
    )
  end

  defp paste(view, json, replace \\ false) do
    view
    |> form("#import-form", import: %{json: json, replace: to_string(replace)})
    |> render_submit()
  end

  test "is reachable from the boards page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/boards")

    assert {:error, {:live_redirect, %{to: "/boards/import"}}} =
             view |> element("#import-boards") |> render_click()
  end

  test "is not mistaken for a board id", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    assert has_element?(view, "#import-form")
  end

  test "imports pasted JSON and links to the new board", %{conn: conn, collection: collection} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    paste(view, board_json(collection, "Lesson 1"))

    assert has_element?(view, "#result-0[data-status=ok]", "Pasted JSON")
    assert boards_in(collection) == ["Lesson 1"]

    [board] =
      Repo.all(from b in Board, join: c in assoc(b, :collection), where: c.name == ^collection)

    assert has_element?(
             view,
             ~s(#imported-board-#{board.id} a[href="/boards/#{board.id}"]),
             "Lesson 1"
           )

    assert has_element?(view, "#imported-board-#{board.id}", "Imported")
  end

  test "shows the importer's error and keeps the pasted text", %{
    conn: conn,
    collection: collection
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/import")
    bad = board_json(collection, "Bad", "")

    paste(view, bad)

    assert has_element?(view, "#result-0[data-status=error]", "clue 1: prompt can't be blank")
    assert has_element?(view, "#import-form textarea", "Bad")
    assert boards_in(collection) == []
  end

  test "refuses an existing board unless replace is ticked", %{
    conn: conn,
    collection: collection
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/import")
    paste(view, board_json(collection, "Lesson 1"))

    paste(view, board_json(collection, "Lesson 1", "New prompt"))
    assert has_element?(view, "#result-0[data-status=error]", "already exists")

    paste(view, board_json(collection, "Lesson 1", "New prompt"), true)
    assert has_element?(view, "#result-0[data-status=ok]", "Replaced")

    [board] =
      Repo.all(from b in Board, join: c in assoc(b, :collection), where: c.name == ^collection)

    assert [%{clues: [%{prompt: "New prompt"}]}] = Boards.get_board!(board.id).categories
  end

  test "imports each uploaded file on its own", %{conn: conn, collection: collection} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    files =
      file_input(view, "#import-form", :board_files, [
        %{name: "good.json", content: board_json(collection, "Good"), type: "application/json"},
        %{name: "bad.json", content: board_json(collection, "Bad", ""), type: "application/json"}
      ])

    assert render_upload(files, "good.json") =~ "good.json"
    assert render_upload(files, "bad.json") =~ "bad.json"
    assert has_element?(view, "#chosen-files", "good.json")

    paste(view, "")

    assert has_element?(view, "#import-results [data-status=ok]", "good.json")
    assert has_element?(view, "#import-results [data-status=error]", "bad.json")
    assert boards_in(collection) == ["Good"]
  end

  test "imports pasted JSON and files together", %{conn: conn, collection: collection} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    files =
      file_input(view, "#import-form", :board_files, [
        %{
          name: "one.json",
          content: board_json(collection, "From file"),
          type: "application/json"
        }
      ])

    render_upload(files, "one.json")
    paste(view, board_json(collection, "Pasted"))

    assert has_element?(view, "#result-0", "Pasted JSON")
    assert has_element?(view, "#result-1", "one.json")
    assert boards_in(collection) == ["From file", "Pasted"]
  end

  test "asks for something to import when there is nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    paste(view, "   ")

    assert has_element?(view, "#flash-error", "Paste some JSON or choose a file")
    refute has_element?(view, "#import-results")
  end

  test "rejects files that aren't .json", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/boards/import")

    files =
      file_input(view, "#import-form", :board_files, [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(files, "notes.txt")
  end
end
