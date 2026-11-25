defmodule Mix.Tasks.Cluebert.ImportTest do
  # Mix.shell/1 is global, so these tests run on their own.
  use Cluebert.DataCase, async: false

  alias Cluebert.Boards.Board
  alias Mix.Tasks.Cluebert.Import, as: ImportTask

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{collection: unique_board_name("Lessons")}
  end

  defp write!(dir, file, collection, name, prompt \\ "p") do
    path = Path.join(dir, file)

    board = %{
      collection: collection,
      name: name,
      categories: [%{title: "T", clues: [%{prompt: prompt, response: "r"}]}]
    }

    File.write!(path, Jason.encode!(board))
    path
  end

  defp count(collection) do
    Repo.aggregate(
      from(b in Board, join: c in assoc(b, :collection), where: c.name == ^collection),
      :count
    )
  end

  @tag :tmp_dir
  test "imports each file and reports what it did", %{tmp_dir: dir, collection: collection} do
    one = write!(dir, "one.json", collection, "One")
    two = write!(dir, "two.json", collection, "Two")

    ImportTask.run([one, two])

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ ~s(Imported "One" in "#{collection}")
    assert_received {:mix_shell, :info, [_]}
    assert count(collection) == 2
  end

  @tag :tmp_dir
  test "replaces with --replace", %{tmp_dir: dir, collection: collection} do
    path = write!(dir, "one.json", collection, "One")
    ImportTask.run([path])

    ImportTask.run([path, "--replace"])

    assert_received {:mix_shell, :info, [_]}
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ ~s(Replaced "One")
    assert count(collection) == 1
  end

  @tag :tmp_dir
  test "reports failures, keeps going, and exits with an error", %{
    tmp_dir: dir,
    collection: collection
  } do
    bad = write!(dir, "bad.json", collection, "Bad", "")
    good = write!(dir, "good.json", collection, "Good")
    missing = Path.join(dir, "missing.json")

    assert_raise Mix.Error, ~r/2 of 3 file\(s\) failed/, fn ->
      ImportTask.run([bad, missing, good])
    end

    assert_received {:mix_shell, :error, [bad_msg]}
    assert bad_msg =~ "prompt can't be blank"
    assert_received {:mix_shell, :error, [missing_msg]}
    assert missing_msg =~ "no such file"
    assert count(collection) == 1
  end

  test "needs at least one file" do
    assert_raise Mix.Error, ~r/Usage/, fn -> ImportTask.run([]) end
  end
end
